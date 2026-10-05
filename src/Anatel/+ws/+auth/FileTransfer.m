classdef FileTransfer < handle

    properties (SetAccess = private)
        URL (1,:) char
        TaskID (1,:) char
        TempFolder (1,:) char
        FileName (1,:) char
        LocalPath (1,:) char
        PartialPath (1,:) char
        TransferredBytes (1,1) double = 0
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
        function obj = FileTransfer(session, request, chunkSize, maxRetries)
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
            obj.FileName        = request.FileName;
            obj.LocalPath       = request.LocalPath;
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

            context = obj.Session.getRequestContext(obj.URL);
            checkContentDisposition = isfield(obj.Request, 'AllowSourceFilename') && ...
                                      obj.Request.AllowSourceFilename;
            metadata = datatransfer.downloadSourceMetadata(obj.URL, context, checkContentDisposition);
            if metadata.NeedsAuthentication
                context = obj.Session.authenticateForRequest(obj.URL);
                metadata = datatransfer.downloadSourceMetadata(obj.URL, context, checkContentDisposition);
            end
            if metadata.NeedsAuthentication
                error('ws:auth:FileTransfer:authenticationRequired', ...
                      'Authentication is required to download "%s".', obj.URL)
            end

            if isfield(obj.Request, 'AllowSourceFilename') && obj.Request.AllowSourceFilename
                sourceFileName = metadata.ContentDispositionFileName;
                if ~isempty(sourceFileName)
                    obj.FileName = sourceFileName;
                end
            end

            obj.LocalPath = fullfile(fileparts(obj.LocalPath), obj.FileName);
            obj.PartialPath = fullfile(obj.TempFolder, [obj.TaskID, '_', obj.FileName, '.part']);
            obj.Request.FileName = obj.FileName;
            obj.Request.LocalPath = obj.LocalPath;
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
                error('ws:auth:FileTransfer:backgroundUnavailable', ...
                      'Parallel Computing Toolbox is required for background downloads.')
            end
            try
                pool = backgroundPool;
            catch poolError
                error('ws:auth:FileTransfer:backgroundUnavailable', ...
                      'Could not start the MATLAB background pool: %s', poolError.message)
            end

            obj.RequestContext = obj.Session.getRequestContext(obj.URL);
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
                          'Direction',      obj.Request.Direction, ...
                          'URL',            obj.URL, ...
                          'TempFolder',     obj.TempFolder, ...
                          'FileName',       obj.FileName, ...
                          'LocalPath',      obj.LocalPath, ...
                          'PartialPath',    obj.PartialPath, ...
                          'TransferredBytes', obj.TransferredBytes, ...
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
            obj.TransferredBytes = fileSize(obj.PartialPath);
            obj.TotalBytes    = [];
            obj.IsPaused      = false;
            obj.IsRunning     = true;
            obj.JobId         = obj.JobId + 1;
            jobId             = obj.JobId;

            obj.ProgressQueue = parallel.pool.DataQueue;
            afterEach(obj.ProgressQueue, @(message) receiveMessage(obj, message));

            request = obj.Request;
            obj.Request.PartialAction = 'none';
            obj.Future = parfeval(pool, @datatransfer.downloadFileWorker, 1, ...
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
                obj.TransferredBytes = message.TransferredBytes;
                obj.TotalBytes    = message.TotalBytes;
                if ~isempty(obj.ProgressFcn)
                    try
                        obj.ProgressFcn(obj.TransferredBytes, obj.TotalBytes)
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
            obj.TransferredBytes = result.TransferredBytes;
            obj.TotalBytes    = result.TotalBytes;

            if result.NeedsAuthentication && ~obj.AuthenticationRetried
                try
                    obj.AuthenticationRetried = true;
                    obj.RequestContext = obj.Session.authenticateForRequest(obj.URL);
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
if ~isfield(request, 'Direction') || ~ischar(request.Direction) || ...
        ~strcmp(request.Direction, 'download')
    error('ws:auth:FileTransfer:invalidRequest', ...
          'Only download requests are supported until the upload adapter exists.')
end

requiredFields = {'URL', 'TaskID', 'TempFolder', 'LocalPath', 'FileName'};
for fieldIndex = 1:numel(requiredFields)
    fieldName = requiredFields{fieldIndex};
    if ~isfield(request, fieldName) || ~ischar(request.(fieldName)) || isempty(request.(fieldName))
        error('ws:auth:FileTransfer:invalidRequest', ...
              'The download request must contain a nonempty character field named %s.', fieldName)
    end
end

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
