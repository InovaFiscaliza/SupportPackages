classdef TransferManager < handle
    % TRANSFERMANAGER Provider-neutral HTTP transfer orchestration.
    %
    % The manager owns logical task state and transfer lifecycles. It has
    % no dependency on MATLAB UI classes; callers render the snapshots sent
    % through SnapshotFcn and translate user actions into manager commands.

    properties
        CollisionPolicy (1,:) char = 'askInRow'
        PartialConflictPolicy (1,:) char = 'askInRow'
        MaxUploadBytes (1,1) double {mustBePositive} = 200 * 1024^2
        IncludeSilentTasks (1,1) logical = false
        SnapshotFcn = []
        TaskReorderedFcn = []
        CompletedFcn = []
        ErrorFcn = []
    end

    properties (SetAccess = private)
        TransferFactory
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
        function obj = TransferManager(options)
            % TRANSFERMANAGER Create the transfer manager and reconcile saved history.
            arguments
                options.TransferFactory (1,1) function_handle
                options.HistoryFile (1,:) char {mustBeNonempty}
                options.TempFolder (1,:) char = ''
                options.CollisionPolicy (1,:) char = 'askInRow'
                options.PartialConflictPolicy (1,:) char = 'askInRow'
                options.IncludeSilentTasks (1,1) logical = false
            end

            obj.TransferFactory = options.TransferFactory;
            obj.HistoryFile = absolutePath(options.HistoryFile);
            obj.TempFolder = options.TempFolder;
            if isempty(obj.TempFolder)
                obj.TempFolder = fileparts(obj.HistoryFile);
            end
            obj.TempFolder = absolutePath(obj.TempFolder);
            obj.CollisionPolicy = options.CollisionPolicy;
            obj.PartialConflictPolicy = options.PartialConflictPolicy;
            obj.IncludeSilentTasks = options.IncludeSilentTasks;
            obj.HistoryStore = datatransfer.TransferHistoryStore(obj.HistoryFile);
            obj.reconcileHistory();
        end

        function delete(obj)
            % DELETE Persist active tasks as interrupted and release their downloaders.
            if obj.IsDeleting
                return
            end
            obj.IsDeleting = true;
            for taskIndex = 1:numel(obj.Tasks)
                task = obj.Tasks{taskIndex};
                if ~isempty(task)
                    task.LifecycleState = 'interrupted';
                    task.UpdatedAt = utcNow();
                    task.ErrorIdentifier = 'datatransfer:TransferManager:interrupted';
                    task.ErrorMessage = 'Transferência interrompida: o gerenciador foi fechado.';
                    try
                        obj.persistTask(task)
                    catch
                    end
                    obj.releaseDownloader(task)
                end
            end
            obj.Tasks = {};
        end

        function taskID = addTransfer(obj, request)
            % ADDTRANSFER Require Direction, URL, LocalPath, and TempFolder; raise request errors and report outcomes through callbacks.
            request = normalizeRequest(request);
            totalBytes = [];
            if strcmp(request.Direction, 'upload')
                if ~isfile(request.LocalPath)
                    error('datatransfer:TransferManager:invalidRequest', ...
                          'O arquivo de origem do envio não existe ou não é um arquivo regular.')
                end
                localFileInfo = dir(request.LocalPath);
                if isempty(localFileInfo) || numel(localFileInfo) ~= 1 || ...
                        localFileInfo.isdir
                    error('datatransfer:TransferManager:invalidRequest', ...
                          'O arquivo de origem do envio não existe ou não é um arquivo regular.')
                end
                currentLocalBytes = double(localFileInfo.bytes);
                currentModifiedAt = timestampISO(datetime( ...
                    localFileInfo.datenum, 'ConvertFrom', 'datenum', 'TimeZone', 'local'));
                if currentLocalBytes > obj.MaxUploadBytes
                    error('datatransfer:TransferManager:uploadTooLarge', ...
                          'O arquivo excede o limite máximo de tamanho para envio.')
                end
                if isempty(request.UploadURL) || isempty(request.LocalBytes)
                    request.LocalBytes = currentLocalBytes;
                end
                if isempty(request.UploadURL) || isempty(request.LocalModifiedAt)
                    request.LocalModifiedAt = currentModifiedAt;
                end
                totalBytes = currentLocalBytes;
            end
            request.AttemptedTimestamps = obj.attemptedTimestampsFor( ...
                request.Direction, request.URL, request.LocalPath, ...
                request.AttemptedTimestamps);
            duplicateTaskID = obj.findDuplicate(request);
            if ~isempty(duplicateTaskID)
                taskID = duplicateTaskID;
                task = obj.Tasks{taskID};
                if strcmp(request.DisplayMode, 'normal') && strcmp(task.DisplayMode, 'silent')
                    task.DisplayMode = 'normal';
                    obj.Tasks{taskID} = task;
                end
                obj.notifyTaskReordered(taskID)
                return
            end

            obj.NextTaskID = obj.NextTaskID + 1;
            taskID = obj.NextTaskID;
            taskUniqueID = shortTaskID();
            if strcmp(request.Direction, 'download') && isempty(request.PartialPath)
                request.PartialPath = fullfile(request.TempFolder, ...
                                               [taskUniqueID, '_', request.FileName, '.part']);
            end
            if strcmp(request.Direction, 'download') && isempty(request.ChunkPath)
                request.ChunkPath = [request.PartialPath, '.chunk'];
            end

            task = struct('ID', taskID, ...
                          'TaskID', taskUniqueID, ...
                          'HistoryEntryID', uniqueID(), ...
                          'Direction', request.Direction, ...
                          'LogicalFileID', request.LogicalFileID, ...
                          'URL', request.URL, ...
                          'LocalPath', request.LocalPath, ...
                          'DisplayMode', request.DisplayMode, ...
                          'FileName', request.FileName, ...
                          'TempFolder', request.TempFolder, ...
                          'PartialPath', request.PartialPath, ...
                          'ChunkPath', request.ChunkPath, ...
                          'BackupPath', request.BackupPath, ...
                          'AllowSourceFilename', request.AllowSourceFilename, ...
                          'SourcePrepared', request.SourcePrepared, ...
                          'Protocol', request.Protocol, ...
                          'Method', request.Method, ...
                          'FormFieldName', request.FormFieldName, ...
                          'FormFields', request.FormFields, ...
                          'ContentType', request.ContentType, ...
                          'ChunkSize', request.ChunkSize, ...
                          'UploadURL', request.UploadURL, ...
                          'UploadOffset', request.UploadOffset, ...
                          'ResolvedProtocol', request.ResolvedProtocol, ...
                          'LocalBytes', request.LocalBytes, ...
                          'LocalModifiedAt', request.LocalModifiedAt, ...
                          'IsResumable', strcmp(request.Direction, 'download'), ...
                          'Response', [], ...
                          'SourceChangedMessage', '', ...
                          'Downloader', [], ...
                          'CallbackGeneration', 0, ...
                          'LifecycleState', 'created', ...
                          'ConflictType', '', ...
                          'CollisionAction', 'none', ...
                          'PartialAction', 'none', ...
                          'IsPaused', false, ...
                          'IsStopped', false, ...
                          'TransferredBytes', 0, ...
                          'TotalBytes', totalBytes, ...
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

            if strcmp(task.Direction, 'download') && pathExists(task.LocalPath)
                obj.setConflict(taskID, 'target')
            elseif strcmp(task.Direction, 'upload') && ~isempty(task.UploadURL)
                obj.setConflict(taskID, 'partial')
            elseif strcmp(task.Direction, 'download') && isfile(task.PartialPath)
                obj.setConflict(taskID, 'partial')
            else
                obj.startTask(taskID)
            end
        end

        function resolveConflict(obj, taskID, action)
            % RESOLVECONFLICT Apply an action to a pending target or partial-file conflict.
            task = obj.getTask(taskID);
            if isempty(task) || ~strcmp(task.LifecycleState, 'awaitingConflictDecision')
                return
            end

            allowedActions = conflictActions(task.ConflictType, ...
                                             ~isempty(task.SourceChangedMessage));
            if ~ismember(action, allowedActions)
                error('datatransfer:TransferManager:invalidConflictAction', ...
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
                fileInfo = dir(task.LocalPath);
                task.LocalBytes = double(fileInfo.bytes);
                task.LocalModifiedAt = timestampISO(datetime( ...
                    fileInfo.datenum, 'ConvertFrom', 'datenum', 'TimeZone', 'local'));
                task.TransferredBytes = fileInfo.bytes;
                task.TotalBytes = fileInfo.bytes;
                task.ProgressFraction = 1;
                task.LifecycleState = 'completed';
                task.CompletedAt = actionTime;
                task.UpdatedAt = actionTime;
                obj.Tasks{taskID} = task;
                obj.persistTask(task)
                cleanupTemporaryFiles(task)
                snapshot = obj.snapshot(task);
                info = struct('LocalPath', task.LocalPath, ...
                              'TransferredBytes', task.TransferredBytes, ...
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
                    moveFileWithFallback(task.LocalPath, task.BackupPath)
                catch exception
                    obj.failTask(taskID, exception)
                    return
                end
                task.CollisionAction = 'overwrite';
            elseif strcmp(task.ConflictType, 'target') && strcmp(action, 'uniqueName')
                task.LocalPath = uniqueLocalPath(task.LocalPath);
                [~, baseName, extension] = fileparts(task.LocalPath);
                task.FileName = [baseName, extension];
                task.PartialPath = fullfile(task.TempFolder, ...
                                            [task.TaskID, '_', task.FileName, '.part']);
                task.ChunkPath = [task.PartialPath, '.chunk'];
                task.CollisionAction = 'uniqueName';
            elseif strcmp(task.ConflictType, 'partial') && strcmp(action, 'restart')
                if strcmp(task.Direction, 'download')
                    deleteIfExists(task.PartialPath)
                    deleteIfExists(task.ChunkPath)
                    task.PartialPath = fullfile(task.TempFolder, ...
                                                [task.TaskID, '_', task.FileName, '.part']);
                    task.ChunkPath = [task.PartialPath, '.chunk'];
                else
                    fileInfo = dir(task.LocalPath);
                    if ~isfile(task.LocalPath) || isempty(fileInfo) || ...
                            numel(fileInfo) ~= 1 || fileInfo.isdir
                        exception = MException( ...
                            'datatransfer:TransferManager:sourceUnavailable', ...
                            'O arquivo de origem do envio não está disponível.');
                        obj.failTask(taskID, exception)
                        return
                    end
                    task.UploadURL = '';
                    task.UploadOffset = 0;
                    task.LocalBytes = double(fileInfo.bytes);
                    task.LocalModifiedAt = timestampISO(datetime( ...
                        fileInfo.datenum, 'ConvertFrom', 'datenum', 'TimeZone', 'local'));
                    task.TotalBytes = task.LocalBytes;
                    task.TransferredBytes = 0;
                    task.SourceChangedMessage = '';
                end
                task.PartialAction = 'restart';
            elseif strcmp(task.ConflictType, 'partial') && strcmp(action, 'resume')
                task.PartialAction = 'resume';
            end

            task.ConflictType = '';
            task.LifecycleState = 'created';
            task.UpdatedAt = utcNow();
            obj.Tasks{taskID} = task;

            if isfile(task.PartialPath) && ~strcmp(task.PartialAction, 'resume')
                if strcmp(task.Direction, 'upload')
                    obj.startTask(taskID)
                    return
                end
                obj.setConflict(taskID, 'partial')
            else
                obj.startTask(taskID)
            end
        end

        function pause(obj, taskID)
            % PAUSE Pause an active resumable transfer.
            task = obj.getTask(taskID);
            if isempty(task) || ~task.IsResumable || ...
                    ~strcmp(task.LifecycleState, 'active') || isempty(task.Downloader)
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
            % RESUME Resume a paused resumable transfer.
            task = obj.getTask(taskID);
            if isempty(task) || ~task.IsResumable || ...
                    ~strcmp(task.LifecycleState, 'paused') || isempty(task.Downloader)
                return
            end
            try
                resume(task.Downloader)
                task.IsPaused = false;
                task.LifecycleState = 'active';
                task.StartClock = tic;
                task.UpdatedAt = utcNow();
                obj.Tasks{taskID} = task;
                obj.persistTask(task)
                obj.notifySnapshot(task)
            catch exception
                obj.failTask(taskID, exception)
            end
        end

        function cancelAll(obj)
            % CANCELALL Cancel every current transfer.
            for taskID = 1:numel(obj.Tasks)
                if ~isempty(obj.Tasks{taskID})
                    obj.cancel(taskID)
                end
            end
        end

        function cancel(obj, taskID)
            % CANCEL Cancel a task and remove its history record.
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
            % RESTART Restart a task using its saved request state.
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
            if strcmp(task.Direction, 'upload')
                request.SourcePrepared = false;
                request.ResolvedProtocol = '';
                request.UploadURL = '';
                request.UploadOffset = 0;
            end
            obj.cancel(taskID)
            newTaskID = obj.addTransfer(request);
        end

        function tf = isActive(obj, filePath)
            % ISACTIVE Return whether a transfer is active for the given local path.
            tf = false;
            for taskIndex = 1:numel(obj.Tasks)
                task = obj.Tasks{taskIndex};
                if isempty(task) || task.IsStopped
                    continue
                end
                if samePath(task.LocalPath, absolutePath(filePath))
                    tf = true;
                    return
                end
            end
        end

        function snapshot = getSnapshot(obj, taskID)
            % GETSNAPSHOT Return a task snapshot, or empty when it is unavailable.
            task = obj.getTask(taskID);
            if isempty(task)
                snapshot = [];
            else
                snapshot = obj.snapshot(task);
            end
        end

        function entries = getHistory(obj)
            % GETHISTORY Return the persisted transfer history entries.
            entries = obj.HistoryStore.getEntries();
        end

        function removed = deleteHistoryEntry(obj, entryID)
            % DELETEHISTORYENTRY Delete an entry and its associated download artifacts.
            entry = obj.HistoryStore.getEntry(entryID);
            if isempty(entry)
                removed = false;
                return
            end
            if strcmp(entry.Direction, 'download')
                deleteIfExists(entry.TemporaryPath)
                deleteIfExists(entry.ChunkPath)
                deleteIfExists(entry.BackupPath)
            end
            removed = obj.HistoryStore.removeEntry(entryID);
        end

        function timestamps = attemptedTimestampsFor(obj, direction, url, localPath, extraTimestamps)
            % ATTEMPTEDTIMESTAMPSFOR Collect attempts for a direction-specific history key.
            timestamps = extraTimestamps;
            entries = obj.HistoryStore.getEntries();
            for entryIndex = 1:numel(entries)
                entry = entries(entryIndex);
                if ~strcmp(entry.Direction, direction) || ~strcmp(entry.URL, url) || ...
                    ~samePath(entry.LocalPath, localPath)
                    continue
                end
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
            % RESTARTHISTORYENTRY Restart a transfer from its persisted history entry.
            entry = obj.HistoryStore.getEntry(entryID);
            if isempty(entry)
                newTaskID = [];
                return
            end
            request = struct('Direction', entry.Direction, ...
                             'URL', entry.URL, ...
                             'LocalPath', entry.LocalPath, ...
                             'TempFolder', entry.TempFolder, ...
                             'FileName', historyRequestFileName(entry), ...
                             'LogicalFileID', entry.LogicalFileID, ...
                             'AttemptedTimestamps', {entry.AttemptedTimestamps}, ...
                             'PartialPath', '', ...
                             'ChunkPath', '', ...
                             'BackupPath', '', ...
                             'Protocol', entry.Protocol, ...
                             'ResolvedProtocol', entry.Protocol, ...
                             'UploadURL', '', ...
                             'UploadOffset', 0, ...
                             'SourcePrepared', false);
            newTaskID = obj.addTransfer(request);
            snapshot = obj.getSnapshot(newTaskID);
            if isempty(snapshot) || ~strcmp(snapshot.LifecycleState, 'awaitingConflictDecision')
                return
            end
            obj.resolveConflict(newTaskID, 'restart')
        end

        function taskIDs = restoreInterruptedTransfers(obj)
            % RESTOREINTERRUPTEDTRANSFERS Restore eligible interrupted transfers from history.
            entries = obj.HistoryStore.getEntries();
            candidateIndices = [];
            seenKeys = {};
            for entryIndex = numel(entries):-1:1
                entry = entries(entryIndex);
                if ~strcmp(entry.LifecycleState, 'interrupted')
                    continue
                end
                if strcmp(entry.Direction, 'download')
                    canRestore = ~isempty(entry.TemporaryPath) && isfile(entry.TemporaryPath);
                else
                    canRestore = ~isempty(entry.UploadURL) && isfile(entry.LocalPath);
                end
                if ~canRestore
                    continue
                end
                rowKey = historyRowKey(entry.Direction, entry.URL, entry.LocalPath);
                if any(strcmp(seenKeys, rowKey))
                    continue
                end
                seenKeys{end+1} = rowKey;
                candidateIndices(end+1) = entryIndex; %#ok<AGROW>
            end

            taskIDs = [];
            for entryIndex = fliplr(candidateIndices)
                entry = entries(entryIndex);
                request = struct('Direction', entry.Direction, ...
                                 'URL', entry.URL, ...
                                 'LocalPath', entry.LocalPath, ...
                                 'TempFolder', entry.TempFolder, ...
                                 'FileName', historyRequestFileName(entry), ...
                                 'LogicalFileID', entry.LogicalFileID, ...
                                 'AttemptedTimestamps', {entry.AttemptedTimestamps}, ...
                                 'PartialPath', '', ...
                                 'ChunkPath', '', ...
                                 'BackupPath', '', ...
                                 'Protocol', entry.Protocol, ...
                                 'ResolvedProtocol', entry.Protocol, ...
                                 'UploadURL', entry.UploadURL, ...
                                 'UploadOffset', entry.UploadOffset, ...
                                 'LocalBytes', entry.LocalBytes, ...
                                 'LocalModifiedAt', entry.LocalModifiedAt, ...
                                 'SourcePrepared', strcmp(entry.Direction, 'download'));
                if strcmp(entry.Direction, 'download')
                    request.PartialPath = entry.TemporaryPath;
                    request.ChunkPath = entry.ChunkPath;
                end
                taskIDs(end+1) = obj.addTransfer(request); %#ok<AGROW>
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
                if strcmp(task.Direction, 'upload')
                    request.MaxUploadBytes = obj.MaxUploadBytes;
                end
                downloader = obj.TransferFactory(request);
                validateDownloader(downloader)
                task.Downloader = downloader;
                task.CallbackGeneration = task.CallbackGeneration + 1;
                callbackGeneration = task.CallbackGeneration;
                obj.Tasks{taskID} = task;
                downloader.ProgressFcn = @(transferredBytes, totalBytes) ...
                    obj.onProgress(taskID, callbackGeneration, transferredBytes, totalBytes);
                downloader.CompletedFcn = @(info) ...
                    obj.onCompleted(taskID, callbackGeneration, info);
                downloader.ErrorFcn = @(exception) ...
                    obj.onError(taskID, callbackGeneration, exception);
                if isprop(downloader, 'StateFcn')
                    downloader.StateFcn = @(state) ...
                        obj.onState(taskID, callbackGeneration, state);
                end
                if task.SourcePrepared && isprop(downloader, 'IsResumable')
                    try
                        resumableValue = downloader.IsResumable;
                        if islogical(resumableValue) && isscalar(resumableValue) && ...
                                task.IsResumable ~= resumableValue
                            task.IsResumable = resumableValue;
                            obj.Tasks{taskID} = task;
                            obj.notifySnapshot(task)
                        end
                    catch
                    end
                end

                if ~task.SourcePrepared && ismethod(downloader, 'prepare')
                    sourceInfo = prepare(downloader);
                    task = obj.getTask(taskID);
                    if isempty(task) || task.IsStopped || obj.IsDeleting
                        return
                    end
                    previousIsResumable = task.IsResumable;
                    task = applySourceInfo(task, sourceInfo);
                    task.SourcePrepared = true;
                    if isprop(downloader, 'IsResumable')
                        try
                            resumableValue = downloader.IsResumable;
                            if islogical(resumableValue) && isscalar(resumableValue)
                                task.IsResumable = resumableValue;
                            end
                        catch
                        end
                    end
                    if task.IsResumable ~= previousIsResumable
                        obj.Tasks{taskID} = task;
                        obj.notifySnapshot(task)
                    end
                    obj.persistTask(task)
                end

                existingPartialPath = '';
                if strcmp(task.Direction, 'download')
                    existingPartialPath = task.PartialPath;
                    if ~isfile(existingPartialPath)
                        existingPartialPath = findPartialPath(task.TempFolder, task.FileName);
                    end
                    if ~isempty(existingPartialPath)
                        task.PartialPath = existingPartialPath;
                        task.ChunkPath = [existingPartialPath, '.chunk'];
                    end
                end

                if strcmp(task.Direction, 'download') && pathExists(task.LocalPath)
                    obj.releaseDownloader(task)
                    task.Downloader = [];
                    obj.Tasks{taskID} = task;
                    obj.setConflict(taskID, 'target')
                    return
                elseif strcmp(task.Direction, 'download') && ...
                        ~strcmp(task.PartialAction, 'resume') && ...
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
            if strcmp(conflictType, 'partial') && ...
                    strcmp(task.Direction, 'download') && isfile(task.PartialPath)
                partialInfo = dir(task.PartialPath);
                task.TransferredBytes = partialInfo.bytes;
                if ~isempty(task.TotalBytes) && task.TotalBytes > 0
                    task.ProgressFraction = min(task.TransferredBytes / task.TotalBytes, 1);
                end
            elseif strcmp(conflictType, 'partial') && strcmp(task.Direction, 'upload')
                task.TransferredBytes = task.UploadOffset;
                localFileInfo = dir(task.LocalPath);
                if ~isfile(task.LocalPath) || isempty(localFileInfo) || ...
                    numel(localFileInfo) ~= 1 || localFileInfo.isdir
                    exception = MException( ...
                        'datatransfer:TransferManager:sourceUnavailable', ...
                        'O arquivo de origem do envio não está disponível.');
                    obj.failTask(taskID, exception)
                    return
                end
                if isempty(task.LocalBytes) || ...
                    isempty(task.LocalModifiedAt) || ...
                    localFileInfo.bytes ~= task.LocalBytes || ...
                        ~strcmp(timestampISO(datetime( ...
                            localFileInfo.datenum, 'ConvertFrom', 'datenum', ...
                            'TimeZone', 'local')), task.LocalModifiedAt)
                    task.SourceChangedMessage = ...
                        'O arquivo de origem foi alterado; não é possível retomar o envio.';
                else
                    task.SourceChangedMessage = '';
                end
            elseif strcmp(conflictType, 'target') && ...
                    strcmp(task.Direction, 'download') && isfile(task.LocalPath)
                targetInfo = dir(task.LocalPath);
                task.TransferredBytes = targetInfo.bytes;
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
            if ~isempty(task.SourceChangedMessage) && strcmp(policy, 'resume')
                policy = 'askInRow';
            end
            if strcmp(policy, 'askInRow')
                obj.notifySnapshot(task)
            else
                obj.resolveConflict(taskID, policy)
            end
        end

        function onState(obj, taskID, callbackGeneration, state)
            task = obj.getTask(taskID);
            if isempty(task) || task.CallbackGeneration ~= callbackGeneration || ...
                    isempty(task.Downloader) || task.IsStopped || ...
                    ~strcmp(task.LifecycleState, 'active') || obj.IsDeleting || ...
                    ~isstruct(state) || ~isscalar(state)
                return
            end
            if isfield(state, 'IsResumable') && islogical(state.IsResumable) && ...
                    isscalar(state.IsResumable)
                task.IsResumable = state.IsResumable;
            end
            if isfield(state, 'ResolvedProtocol') && ischar(state.ResolvedProtocol) && ...
                    isrow(state.ResolvedProtocol) && ...
                    ismember(state.ResolvedProtocol, {'', 'multipart', 'raw', 'tus'})
                task.ResolvedProtocol = state.ResolvedProtocol;
            end
            if isfield(state, 'UploadURL') && ischar(state.UploadURL) && ...
                    isrow(state.UploadURL)
                task.UploadURL = state.UploadURL;
            end
            if isfield(state, 'UploadOffset') && isnumeric(state.UploadOffset) && ...
                    isscalar(state.UploadOffset) && isfinite(state.UploadOffset) && ...
                    state.UploadOffset >= 0
                task.UploadOffset = double(state.UploadOffset);
                if strcmp(task.Direction, 'upload')
                    task.TransferredBytes = task.UploadOffset;
                end
            end
            if ~isempty(task.TotalBytes) && task.TotalBytes > 0
                task.ProgressFraction = min(task.TransferredBytes / task.TotalBytes, 1);
            end
            task.UpdatedAt = utcNow();
            obj.Tasks{taskID} = task;
            obj.persistTask(task)
            obj.notifySnapshot(task)
        end

        function onProgress(obj, taskID, callbackGeneration, transferredBytes, totalBytes)
            task = obj.getTask(taskID);
            if isempty(task) || task.CallbackGeneration ~= callbackGeneration || ...
                    ~strcmp(task.LifecycleState, 'active') || obj.IsDeleting
                return
            end
            task.TransferredBytes = double(transferredBytes);
            if isempty(totalBytes)
                task.TotalBytes = [];
            else
                task.TotalBytes = double(totalBytes);
            end
            elapsedSeconds = toc(task.StartClock);
            task.ProgressSamples(end+1, :) = [elapsedSeconds, task.TransferredBytes];
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
                task.ProgressFraction = min(task.TransferredBytes / task.TotalBytes, 1);
            end
            task.UpdatedAt = utcNow();
            obj.Tasks{taskID} = task;
            obj.notifySnapshot(task)
        end

        function onCompleted(obj, taskID, callbackGeneration, info)
            task = obj.getTask(taskID);
            if isempty(task) || task.CallbackGeneration ~= callbackGeneration || ...
                    task.IsStopped || ~strcmp(task.LifecycleState, 'active') || obj.IsDeleting
                return
            end
            if ~isstruct(info)
                info = struct();
            end
            if ~isfield(info, 'LocalPath') || isempty(info.LocalPath)
                info.LocalPath = task.LocalPath;
            end
            if isfield(info, 'TransferredBytes') && isnumeric(info.TransferredBytes) && ...
                    isscalar(info.TransferredBytes) && isfinite(info.TransferredBytes) && ...
                    info.TransferredBytes >= 0
                task.TransferredBytes = double(info.TransferredBytes);
            end
            if isfield(info, 'TotalBytes')
                task.TotalBytes = info.TotalBytes;
            end
            if strcmp(task.Direction, 'download') && ~isempty(info.LocalPath)
                task.LocalPath = absolutePath(char(info.LocalPath));
                [~, baseName, extension] = fileparts(task.LocalPath);
                task.FileName = [baseName, extension];
            end
            if isfield(info, 'ResolvedProtocol') && ~isempty(info.ResolvedProtocol)
                task.ResolvedProtocol = char(info.ResolvedProtocol);
            end
            if isfield(info, 'UploadURL')
                task.UploadURL = char(info.UploadURL);
            end
            if isfield(info, 'UploadOffset') && isnumeric(info.UploadOffset) && ...
                    isscalar(info.UploadOffset) && isfinite(info.UploadOffset) && ...
                    info.UploadOffset >= 0
                task.UploadOffset = double(info.UploadOffset);
            end
            task.LifecycleState = 'completed';
            task.IsPaused = false;
            task.CompletedAt = utcNow();
            task.UpdatedAt = task.CompletedAt;
            if strcmp(task.Direction, 'download') && isfile(task.LocalPath)
                localFileInfo = dir(task.LocalPath);
                task.LocalBytes = double(localFileInfo.bytes);
                task.LocalModifiedAt = timestampISO(datetime( ...
                    localFileInfo.datenum, 'ConvertFrom', 'datenum', 'TimeZone', 'local'));
            elseif strcmp(task.Direction, 'upload')
                statusCode = [];
                if isfield(info, 'StatusCode') && isnumeric(info.StatusCode) && ...
                        isscalar(info.StatusCode) && isfinite(info.StatusCode)
                    statusCode = double(info.StatusCode);
                end
                outcomeUncertain = isfield(info, 'OutcomeUncertain') && ...
                    islogical(info.OutcomeUncertain) && isscalar(info.OutcomeUncertain) && ...
                    info.OutcomeUncertain;
                task.Response = struct('FileName', task.FileName, ...
                                       'CompletedAt', timestampISO(task.CompletedAt), ...
                                       'Success', true, ...
                                       'StatusCode', statusCode, ...
                                       'Message', 'Envio concluído.', ...
                                       'OutcomeUncertain', outcomeUncertain);
            end
            obj.persistTask(task)
            snapshot = obj.snapshot(task);
            obj.releaseDownloader(task)
            cleanupTemporaryFiles(task)
            obj.Tasks{taskID} = task;
            obj.notifySnapshot(snapshot)
            invokeCallback(obj.CompletedFcn, taskID, info, snapshot)
            obj.Tasks{taskID} = [];
        end

        function onError(obj, taskID, callbackGeneration, exception)
            task = obj.getTask(taskID);
            if isempty(task) || task.CallbackGeneration ~= callbackGeneration || ...
                    task.IsStopped || ~strcmp(task.LifecycleState, 'active') || obj.IsDeleting
                return
            end
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
            if strcmp(task.Direction, 'upload')
                statusCode = [];
                outcomeUncertain = false;
                if isstruct(exception)
                    if isfield(exception, 'StatusCode') && ...
                            isnumeric(exception.StatusCode) && ...
                            isscalar(exception.StatusCode) && isfinite(exception.StatusCode)
                        statusCode = double(exception.StatusCode);
                    end
                    if isfield(exception, 'OutcomeUncertain') && ...
                            islogical(exception.OutcomeUncertain) && ...
                            isscalar(exception.OutcomeUncertain)
                        outcomeUncertain = exception.OutcomeUncertain;
                    end
                elseif isobject(exception)
                    if isprop(exception, 'StatusCode')
                        try
                            statusCode = exception.StatusCode;
                        catch
                        end
                    end
                    if isprop(exception, 'OutcomeUncertain')
                        try
                            outcomeUncertain = logical(exception.OutcomeUncertain);
                        catch
                        end
                    end
                end
                if ~isnumeric(statusCode) || ~isscalar(statusCode) || ~isfinite(statusCode)
                    statusCode = [];
                else
                    statusCode = double(statusCode);
                end
                if ~islogical(outcomeUncertain) || ~isscalar(outcomeUncertain)
                    outcomeUncertain = false;
                end
                task.Response = struct('FileName', task.FileName, ...
                                       'CompletedAt', timestampISO(task.UpdatedAt), ...
                                       'Success', false, ...
                                       'StatusCode', statusCode, ...
                                       'Message', exception.message, ...
                                       'OutcomeUncertain', outcomeUncertain);
            end
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
                if isprop(downloader, 'StateFcn')
                    downloader.StateFcn = [];
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
                if strcmp(entry.Direction, 'download') && isfile(entry.TemporaryPath)
                    fileInfo = dir(entry.TemporaryPath);
                    entry.TransferredBytes = double(fileInfo.bytes);
                end
                if ismember(entry.LifecycleState, ...
                        {'created', 'active', 'awaitingConflictDecision'})
                    entry.LifecycleState = 'interrupted';
                    entry.ErrorMessages{end+1} = ...
                        'Transferência interrompida antes de o gerenciador reiniciar.';
                    entry.UpdatedAt = timestampISO(utcNow());
                end
                if strcmp(entry.Direction, 'upload')
                    entry.isAvailable = isfile(entry.LocalPath);
                else
                    entry.isAvailable = strcmp(entry.LifecycleState, 'completed') && ...
                                        isfile(entry.LocalPath);
                end
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
                if ~isempty(entry.LocalPath)
                    referencedPaths{end+1} = absolutePath(entry.LocalPath); %#ok<AGROW>
                end
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
                        datatransfer.moveToTrash(filePath)
                    catch exception
                        warning('datatransfer:TransferManager:temporaryCleanupFailed', ...
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
                if ~strcmp(task.Direction, request.Direction)
                    continue
                end
                if strcmp(request.Direction, 'download')
                    isDuplicate = strcmp(task.URL, request.URL) && ...
                                  strcmpi(task.FileName, request.FileName);
                else
                    isDuplicate = strcmp(task.URL, request.URL) && ...
                                  samePath(task.LocalPath, request.LocalPath);
                end
                if isDuplicate
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
                           'Direction', task.Direction, ...
                           'LogicalFileID', task.LogicalFileID, ...
                           'URL', task.URL, ...
                           'LocalPath', task.LocalPath, ...
                           'DisplayMode', task.DisplayMode, ...
                           'FileName', task.FileName, ...
                           'TempFolder', task.TempFolder, ...
                           'PartialPath', task.PartialPath, ...
                           'ChunkPath', task.ChunkPath, ...
                           'BackupPath', task.BackupPath, ...
                           'LifecycleState', task.LifecycleState, ...
                           'ConflictType', task.ConflictType, ...
                           'CollisionAction', task.CollisionAction, ...
                           'PartialAction', task.PartialAction, ...
                           'IsPaused', task.IsPaused, ...
                           'IsStopped', task.IsStopped, ...
                           'IsResumable', task.IsResumable, ...
                           'TransferredBytes', task.TransferredBytes, ...
                           'TotalBytes', task.TotalBytes, ...
                           'ProgressFraction', task.ProgressFraction, ...
                           'TransferRate', task.TransferRate, ...
                           'MeasuredSpeed', finiteRate(task.LastMeasuredRate), ...
                           'RateSource', rateSource(task.LastMeasuredRate), ...
                           'isAvailable', (strcmp(task.Direction, 'upload') && ...
                                          isfile(task.LocalPath)) || ...
                                          (strcmp(task.Direction, 'download') && ...
                                          strcmp(task.LifecycleState, 'completed') && ...
                                          isfile(task.LocalPath)), ...
                           'ResolvedProtocol', task.ResolvedProtocol, ...
                           'Response', task.Response, ...
                           'LocalBytes', task.LocalBytes, ...
                           'LocalModifiedAt', task.LocalModifiedAt, ...
                           'SourceChangedMessage', task.SourceChangedMessage, ...
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
        function set.MaxUploadBytes(obj, value)
            % SET.MAXUPLOADBYTES Validate the maximum upload size.
            if ~isnumeric(value) || ~isscalar(value) || isnan(value) || value <= 0
                error('datatransfer:TransferManager:invalidUploadLimit', ...
                      'O limite máximo de envio deve ser positivo.')
            end
            obj.MaxUploadBytes = double(value);
        end

        function set.CollisionPolicy(obj, value)
            value = char(value);
            if ~ismember(value, {'askInRow', 'overwrite', 'uniqueName', 'reject'})
                error('datatransfer:TransferManager:invalidCollisionPolicy', ...
                      'CollisionPolicy is not supported.')
            end
            obj.CollisionPolicy = value;
        end

        function set.PartialConflictPolicy(obj, value)
            value = char(value);
            if ~ismember(value, {'askInRow', 'resume', 'restart', 'cancel'})
                error('datatransfer:TransferManager:invalidPartialConflictPolicy', ...
                      'PartialConflictPolicy is not supported.')
            end
            obj.PartialConflictPolicy = value;
        end
    end
end


function fileName = historyRequestFileName(entry)
[~, baseName, extension] = fileparts(entry.LocalPath);
fileName = [baseName, extension];
% Non-terminal entries carry no remote name, so they fall back to the local basename.
if strcmp(entry.Direction, 'upload') && isstruct(entry.Response) && ...
        isscalar(entry.Response) && isfield(entry.Response, 'FileName') && ...
        ~isempty(entry.Response.FileName)
    [fileName, isUseful] = datatransfer.transferFileName( ...
        char(entry.Response.FileName), SanitizeOnly=true);
    if ~isUseful
        error('datatransfer:TransferManager:invalidRequest', ...
              'FileName do envio fica vazio após a validação de segurança.')
    end
end
end

function request = normalizeRequest(request)
if ~isstruct(request) || ~isscalar(request)
    error('datatransfer:TransferManager:invalidRequest', ...
          'A solicitação de transferência deve ser uma estrutura escalar.')
end
if ~isfield(request, 'Direction')
    error('datatransfer:TransferManager:invalidRequest', ...
          'Direction deve ser download ou upload.')
end
if isstring(request.Direction) && isscalar(request.Direction)
    request.Direction = char(request.Direction);
end
if ~ischar(request.Direction) || ~isrow(request.Direction) || ...
        ~ismember(request.Direction, {'download', 'upload'})
    error('datatransfer:TransferManager:invalidRequest', ...
          'Direction deve ser download ou upload.')
end
requiredFields = {'URL', 'LocalPath', 'TempFolder'};
for fieldIndex = 1:numel(requiredFields)
    fieldName = requiredFields{fieldIndex};
    if ~isfield(request, fieldName)
        error('datatransfer:TransferManager:invalidRequest', ...
              'A solicitação deve conter o campo %s.', fieldName)
    end
    fieldValue = request.(fieldName);
    if isstring(fieldValue) && isscalar(fieldValue)
        fieldValue = char(fieldValue);
    end
    if ~ischar(fieldValue) || ~isrow(fieldValue) || isempty(fieldValue)
        error('datatransfer:TransferManager:invalidRequest', ...
              'O campo %s deve ser um texto não vazio.', fieldName)
    end
    request.(fieldName) = fieldValue;
end
request.URL = char(request.URL);
request.LocalPath = absolutePath(char(request.LocalPath));
request.TempFolder = absolutePath(char(request.TempFolder));
if isfield(request, 'FileName') && isstring(request.FileName) && ...
        isscalar(request.FileName)
    request.FileName = char(request.FileName);
end
if ~isfield(request, 'FileName') || isempty(request.FileName)
    if strcmp(request.Direction, 'upload')
        [~, baseName, extension] = fileparts(request.LocalPath);
        request.FileName = [baseName, extension];
    else
        error('datatransfer:TransferManager:invalidRequest', ...
              'FileName é obrigatório para transferências de download.')
    end
elseif ~ischar(request.FileName) || ~isrow(request.FileName)
    error('datatransfer:TransferManager:invalidRequest', ...
          'FileName deve ser um texto.')
end
if strcmp(request.Direction, 'upload')
    [request.FileName, isUseful] = datatransfer.transferFileName( ...
        request.FileName, SanitizeOnly=true);
    if ~isUseful
        error('datatransfer:TransferManager:invalidRequest', ...
              'FileName do envio fica vazio após a validação de segurança.')
    end
else
    [~, localBaseName, localExtension] = fileparts(request.LocalPath);
    localFileName = [localBaseName, localExtension];
    if ~strcmp(request.FileName, localFileName)
        request.LocalPath = absolutePath(fullfile( ...
            fileparts(request.LocalPath), request.FileName));
    end
end
if ~isfield(request, 'DisplayMode') || isempty(request.DisplayMode)
    request.DisplayMode = 'normal';
elseif isstring(request.DisplayMode) && isscalar(request.DisplayMode)
    request.DisplayMode = char(request.DisplayMode);
elseif ~ischar(request.DisplayMode)
    error('datatransfer:TransferManager:invalidRequest', ...
          'DisplayMode must be normal or silent.')
end
if ~ismember(request.DisplayMode, {'normal', 'silent'})
    error('datatransfer:TransferManager:invalidRequest', ...
          'DisplayMode must be normal or silent.')
end
if ~isfield(request, 'AttemptedTimestamps') || isempty(request.AttemptedTimestamps)
    request.AttemptedTimestamps = {};
elseif isstring(request.AttemptedTimestamps)
    request.AttemptedTimestamps = cellstr(request.AttemptedTimestamps);
elseif ischar(request.AttemptedTimestamps)
    request.AttemptedTimestamps = {request.AttemptedTimestamps};
elseif ~iscell(request.AttemptedTimestamps)
    error('datatransfer:TransferManager:invalidRequest', ...
          'AttemptedTimestamps must be a string array.')
end
if isfield(request, 'LogicalFileID') && ...
        isstring(request.LogicalFileID) && isscalar(request.LogicalFileID)
    request.LogicalFileID = char(request.LogicalFileID);
elseif isfield(request, 'LogicalFileID') && ...
        ~isempty(request.LogicalFileID) && ~ischar(request.LogicalFileID)
    error('datatransfer:TransferManager:invalidRequest', ...
          'LogicalFileID must be a character vector or scalar string.')
end
if ~isfield(request, 'LogicalFileID') || isempty(request.LogicalFileID)
    request.LogicalFileID = logicalFileID( ...
        request.Direction, request.URL, request.LocalPath);
end
if strcmp(request.Direction, 'upload')
    request.PartialPath = '';
    request.ChunkPath = '';
    request.BackupPath = '';
elseif ~isfield(request, 'PartialPath') || isempty(request.PartialPath)
    request.PartialPath = '';
else
    request.PartialPath = absolutePath(char(request.PartialPath));
end
if strcmp(request.Direction, 'download') && ...
        (~isfield(request, 'ChunkPath') || isempty(request.ChunkPath))
    request.ChunkPath = '';
elseif strcmp(request.Direction, 'download')
    request.ChunkPath = absolutePath(char(request.ChunkPath));
end
if strcmp(request.Direction, 'download') && ~isfield(request, 'BackupPath')
    request.BackupPath = '';
elseif strcmp(request.Direction, 'download') && ~isempty(request.BackupPath)
    request.BackupPath = absolutePath(char(request.BackupPath));
end
if ~isfield(request, 'AllowSourceFilename') || isempty(request.AllowSourceFilename)
    request.AllowSourceFilename = false;
end
if ~isfield(request, 'SourcePrepared') || isempty(request.SourcePrepared)
    request.SourcePrepared = false;
end
uploadTextFields = {'Protocol', 'Method', 'FormFieldName', 'ContentType', ...
                    'UploadURL', 'ResolvedProtocol', 'LocalModifiedAt'};
if strcmp(request.Direction, 'upload')
    uploadDefaults = {'auto', 'POST', 'file', '', '', '', ''};
else
    uploadDefaults = {'', '', '', '', '', '', ''};
end
for fieldIndex = 1:numel(uploadTextFields)
    fieldName = uploadTextFields{fieldIndex};
    if ~isfield(request, fieldName) || isempty(request.(fieldName))
        request.(fieldName) = uploadDefaults{fieldIndex};
    elseif isstring(request.(fieldName)) && isscalar(request.(fieldName))
        request.(fieldName) = char(request.(fieldName));
    end
    if ~ischar(request.(fieldName)) || ...
            (~isrow(request.(fieldName)) && ~isempty(request.(fieldName)))
        error('datatransfer:TransferManager:invalidRequest', ...
              '%s deve ser um texto.', fieldName)
    end
end
if ~ismember(request.ResolvedProtocol, {'', 'multipart', 'raw', 'tus'})
    error('datatransfer:TransferManager:invalidRequest', ...
          'ResolvedProtocol deve ser vazio, multipart, raw ou tus.')
end
if strcmp(request.Direction, 'upload')
    if ~ismember(request.Protocol, {'auto', 'multipart', 'raw', 'tus'}) || ...
            ~ismember(request.Method, {'POST', 'PUT'}) || ...
            (strcmp(request.Protocol, 'multipart') && strcmp(request.Method, 'PUT'))
        error('datatransfer:TransferManager:invalidRequest', ...
              'Protocol ou Method não é válido para o envio.')
    end
    if isempty(regexp(request.FormFieldName, '^[A-Za-z0-9_.-]{1,64}$', 'once'))
        error('datatransfer:TransferManager:invalidRequest', ...
              'FormFieldName deve conter de 1 a 64 caracteres permitidos.')
    end
    if ~isfield(request, 'FormFields') || isempty(request.FormFields)
        request.FormFields = struct();
    end
    if ~isstruct(request.FormFields) || ~isscalar(request.FormFields)
        error('datatransfer:TransferManager:invalidRequest', ...
              'FormFields deve ser uma estrutura escalar de textos.')
    end
    formFieldNames = fieldnames(request.FormFields);
    for fieldIndex = 1:numel(formFieldNames)
        fieldName = formFieldNames{fieldIndex};
        fieldValue = request.FormFields.(fieldName);
        if isempty(regexp(fieldName, '^[A-Za-z0-9_.-]{1,64}$', 'once'))
            error('datatransfer:TransferManager:invalidRequest', ...
                  'O nome do campo adicional não é válido.')
        end
        if isstring(fieldValue) && isscalar(fieldValue)
            fieldValue = char(fieldValue);
        end
        if ~ischar(fieldValue) || (~isrow(fieldValue) && ~isempty(fieldValue))
            error('datatransfer:TransferManager:invalidRequest', ...
                  'Os valores de FormFields devem ser textos escalares.')
        end
        request.FormFields.(fieldName) = fieldValue;
    end
    if isempty(request.ContentType)
        [~, ~, extension] = fileparts(request.LocalPath);
        switch lower(extension)
            case '.txt'
                request.ContentType = 'text/plain';
            case '.csv'
                request.ContentType = 'text/csv';
            case '.json'
                request.ContentType = 'application/json';
            case '.xml'
                request.ContentType = 'application/xml';
            case '.pdf'
                request.ContentType = 'application/pdf';
            case '.zip'
                request.ContentType = 'application/zip';
            case '.png'
                request.ContentType = 'image/png';
            case {'.jpg', '.jpeg'}
                request.ContentType = 'image/jpeg';
            case '.gif'
                request.ContentType = 'image/gif';
            otherwise
                request.ContentType = 'application/octet-stream';
        end
    end
    if ~isfield(request, 'ChunkSize') || isempty(request.ChunkSize)
        request.ChunkSize = 8 * 1024^2;
    end
    if ~isnumeric(request.ChunkSize) || ~isscalar(request.ChunkSize) || ...
            ~isfinite(request.ChunkSize) || request.ChunkSize <= 0
        error('datatransfer:TransferManager:invalidRequest', ...
              'ChunkSize deve ser um número positivo e finito.')
    end
else
    request.Protocol = '';
    request.Method = '';
    request.FormFieldName = '';
    request.ContentType = '';
    request.UploadURL = '';
    request.ResolvedProtocol = '';
    request.FormFields = struct();
    request.ChunkSize = [];
    request.UploadOffset = 0;
end
if ~isfield(request, 'UploadOffset') || isempty(request.UploadOffset)
    request.UploadOffset = 0;
end
if ~isnumeric(request.UploadOffset) || ~isscalar(request.UploadOffset) || ...
        ~isfinite(request.UploadOffset) || request.UploadOffset < 0
    error('datatransfer:TransferManager:invalidRequest', ...
          'UploadOffset deve ser um número não negativo e finito.')
end
request.UploadOffset = double(request.UploadOffset);
if ~isfield(request, 'LocalBytes')
    request.LocalBytes = [];
end
if ~isempty(request.LocalBytes) && ...
        (~isnumeric(request.LocalBytes) || ~isscalar(request.LocalBytes) || ...
         ~isfinite(request.LocalBytes) || request.LocalBytes < 0)
    error('datatransfer:TransferManager:invalidRequest', ...
          'LocalBytes deve ser vazio ou um número não negativo e finito.')
end
if ~isempty(request.LocalBytes)
    request.LocalBytes = double(request.LocalBytes);
end
if ~isempty(regexp(request.LocalModifiedAt, '[\r\n]', 'once'))
    error('datatransfer:TransferManager:invalidRequest', ...
          'LocalModifiedAt não é válido.')
end
if strcmp(request.Direction, 'download')
    request.LocalBytes = [];
    request.LocalModifiedAt = '';
end
end

function request = requestFromTask(task)
request = struct('Direction', task.Direction, ...
                 'URL', task.URL, ...
                 'LocalPath', task.LocalPath, ...
                 'TaskID', task.TaskID, ...
                 'DisplayMode', task.DisplayMode, ...
                 'LogicalFileID', task.LogicalFileID, ...
                 'AttemptedTimestamps', {task.AttemptedTimestamps}, ...
                 'TempFolder', task.TempFolder, ...
                 'FileName', task.FileName, ...
                 'PartialPath', task.PartialPath, ...
                 'ChunkPath', task.ChunkPath, ...
                 'BackupPath', task.BackupPath, ...
                 'CollisionAction', task.CollisionAction, ...
                 'PartialAction', task.PartialAction, ...
                 'AllowSourceFilename', task.AllowSourceFilename, ...
                 'SourcePrepared', task.SourcePrepared, ...
                 'Protocol', task.Protocol, ...
                 'Method', task.Method, ...
                 'FormFieldName', task.FormFieldName, ...
                 'FormFields', task.FormFields, ...
                 'ContentType', task.ContentType, ...
                 'ChunkSize', task.ChunkSize, ...
                 'UploadURL', task.UploadURL, ...
                 'UploadOffset', task.UploadOffset, ...
                 'ResolvedProtocol', task.ResolvedProtocol, ...
                 'LocalBytes', task.LocalBytes, ...
                 'LocalModifiedAt', task.LocalModifiedAt);
end

function task = applySourceInfo(task, sourceInfo)
if ~isstruct(sourceInfo) || ~isscalar(sourceInfo)
    return
end
if strcmp(task.Direction, 'download') && task.AllowSourceFilename && ...
        isfield(sourceInfo, 'FileName') && ...
        ~isempty(sourceInfo.FileName)
    task.FileName = char(sourceInfo.FileName);
    task.LocalPath = absolutePath(fullfile(fileparts(task.LocalPath), task.FileName));
    task.PartialPath = fullfile(task.TempFolder, ...
                                [task.TaskID, '_', task.FileName, '.part']);
    task.ChunkPath = [task.PartialPath, '.chunk'];
end
if isfield(sourceInfo, 'ResolvedProtocol')
    resolvedProtocol = sourceInfo.ResolvedProtocol;
    if isstring(resolvedProtocol) && isscalar(resolvedProtocol)
        resolvedProtocol = char(resolvedProtocol);
    end
    if ischar(resolvedProtocol) && isrow(resolvedProtocol) && ...
            ismember(resolvedProtocol, {'', 'multipart', 'raw', 'tus'})
        task.ResolvedProtocol = resolvedProtocol;
    end
end
if isfield(sourceInfo, 'UploadURL')
    task.UploadURL = char(sourceInfo.UploadURL);
end
if isfield(sourceInfo, 'UploadOffset') && isnumeric(sourceInfo.UploadOffset) && ...
        isscalar(sourceInfo.UploadOffset) && isfinite(sourceInfo.UploadOffset) && ...
        sourceInfo.UploadOffset >= 0
    task.UploadOffset = double(sourceInfo.UploadOffset);
end
if isfield(sourceInfo, 'IsResumable') && islogical(sourceInfo.IsResumable) && ...
        isscalar(sourceInfo.IsResumable)
    task.IsResumable = sourceInfo.IsResumable;
end
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

function values = conflictActions(conflictType, sourceChanged)
if strcmp(conflictType, 'target')
    values = {'keep', 'restart', 'overwrite', 'uniqueName', 'cancel'};
else
    values = {'resume', 'restart', 'cancel'};
    if sourceChanged
        values(strcmp(values, 'resume')) = [];
    end
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
    error('datatransfer:TransferManager:fileTransferFailed', ...
          'Could not move or copy "%s" to "%s": %s %s', ...
          sourcePath, destinationPath, message, copyMessage)
end
delete(sourcePath)
end

function restoreBackup(task)
if strcmp(task.Direction, 'upload')
    return
end
if isempty(task.BackupPath) || ~isfile(task.BackupPath)
    return
end
if isfile(task.LocalPath) || isfolder(task.LocalPath)
    return
end
try
    moveFileWithFallback(task.BackupPath, task.LocalPath)
catch
end
end

function deleteIfExists(filePath)
if ~isempty(filePath) && (isfile(filePath) || isfolder(filePath))
    delete(filePath)
end
end

function cleanupTemporaryFiles(task)
if strcmp(task.Direction, 'upload')
    return
end
deleteIfExists(task.PartialPath)
deleteIfExists(task.ChunkPath)
deleteIfExists(task.BackupPath)
end

function exists = pathExists(filePath)
exists = isfile(filePath) || isfolder(filePath);
end

function ensureFolder(folderPath)
if isempty(folderPath)
    error('datatransfer:TransferManager:missingTempPath', ...
          'TempFolder must not be empty.')
end
if ~isfolder(folderPath)
    [created, message] = mkdir(folderPath);
    if ~created && ~isfolder(folderPath)
        error('datatransfer:TransferManager:tempPathUnavailable', '%s', message)
    end
end
end

function validateDownloader(downloader)
if isempty(downloader)
    error('datatransfer:TransferManager:invalidDownloader', ...
          'TransferFactory returned an empty value.')
end
for methodName = {'start', 'pause', 'resume', 'stop'}
    if ~ismethod(downloader, methodName{1})
        error('datatransfer:TransferManager:invalidDownloader', ...
              'TransferFactory result does not implement %s.', methodName{1})
    end
end
for propertyName = {'ProgressFcn', 'CompletedFcn', 'ErrorFcn'}
    if ~isprop(downloader, propertyName{1})
        error('datatransfer:TransferManager:invalidDownloader', ...
              'TransferFactory result does not expose %s.', propertyName{1})
    end
end
end

function value = uniqueLocalPath(filePath)
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
entry.Direction = task.Direction;
entry.LogicalFileID = task.LogicalFileID;
entry.TaskID = task.TaskID;
entry.URL = task.URL;
entry.LocalPath = absolutePath(task.LocalPath);
entry.TemporaryPath = task.PartialPath;
if ~isempty(entry.TemporaryPath)
    entry.TemporaryPath = absolutePath(entry.TemporaryPath);
end
entry.ChunkPath = task.ChunkPath;
entry.BackupPath = task.BackupPath;
if ~isempty(entry.ChunkPath)
    entry.ChunkPath = absolutePath(entry.ChunkPath);
end
if ~isempty(entry.BackupPath)
    entry.BackupPath = absolutePath(entry.BackupPath);
end
entry.TempFolder = absolutePath(task.TempFolder);
entry.StartedAt = timestampISO(task.StartedAt);
entry.AttemptedTimestamps = task.AttemptedTimestamps;
entry.CompletedAt = timestampISO(task.CompletedAt);
entry.UpdatedAt = timestampISO(task.UpdatedAt);
entry.LifecycleState = task.LifecycleState;
entry.TransferredBytes = double(task.TransferredBytes);
entry.MeasuredSpeed = finiteRate(task.LastMeasuredRate);
entry.RateSource = rateSource(task.LastMeasuredRate);
entry.ErrorMessages = {};
if ~isempty(task.ErrorMessage)
    entry.ErrorMessages = {task.ErrorMessage};
end
entry.isAvailable = (strcmp(task.Direction, 'upload') && isfile(task.LocalPath)) || ...
                    (strcmp(task.Direction, 'download') && ...
                     strcmp(task.LifecycleState, 'completed') && isfile(task.LocalPath));
entry.Protocol = task.ResolvedProtocol;
entry.UploadURL = task.UploadURL;
entry.UploadOffset = task.UploadOffset;
entry.LocalBytes = task.LocalBytes;
entry.LocalModifiedAt = task.LocalModifiedAt;
entry.Response = task.Response;
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

function value = logicalFileID(direction, url, localPath)
if strcmp(direction, 'download')
    value = ['url-', Hash.sha1(uint8(unicode2native(url, 'UTF-8')))];
    return
end
normalizedPath = absolutePath(localPath);
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

function key = historyRowKey(direction, url, localPath)
pathKey = absolutePath(localPath);
if ispc
    pathKey = lower(pathKey);
end
key = [direction, '|', url, '|', pathKey];
end
