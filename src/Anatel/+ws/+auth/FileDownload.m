classdef FileDownload < handle

    properties (SetAccess = private)
        URL (1,:) char
        FilePath (1,:) char
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
        RequestContext
        ChunkSize  (1,1) double
        MaxRetries (1,1) double
        Future = []
        FutureObserver = []
        ProgressQueue = []
        JobId (1,1) uint64 = 0
    end


    methods
        %-----------------------------------------------------------------%
        function obj = FileDownload(session, url, filePath, chunkSize, maxRetries)
            arguments
                session    (1,1) ws.auth.F5Session
                url        (1,:) char {mustBeNonempty}
                filePath   (1,:) char {mustBeNonempty}
                chunkSize  (1,1) double {mustBeInteger, mustBePositive} = 1024*1024
                maxRetries (1,1) double {mustBeInteger, mustBeNonnegative} = 3
            end

            obj.RequestContext = session.getDownloadContext();
            obj.URL             = url;
            obj.FilePath        = filePath;
            obj.ChunkSize       = chunkSize;
            obj.MaxRetries      = maxRetries;
        end

        %-----------------------------------------------------------------%
        function start(obj)
            if obj.IsRunning
                return
            end
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

            obj.BytesReceived = fileSize(obj.FilePath);
            obj.TotalBytes    = [];
            obj.IsPaused      = false;
            obj.IsRunning     = true;
            obj.JobId         = obj.JobId + 1;
            jobId             = obj.JobId;

            obj.ProgressQueue = parallel.pool.DataQueue;
            afterEach(obj.ProgressQueue, @(message) receiveMessage(obj, message));

            obj.Future = parfeval(pool, @ws.auth.downloadFileWorker, 1, ...
                                  obj.RequestContext, obj.URL, obj.FilePath, ...
                                  obj.ChunkSize, obj.MaxRetries, obj.ProgressQueue, jobId);
            obj.FutureObserver = afterEach(obj.Future, @(future) workerFinished(obj, future, jobId), ...
                                           0, 'PassFuture', true);
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
            info = struct('FilePath',      obj.FilePath, ...
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
