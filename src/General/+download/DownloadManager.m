classdef DownloadManager < handle

    % DOWNLOADMANAGER Provider-neutral transfer orchestration.
    %
    % The manager owns logical task state and downloader lifecycles. It has
    % no dependency on MATLAB UI classes; callers render the snapshots sent
    % through SnapshotFcn and translate user actions into manager commands.

    properties
        CollisionPolicy (1,:) char = 'askInRow'
        PartialConflictPolicy (1,:) char = 'askInRow'
        SnapshotFcn = []
        TaskReorderedFcn = []
        CompletedFcn = []
        ErrorFcn = []
    end

    properties (SetAccess = private)
        DownloaderFactory
    end

    properties (Access = private)
        Tasks = {}
        NextTaskID (1,1) double = 0
        IsDeleting (1,1) logical = false
    end

    methods
        function obj = DownloadManager(options)
            arguments
                options.DownloaderFactory (1,1) function_handle
                options.CollisionPolicy (1,:) char = 'askInRow'
                options.PartialConflictPolicy (1,:) char = 'askInRow'
            end

            obj.DownloaderFactory = options.DownloaderFactory;
            obj.CollisionPolicy = options.CollisionPolicy;
            obj.PartialConflictPolicy = options.PartialConflictPolicy;
        end

        function delete(obj)
            if obj.IsDeleting
                return
            end
            obj.IsDeleting = true;
            for taskIndex = 1:numel(obj.Tasks)
                task = obj.Tasks{taskIndex};
                if ~isempty(task)
                    obj.releaseDownloader(task)
                end
            end
            obj.Tasks = {};
        end

        function taskID = addDownload(obj, request)
            request = normalizeRequest(request);
            duplicateTaskID = obj.findDuplicate(request);
            if ~isempty(duplicateTaskID)
                taskID = duplicateTaskID;
                obj.notifyTaskReordered(taskID)
                return
            end

            obj.NextTaskID = obj.NextTaskID + 1;
            taskID = obj.NextTaskID;

            task = struct('ID', taskID, ...
                          'TaskID', shortTaskID(), ...
                          'URL', request.URL, ...
                          'FileName', request.FileName, ...
                          'TempFolder', request.TempFolder, ...
                          'TargetFolder', request.TargetFolder, ...
                          'FinalPath', request.FinalPath, ...
                          'PartialPath', request.PartialPath, ...
                          'ChunkPath', request.ChunkPath, ...
                          'BackupPath', request.BackupPath, ...
                          'AllowSourceFilename', request.AllowSourceFilename, ...
                          'SourcePrepared', request.SourcePrepared, ...
                          'Downloader', [], ...
                          'LifecycleState', 'created', ...
                          'ConflictType', '', ...
                          'CollisionAction', 'none', ...
                          'PartialAction', 'none', ...
                          'IsPaused', false, ...
                          'IsStopped', false, ...
                          'ReceivedBytes', 0, ...
                          'TotalBytes', [], ...
                          'ProgressFraction', 0, ...
                          'TransferRate', NaN, ...
                          'StartClock', [], ...
                          'StartedAt', datetime.empty, ...
                          'UpdatedAt', utcNow(), ...
                          'CompletedAt', datetime.empty, ...
                          'ProgressSamples', zeros(0, 2), ...
                          'ErrorIdentifier', '', ...
                          'ErrorMessage', '');
            obj.Tasks{taskID} = task;
            obj.notifySnapshot(task)

            if pathExists(task.FinalPath)
                obj.setConflict(taskID, 'target')
            elseif isfile(task.PartialPath)
                obj.setConflict(taskID, 'partial')
            else
                obj.startTask(taskID)
            end
        end

        function resolveConflict(obj, taskID, action)
            task = obj.getTask(taskID);
            if isempty(task) || ~strcmp(task.LifecycleState, 'awaitingConflictDecision')
                return
            end

            allowedActions = conflictActions(task.ConflictType);
            if ~ismember(action, allowedActions)
                error('download:DownloadManager:invalidConflictAction', ...
                      'Action "%s" is not valid for a %s conflict.', action, task.ConflictType)
            end
            if strcmp(action, 'cancel')
                obj.cancel(taskID)
                return
            end

            if strcmp(task.ConflictType, 'target') && strcmp(action, 'overwrite')
                task.BackupPath = fullfile(task.TempFolder, ...
                                           [task.TaskID, '_backup_', task.FileName]);
                try
                    ensureFolder(task.TempFolder)
                    moveFileWithFallback(task.FinalPath, task.BackupPath)
                catch exception
                    obj.failTask(taskID, exception)
                    return
                end
                task.CollisionAction = 'overwrite';
            elseif strcmp(task.ConflictType, 'target') && strcmp(action, 'uniqueName')
                task.FinalPath = uniqueTargetPath(task.FinalPath);
                [task.TargetFolder, baseName, extension] = fileparts(task.FinalPath);
                task.FileName = [baseName, extension];
                task.PartialPath = fullfile(task.TempFolder, ...
                                            [task.TaskID, '_', task.FileName, '.part']);
                task.ChunkPath = [task.PartialPath, '.chunk'];
                task.CollisionAction = 'uniqueName';
            elseif strcmp(task.ConflictType, 'partial') && strcmp(action, 'restart')
                deleteIfExists(task.PartialPath)
                deleteIfExists(task.ChunkPath)
                task.PartialPath = fullfile(task.TempFolder, ...
                                            [task.TaskID, '_', task.FileName, '.part']);
                task.ChunkPath = [task.PartialPath, '.chunk'];
                task.PartialAction = 'restart';
            elseif strcmp(task.ConflictType, 'partial') && strcmp(action, 'resume')
                task.PartialAction = 'resume';
            end

            task.ConflictType = '';
            task.LifecycleState = 'created';
            task.UpdatedAt = utcNow();
            obj.Tasks{taskID} = task;

            if isfile(task.PartialPath) && ~strcmp(task.PartialAction, 'resume')
                obj.setConflict(taskID, 'partial')
            else
                obj.startTask(taskID)
            end
        end

        function pause(obj, taskID)
            task = obj.getTask(taskID);
            if isempty(task) || ~strcmp(task.LifecycleState, 'active') || isempty(task.Downloader)
                return
            end
            try
                pause(task.Downloader)
                task.IsPaused = true;
                task.LifecycleState = 'paused';
                task.TransferRate = NaN;
                task.UpdatedAt = utcNow();
                obj.Tasks{taskID} = task;
                obj.notifySnapshot(task)
            catch exception
                obj.failTask(taskID, exception)
            end
        end

        function resume(obj, taskID)
            task = obj.getTask(taskID);
            if isempty(task) || ~strcmp(task.LifecycleState, 'paused') || isempty(task.Downloader)
                return
            end
            try
                resume(task.Downloader)
                task.IsPaused = false;
                task.LifecycleState = 'active';
                task.StartClock = tic;
                task.UpdatedAt = utcNow();
                obj.Tasks{taskID} = task;
                obj.notifySnapshot(task)
            catch exception
                obj.failTask(taskID, exception)
            end
        end

        function cancelAll(obj)
            for taskID = 1:numel(obj.Tasks)
                if ~isempty(obj.Tasks{taskID})
                    obj.cancel(taskID)
                end
            end
        end

        function cancel(obj, taskID)
            task = obj.getTask(taskID);
            if isempty(task)
                return
            end
            task.IsStopped = true;
            task.LifecycleState = 'canceled';
            task.UpdatedAt = utcNow();
            snapshot = obj.snapshot(task);
            obj.releaseDownloader(task)
            restoreBackup(task)
            cleanupTemporaryFiles(task)
            obj.notifySnapshot(snapshot)
            obj.Tasks{taskID} = [];
        end

        function tf = isActive(obj, filePath)
            tf = false;
            for taskIndex = 1:numel(obj.Tasks)
                task = obj.Tasks{taskIndex};
                if isempty(task) || task.IsStopped
                    continue
                end
                if strcmpi(task.FinalPath, filePath)
                    tf = true;
                    return
                end
            end
        end

        function snapshot = getSnapshot(obj, taskID)
            task = obj.getTask(taskID);
            if isempty(task)
                snapshot = [];
            else
                snapshot = obj.snapshot(task);
            end
        end
    end

    methods (Access = private)
        function startTask(obj, taskID)
            task = obj.getTask(taskID);
            if isempty(task) || task.IsStopped || obj.IsDeleting
                return
            end

            try
                ensureFolder(task.TempFolder)
                request = requestFromTask(task);
                downloader = obj.DownloaderFactory(request);
                validateDownloader(downloader)
                task.Downloader = downloader;
                obj.Tasks{taskID} = task;

                if ~task.SourcePrepared && ismethod(downloader, 'prepare')
                    sourceInfo = prepare(downloader);
                    task = applySourceInfo(task, sourceInfo);
                    task.SourcePrepared = true;
                end

                existingPartialPath = findPartialPath(task.TempFolder, task.FileName);
                if ~isempty(existingPartialPath)
                    task.PartialPath = existingPartialPath;
                    task.ChunkPath = [existingPartialPath, '.chunk'];
                end

                if pathExists(task.FinalPath)
                    obj.releaseDownloader(task)
                    task.Downloader = [];
                    obj.Tasks{taskID} = task;
                    obj.setConflict(taskID, 'target')
                    return
                elseif ~strcmp(task.PartialAction, 'resume') && ...
                        ~isempty(existingPartialPath)
                    obj.releaseDownloader(task)
                    task.Downloader = [];
                    obj.Tasks{taskID} = task;
                    obj.setConflict(taskID, 'partial')
                    return
                end

                task.LifecycleState = 'active';
                task.IsPaused = false;
                task.StartClock = tic;
                if isempty(task.StartedAt)
                    task.StartedAt = utcNow();
                end
                task.UpdatedAt = utcNow();
                obj.Tasks{taskID} = task;
                downloader.ProgressFcn = @(receivedBytes, totalBytes) ...
                    obj.onProgress(taskID, receivedBytes, totalBytes);
                downloader.CompletedFcn = @(info) obj.onCompleted(taskID, info);
                downloader.ErrorFcn = @(exception) obj.onError(taskID, exception);
                obj.notifySnapshot(task)
                start(downloader)
            catch exception
                obj.failTask(taskID, exception)
            end
        end

        function setConflict(obj, taskID, conflictType)
            task = obj.getTask(taskID);
            if isempty(task) || task.IsStopped
                return
            end
            task.ConflictType = conflictType;
            task.LifecycleState = 'awaitingConflictDecision';
            task.UpdatedAt = utcNow();
            obj.Tasks{taskID} = task;

            if strcmp(conflictType, 'target')
                policy = obj.CollisionPolicy;
            else
                policy = obj.PartialConflictPolicy;
            end
            if strcmp(policy, 'reject')
                policy = 'cancel';
            end
            if strcmp(policy, 'askInRow')
                obj.notifySnapshot(task)
            else
                obj.resolveConflict(taskID, policy)
            end
        end

        function onProgress(obj, taskID, receivedBytes, totalBytes)
            task = obj.getTask(taskID);
            if isempty(task) || ~strcmp(task.LifecycleState, 'active') || obj.IsDeleting
                return
            end
            task.ReceivedBytes = double(receivedBytes);
            if isempty(totalBytes)
                task.TotalBytes = [];
            else
                task.TotalBytes = double(totalBytes);
            end
            elapsedSeconds = toc(task.StartClock);
            task.ProgressSamples(end+1, :) = [elapsedSeconds, task.ReceivedBytes];
            cutoffTime = elapsedSeconds - 10;
            samplesBeforeCutoff = find(task.ProgressSamples(:, 1) <= cutoffTime, 1, 'last');
            if ~isempty(samplesBeforeCutoff)
                task.ProgressSamples = task.ProgressSamples(samplesBeforeCutoff:end, :);
            end
            task.TransferRate = measuredRate(task.ProgressSamples, elapsedSeconds);
            if isempty(task.TotalBytes) || task.TotalBytes <= 0
                task.ProgressFraction = 0;
            else
                task.ProgressFraction = min(task.ReceivedBytes / task.TotalBytes, 1);
            end
            task.UpdatedAt = utcNow();
            obj.Tasks{taskID} = task;
            obj.notifySnapshot(task)
        end

        function onCompleted(obj, taskID, info)
            task = obj.getTask(taskID);
            if isempty(task) || task.IsStopped || obj.IsDeleting
                return
            end
            if ~isstruct(info)
                info = struct();
            end
            if ~isfield(info, 'FinalPath') || isempty(info.FinalPath)
                info.FinalPath = task.FinalPath;
            end
            if isfield(info, 'BytesReceived')
                task.ReceivedBytes = double(info.BytesReceived);
            end
            if isfield(info, 'TotalBytes')
                task.TotalBytes = info.TotalBytes;
            end
            task.LifecycleState = 'completed';
            task.IsPaused = false;
            task.CompletedAt = utcNow();
            task.UpdatedAt = task.CompletedAt;
            snapshot = obj.snapshot(task);
            obj.releaseDownloader(task)
            cleanupTemporaryFiles(task)
            obj.Tasks{taskID} = task;
            obj.notifySnapshot(snapshot)
            invokeCallback(obj.CompletedFcn, taskID, info, snapshot)
            obj.Tasks{taskID} = [];
        end

        function onError(obj, taskID, exception)
            obj.failTask(taskID, exception)
        end

        function failTask(obj, taskID, exception)
            task = obj.getTask(taskID);
            if isempty(task) || task.IsStopped || obj.IsDeleting
                return
            end
            task.LifecycleState = 'failed';
            task.ErrorIdentifier = exception.identifier;
            task.ErrorMessage = exception.message;
            task.UpdatedAt = utcNow();
            snapshot = obj.snapshot(task);
            obj.releaseDownloader(task)
            restoreBackup(task)
            obj.Tasks{taskID} = task;
            obj.notifySnapshot(snapshot)
            invokeCallback(obj.ErrorFcn, taskID, exception, snapshot)
            obj.Tasks{taskID} = [];
        end

        function releaseDownloader(~, task)
            downloader = task.Downloader;
            if isempty(downloader)
                return
            end
            try
                if isprop(downloader, 'ProgressFcn')
                    downloader.ProgressFcn = [];
                end
                if isprop(downloader, 'CompletedFcn')
                    downloader.CompletedFcn = [];
                end
                if isprop(downloader, 'ErrorFcn')
                    downloader.ErrorFcn = [];
                end
            catch
            end
            try
                if ismethod(downloader, 'stop')
                    stop(downloader)
                end
            catch
            end
            try
                if ismethod(downloader, 'delete')
                    delete(downloader)
                end
            catch
            end
        end

        function notifySnapshot(obj, taskOrSnapshot)
            if isstruct(taskOrSnapshot) && isfield(taskOrSnapshot, 'Downloader')
                snapshot = obj.snapshot(taskOrSnapshot);
            else
                snapshot = taskOrSnapshot;
            end
            invokeCallback(obj.SnapshotFcn, snapshot)
        end

        function task = getTask(obj, taskID)
            task = [];
            if ~isscalar(taskID) || ~isnumeric(taskID) || taskID < 1 || ...
                    taskID > numel(obj.Tasks)
                return
            end
            task = obj.Tasks{taskID};
        end

        function taskID = findDuplicate(obj, request)
            taskID = [];
            for taskIndex = 1:numel(obj.Tasks)
                task = obj.Tasks{taskIndex};
                if isempty(task) || task.IsStopped
                    continue
                end
                if strcmp(task.URL, request.URL) && strcmpi(task.FileName, request.FileName)
                    taskID = task.ID;
                    return
                end
            end
        end

        function notifyTaskReordered(obj, taskID)
            task = obj.getTask(taskID);
            if isempty(task)
                return
            end
            invokeCallback(obj.TaskReorderedFcn, obj.snapshot(task))
        end

        function value = snapshot(~, task)
            value = struct('ID', task.ID, ...
                           'TaskID', task.TaskID, ...
                           'URL', task.URL, ...
                           'FileName', task.FileName, ...
                           'TempFolder', task.TempFolder, ...
                           'TargetFolder', task.TargetFolder, ...
                           'FinalPath', task.FinalPath, ...
                           'PartialPath', task.PartialPath, ...
                           'ChunkPath', task.ChunkPath, ...
                           'BackupPath', task.BackupPath, ...
                           'LifecycleState', task.LifecycleState, ...
                           'ConflictType', task.ConflictType, ...
                           'CollisionAction', task.CollisionAction, ...
                           'PartialAction', task.PartialAction, ...
                           'IsPaused', task.IsPaused, ...
                           'IsStopped', task.IsStopped, ...
                           'ReceivedBytes', task.ReceivedBytes, ...
                           'TotalBytes', task.TotalBytes, ...
                           'ProgressFraction', task.ProgressFraction, ...
                           'TransferRate', task.TransferRate, ...
                           'StartedAt', task.StartedAt, ...
                           'UpdatedAt', task.UpdatedAt, ...
                           'CompletedAt', task.CompletedAt, ...
                           'ErrorIdentifier', task.ErrorIdentifier, ...
                           'ErrorMessage', task.ErrorMessage);
        end
    end

    methods
        function set.CollisionPolicy(obj, value)
            value = char(value);
            if ~ismember(value, {'askInRow', 'overwrite', 'uniqueName', 'reject'})
                error('download:DownloadManager:invalidCollisionPolicy', ...
                      'CollisionPolicy is not supported.')
            end
            obj.CollisionPolicy = value;
        end

        function set.PartialConflictPolicy(obj, value)
            value = char(value);
            if ~ismember(value, {'askInRow', 'resume', 'restart', 'cancel'})
                error('download:DownloadManager:invalidPartialConflictPolicy', ...
                      'PartialConflictPolicy is not supported.')
            end
            obj.PartialConflictPolicy = value;
        end
    end
end


function request = normalizeRequest(request)
requiredFields = {'URL', 'TempFolder', 'TargetFolder', 'FileName'};
for fieldIndex = 1:numel(requiredFields)
    fieldName = requiredFields{fieldIndex};
    if ~isfield(request, fieldName) || ~ischar(request.(fieldName)) || ...
            isempty(request.(fieldName))
        error('download:DownloadManager:invalidRequest', ...
              'The request must contain a nonempty character field named %s.', fieldName)
    end
end

request.URL = char(request.URL);
request.TempFolder = char(request.TempFolder);
request.TargetFolder = char(request.TargetFolder);
request.FileName = char(request.FileName);
request.FinalPath = fullfile(request.TargetFolder, request.FileName);
if ~isfield(request, 'PartialPath') || isempty(request.PartialPath)
    request.PartialPath = fullfile(request.TempFolder, ...
                                   ['pending_', request.FileName, '.part']);
end
if ~isfield(request, 'ChunkPath') || isempty(request.ChunkPath)
    request.ChunkPath = [request.PartialPath, '.chunk'];
end
if ~isfield(request, 'BackupPath')
    request.BackupPath = '';
end
if ~isfield(request, 'AllowSourceFilename') || isempty(request.AllowSourceFilename)
    request.AllowSourceFilename = false;
end
if ~isfield(request, 'SourcePrepared') || isempty(request.SourcePrepared)
    request.SourcePrepared = false;
end
end

function request = requestFromTask(task)
request = struct('URL', task.URL, ...
                 'TaskID', task.TaskID, ...
                 'TempFolder', task.TempFolder, ...
                 'TargetFolder', task.TargetFolder, ...
                 'FileName', task.FileName, ...
                 'FinalPath', task.FinalPath, ...
                 'PartialPath', task.PartialPath, ...
                 'ChunkPath', task.ChunkPath, ...
                 'BackupPath', task.BackupPath, ...
                 'CollisionAction', task.CollisionAction, ...
                 'PartialAction', task.PartialAction, ...
                 'AllowSourceFilename', task.AllowSourceFilename, ...
                 'SourcePrepared', task.SourcePrepared);
end

function task = applySourceInfo(task, sourceInfo)
if ~isstruct(sourceInfo) || ~isfield(sourceInfo, 'FileName') || ...
        isempty(sourceInfo.FileName)
    return
end
task.FileName = char(sourceInfo.FileName);
task.FinalPath = fullfile(task.TargetFolder, task.FileName);
task.PartialPath = fullfile(task.TempFolder, ...
                            [task.TaskID, '_', task.FileName, '.part']);
task.ChunkPath = [task.PartialPath, '.chunk'];
end

function value = measuredRate(samples, elapsedSeconds)
value = NaN;
if elapsedSeconds < 1 || size(samples, 1) < 2
    return
end
duration = samples(end, 1) - samples(1, 1);
if duration > 0
    value = max(0, (samples(end, 2) - samples(1, 2)) / duration);
end
end

function values = conflictActions(conflictType)
if strcmp(conflictType, 'target')
    values = {'overwrite', 'uniqueName', 'cancel'};
else
    values = {'resume', 'restart', 'cancel'};
end
end

function value = shortTaskID()
value = char(matlab.lang.internal.uuid());
value = regexprep(value, '-', '');
value = value(1:min(8, numel(value)));
end

function value = utcNow()
value = datetime('now', 'TimeZone', 'UTC');
end

function partialPath = findPartialPath(folderPath, fileName)
partialPath = '';
if isempty(folderPath) || ~isfolder(folderPath)
    return
end
entries = dir(fullfile(folderPath, ['*_', fileName, '.part']));
if isempty(entries)
    entries = dir(fullfile(folderPath, ['*_', fileName, '.part.chunk']));
    for entryIndex = 1:numel(entries)
        entries(entryIndex).name = erase(entries(entryIndex).name, '.chunk');
    end
end
if isempty(entries)
    return
end
[~, newestIndex] = max([entries.datenum]);
partialPath = fullfile(folderPath, entries(newestIndex).name);
end

function moveFileWithFallback(sourcePath, destinationPath)
[moved, message] = movefile(sourcePath, destinationPath, 'f');
if moved
    return
end
[copied, copyMessage] = copyfile(sourcePath, destinationPath, 'f');
if ~copied
    error('download:DownloadManager:fileTransferFailed', ...
          'Could not move or copy "%s" to "%s": %s %s', ...
          sourcePath, destinationPath, message, copyMessage)
end
delete(sourcePath)
end

function restoreBackup(task)
if isempty(task.BackupPath) || ~isfile(task.BackupPath)
    return
end
if isfile(task.FinalPath) || isfolder(task.FinalPath)
    return
end
try
    moveFileWithFallback(task.BackupPath, task.FinalPath)
catch
end
end

function deleteIfExists(filePath)
if ~isempty(filePath) && (isfile(filePath) || isfolder(filePath))
    delete(filePath)
end
end

function cleanupTemporaryFiles(task)
deleteIfExists(task.PartialPath)
deleteIfExists(task.ChunkPath)
deleteIfExists(task.BackupPath)
end

function exists = pathExists(filePath)
exists = isfile(filePath) || isfolder(filePath);
end

function ensureFolder(folderPath)
if isempty(folderPath)
    error('download:DownloadManager:missingTempPath', ...
          'TempFolder must not be empty.')
end
if ~isfolder(folderPath)
    [created, message] = mkdir(folderPath);
    if ~created && ~isfolder(folderPath)
        error('download:DownloadManager:tempPathUnavailable', '%s', message)
    end
end
end

function validateDownloader(downloader)
if isempty(downloader)
    error('download:DownloadManager:invalidDownloader', ...
          'DownloaderFactory returned an empty value.')
end
for methodName = {'start', 'pause', 'resume', 'stop'}
    if ~ismethod(downloader, methodName{1})
        error('download:DownloadManager:invalidDownloader', ...
              'DownloaderFactory result does not implement %s.', methodName{1})
    end
end
for propertyName = {'ProgressFcn', 'CompletedFcn', 'ErrorFcn'}
    if ~isprop(downloader, propertyName{1})
        error('download:DownloadManager:invalidDownloader', ...
              'DownloaderFactory result does not expose %s.', propertyName{1})
    end
end
end

function value = uniqueTargetPath(filePath)
[folderPath, baseName, extension] = fileparts(filePath);
value = filePath;
index = 1;
while isfile(value) || isfolder(value)
    value = fullfile(folderPath, sprintf('%s (%d)%s', baseName, index, extension));
    index = index + 1;
end
end

function invokeCallback(callback, varargin)
if isempty(callback)
    return
end
try
    callback(varargin{:})
catch
end
end
