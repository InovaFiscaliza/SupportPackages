function result = uploadCapabilities(url, requestContext, request, senderFcn)
% UPLOADCAPABILITIES Discover upload capabilities without sending a body.

arguments
    url (1,:) char {mustBeNonempty}
    requestContext (1,1) struct
    request (1,1) struct
    senderFcn = []
end

if ~isempty(senderFcn) && ~isa(senderFcn, 'function_handle')
    error('datatransfer:uploadCapabilities:invalidSender', ...
          'senderFcn deve ser um function handle ou vazio.')
end
requiredFields = {'Protocol', 'Method', 'LocalBytes'};
if ~all(isfield(request, requiredFields))
    error('datatransfer:uploadCapabilities:invalidRequest', ...
          'A solicitação normalizada não contém os campos de upload necessários.')
end
if ~ismember(request.Protocol, {'auto', 'multipart', 'raw', 'tus'}) || ...
        ~ismember(request.Method, {'POST', 'PUT'})
    error('datatransfer:uploadCapabilities:invalidRequest', ...
          'Protocol ou Method não é válido para o envio.')
end

result = struct('NeedsAuthentication', false, ...
                'ResolvedProtocol', '', ...
                'IsResumable', false, ...
                'AllowedMethods', {cell(1, 0)}, ...
                'TusVersion', '', ...
                'TusExtensions', {cell(1, 0)}, ...
                'TusMaxSize', inf, ...
                'StatusCode', []);

headers = matlab.net.http.HeaderField.empty;
if strcmp(request.Protocol, 'tus')
    headers = matlab.net.http.HeaderField('Tus-Resumable', '1.0.0');
end
options = struct('FollowRedirects', false, 'Headers', headers);
optionsInconclusive = true;
isTusAdvertised = false;
optionsResponse = [];
needsAuthentication = false;

try
    [optionsResponse, needsAuthentication] = sendPreflightRequest( ...
        url, requestContext, 'OPTIONS', options, senderFcn);
catch exception
    if isempty(senderFcn) && ...
            strcmp(exception.identifier, 'datatransfer:sendHTTPRequest:networkError')
        optionsInconclusive = true;
    else
        rethrow(exception)
    end
end

if ~isempty(optionsResponse)
    optionsStatusCode = double(optionsResponse.StatusCode);
    result.StatusCode = optionsStatusCode;
    if isRedirect(optionsStatusCode)
        if isEligibleF5URL(url, requestContext)
            result.NeedsAuthentication = true;
            return
        end
        error('datatransfer:uploadCapabilities:unexpectedOptionsRedirect', ...
              'OPTIONS capability request to "%s" returned redirect HTTP %d; redirects are not followed.', ...
              url, optionsStatusCode)
    end
    if needsAuthentication || isAuthenticationStatus(optionsStatusCode)
        result.NeedsAuthentication = true;
        return
    end

    result.AllowedMethods = allowedMethods(optionsResponse);
    versions = commaTokens(headerValues(optionsResponse, 'Tus-Version'));
    extensions = commaTokens(headerValues(optionsResponse, 'Tus-Extension'));
    result.TusVersion = strjoin(versions, ', ');
    result.TusExtensions = extensions;
    result.TusMaxSize = tusMaxSize(optionsResponse);
    isTusAdvertised = any(strcmp(versions, '1.0.0')) && ...
                      any(strcmpi(extensions, 'creation'));
    hasAllow = ~isempty(result.AllowedMethods);
    optionsInconclusive = ismember(optionsStatusCode, [405, 501]) || ~hasAllow;
    if ~optionsInconclusive && (optionsStatusCode < 200 || optionsStatusCode >= 300)
        error('datatransfer:uploadCapabilities:unexpectedOptionsStatus', ...
              'OPTIONS capability request returned HTTP %d.', optionsStatusCode)
    end
end

if optionsInconclusive && isEligibleF5URL(url, requestContext)
    headOptions = struct('FollowRedirects', false, ...
                         'Headers', matlab.net.http.HeaderField.empty);
    try
        [headResponse, needsAuthentication] = sendPreflightRequest( ...
            url, requestContext, 'HEAD', headOptions, senderFcn);
        if ~isempty(headResponse)
            headStatusCode = double(headResponse.StatusCode);
            if isempty(result.StatusCode)
                result.StatusCode = headStatusCode;
            end
            if needsAuthentication || isAuthenticationStatus(headStatusCode) || ...
                    (isRedirect(headStatusCode) && isEligibleF5URL(url, requestContext))
                result.StatusCode = headStatusCode;
                result.NeedsAuthentication = true;
                return
            end
        end
    catch exception
        if ~isempty(senderFcn) || ...
                ~strcmp(exception.identifier, 'datatransfer:sendHTTPRequest:networkError')
            rethrow(exception)
        end
    end
end

if strcmp(request.Protocol, 'auto')
    if optionsInconclusive
        result.ResolvedProtocol = fallbackProtocol(request.Method);
    elseif isTusAdvertised
        result.ResolvedProtocol = 'tus';
    elseif any(strcmp(result.AllowedMethods, request.Method))
        result.ResolvedProtocol = 'raw';
    else
        result.ResolvedProtocol = 'multipart';
    end
else
    result.ResolvedProtocol = request.Protocol;
end
result.IsResumable = strcmp(result.ResolvedProtocol, 'tus');

if result.IsResumable && ~isempty(request.LocalBytes) && ...
        result.TusMaxSize < request.LocalBytes
    error('datatransfer:TransferManager:uploadTooLarge', ...
          'O arquivo possui %g bytes, acima do limite Tus-Max-Size de %g bytes.', ...
          request.LocalBytes, result.TusMaxSize)
end
end


function [response, needsAuthentication] = sendPreflightRequest( ...
        url, requestContext, method, options, senderFcn)
if isempty(senderFcn)
    sentResult = datatransfer.sendHTTPRequest(url, requestContext, method, ...
        FollowRedirects=options.FollowRedirects, Headers=options.Headers);
else
    sentResult = senderFcn(url, requestContext, method, options);
end
[response, needsAuthentication] = normalizeSendResult(sentResult);
end


function [response, needsAuthentication] = normalizeSendResult(value)
needsAuthentication = false;
if isa(value, 'matlab.net.http.ResponseMessage')
    response = value;
    return
end
if ~isstruct(value) || ~isscalar(value) || ~isfield(value, 'Response') || ...
        ~isa(value.Response, 'matlab.net.http.ResponseMessage')
    error('datatransfer:uploadCapabilities:invalidSenderResult', ...
          'O sender deve retornar ResponseMessage ou resultado de sendHTTPRequest.')
end
response = value.Response;
if isfield(value, 'NeedsAuthentication')
    if ~islogical(value.NeedsAuthentication) || ~isscalar(value.NeedsAuthentication)
        error('datatransfer:uploadCapabilities:invalidSenderResult', ...
              'NeedsAuthentication must be a logical scalar when provided.')
    end
    needsAuthentication = value.NeedsAuthentication;
end
end


function methods = allowedMethods(response)
methods = commaTokens(headerValues(response, 'Allow'));
for index = 1:numel(methods)
    methods{index} = upper(methods{index});
end
end


function values = headerValues(response, name)
fields = response.getFields(name);
values = cell(1, numel(fields));
for index = 1:numel(fields)
    values{index} = char(fields(index).Value);
end
end


function tokens = commaTokens(values)
    maximumTokens = 0;
    for valueIndex = 1:numel(values)
        maximumTokens = maximumTokens + numel(strfind(values{valueIndex}, ',')) + 1;
    end
    tokens = cell(1, maximumTokens);
    tokenCount = 0;
for valueIndex = 1:numel(values)
    parts = strsplit(values{valueIndex}, ',');
    for partIndex = 1:numel(parts)
        token = strtrim(parts{partIndex});
        if ~isempty(token) && ~any(strcmpi(tokens, token))
                tokenCount = tokenCount + 1;
                tokens{tokenCount} = token;
        end
    end
end
    tokens = tokens(1:tokenCount);
end


function value = tusMaxSize(response)
value = inf;
values = headerValues(response, 'Tus-Max-Size');
for index = 1:numel(values)
    candidate = str2double(strtrim(values{index}));
    if isscalar(candidate) && isfinite(candidate) && candidate >= 0
        value = min(value, candidate);
    end
end
end


function protocol = fallbackProtocol(method)
if strcmp(method, 'PUT')
    protocol = 'raw';
else
    protocol = 'multipart';
end
end


function tf = isAuthenticationStatus(statusCode)
tf = ismember(statusCode, [401, 403]);
end


function tf = isRedirect(statusCode)
tf = statusCode >= 300 && statusCode < 400;
end


function tf = isEligibleF5URL(url, requestContext)
tf = false;
if ~isfield(requestContext, 'AuthenticationEligible') || ...
        ~islogical(requestContext.AuthenticationEligible) || ...
        ~isscalar(requestContext.AuthenticationEligible) || ...
        ~requestContext.AuthenticationEligible || ...
        ~isfield(requestContext, 'AllowedHost') || isempty(requestContext.AllowedHost)
    return
end
try
    uri = matlab.net.URI(url);
    tf = strcmpi(char(uri.Scheme), 'https') && ...
         strcmpi(char(uri.Host), char(requestContext.AllowedHost));
catch
end
end