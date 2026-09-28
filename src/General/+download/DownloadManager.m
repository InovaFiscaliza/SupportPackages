classdef DownloadManager < handle

    % DOWNLOADMANAGER Provider-neutral transfer orchestration.
    %
    % The manager owns logical task state and downloader lifecycles. It has
    % no dependency on MATLAB UI classes; callers render the snapshots sent
    % through SnapshotFcn and translate user actions into manager commands.

    properties
        CollisionPolicy (1,:) char = 'askInRow'
        PartialConflictPolicy (1,:) char = 'askInRow'
        IncludeSilentTasks (1,1) logical = false
        SnapshotFcn = []
        TaskReorderedFcn = []
        CompletedFcn = []
        ErrorFcn = []
    end

    properties (SetAccess = private)
        DownloaderFactory
        HistoryFile (1,:) char = ''
        TempFolder (1,:) char = ''
    end

    properties (Access = private)
        Tasks = {}
        NextTaskID (1,1) double = 0
        IsDeleting (1,1) logical = false
        HistoryStore
    end

    methods
        function obj = DownloadManager(options)
            arguments
                options.DownloaderFactory (1,1) function_handle
                options.HistoryFile (1,:) char {mustBeNonempty}
                options.TempFolder (1,:) char = ''
                options.CollisionPolicy (1,:) char = 'askInRow'
                options.PartialConflictPolicy (1,:) char = 'askInRow'
                options.IncludeSilentTasks (1,1) logical = false
            end

            obj.DownloaderFactory = options.DownloaderFactory;
            obj.HistoryFile = absolutePath(options.HistoryFile);
            obj.TempFolder = options.TempFolder;
            if isempty(obj.TempFolder)
                obj.TempFolder = fileparts(obj.HistoryFile);
            end
            obj.TempFolder = absolutePath(obj.TempFolder);
            obj.CollisionPolicy = options.CollisionPolicy;
            obj.PartialConflictPolicy = options.PartialConflictPolicy;
            obj.IncludeSilentTasks = options.IncludeSilentTasks;
            obj.HistoryStore = download.DownloadHistoryStore(obj.HistoryFile);
            obj.reconcileHistory();
        end

        function delete(obj)
            if obj.IsDeleting
                return
            end
            obj.IsDeleting = true;
            for taskIndex = 1:numel(obj.Tasks)
                task = obj.Tasks{taskIndex};
                if ~isempty(task)
                    task.LifecycleState = 'interrupted';
                    task.UpdatedAt = utcNow();
                    task.ErrorIdentifier = 'download:DownloadManager:interrupted';
                    task.ErrorMessage = 'Download was interrupted when the manager closed.';
                    try
                        obj.persistTask(task)
                    catch
                    end
                    obj.releaseDownloader(task)
                end
            end
            obj.Tasks = {};
        end

        function taskID = addDownload(obj, request)
            request = normalizeRequest(request);
            request.AttemptedTimestamps = obj.attemptedTimestampsFor(request.LogicalFileID, ...
                                                                    request.AttemptedTimestamps);
            duplicateTaskID = obj.findDuplicate(request);
            if ~isempty(duplicateTaskID)
                taskID = duplicateTaskID;
                obj.notifyTaskReordered(taskID)
                return
            end

            obj.NextTaskID = obj.NextTaskID + 1;
            taskID = obj.NextTaskID;
            taskUniqueID = shortTaskID();
            if isempty(request.PartialPath)
                request.PartialPath = fullfile(request.TempFolder, ...
                                               [taskUniqueID, '_', request.FileName, '.part']);
            end
            if isempty(request.ChunkPath)
                request.ChunkPath = [request.PartialPath, '.chunk'];
            end

            task = struct('ID', taskID, ...
                          'TaskID', taskUniqueID, ...
                          'HistoryEntryID', uniqueID(), ...
                          'LogicalFileID', request.LogicalFileID, ...
                          'URL', request.URL, ...
                          'DisplayMode', request.DisplayMode, ...
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
                          'LastMeasuredRate', NaN, ...
                          'StartClock', [], ...
                          'StartedAt', datetime.empty, ...
                          'AttemptedTimestamps', {request.AttemptedTimestamps}, ...
                          'UpdatedAt', utcNow(), ...
                          'CompletedAt', datetime.empty, ...
                          'ProgressSamples', zeros(0, 2), ...
                          'ErrorIdentifier', '', ...
                          'ErrorMessage', '');
            obj.Tasks{taskID} = task;
            obj.persistTask(task)
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

            if strcmp(task.ConflictType, 'target') && strcmp(action, 'keep')
                actionTime = utcNow();
                if isempty(task.StartedAt)
                    task.StartedAt = actionTime;
                    task.AttemptedTimestamps{end+1} = timestampISO(actionTime);
                end
                fileInfo = dir(task.FinalPath);
                task.ReceivedBytes = fileInfo.bytes;
                task.TotalBytes = fileInfo.bytes;
                task.ProgressFraction = 1;
                task.LifecycleState = 'completed';
                task.CompletedAt = actionTime;
                task.UpdatedAt = actionTime;
                obj.Tasks{taskID} = task;
                obj.persistTask(task)
                cleanupTemporaryFiles(task)
                snapshot = obj.snapshot(task);
                info = struct('FinalPath', task.FinalPath, ...
                              'BytesReceived', task.ReceivedBytes, ...
                              'TotalBytes', task.TotalBytes, ...
                              'KeptExisting', true);
                obj.notifySnapshot(snapshot)
                invokeCallback(obj.CompletedFcn, taskID, info, snapshot)
                obj.Tasks{taskID} = [];
                return
            end

            if strcmp(task.ConflictType, 'target') && ...
                    ismember(action, {'restart', 'overwrite'})
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
                obj.persistTask(task)
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
                task.AttemptedTimestamps{end+1} = timestampISO(task.UpdatedAt);
                obj.Tasks{taskID} = task;
                obj.persistTask(task)
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
            obj.HistoryStore.removeEntry(task.HistoryEntryID);
            obj.notifySnapshot(snapshot)
            obj.Tasks{taskID} = [];
        end

        function newTaskID = restart(obj, taskID)
            task = obj.getTask(taskID);
            if isempty(task)
                newTaskID = [];
                return
            end
            request = requestFromTask(task);
            request.AttemptedTimestamps = task.AttemptedTimestamps;
            request.BackupPath = '';
            request.PartialPath = '';
            request.ChunkPath = '';
            request.CollisionAction = 'none';
            request.PartialAction = 'restart';
            obj.cancel(taskID)
            newTaskID = obj.addDownload(request);
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

        function entries = getHistory(obj)
            entries = obj.HistoryStore.getEntries();
        end

        function removed = deleteHistoryEntry(obj, entryID)
            entry = obj.HistoryStore.getEntry(entryID);
            if isempty(entry)
                removed = false;
                return
            end
            deleteIfExists(entry.TemporaryPath)
            deleteIfExists(entry.ChunkPath)
            deleteIfExists(entry.BackupPath)
            removed = obj.HistoryStore.removeEntry(entryID);
        end

        function timestamps = attemptedTimestampsFor(obj, logicalFileID, extraTimestamps)
            timestamps = extraTimestamps;
            entries = obj.HistoryStore.getEntries();
            matchingEntries = find(strcmp({entries.LogicalFileID}, logicalFileID));
            for entryIndex = matchingEntries
                entryTimestamps = entries(entryIndex).AttemptedTimestamps;
                for timestampIndex = 1:numel(entryTimestamps)
                    timestamp = entryTimestamps{timestampIndex};
                    if ~any(strcmp(timestamps, timestamp))
                        timestamps{end+1} = timestamp;
                    end
                end
            end
        end

        function newTaskID = restartHistoryEntry(obj, entryID)
            entry = obj.HistoryStore.getEntry(entryID);
            if isempty(entry)
                newTaskID = [];
                return
            end
            [targetFolder, baseName, extension] = fileparts(entry.TargetPath);
            request = struct('URL', entry.SourceURL, ...
                             'TempFolder', entry.TempFolder, ...
                             'TargetFolder', targetFolder, ...
                             'FileName', [baseName, extension], ...
                             'LogicalFileID', entry.LogicalFileID, ...
                             'AttemptedTimestamps', {entry.AttemptedTimestamps}, ...
                             'PartialPath', '', ...
                             'ChunkPath', '', ...
                             'BackupPath', '', ...
                             'SourcePrepared', false);
            newTaskID = obj.addDownload(request);
            snapshot = obj.getSnapshot(newTaskID);
            if isempty(snapshot) || ~strcmp(snapshot.LifecycleState, 'awaitingConflictDecision')
                return
            end
            obj.resolveConflict(newTaskID, 'restart')
        end

        function taskIDs = restoreInterruptedDownloads(obj)
            entries = obj.HistoryStore.getEntries();
            candidateIndices = [];
            seenLogicalFileIDs = {};
            seenSourceURLs = {};
            for entryIndex = numel(entries):-1:1
                entry = entries(entryIndex);
                if ~strcmp(entry.LifecycleState, 'interrupted') || ...
                        isempty(entry.TemporaryPath) || ~isfile(entry.TemporaryPath)
                    continue
                end
                alreadyRestored = false;
                for seenIndex = 1:numel(seenLogicalFileIDs)
                    if strcmp(seenLogicalFileIDs{seenIndex}, entry.LogicalFileID) && ...
                            strcmp(seenSourceURLs{seenIndex}, entry.SourceURL)
                        alreadyRestored = true;
                        break
                    end
                end
                if alreadyRestored
                    continue
                end
                seenLogicalFileIDs{end+1} = entry.LogicalFileID;
                seenSourceURLs{end+1} = entry.SourceURL;
                candidateIndices(end+1) = entryIndex; %#ok<AGROW>
            end

            taskIDs = [];
            for entryIndex = fliplr(candidateIndices)
                entry = entries(entryIndex);
                [targetFolder, baseName, extension] = fileparts(entry.TargetPath);
                request = struct('URL', entry.SourceURL, ...
                                 'TempFolder', entry.TempFolder, ...
                                 'TargetFolder', targetFolder, ...
                                 'FileName', [baseName, extension], ...
                                 'LogicalFileID', entry.LogicalFileID, ...
                                 'AttemptedTimestamps', {entry.AttemptedTimestamps}, ...
                                 'PartialPath', entry.TemporaryPath, ...
                                 'ChunkPath', entry.ChunkPath, ...
                                 'BackupPath', '', ...
                                 'SourcePrepared', true);
                taskIDs(end+1) = obj.addDownload(request); %#ok<AGROW>
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

                existingPartialPath = task.PartialPath;
                if ~isfile(existingPartialPath)
                    existingPartialPath = findPartialPath(task.TempFolder, task.FileName);
                end
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
                    task.AttemptedTimestamps{end+1} = timestampISO(task.StartedAt);
                end
                task.UpdatedAt = utcNow();
                obj.Tasks{taskID} = task;
                obj.persistTask(task)
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
            if strcmp(conflictType, 'partial') && isfile(task.PartialPath)
                partialInfo = dir(task.PartialPath);
                task.ReceivedBytes = partialInfo.bytes;
                if ~isempty(task.TotalBytes) && task.TotalBytes > 0
                    task.ProgressFraction = min(task.ReceivedBytes / task.TotalBytes, 1);
                end
            elseif strcmp(conflictType, 'target') && isfile(task.FinalPath)
                targetInfo = dir(task.FinalPath);
                task.ReceivedBytes = targetInfo.bytes;
                task.TotalBytes = targetInfo.bytes;
                task.ProgressFraction = 1;
            end
            task.UpdatedAt = utcNow();
            obj.Tasks{taskID} = task;
            obj.persistTask(task)

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
            if isfinite(task.TransferRate)
                task.LastMeasuredRate = task.TransferRate;
            end
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
            if isfield(info, 'FinalPath') && ~isempty(info.FinalPath)
                task.FinalPath = absolutePath(char(info.FinalPath));
                [task.TargetFolder, baseName, extension] = fileparts(task.FinalPath);
                task.FileName = [baseName, extension];
            end
            task.LifecycleState = 'completed';
            task.IsPaused = false;
            task.CompletedAt = utcNow();
            task.UpdatedAt = task.CompletedAt;
            obj.persistTask(task)
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
            obj.persistTask(task)
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

        function persistTask(obj, task)
            obj.HistoryStore.upsert(historyEntry(task));
        end

        function reconcileHistory(obj)
            entries = obj.HistoryStore.getEntries();
            foldersToScan = {obj.TempFolder, fileparts(obj.HistoryFile)};
            for entryIndex = 1:numel(entries)
                entry = entries(entryIndex);
                foldersToScan{end+1} = entry.TempFolder;
                if isfile(entry.TemporaryPath)
                    fileInfo = dir(entry.TemporaryPath);
                    entry.DownloadedBytes = fileInfo.bytes;
                end
                if ismember(entry.LifecycleState, ...
                        {'created', 'active', 'awaitingConflictDecision'})
                    entry.LifecycleState = 'interrupted';
                    entry.ErrorMessages{end+1} = ...
                        'Download was interrupted before the manager restarted.';
                    entry.UpdatedAt = timestampISO(utcNow());
                end
                entry.isAvailable = strcmp(entry.LifecycleState, 'completed') && ...
                                    isfile(entry.TargetPath);
                entries(entryIndex) = entry;
            end
            obj.HistoryStore.replace(entries)
            obj.cleanupUnreferencedTemporaryFiles(foldersToScan, entries)
        end

        function cleanupUnreferencedTemporaryFiles(~, foldersToScan, entries)
            foldersToScan = unique(foldersToScan, 'stable');
            referencedPaths = {};
            recoverableStates = {'paused', 'failed', 'interrupted'};
            for entryIndex = 1:numel(entries)
                entry = entries(entryIndex);
                if ~ismember(entry.LifecycleState, recoverableStates)
                    continue
                end
                if ~isempty(entry.TemporaryPath)
                    referencedPaths{end+1} = absolutePath(entry.TemporaryPath);
                end
                if ~isempty(entry.BackupPath)
                    referencedPaths{end+1} = absolutePath(entry.BackupPath);
                end
            end

            for folderIndex = 1:numel(foldersToScan)
                folderPath = foldersToScan{folderIndex};
                if isempty(folderPath) || ~isfolder(folderPath)
                    continue
                end
                files = dir(folderPath);
                files = files(~[files.isdir]);
                for fileIndex = 1:numel(files)
                    fileName = files(fileIndex).name;
                    isTaskScoped = ~isempty(regexp(fileName, ...
                                                   '^[0-9a-fA-F]{8}_', 'once'));
                    isStagingFile = endsWith(fileName, '.part') || ...
                                    endsWith(fileName, '.part.chunk') || ...
                                    contains(fileName, '_backup_');
                    if ~isTaskScoped && ~isStagingFile
                        continue
                    end
                    filePath = absolutePath(fullfile(folderPath, fileName));
                    if any(cellfun(@(path) samePath(path, filePath), referencedPaths))
                        continue
                    end
                    try
                        download.moveToTrash(filePath)
                    catch exception
                        warning('download:DownloadManager:temporaryCleanupFailed', ...
                                'Could not remove temporary file "%s": %s', ...
                                filePath, exception.message)
                    end
                end
            end
        end

        function notifySnapshot(obj, taskOrSnapshot)
            if isstruct(taskOrSnapshot) && isfield(taskOrSnapshot, 'Downloader')
                snapshot = obj.snapshot(taskOrSnapshot);
            else
                snapshot = taskOrSnapshot;
            end
            if ~obj.shouldNotifyPresentation(snapshot)
                return
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
                    if ~strcmp(task.DisplayMode, request.DisplayMode)
                        continue
                    end
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
            snapshot = obj.snapshot(task);
            if obj.shouldNotifyPresentation(snapshot)
                invokeCallback(obj.TaskReorderedFcn, snapshot)
            end
        end

        function tf = shouldNotifyPresentation(obj, snapshot)
            tf = obj.IncludeSilentTasks || ~strcmp(snapshot.DisplayMode, 'silent');
        end

        function value = snapshot(~, task)
            value = struct('ID', task.ID, ...
                           'TaskID', task.TaskID, ...
                           'HistoryEntryID', task.HistoryEntryID, ...
                           'LogicalFileID', task.LogicalFileID, ...
                           'URL', task.URL, ...
                           'DisplayMode', task.DisplayMode, ...
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
                           'MeasuredSpeed', finiteRate(task.LastMeasuredRate), ...
                           'RateSource', rateSource(task.LastMeasuredRate), ...
                           'isAvailable', strcmp(task.LifecycleState, 'completed') && ...
                                          isfile(task.FinalPath), ...
                           'StartedAt', task.StartedAt, ...
                           'AttemptedTimestamps', {task.AttemptedTimestamps}, ...
                           'UpdatedAt', task.UpdatedAt, ...
                           'CompletedAt', task.CompletedAt, ...
                           'ErrorIdentifier', task.ErrorIdentifier, ...
                           'ErrorMessage', task.ErrorMessage, ...
                           'HistoryEntry', historyEntry(task));
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
request.TempFolder = absolutePath(char(request.TempFolder));
request.TargetFolder = absolutePath(char(request.TargetFolder));
request.FileName = char(request.FileName);
if ~isfield(request, 'DisplayMode') || isempty(request.DisplayMode)
    request.DisplayMode = 'normal';
elseif isstring(request.DisplayMode) && isscalar(request.DisplayMode)
    request.DisplayMode = char(request.DisplayMode);
elseif ~ischar(request.DisplayMode)
    error('download:DownloadManager:invalidRequest', ...
          'DisplayMode must be normal or silent.')
end
if ~ismember(request.DisplayMode, {'normal', 'silent'})
    error('download:DownloadManager:invalidRequest', ...
          'DisplayMode must be normal or silent.')
end
if ~isfield(request, 'AttemptedTimestamps') || isempty(request.AttemptedTimestamps)
    request.AttemptedTimestamps = {};
elseif isstring(request.AttemptedTimestamps)
    request.AttemptedTimestamps = cellstr(request.AttemptedTimestamps);
elseif ischar(request.AttemptedTimestamps)
    request.AttemptedTimestamps = {request.AttemptedTimestamps};
elseif ~iscell(request.AttemptedTimestamps)
    error('download:DownloadManager:invalidRequest', ...
          'AttemptedTimestamps must be a string array.')
end
request.FinalPath = absolutePath(fullfile(request.TargetFolder, request.FileName));
if isfield(request, 'LogicalFileID') && ...
        isstring(request.LogicalFileID) && isscalar(request.LogicalFileID)
    request.LogicalFileID = char(request.LogicalFileID);
elseif isfield(request, 'LogicalFileID') && ...
        ~isempty(request.LogicalFileID) && ~ischar(request.LogicalFileID)
    error('download:DownloadManager:invalidRequest', ...
          'LogicalFileID must be a character vector or scalar string.')
end
if ~isfield(request, 'LogicalFileID') || isempty(request.LogicalFileID)
    request.LogicalFileID = logicalFileID(request.FinalPath);
end
if ~isfield(request, 'PartialPath') || isempty(request.PartialPath)
    request.PartialPath = '';
else
    request.PartialPath = absolutePath(char(request.PartialPath));
end
if ~isfield(request, 'ChunkPath') || isempty(request.ChunkPath)
    request.ChunkPath = '';
else
    request.ChunkPath = absolutePath(char(request.ChunkPath));
end
if ~isfield(request, 'BackupPath')
    request.BackupPath = '';
elseif ~isempty(request.BackupPath)
    request.BackupPath = absolutePath(char(request.BackupPath));
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
                 'DisplayMode', task.DisplayMode, ...
                 'LogicalFileID', task.LogicalFileID, ...
                 'AttemptedTimestamps', {task.AttemptedTimestamps}, ...
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
    values = {'keep', 'restart', 'overwrite', 'uniqueName', 'cancel'};
else
    values = {'resume', 'restart', 'cancel'};
end
end

function value = shortTaskID()
value = uniqueID();
value = value(1:min(8, numel(value)));
end

function value = uniqueID()
value = char(matlab.lang.internal.uuid());
value = lower(regexprep(value, '-', ''));
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

function entry = historyEntry(task)
entry = struct();
entry.EntryID = task.HistoryEntryID;
entry.LogicalFileID = task.LogicalFileID;
entry.TaskID = task.TaskID;
entry.SourceURL = task.URL;
entry.TargetPath = absolutePath(task.FinalPath);
entry.TemporaryPath = absolutePath(task.PartialPath);
entry.ChunkPath = task.ChunkPath;
entry.BackupPath = task.BackupPath;
entry.TempFolder = absolutePath(task.TempFolder);
entry.StartedAt = timestampISO(task.StartedAt);
entry.AttemptedTimestamps = task.AttemptedTimestamps;
entry.CompletedAt = timestampISO(task.CompletedAt);
entry.UpdatedAt = timestampISO(task.UpdatedAt);
entry.LifecycleState = task.LifecycleState;
entry.DownloadedBytes = double(task.ReceivedBytes);
entry.MeasuredSpeed = finiteRate(task.LastMeasuredRate);
entry.RateSource = rateSource(task.LastMeasuredRate);
entry.ErrorMessages = {};
if ~isempty(task.ErrorMessage)
    entry.ErrorMessages = {task.ErrorMessage};
end
entry.isAvailable = strcmp(task.LifecycleState, 'completed') && isfile(task.FinalPath);
end

function value = timestampISO(timestamp)
if isempty(timestamp)
    value = '';
    return
end
timestamp.TimeZone = 'UTC';
timestamp.Format = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
value = char(timestamp);
end

function value = finiteRate(rate)
value = [];
if isfinite(rate)
    value = double(rate);
end
end

function value = rateSource(rate)
value = 'none';
if isfinite(rate)
    value = 'measured';
end
end

function value = logicalFileID(filePath)
normalizedPath = absolutePath(filePath);
if ispc
    normalizedPath = lower(normalizedPath);
end
value = ['path-', Hash.sha1(uint8(unicode2native(normalizedPath, 'UTF-8')))];
end

function value = absolutePath(pathValue)
try
    fileObject = java.io.File(pathValue);
    value = char(fileObject.getCanonicalPath());
catch
    if startsWith(pathValue, filesep) || startsWith(pathValue, '\\') || ...
            (numel(pathValue) >= 2 && pathValue(2) == ':')
        value = pathValue;
    else
        value = fullfile(pwd, pathValue);
    end
end
end

function tf = samePath(firstPath, secondPath)
if ispc
    tf = strcmpi(firstPath, secondPath);
else
    tf = strcmp(firstPath, secondPath);
end
end
