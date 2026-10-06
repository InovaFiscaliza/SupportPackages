function result = uploadFileWorker(requestContext, request, chunkSize, maxRetries, progressQueue, jobId)
% UPLOADFILEWORKER Stream a prepared upload without mutating its source file.

result = resultTemplate(request);
try
    validatePreparedRequest(request)
    verifySource(request)
    result.TotalBytes = double(request.LocalBytes);

    effectiveLimit = min(double(request.MaxUploadBytes), double(request.TusMaxSize));
    if result.TotalBytes > effectiveLimit
        error('datatransfer:TransferManager:uploadTooLarge', ...
              'O arquivo excede o limite máximo permitido para envio.')
    end

    retryLimit = max(0, floor(double(maxRetries)));
    switch request.ResolvedProtocol
        case {'multipart', 'raw'}
            result = uploadOneShot(requestContext, request, progressQueue, jobId, result);
        case 'tus'
            if isempty(chunkSize)
                chunkSize = request.ChunkSize;
            end
            if ~isnumeric(chunkSize) || ~isscalar(chunkSize) || ...
                    ~isfinite(chunkSize) || chunkSize <= 0
                error('datatransfer:uploadFileWorker:invalidChunkSize', ...
                      'O tamanho do bloco Tus deve ser positivo e finito.')
            end
            result = uploadTus(requestContext, request, floor(double(chunkSize)), ...
                               retryLimit, progressQueue, jobId, result);
    end
catch exception
    result.Error = exception;
end
end


function validatePreparedRequest(request)
if ~isfield(request, 'ResolvedProtocol') || isempty(request.ResolvedProtocol) || ...
        strcmp(request.ResolvedProtocol, 'auto') || ...
        ~ismember(request.ResolvedProtocol, {'multipart', 'raw', 'tus'}) || ...
        ~isfield(request, 'TusMaxSize') || isempty(request.TusMaxSize)
    error('datatransfer:uploadFileWorker:unpreparedRequest', ...
          'A solicitação de envio não foi preparada com um protocolo e limite Tus.')
end
if ~isfield(request, 'Direction') || ~strcmp(request.Direction, 'upload') || ...
        ~isfield(request, 'URL') || ~ischar(request.URL) || isempty(request.URL) || ...
        ~isfield(request, 'LocalPath') || ~ischar(request.LocalPath) || ...
        ~isfield(request, 'FileName') || ~ischar(request.FileName) || ...
        ~isfield(request, 'LocalBytes') || ~isnumeric(request.LocalBytes) || ...
        ~isscalar(request.LocalBytes) || ~isfinite(request.LocalBytes) || ...
        request.LocalBytes < 0 || ~isfield(request, 'LocalModifiedAt') || ...
        isempty(request.LocalModifiedAt) || ~isfield(request, 'MaxUploadBytes') || ...
        ~isnumeric(request.MaxUploadBytes) || ~isscalar(request.MaxUploadBytes) || ...
        isnan(request.MaxUploadBytes) || request.MaxUploadBytes <= 0 || ...
        ~isnumeric(request.TusMaxSize) || ~isscalar(request.TusMaxSize) || ...
        isnan(request.TusMaxSize) || request.TusMaxSize < 0
    error('datatransfer:uploadFileWorker:invalidRequest', ...
          'A solicitação normalizada de envio está incompleta ou inválida.')
end
if ismember(request.ResolvedProtocol, {'multipart', 'raw'}) && ...
        (~isfield(request, 'Method') || ...
         ~ismember(request.Method, {'POST', 'PUT'}) || ...
         (strcmp(request.ResolvedProtocol, 'multipart') && ~strcmp(request.Method, 'POST')))
    error('datatransfer:uploadFileWorker:invalidRequest', ...
          'O método HTTP não é válido para o protocolo de envio resolvido.')
end
[safeFileName, isUseful] = datatransfer.transferFileName( ...
    request.FileName, SanitizeOnly=true);
if ~isUseful || ~strcmp(safeFileName, request.FileName)
    error('datatransfer:uploadFileWorker:invalidRequest', ...
          'O nome remoto do arquivo não passou pela validação de segurança.')
end
end


function result = resultTemplate(request)
result = struct('Success', false, ...
                'NeedsAuthentication', false, ...
                'Direction', fieldOr(request, 'Direction', 'upload'), ...
                'URL', fieldOr(request, 'URL', ''), ...
                'LocalPath', fieldOr(request, 'LocalPath', ''), ...
                'FileName', fieldOr(request, 'FileName', ''), ...
                'TransferredBytes', 0, ...
                'TotalBytes', fieldOr(request, 'LocalBytes', []), ...
                'ResolvedProtocol', fieldOr(request, 'ResolvedProtocol', ''), ...
                'UploadURL', fieldOr(request, 'UploadURL', ''), ...
                'UploadOffset', fieldOr(request, 'UploadOffset', 0), ...
                'OutcomeUncertain', false, ...
                'StatusCode', [], ...
                'ResponseHeaders', struct(), ...
                'ResponseBody', uint8.empty(0, 1), ...
                'ResponseTruncated', false, ...
                'Error', []);
end


function value = fieldOr(source, fieldName, defaultValue)
if isfield(source, fieldName)
    value = source.(fieldName);
else
    value = defaultValue;
end
end


function verifySource(request)
if ~isfile(request.LocalPath)
    error('datatransfer:uploadFileWorker:sourceUnavailable', ...
          'O arquivo de origem do envio não existe ou não é um arquivo regular.')
end
fileInfo = dir(request.LocalPath);
if isempty(fileInfo) || numel(fileInfo) ~= 1 || fileInfo.isdir
    error('datatransfer:uploadFileWorker:sourceUnavailable', ...
          'O arquivo de origem do envio não existe ou não é um arquivo regular.')
end
modifiedAt = timestampISO(datetime( ...
    fileInfo.datenum, 'ConvertFrom', 'datenum', 'TimeZone', 'local'));
if double(fileInfo.bytes) ~= double(request.LocalBytes) || ...
        ~strcmp(modifiedAt, char(request.LocalModifiedAt))
    error('datatransfer:uploadFileWorker:sourceChanged', ...
          'O arquivo de origem foi alterado desde que o envio foi preparado.')
end
end


function value = timestampISO(timestamp)
timestamp.TimeZone = 'UTC';
timestamp.Format = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
value = char(timestamp);
end


function result = uploadOneShot(requestContext, request, progressQueue, jobId, result)
progressMonitor = datatransfer.UploadProgressMonitor( ...
    progressQueue, jobId, double(request.LocalBytes));
progressMonitorFactory = @() progressMonitor;
if strcmp(request.ResolvedProtocol, 'raw')
    body = rawFileProvider(request, progressMonitor);
else
    body = multipartFormProvider(request, progressMonitor);
end
consumer = datatransfer.UploadResponseBodyConsumer();
try
    sent = datatransfer.sendHTTPRequest(request.URL, requestContext, request.Method, ...
        Body=body, FollowRedirects=false, ProgressMonitor=progressMonitorFactory, ...
        ResponseConsumer=consumer);
catch exception
    [result, ~] = storeConsumerResponse(result, consumer);
    result.OutcomeUncertain = mayHaveSubmittedBody(exception);
    result.Error = exception;
    return
end

result = storeResponse(result, sent, consumer);
statusCode = result.StatusCode;
if statusCode >= 200 && statusCode < 300
    result.Success = true;
    result.TransferredBytes = result.TotalBytes;
    result.OutcomeUncertain = false;
    sendProgress(progressQueue, jobId, result.TransferredBytes, result.TotalBytes);
    return
end

result.OutcomeUncertain = sent.NeedsAuthentication || ...
    ismember(statusCode, [401, 403]) || ...
    (statusCode >= 300 && statusCode < 400) || statusCode >= 500;
result.Error = httpError(statusCode, request.ResolvedProtocol);
end


function provider = rawFileProvider(request, progressMonitor)
provider = datatransfer.UploadFileProvider( ...
    request.LocalPath, double(request.LocalBytes), progressMonitor);
provider.Header = filePartHeaders(request, 'attachment');
end


function provider = multipartFormProvider(request, progressMonitor)
fileProvider = datatransfer.UploadFileProvider( ...
    request.LocalPath, double(request.LocalBytes), progressMonitor);
fileProvider.Header = filePartHeaders(request, 'form-data', request.FormFieldName);
filePart = matlab.net.http.RequestMessage();
filePart.Header = fileProvider.Header;
filePart.Body = fileProvider;

formFieldNames = fieldnames(request.FormFields);
formArguments = cell(1, 2 * (numel(formFieldNames) + 1));
formArguments{1} = request.FormFieldName;
formArguments{2} = filePart;
for fieldIndex = 1:numel(formFieldNames)
    fieldName = formFieldNames{fieldIndex};
    fieldValue = request.FormFields.(fieldName);
    if isstring(fieldValue) && isscalar(fieldValue)
        fieldValue = char(fieldValue);
    end
    if ~ischar(fieldValue) || ~isrow(fieldValue)
        error('datatransfer:uploadFileWorker:invalidRequest', ...
              'Os valores adicionais do formulário devem ser textos escalares.')
    end
    formArguments{2 * fieldIndex + 1} = fieldName;
    formArguments{2 * fieldIndex + 2} = ...
        matlab.net.http.io.StringProvider(fieldValue);
end
provider = matlab.net.http.io.MultipartFormProvider(formArguments{:});
end


function headers = filePartHeaders(request, dispositionType, formFieldName)
if nargin < 3
    formFieldName = '';
end
if isempty(formFieldName)
    disposition = matlab.net.http.field.ContentDispositionField( ...
        dispositionType, 'filename', request.FileName);
else
    disposition = matlab.net.http.field.ContentDispositionField( ...
        dispositionType, 'name', formFieldName, 'filename', request.FileName);
end
contentType = matlab.net.http.field.ContentTypeField(request.ContentType);
headers = [contentType, disposition];
end


function result = uploadTus(requestContext, request, chunkSize, retryLimit, ...
                            progressQueue, jobId, result)
if isempty(result.UploadURL)
    result = createTusResource(requestContext, request, progressQueue, jobId, result);
    if ~isempty(result.Error) || result.NeedsAuthentication
        return
    end
    currentOffset = 0;
else
    validateTusHost(request.URL, result.UploadURL)
    [result, currentOffset, confirmed] = confirmTusOffset( ...
        requestContext, request, result.UploadURL, request.UploadOffset, ...
        progressQueue, jobId, result);
    if ~confirmed
        return
    end
end

unchangedRecoveryAttempts = 0;
while currentOffset < result.TotalBytes
    verifySource(request)
    result = clearResponseEvidence(result);
    consumer = datatransfer.UploadResponseBodyConsumer();
    patchResponse = struct();
    try
        sent = sendTusPatch(requestContext, request, result.UploadURL, ...
                            currentOffset, chunkSize, consumer);
        result = storeResponse(result, sent, consumer);
        patchStatus = result.StatusCode;
        patchResponseKnown = true;
        patchResponse = responseEvidence(result);
        patchNeedsAuthentication = sent.NeedsAuthentication;
        transportFailure = false;
        redirectFailure = false;
        result.OutcomeUncertain = patchNeedsAuthentication || ...
            ismember(patchStatus, [401, 403]) || ...
            (patchStatus >= 300 && patchStatus < 400) || patchStatus >= 500;
        if patchStatus == 204
            [acknowledgedOffset, validOffset] = uploadOffset(sent.Response);
            if validOffset && acknowledgedOffset > currentOffset && ...
                    acknowledgedOffset <= result.TotalBytes
                currentOffset = acknowledgedOffset;
                result = recordConfirmedOffset( ...
                    result, currentOffset, progressQueue, jobId);
                unchangedRecoveryAttempts = 0;
                continue
            end
            result.OutcomeUncertain = true;
            patchException = offsetError( ...
                'O PATCH Tus não retornou um Upload-Offset válido e crescente.');
        else
            patchException = httpError(patchStatus, 'tus');
        end
    catch exception
        patchException = exception;
        [result, patchResponseKnown] = storeConsumerResponse(result, consumer);
        if patchResponseKnown
            patchStatus = result.StatusCode;
            patchResponse = responseEvidence(result);
        else
            patchStatus = [];
        end
        patchNeedsAuthentication = false;
        transportFailure = mayHaveSubmittedBody(exception);
        redirectFailure = strcmp(exception.identifier, ...
                     'datatransfer:sendHTTPRequest:unexpectedRedirect');
        if ~transportFailure
            result.Error = exception;
            return
        end
        result.OutcomeUncertain = true;
    end

    previousOffset = currentOffset;
    [result, confirmedOffset, confirmed] = confirmTusOffset( ...
        requestContext, request, result.UploadURL, previousOffset, ...
        progressQueue, jobId, result);
    if patchResponseKnown
        result = restoreResponseEvidence(result, patchResponse);
    end
    if ~confirmed
        if isempty(result.Error)
            result.Error = patchException;
        end
        return
    end
    currentOffset = confirmedOffset;

    if ~isempty(patchStatus) && ismember(patchStatus, [404, 410])
        result.Error = resumeResourceError(patchStatus);
        return
    end
    if patchNeedsAuthentication || redirectFailure || ...
            (~isempty(patchStatus) && patchStatus >= 300 && patchStatus < 400)
        result.NeedsAuthentication = patchNeedsAuthentication || ...
            (~isempty(patchStatus) && ismember(patchStatus, [401, 403]));
        result.Error = patchException;
        return
    end
    if currentOffset > previousOffset
        result.Error = [];
        unchangedRecoveryAttempts = 0;
        continue
    end

    if ~transportFailure && patchStatus ~= 204
        result.Error = patchException;
        return
    end
    if redirectFailure
        result.Error = patchException;
        return
    end
    if unchangedRecoveryAttempts >= retryLimit
        result.Error = patchException;
        return
    end
    unchangedRecoveryAttempts = unchangedRecoveryAttempts + 1;
end

result.Success = true;
result.TransferredBytes = result.TotalBytes;
result.UploadOffset = result.TotalBytes;
result.OutcomeUncertain = false;
result.Error = [];
end


function result = createTusResource(requestContext, request, progressQueue, jobId, result)
metadata = ['filename ', base64Value(request.FileName), ...
           ',filetype ', base64Value(request.ContentType)];
headers = [matlab.net.http.HeaderField( ...
                'Upload-Length', sprintf('%.0f', result.TotalBytes)), ...
           matlab.net.http.HeaderField('Upload-Metadata', metadata), ...
           matlab.net.http.HeaderField('Tus-Resumable', '1.0.0')];
consumer = datatransfer.UploadResponseBodyConsumer();
try
    sent = sendTusRequest(requestContext, request.URL, 'POST', headers, [], consumer);
catch exception
    [result, ~] = storeConsumerResponse(result, consumer);
    result.OutcomeUncertain = mayHaveSubmittedBody(exception);
    result.Error = exception;
    return
end
result = storeResponse(result, sent, consumer);
result.OutcomeUncertain = true;
if sent.NeedsAuthentication
    result.Error = httpError(result.StatusCode, 'tus');
    return
end
if result.StatusCode ~= 201
    result.Error = httpError(result.StatusCode, 'tus');
    return
end

location = fieldOr(result.ResponseHeaders, 'Location', '');
if isempty(location)
    result.Error = MException('datatransfer:uploadFileWorker:missingTusLocation', ...
        'A criação Tus retornou HTTP 201 sem um cabeçalho Location; o resultado é incerto.');
    return
end
resolvedUploadURL = resolveLocation(request.URL, location);
validateTusHost(request.URL, resolvedUploadURL)
result.UploadURL = resolvedUploadURL;
result.UploadOffset = 0;
result.TransferredBytes = 0;
result.OutcomeUncertain = false;
result = recordConfirmedOffset(result, 0, progressQueue, jobId);
end


function sent = sendTusRequest(requestContext, url, method, headers, body, consumer)
sent = datatransfer.sendHTTPRequest(url, requestContext, method, ...
    Headers=headers, Body=body, FollowRedirects=false, ResponseConsumer=consumer);
end


function sent = sendTusPatch(requestContext, request, uploadURL, offset, chunkSize, consumer)
fileID = fopen(request.LocalPath, 'rb');
if fileID == -1
    error('datatransfer:uploadFileWorker:sourceUnavailable', ...
          'O arquivo de origem do envio não pôde ser aberto para leitura.')
end
fileCleanup = onCleanup(@() closeFileQuietly(fileID));
if fseek(fileID, offset, 'bof') ~= 0
    error('datatransfer:uploadFileWorker:sourceUnavailable', ...
          'Não foi possível posicionar a leitura no offset Tus confirmado.')
end

provider = datatransfer.UploadFileProvider( ...
    fileID, min(chunkSize, double(request.LocalBytes) - offset));
headers = [matlab.net.http.HeaderField( ...
                'Upload-Offset', sprintf('%.0f', offset)), ...
           matlab.net.http.HeaderField('Tus-Resumable', '1.0.0'), ...
           matlab.net.http.HeaderField( ...
                'Content-Type', 'application/offset+octet-stream')];
sent = datatransfer.sendHTTPRequest(uploadURL, requestContext, 'PATCH', ...
    Headers=headers, Body=provider, FollowRedirects=false, ResponseConsumer=consumer);
end


function [result, offset, confirmed] = confirmTusOffset( ...
        requestContext, request, uploadURL, minimumOffset, progressQueue, jobId, result)
confirmed = false;
offset = minimumOffset;
verifySource(request)
headers = matlab.net.http.HeaderField('Tus-Resumable', '1.0.0');
consumer = datatransfer.UploadResponseBodyConsumer();
try
    sent = sendTusRequest(requestContext, uploadURL, 'HEAD', headers, [], consumer);
catch exception
    [result, responseKnown] = storeConsumerResponse(result, consumer);
    if responseKnown && ismember(result.StatusCode, [404, 410])
        result.Error = resumeResourceError(result.StatusCode);
        result.OutcomeUncertain = false;
    else
        result.Error = exception;
    end
    return
end
result = storeResponse(result, sent, consumer);
if sent.NeedsAuthentication
    result.NeedsAuthentication = true;
    result.Error = httpError(result.StatusCode, 'tus');
    return
end
if ismember(result.StatusCode, [404, 410])
    result.Error = resumeResourceError(result.StatusCode);
    result.OutcomeUncertain = false;
    return
end
if result.StatusCode < 200 || result.StatusCode >= 300
    result.Error = httpError(result.StatusCode, 'tus');
    return
end

[offset, validOffset] = uploadOffset(sent.Response);
if ~validOffset || offset < minimumOffset || offset > result.TotalBytes
    result.Error = offsetError( ...
        'O HEAD Tus não retornou um Upload-Offset inteiro, monotônico e dentro do arquivo.');
    return
end
result = recordConfirmedOffset(result, offset, progressQueue, jobId);
confirmed = true;
end


function result = recordConfirmedOffset(result, offset, progressQueue, jobId)
result.UploadOffset = offset;
result.TransferredBytes = offset;
result.OutcomeUncertain = false;
result.Error = [];
sendProgress(progressQueue, jobId, offset, result.TotalBytes);
if isempty(progressQueue)
    return
end
send(progressQueue, struct('Type', 'offset', ...
                            'JobId', jobId, ...
                            'UploadURL', result.UploadURL, ...
                            'UploadOffset', offset));
end


function sendProgress(progressQueue, jobId, transferredBytes, totalBytes)
if isempty(progressQueue)
    return
end
send(progressQueue, struct('Type', 'progress', ...
                           'JobId', jobId, ...
                           'TransferredBytes', transferredBytes, ...
                           'TotalBytes', totalBytes));
end


function result = storeResponse(result, sent, consumer)
[result, ~] = storeResponseMessage(result, sent.Response, consumer);
result.NeedsAuthentication = sent.NeedsAuthentication;
end


function [result, available] = storeConsumerResponse(result, consumer)
available = false;
if ~isa(consumer, 'datatransfer.UploadResponseBodyConsumer') || ~isscalar(consumer)
    return
end
try
    response = consumer.Response;
catch
    return
end
[result, available] = storeResponseMessage(result, response, consumer);
end


function [result, available] = storeResponseMessage(result, response, consumer)
available = false;
if isempty(response) || ~isa(response, 'matlab.net.http.ResponseMessage') || ...
        ~isscalar(response)
    return
end
try
    statusCode = double(response.StatusCode);
    responseHeaders = allowedResponseHeaders(response);
catch
    return
end
if ~isnumeric(statusCode) || ~isscalar(statusCode) || ~isfinite(statusCode)
    return
end

result.StatusCode = statusCode;
result.ResponseHeaders = responseHeaders;
result.ResponseBody = uint8.empty(0, 1);
result.ResponseTruncated = false;
try
    capturedBody = consumer.CapturedBody;
    responseTruncated = consumer.ResponseTruncated;
    if isa(capturedBody, 'uint8') && ...
            (isempty(capturedBody) || isvector(capturedBody)) && ...
            numel(capturedBody) <= 64 * 1024 && ...
            islogical(responseTruncated) && isscalar(responseTruncated)
        result.ResponseBody = reshape(capturedBody, [], 1);
        result.ResponseTruncated = responseTruncated;
    end
catch
end
available = true;
end


function result = clearResponseEvidence(result)
result.StatusCode = [];
result.ResponseHeaders = struct();
result.ResponseBody = uint8.empty(0, 1);
result.ResponseTruncated = false;
result.NeedsAuthentication = false;
end


function evidence = responseEvidence(result)
evidence = struct('StatusCode', result.StatusCode, ...
                  'ResponseHeaders', result.ResponseHeaders, ...
                  'ResponseBody', result.ResponseBody, ...
                  'ResponseTruncated', result.ResponseTruncated, ...
                  'NeedsAuthentication', result.NeedsAuthentication);
end


function result = restoreResponseEvidence(result, evidence)
result.StatusCode = evidence.StatusCode;
result.ResponseHeaders = evidence.ResponseHeaders;
result.ResponseBody = evidence.ResponseBody;
result.ResponseTruncated = evidence.ResponseTruncated;
result.NeedsAuthentication = evidence.NeedsAuthentication;
end


function headers = allowedResponseHeaders(response)
headers = struct();
fieldNames = {'Location', 'ContentType', 'ETag'};
headerNames = {'Location', 'Content-Type', 'ETag'};
for index = 1:numel(headerNames)
    fields = response.getFields(headerNames{index});
    if ~isempty(fields)
        headers.(fieldNames{index}) = char(fields(1).Value);
    end
end
end


function [offset, valid] = uploadOffset(response)
offset = [];
valid = false;
fields = response.getFields('Upload-Offset');
if numel(fields) ~= 1
    return
end
textValue = strtrim(char(fields(1).Value));
if isempty(regexp(textValue, '^\d+$', 'once'))
    return
end
offset = str2double(textValue);
valid = isfinite(offset) && offset >= 0 && offset == floor(offset);
end


function result = httpError(statusCode, protocol)
switch statusCode
    case 409
        messageText = '409 Conflito: o servidor recusou o envio por conflito de estado.';
    case 412
        messageText = '412 Pré-condição não atendida: verifique as condições exigidas pelo servidor.';
    case 413
        messageText = '413 Tamanho da carga excedido: verifique client_max_body_size e os limites do servidor.';
    case 415
        messageText = '415 Tipo de mídia não suportado: verifique o Content-Type do arquivo.';
    otherwise
        messageText = sprintf('O servidor respondeu com HTTP %g ao protocolo %s.', ...
                              statusCode, protocol);
end
result = MException('datatransfer:uploadFileWorker:httpError', '%s', messageText);
end


function exception = offsetError(messageText)
exception = MException('datatransfer:uploadFileWorker:invalidOffset', '%s', messageText);
end


function exception = resumeResourceError(statusCode)
exception = MException('datatransfer:uploadFileWorker:resumeResourceUnavailable', ...
    'HTTP %d: o recurso Tus não está disponível; reinicie ou cancele o envio.', statusCode);
end


function tf = mayHaveSubmittedBody(exception)
if strcmp(exception.identifier, 'datatransfer:sendHTTPRequest:unexpectedRedirect')
    tf = true;
elseif strcmp(exception.identifier, 'datatransfer:sendHTTPRequest:networkError')
    tf = ~isDefinitivePreSubmissionFailure(exception);
else
    tf = false;
end
end


function tf = isDefinitivePreSubmissionFailure(exception)
tf = false;
if ~isa(exception, 'MException')
    return
end
failureTypes = {'java.net.connectexception', ...
                'java.net.unknownhostexception', ...
                'javax.net.ssl.sslhandshakeexception', ...
                'javax.net.ssl.sslpeerunverifiedexception', ...
                'java.security.cert.certificateexception'};
identifier = lower(char(exception.identifier));
messageText = lower(char(exception.message));
for typeIndex = 1:numel(failureTypes)
    failureType = failureTypes{typeIndex};
    if contains(identifier, failureType) || contains(messageText, failureType)
        tf = true;
        return
    end
end
causes = exception.cause;
for causeIndex = 1:numel(causes)
    if isDefinitivePreSubmissionFailure(causes{causeIndex})
        tf = true;
        return
    end
end
end


function encoded = base64Value(value)
encoded = char(matlab.net.base64encode(unicode2native(value, 'UTF-8')));
end


function validateTusHost(endpointURL, uploadURL)
try
    endpointHost = char(matlab.net.URI(endpointURL).Host);
    resourceHost = char(matlab.net.URI(uploadURL).Host);
catch cause
    exception = MException('datatransfer:uploadFileWorker:invalidTusLocation', ...
                           'A URL do recurso Tus é inválida.');
    exception = addCause(exception, cause);
    throw(exception)
end
if ~strcmpi(endpointHost, resourceHost)
    error('datatransfer:uploadFileWorker:crossHostTusLocation', ...
          'O recurso Tus retornado está em outro host; o envio foi bloqueado.')
end
end


function value = resolveLocation(baseURL, location)
location = strtrim(char(location));
if ~isempty(regexp(location, '^[A-Za-z][A-Za-z0-9+.-]*:', 'once'))
    value = location;
    return
end

baseTokens = regexp(baseURL, ...
    '^(https?://[^/?#]+)([^?#]*)(\?[^#]*)?(#.*)?$', ...
    'tokens', 'once', 'ignorecase');
if isempty(baseTokens)
    error('datatransfer:uploadFileWorker:invalidTusLocation', ...
          'Não foi possível resolver o cabeçalho Location do recurso Tus.')
end
origin = baseTokens{1};
basePath = tokenAt(baseTokens, 2);
baseQuery = tokenAt(baseTokens, 3);

if startsWith(location, '//')
    scheme = regexp(baseURL, '^([^:]+):', 'tokens', 'once', 'ignorecase');
    value = [scheme{1}, ':', location];
    return
elseif startsWith(location, '#')
    value = [origin, basePath, baseQuery, location];
    return
end

locationTokens = regexp(location, '^([^?#]*)(\?[^#]*)?(#.*)?$', ...
                        'tokens', 'once');
locationPath = tokenAt(locationTokens, 1);
query = tokenAt(locationTokens, 2);
fragment = tokenAt(locationTokens, 3);
if isempty(locationPath) && startsWith(location, '?')
    path = basePath;
elseif startsWith(locationPath, '/')
    path = locationPath;
else
    slashIndex = find(basePath == '/', 1, 'last');
    if isempty(slashIndex)
        directory = '/';
    else
        directory = basePath(1:slashIndex);
    end
    path = [directory, locationPath];
end
path = removeDotSegments(path);
value = [origin, path, query, fragment];
end


function value = tokenAt(tokens, index)
value = '';
if numel(tokens) >= index && ~isempty(tokens{index})
    value = tokens{index};
end
end


function path = removeDotSegments(path)
isAbsolute = startsWith(path, '/');
hasTrailingSlash = endsWith(path, '/');
segments = strsplit(path, '/');
resolved = cell(1, numel(segments));
resolvedCount = 0;
for index = 1:numel(segments)
    segment = segments{index};
    if isempty(segment) || strcmp(segment, '.')
        continue
    elseif strcmp(segment, '..')
        if resolvedCount > 0
            resolvedCount = resolvedCount - 1;
        end
    else
        resolvedCount = resolvedCount + 1;
        resolved{resolvedCount} = segment;
    end
end
path = strjoin(resolved(1:resolvedCount), '/');
if isAbsolute
    path = ['/', path];
end
if hasTrailingSlash && ~endsWith(path, '/')
    path = [path, '/'];
end
if isempty(path)
    path = '/';
end
end


function closeFileQuietly(fileID)
try
    fclose(fileID);
catch
end
end