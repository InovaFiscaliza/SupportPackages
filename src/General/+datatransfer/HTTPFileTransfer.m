classdef HTTPFileTransfer < handle
    % HTTPFILETRANSFER Own provider-neutral asynchronous HTTP transfer lifecycle.
    %
    % Preparation resolves download metadata or upload capabilities before a
    % worker starts. Context hooks allow adapters to supply opaque credentials.

    properties (SetAccess = private)
        Direction (1,:) char
        URL (1,:) char
        TaskID (1,:) char
        TempFolder (1,:) char
        FileName (1,:) char
        LocalPath (1,:) char
        PartialPath (1,:) char = ''
        TransferredBytes (1,1) double = 0
        TotalBytes = []
        IsRunning (1,1) logical = false
        IsPaused (1,1) logical = false
        IsResumable (1,1) logical = false
        ResolvedProtocol (1,:) char = ''
        UploadURL (1,:) char = ''
        UploadOffset (1,1) double = 0
        TusMaxSize (1,1) double = inf
    end

    properties
        ProgressFcn = []
        CompletedFcn = []
        ErrorFcn = []
        StateFcn = []
    end

    properties (Access = protected, Transient, NonCopyable)
        RequestContextProvider = []
    end

    properties (Access = private, Transient, NonCopyable)
        Request
        RequestContext
        ChunkSize (1,1) double
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
        function obj = HTTPFileTransfer(requestOrContextProvider, request, chunkSize, maxRetries)
            % HTTPFILETRANSFER Create a transfer; an optional first provider is opaque to this class.
            arguments
                requestOrContextProvider
                request = []
                chunkSize (1,1) double {mustBeInteger, mustBePositive} = 1024*1024
                maxRetries (1,1) double {mustBeInteger, mustBeNonnegative} = 3
            end

            if isstruct(requestOrContextProvider) && isscalar(requestOrContextProvider)
                if ~isempty(request)
                    error('datatransfer:HTTPFileTransfer:invalidRequest', ...
                          'Uma solicitação sem provedor não aceita um segundo argumento de solicitação.')
                end
                transferRequest = requestOrContextProvider;
                contextProvider = [];
            else
                transferRequest = request;
                contextProvider = requestOrContextProvider;
            end
            if ~isstruct(transferRequest) || ~isscalar(transferRequest)
                error('datatransfer:HTTPFileTransfer:invalidRequest', ...
                      'A solicitação de transferência deve ser um struct escalar.')
            end

            obj.Request = normalizeRequest(transferRequest);
            obj.RequestContextProvider = contextProvider;
            obj.Direction = obj.Request.Direction;
            obj.URL = obj.Request.URL;
            obj.TaskID = obj.Request.TaskID;
            obj.TempFolder = obj.Request.TempFolder;
            obj.FileName = obj.Request.FileName;
            obj.LocalPath = obj.Request.LocalPath;
            obj.PartialPath = obj.Request.PartialPath;
            obj.UploadURL = obj.Request.UploadURL;
            obj.UploadOffset = obj.Request.UploadOffset;
            obj.ResolvedProtocol = obj.Request.ResolvedProtocol;
            obj.TusMaxSize = obj.Request.TusMaxSize;
            obj.SourcePrepared = obj.Request.SourcePrepared;
            obj.ChunkSize = chunkSize;
            obj.MaxRetries = maxRetries;
            if strcmp(obj.Direction, 'upload')
                obj.TotalBytes = fieldOr(obj.Request, 'LocalBytes', []);
            end
            if obj.SourcePrepared
                if strcmp(obj.Direction, 'download')
                    obj.IsResumable = true;
                else
                    obj.IsResumable = strcmp(obj.ResolvedProtocol, 'tus');
                end
            end
        end

        %-----------------------------------------------------------------%
        function info = prepare(obj)
            % PREPARE Resolve download metadata or upload capabilities before worker execution.
            if obj.SourcePrepared
                info = prepareInfo(obj);
                return
            end

            obj.AuthenticationRetried = false;
            context = acquireContext(obj, obj.URL);
            obj.RequestContext = context;
            if strcmp(obj.Direction, 'download')
                checkContentDisposition = obj.Request.AllowSourceFilename;
                metadata = datatransfer.downloadSourceMetadata( ...
                    obj.URL, context, checkContentDisposition);
                if metadata.NeedsAuthentication
                    context = reauthenticate(obj, obj.URL);
                    obj.RequestContext = context;
                    obj.AuthenticationRetried = true;
                    metadata = datatransfer.downloadSourceMetadata( ...
                        obj.URL, context, checkContentDisposition);
                end
                if metadata.NeedsAuthentication
                    error('datatransfer:HTTPFileTransfer:authenticationRequired', ...
                          'A autenticação é necessária para preparar "%s".', obj.URL)
                end

                if checkContentDisposition && ...
                        ~isempty(metadata.ContentDispositionFileName)
                    obj.FileName = metadata.ContentDispositionFileName;
                end
                obj.LocalPath = fullfile(fileparts(obj.LocalPath), obj.FileName);
                obj.PartialPath = fullfile(obj.TempFolder, ...
                    [obj.TaskID, '_', obj.FileName, '.part']);
                obj.Request.FileName = obj.FileName;
                obj.Request.LocalPath = obj.LocalPath;
                obj.Request.PartialPath = obj.PartialPath;
                obj.Request.ChunkPath = [obj.PartialPath, '.chunk'];
                obj.IsResumable = true;
            else
                senderFcn = @(url, requestContext, method, options) ...
                    sendUploadPreflight(obj, url, requestContext, method, options);
                capabilities = datatransfer.uploadCapabilities( ...
                    obj.URL, context, obj.Request, senderFcn);
                if capabilities.NeedsAuthentication
                    error('datatransfer:HTTPFileTransfer:authenticationRequired', ...
                          'A autenticação é necessária para preparar "%s".', obj.URL)
                end
                obj.ResolvedProtocol = capabilities.ResolvedProtocol;
                obj.IsResumable = capabilities.IsResumable;
                obj.TusMaxSize = capabilities.TusMaxSize;
                obj.Request.ResolvedProtocol = obj.ResolvedProtocol;
                obj.Request.TusMaxSize = obj.TusMaxSize;
                obj.Request.MaxUploadBytes = fieldOr( ...
                    obj.Request, 'MaxUploadBytes', 200 * 1024^2);
            end

            obj.SourcePrepared = true;
            obj.Request.SourcePrepared = true;
            info = prepareInfo(obj);
        end

        %-----------------------------------------------------------------%
        function start(obj)
            % START Prepare and launch the direction-specific worker asynchronously.
            if obj.IsRunning
                return
            end
            prepare(obj)
            obj.AuthenticationRetried = false;
            if isempty(which('parfeval'))
                error('datatransfer:HTTPFileTransfer:backgroundUnavailable', ...
                      'Parallel Computing Toolbox é necessário para transferências assíncronas.')
            end
            try
                pool = backgroundPool;
            catch poolError
                error('datatransfer:HTTPFileTransfer:backgroundUnavailable', ...
                      'Não foi possível iniciar o pool em segundo plano: %s', poolError.message)
            end
            try
                startWorker(obj, pool)
            catch exception
                obj.IsRunning = false;
                obj.IsPaused = false;
                cancelFuture(obj)
                rethrow(exception)
            end
        end

        %-----------------------------------------------------------------%
        function pause(obj)
            % PAUSE Pause only resumable transfers.
            if ~obj.IsRunning || ~obj.IsResumable
                return
            end
            obj.IsPaused = true;
            obj.IsRunning = false;
            cancelFuture(obj)
        end

        %-----------------------------------------------------------------%
        function resume(obj)
            % RESUME Restart a paused transfer from its prepared state.
            if obj.IsPaused && obj.IsResumable
                start(obj)
            end
        end

        %-----------------------------------------------------------------%
        function stop(obj)
            % STOP Cancel the active worker without discarding prepared transfer state.
            obj.IsRunning = false;
            obj.IsPaused = false;
            cancelFuture(obj)
        end

        %-----------------------------------------------------------------%
        function info = summary(obj)
            % SUMMARY Return current direction-neutral transfer state.
            info = struct('TaskID', obj.TaskID, ...
                          'Direction', obj.Direction, ...
                          'URL', obj.URL, ...
                          'TempFolder', obj.TempFolder, ...
                          'FileName', obj.FileName, ...
                          'LocalPath', obj.LocalPath, ...
                          'PartialPath', obj.PartialPath, ...
                          'TransferredBytes', obj.TransferredBytes, ...
                          'TotalBytes', obj.TotalBytes, ...
                          'IsResumable', obj.IsResumable, ...
                          'ResolvedProtocol', obj.ResolvedProtocol, ...
                          'UploadURL', obj.UploadURL, ...
                          'UploadOffset', obj.UploadOffset, ...
                          'TusMaxSize', obj.TusMaxSize);
        end

        %-----------------------------------------------------------------%
        function delete(obj)
            % DELETE Cancel the worker and release its callbacks.
            stop(obj)
            obj.ProgressFcn = [];
            obj.CompletedFcn = [];
            obj.ErrorFcn = [];
            obj.StateFcn = [];
        end
    end

    methods (Access = protected)
        %-----------------------------------------------------------------%
        function context = acquireContext(~, ~)
            % ACQUIRECONTEXT Return a public request context without credentials.
            context = struct('CookieHeader', '', ...
                             'AllowedHost', '', ...
                             'AuthenticationEligible', false, ...
                             'Authenticated', false);
        end

        %-----------------------------------------------------------------%
        function context = reauthenticate(~, url)
            % REAUTHENTICATE Reject authentication-required requests by default.
            context = struct(); %#ok<NASGU>
            error('datatransfer:HTTPFileTransfer:authenticationRequired', ...
                  'Não há um provedor de autenticação para "%s".', url)
        end
    end

    methods (Access = private)
        %-----------------------------------------------------------------%
        function sent = sendUploadPreflight(obj, url, requestContext, method, options)
            context = obj.RequestContext;
            if isempty(context)
                context = requestContext;
            end
            sent = datatransfer.sendHTTPRequest(url, context, method, ...
                FollowRedirects=options.FollowRedirects, Headers=options.Headers);
            if sent.NeedsAuthentication && ~obj.AuthenticationRetried
                context = reauthenticate(obj, url);
                obj.RequestContext = context;
                obj.AuthenticationRetried = true;
                sent = datatransfer.sendHTTPRequest(url, context, method, ...
                    FollowRedirects=options.FollowRedirects, Headers=options.Headers);
            end
        end

        %-----------------------------------------------------------------%
        function startWorker(obj, pool)
            obj.IsPaused = false;
            obj.IsRunning = true;
            if strcmp(obj.Direction, 'download')
                obj.TransferredBytes = 0;
                if isfile(obj.PartialPath)
                    partialInfo = dir(obj.PartialPath);
                    obj.TransferredBytes = double(partialInfo.bytes);
                end
                obj.TotalBytes = [];
            else
                obj.TransferredBytes = obj.UploadOffset;
                obj.TotalBytes = fieldOr(obj.Request, 'LocalBytes', []);
            end
            obj.JobId = obj.JobId + uint64(1);
            jobId = obj.JobId;
            obj.ProgressQueue = parallel.pool.DataQueue;
            afterEach(obj.ProgressQueue, @(message) receiveMessage(obj, message));

            request = obj.Request;
            if strcmp(obj.Direction, 'download')
                request.PartialAction = 'none';
                worker = @datatransfer.downloadFileWorker;
                maxRetries = obj.MaxRetries;
            else
                request.ResolvedProtocol = obj.ResolvedProtocol;
                request.TusMaxSize = obj.TusMaxSize;
                request.UploadURL = obj.UploadURL;
                request.UploadOffset = obj.UploadOffset;
                request.MaxUploadBytes = fieldOr(request, 'MaxUploadBytes', 200 * 1024^2);
                request.ChunkSize = fieldOr(request, 'ChunkSize', obj.ChunkSize);
                worker = @datatransfer.uploadFileWorker;
                maxRetries = 0;
            end
            obj.Future = parfeval(pool, worker, 1, obj.RequestContext, request, ...
                                  obj.ChunkSize, maxRetries, obj.ProgressQueue, jobId);
            obj.FutureObserver = afterEach(obj.Future, ...
                @(future) workerFinished(obj, future, jobId), 0, 'PassFuture', true);
        end

        %-----------------------------------------------------------------%
        function receiveMessage(obj, message)
            if ~isvalid(obj) || ~isfield(message, 'JobId') || ...
                    message.JobId ~= obj.JobId || ~obj.IsRunning
                return
            end

            if strcmp(message.Type, 'progress')
                obj.TransferredBytes = message.TransferredBytes;
                obj.TotalBytes = message.TotalBytes;
                invokeCallback(obj.ProgressFcn, obj.TransferredBytes, obj.TotalBytes)
            elseif strcmp(message.Type, 'offset') && ...
                    isfield(message, 'UploadURL') && isfield(message, 'UploadOffset')
                obj.UploadURL = char(message.UploadURL);
                obj.UploadOffset = double(message.UploadOffset);
                obj.Request.UploadURL = obj.UploadURL;
                obj.Request.UploadOffset = obj.UploadOffset;
                obj.TransferredBytes = obj.UploadOffset;
                notifyState(obj)
            end
        end

        %-----------------------------------------------------------------%
        function workerFinished(obj, future, jobId)
            if ~isvalid(obj) || jobId ~= obj.JobId || ~obj.IsRunning
                return
            end

            try
                result = fetchOutputs(future);
            catch exception
                obj.IsRunning = false;
                obj.Future = [];
                obj.FutureObserver = [];
                obj.ProgressQueue = [];
                if strcmp(obj.Direction, 'upload')
                    errorInfo = errorSummary(exception, [], true);
                    invokeCallback(obj.ErrorFcn, errorInfo)
                else
                    invokeCallback(obj.ErrorFcn, exception)
                end
                return
            end

            obj.IsRunning = false;
            obj.Future = [];
            obj.FutureObserver = [];
            obj.ProgressQueue = [];
            obj.TransferredBytes = result.TransferredBytes;
            obj.TotalBytes = result.TotalBytes;
            if strcmp(obj.Direction, 'upload')
                obj.UploadURL = char(fieldOr(result, 'UploadURL', obj.UploadURL));
                obj.UploadOffset = double(fieldOr(result, 'UploadOffset', obj.UploadOffset));
                obj.ResolvedProtocol = char(fieldOr(result, ...
                    'ResolvedProtocol', obj.ResolvedProtocol));
                obj.Request.UploadURL = obj.UploadURL;
                obj.Request.UploadOffset = obj.UploadOffset;
            end
            retrySafeUploadAuthentication = strcmp(obj.Direction, 'upload') && ...
                strcmp(obj.ResolvedProtocol, 'tus') && ...
                ~fieldOr(result, 'OutcomeUncertain', true) && ...
                ~isempty(fieldOr(result, 'UploadURL', obj.UploadURL));
            if result.NeedsAuthentication && ~obj.AuthenticationRetried && ...
                    (strcmp(obj.Direction, 'download') || retrySafeUploadAuthentication)
                if strcmp(obj.Direction, 'upload')
                    notifyState(obj)
                end
                try
                    obj.AuthenticationRetried = true;
                    obj.RequestContext = reauthenticate(obj, obj.URL);
                    startWorker(obj, backgroundPool)
                catch exception
                    obj.IsRunning = false;
                    obj.IsPaused = false;
                    cancelFuture(obj)
                    invokeCallback(obj.ErrorFcn, exception)
                end
                return
            end
            if strcmp(obj.Direction, 'download')
                if isfield(result, 'ResolvedFileName') && ~isempty(result.ResolvedFileName)
                    obj.FileName = char(result.ResolvedFileName);
                    obj.LocalPath = fullfile(fileparts(obj.LocalPath), obj.FileName);
                end
                obj.Request.FileName = obj.FileName;
                obj.Request.LocalPath = obj.LocalPath;
            end
            notifyState(obj)

            if result.Success
                if strcmp(obj.Direction, 'upload')
                    info = result;
                    info.TaskID = obj.TaskID;
                    info.Direction = obj.Direction;
                    info.URL = obj.URL;
                    info.LocalPath = obj.LocalPath;
                    info.FileName = obj.FileName;
                else
                    info = obj.summary();
                end
                invokeCallback(obj.CompletedFcn, info)
                return
            end

            exception = fieldOr(result, 'Error', []);
            if isempty(exception)
                exception = MException( ...
                    'datatransfer:HTTPFileTransfer:workerFailed', ...
                    'O worker de transferência terminou sem sucesso.');
            end
            if strcmp(obj.Direction, 'upload')
                errorInfo = errorSummary(exception, ...
                    fieldOr(result, 'StatusCode', []), ...
                    fieldOr(result, 'OutcomeUncertain', false));
                invokeCallback(obj.ErrorFcn, errorInfo)
            else
                invokeCallback(obj.ErrorFcn, exception)
            end
        end

        %-----------------------------------------------------------------%
        function cancelFuture(obj)
            obj.JobId = obj.JobId + uint64(1);
            if ~isempty(obj.Future) && isvalid(obj.Future)
                try
                    if ~strcmp(obj.Future.State, 'finished')
                        cancel(obj.Future)
                    end
                catch
                end
            end
            obj.Future = [];
            obj.FutureObserver = [];
            obj.ProgressQueue = [];
        end

        %-----------------------------------------------------------------%
        function info = prepareInfo(obj)
            info = struct('Direction', obj.Direction, ...
                          'URL', obj.URL, ...
                          'LocalPath', obj.LocalPath, ...
                          'FileName', obj.FileName, ...
                          'TotalBytes', obj.TotalBytes, ...
                          'IsResumable', obj.IsResumable, ...
                          'ResolvedProtocol', obj.ResolvedProtocol, ...
                          'TusMaxSize', obj.TusMaxSize, ...
                          'UploadURL', obj.UploadURL, ...
                          'UploadOffset', obj.UploadOffset);
        end

        %-----------------------------------------------------------------%
        function state = protocolState(obj)
            state = struct('IsResumable', obj.IsResumable, ...
                           'ResolvedProtocol', obj.ResolvedProtocol, ...
                           'UploadURL', obj.UploadURL, ...
                           'UploadOffset', obj.UploadOffset);
        end

        %-----------------------------------------------------------------%
        function notifyState(obj)
            invokeCallback(obj.StateFcn, protocolState(obj))
        end
    end
end


function request = normalizeRequest(request)
if ~isfield(request, 'Direction') || ~ischar(request.Direction) || ...
        ~ismember(request.Direction, {'download', 'upload'})
    error('datatransfer:HTTPFileTransfer:invalidRequest', ...
          'Direction deve ser download ou upload.')
end
requiredFields = {'URL', 'TaskID', 'TempFolder', 'LocalPath', 'FileName'};
for fieldIndex = 1:numel(requiredFields)
    fieldName = requiredFields{fieldIndex};
    if ~isfield(request, fieldName) || ~ischar(request.(fieldName)) || ...
            isempty(request.(fieldName))
        error('datatransfer:HTTPFileTransfer:invalidRequest', ...
              'A solicitação deve conter o campo de texto não vazio %s.', fieldName)
    end
end
if ~isfield(request, 'AllowSourceFilename') || isempty(request.AllowSourceFilename)
    request.AllowSourceFilename = false;
end
if ~isfield(request, 'SourcePrepared') || isempty(request.SourcePrepared)
    request.SourcePrepared = false;
end
if ~isfield(request, 'PartialPath') || isempty(request.PartialPath)
    request.PartialPath = fullfile(request.TempFolder, ...
        [request.TaskID, '_', request.FileName, '.part']);
end
if ~isfield(request, 'ChunkPath') || isempty(request.ChunkPath)
    request.ChunkPath = [request.PartialPath, '.chunk'];
end
if ~isfield(request, 'Protocol') || isempty(request.Protocol)
    request.Protocol = 'auto';
end
if ~isfield(request, 'Method') || isempty(request.Method)
    request.Method = 'POST';
end
if ~isfield(request, 'ResolvedProtocol') || isempty(request.ResolvedProtocol)
    request.ResolvedProtocol = '';
end
if ~isfield(request, 'UploadURL') || isempty(request.UploadURL)
    request.UploadURL = '';
end
if ~isfield(request, 'UploadOffset') || isempty(request.UploadOffset)
    request.UploadOffset = 0;
end
if ~isfield(request, 'TusMaxSize') || isempty(request.TusMaxSize)
    request.TusMaxSize = inf;
end
if ~isfield(request, 'ChunkSize') || isempty(request.ChunkSize)
    request.ChunkSize = 8 * 1024^2;
end
if ~isfield(request, 'MaxUploadBytes') || isempty(request.MaxUploadBytes)
    request.MaxUploadBytes = 200 * 1024^2;
end
if ~isfield(request, 'FormFieldName') || isempty(request.FormFieldName)
    request.FormFieldName = 'file';
end
if ~isfield(request, 'FormFields') || isempty(request.FormFields)
    request.FormFields = struct();
end
if ~isfield(request, 'ContentType') || isempty(request.ContentType)
    request.ContentType = 'application/octet-stream';
end
end

function value = fieldOr(source, fieldName, defaultValue)
if isstruct(source) && isfield(source, fieldName)
    value = source.(fieldName);
else
    value = defaultValue;
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

function errorInfo = errorSummary(exception, statusCode, outcomeUncertain)
identifier = 'datatransfer:HTTPFileTransfer:workerFailed';
message = 'O worker de transferência terminou sem sucesso.';
if isstruct(exception)
    identifier = fieldOr(exception, 'identifier', identifier);
    message = fieldOr(exception, 'message', message);
elseif isobject(exception)
    try
        identifier = exception.identifier;
        message = exception.message;
    catch
    end
end
errorInfo = struct('identifier', char(identifier), ...
                   'message', char(message), ...
                   'StatusCode', statusCode, ...
                   'OutcomeUncertain', logical(outcomeUncertain));
end