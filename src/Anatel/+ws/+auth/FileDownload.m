classdef FileDownload < handle

    properties (SetAccess = private)
        URL (1,:) char
        TaskID (1,:) char
        TempFolder (1,:) char
        TargetFolder (1,:) char
        FileName (1,:) char
        FinalPath (1,:) char
        PartialPath (1,:) char
        BytesReceived (1,1) double = 0
        TotalBytes = []
        IsRunning (1,1) logical = false
        IsPaused  (1,1) logical = false
    end

    properties
        ProgressFcn = []
        CompletedFcn = []
        ErrorFcn = []
    end

    properties (Access = private, Transient, NonCopyable)
        Session
        Request
        RequestContext
        ChunkSize  (1,1) double
        MaxRetries (1,1) double
        Future = []
        FutureObserver = []
        ProgressQueue = []
        JobId (1,1) uint64 = 0
        SourcePrepared (1,1) logical = false
        AuthenticationRetried (1,1) logical = false
    end


    methods
        %-----------------------------------------------------------------%
        function obj = FileDownload(session, request, chunkSize, maxRetries)
            arguments
                session    (1,1) ws.auth.F5Session
                request    (1,1) struct
                chunkSize  (1,1) double {mustBeInteger, mustBePositive} = 1024*1024
                maxRetries (1,1) double {mustBeInteger, mustBeNonnegative} = 3
            end

            request = normalizeRequest(request);
            obj.Session        = session;
            obj.Request        = request;
            obj.URL             = request.URL;
            obj.TaskID          = request.TaskID;
            obj.TempFolder      = request.TempFolder;
            obj.TargetFolder    = request.TargetFolder;
            obj.FileName        = request.FileName;
            obj.FinalPath       = request.FinalPath;
            obj.PartialPath     = request.PartialPath;
            obj.SourcePrepared  = request.SourcePrepared;
            obj.ChunkSize       = chunkSize;
            obj.MaxRetries      = maxRetries;
        end

        %-----------------------------------------------------------------%
        function info = prepare(obj)
            % PREPARE Resolve source metadata and authenticate lazily.
            if obj.SourcePrepared
                info = obj.summary();
                return
            end

            context = obj.Session.getDownloadContext(obj.URL);
            checkContentDisposition = isfield(obj.Request, 'AllowSourceFilename') && ...
                                      obj.Request.AllowSourceFilename;
            metadata = ui.downloadSourceMetadata(obj.URL, context, checkContentDisposition);
            if metadata.NeedsAuthentication
                context = obj.Session.authenticateForDownload(obj.URL);
                metadata = ui.downloadSourceMetadata(obj.URL, context, checkContentDisposition);
            end
            if metadata.NeedsAuthentication
                error('ws:auth:FileDownload:authenticationRequired', ...
                      'Authentication is required to download "%s".', obj.URL)
            end

            if isfield(obj.Request, 'AllowSourceFilename') && obj.Request.AllowSourceFilename
                sourceFileName = metadata.ContentDispositionFileName;
                if ~isempty(sourceFileName)
                    obj.FileName = sourceFileName;
                end
            end

            obj.FinalPath = fullfile(obj.TargetFolder, obj.FileName);
            obj.PartialPath = fullfile(obj.TempFolder, [obj.TaskID, '_', obj.FileName, '.part']);
            obj.Request.FileName = obj.FileName;
            obj.Request.FinalPath = obj.FinalPath;
            obj.Request.PartialPath = obj.PartialPath;
            obj.Request.ChunkPath = [obj.PartialPath, '.chunk'];
            obj.RequestContext = context;
            obj.SourcePrepared = true;
            info = obj.summary();
        end

        %-----------------------------------------------------------------%
        function start(obj)
            if obj.IsRunning
                return
            end
            prepare(obj)
            if isempty(which('parfeval'))
                error('ws:auth:FileDownload:backgroundUnavailable', ...
                      'Parallel Computing Toolbox is required for background downloads.')
            end
            try
                pool = backgroundPool;
            catch poolError
                error('ws:auth:FileDownload:backgroundUnavailable', ...
                      'Could not start the MATLAB background pool: %s', poolError.message)
            end

            obj.RequestContext = obj.Session.getDownloadContext(obj.URL);
            obj.AuthenticationRetried = false;
            startWorker(obj, pool)
        end

        %-----------------------------------------------------------------%
        function pause(obj)
            if ~obj.IsRunning
                return
            end
            obj.IsPaused  = true;
            obj.IsRunning = false;
            cancelFuture(obj)
        end

        %-----------------------------------------------------------------%
        function resume(obj)
            if obj.IsPaused
                start(obj)
            end
        end

        %-----------------------------------------------------------------%
        function stop(obj)
            obj.IsRunning = false;
            obj.IsPaused  = false;
            cancelFuture(obj)
        end

        %-----------------------------------------------------------------%
        function info = summary(obj)
            info = struct('TaskID',         obj.TaskID, ...
                          'URL',            obj.URL, ...
                          'TempFolder',     obj.TempFolder, ...
                          'TargetFolder',   obj.TargetFolder, ...
                          'FileName',       obj.FileName, ...
                          'FinalPath',      obj.FinalPath, ...
                          'PartialPath',    obj.PartialPath, ...
                          'BytesReceived', obj.BytesReceived, ...
                          'TotalBytes',    obj.TotalBytes);
        end

        %-----------------------------------------------------------------%
        function delete(obj)
            obj.IsRunning = false;
            obj.IsPaused  = false;
            cancelFuture(obj)
        end
    end


    methods (Access = private)
        %-----------------------------------------------------------------%
        function startWorker(obj, pool)
            obj.BytesReceived = fileSize(obj.PartialPath);
            obj.TotalBytes    = [];
            obj.IsPaused      = false;
            obj.IsRunning     = true;
            obj.JobId         = obj.JobId + 1;
            jobId             = obj.JobId;

            obj.ProgressQueue = parallel.pool.DataQueue;
            afterEach(obj.ProgressQueue, @(message) receiveMessage(obj, message));

            request = obj.Request;
            obj.Request.PartialAction = 'none';
            obj.Future = parfeval(pool, @ui.downloadFileWorker, 1, ...
                                  obj.RequestContext, request, ...
                                  obj.ChunkSize, obj.MaxRetries, obj.ProgressQueue, jobId);
            obj.FutureObserver = afterEach(obj.Future, @(future) workerFinished(obj, future, jobId), ...
                                           0, 'PassFuture', true);
        end

        %-----------------------------------------------------------------%
        function receiveMessage(obj, message)
            if ~isvalid(obj) || message.JobId ~= obj.JobId || ~obj.IsRunning
                return
            end

            if strcmp(message.Type, 'progress')
                obj.BytesReceived = message.BytesReceived;
                obj.TotalBytes    = message.TotalBytes;
                if ~isempty(obj.ProgressFcn)
                    try
                        obj.ProgressFcn(obj.BytesReceived, obj.TotalBytes)
                    catch
                    end
                end
            end
        end

        %-----------------------------------------------------------------%
        function workerFinished(obj, future, jobId)
            if ~isvalid(obj) || jobId ~= obj.JobId
                return
            end

            if ~obj.IsRunning
                return
            end

            try
                result = fetchOutputs(future);
            catch exception
                obj.IsRunning = false;
                if ~isempty(obj.ErrorFcn)
                    obj.ErrorFcn(exception)
                end
                return
            end

            obj.IsRunning     = false;
            obj.BytesReceived = result.BytesReceived;
            obj.TotalBytes    = result.TotalBytes;

            if result.NeedsAuthentication && ~obj.AuthenticationRetried
                try
                    obj.AuthenticationRetried = true;
                    obj.RequestContext = obj.Session.authenticateForDownload(obj.URL);
                    startWorker(obj, backgroundPool)
                catch exception
                    if ~isempty(obj.ErrorFcn)
                        obj.ErrorFcn(exception)
                    end
                end
                return
            end

            if result.Success
                if ~isempty(obj.CompletedFcn)
                    obj.CompletedFcn(summary(obj))
                end
            elseif ~isempty(obj.ErrorFcn)
                obj.ErrorFcn(result.Error)
            end
        end

        %-----------------------------------------------------------------%
        function cancelFuture(obj)
            if isempty(obj.Future) || ~isvalid(obj.Future)
                obj.Future = [];
                return
            end

            if ~strcmp(obj.Future.State, 'finished')
                cancel(obj.Future)
            end
            obj.Future = [];
        end
    end

end


function bytes = fileSize(filePath)
    if isfile(filePath)
        fileInfo = dir(filePath);
        bytes = fileInfo.bytes;
    else
        bytes = 0;
    end
end

function request = normalizeRequest(request)
requiredFields = {'URL', 'TaskID', 'TempFolder', 'TargetFolder', 'FileName'};
for fieldIndex = 1:numel(requiredFields)
    fieldName = requiredFields{fieldIndex};
    if ~isfield(request, fieldName) || ~ischar(request.(fieldName)) || isempty(request.(fieldName))
        error('ws:auth:FileDownload:invalidRequest', ...
              'The download request must contain a nonempty character field named %s.', fieldName)
    end
end

request.FinalPath = fullfile(request.TargetFolder, request.FileName);
if ~isfield(request, 'PartialPath') || isempty(request.PartialPath)
    request.PartialPath = fullfile(request.TempFolder, [request.TaskID, '_', request.FileName, '.part']);
end
if ~isfield(request, 'ChunkPath') || isempty(request.ChunkPath)
    request.ChunkPath = [request.PartialPath, '.chunk'];
end
if ~isfield(request, 'BackupPath')
    request.BackupPath = '';
end
if ~isfield(request, 'CollisionAction') || isempty(request.CollisionAction)
    request.CollisionAction = 'none';
end
if ~isfield(request, 'PartialAction') || isempty(request.PartialAction)
    request.PartialAction = 'none';
end
if ~isfield(request, 'AllowSourceFilename') || isempty(request.AllowSourceFilename)
    request.AllowSourceFilename = false;
end
if ~isfield(request, 'SourcePrepared') || isempty(request.SourcePrepared)
    request.SourcePrepared = false;
end
end
