function result = sendHTTPRequest(url, requestContext, method, options)
% SENDHTTPREQUEST Send one HTTP request with safe redirect handling.

arguments
    url (1,:) char {mustBeNonempty}
    requestContext (1,1) struct
    method (1,:) char {mustBeMember(method, {'GET', 'HEAD', 'OPTIONS', 'POST', 'PUT', 'PATCH', 'DELETE'})} = 'GET'
    options.Range = []
    options.Headers = matlab.net.http.HeaderField.empty
    options.Body = []
    options.FollowRedirects = []
    options.ProgressMonitor = []
end

rangeValue = normalizeRange(options.Range);
headers = validateRequestHeaders(options.Headers, rangeValue);
body = validateBody(options.Body);
hasBody = ~isequal(body, []);
followRedirects = resolveFollowRedirects(options.FollowRedirects, method);
progressMonitorFactory = resolveProgressMonitor(options.ProgressMonitor);

maxRedirects = 5;
currentURL = url;
redirectCount = 0;

while true
    validateRequestURL(currentURL)
    response = sendRequest(currentURL, requestContext, method, headers, ...
                           rangeValue, body, hasBody, progressMonitorFactory);
    statusCode = double(response.StatusCode);

    if isAuthenticationResponse(statusCode) && shouldAuthenticate(currentURL, requestContext)
        result = responseResult(response, currentURL, true);
        return
    end

    if ~isRedirect(statusCode)
        result = responseResult(response, currentURL, false);
        return
    end

    if shouldAuthenticate(currentURL, requestContext)
        result = responseResult(response, currentURL, true);
        return
    end

    if hasBody
        error('datatransfer:sendHTTPRequest:unexpectedRedirect', ...
              'Body-bearing request redirected from "%s". The body was not replayed.', currentURL)
    end

    if ~followRedirects
        result = responseResult(response, currentURL, false);
        return
    end

    location = headerValue(response, 'Location');
    if isempty(location)
        error('datatransfer:sendHTTPRequest:missingRedirect', ...
              'HTTP redirect from "%s" did not provide a Location header.', currentURL)
    end
    redirectURL = resolveRedirectURL(currentURL, location);

    if redirectCount >= maxRedirects
        error('datatransfer:sendHTTPRequest:tooManyRedirects', ...
              'The request redirected more than %d times.', maxRedirects)
    end

    redirectCount = redirectCount + 1;
    currentURL = redirectURL;
end
end


function response = sendRequest(url, requestContext, method, headers, rangeValue, body, hasBody, progressMonitorFactory)
requestHeaders = headers;
if ~isempty(rangeValue)
    requestHeaders(end+1) = matlab.net.http.HeaderField('Range', rangeValue);
end
if hasCookieForURL(requestContext, url)
    requestHeaders(end+1) = matlab.net.http.HeaderField( ...
        'Cookie', char(requestContext.CookieHeader));
end

request = matlab.net.http.RequestMessage(method);
request.Header = requestHeaders;
if hasBody
    request.Body = body;
end

httpOptions = matlab.net.http.HTTPOptions('MaxRedirects', 0, ...
                                          'ConnectTimeout', 30, ...
                                          'ConvertResponse', false);
if ~isempty(progressMonitorFactory)
    httpOptions.ProgressMonitorFcn = progressMonitorFactory;
    httpOptions.UseProgressMonitor = true;
end
try
    response = request.send(url, httpOptions);
catch cause
    exception = MException('datatransfer:sendHTTPRequest:networkError', ...
                           'The HTTP transport request failed.');
    exception = addCause(exception, cause);
    throw(exception)
end
end


function rangeValue = normalizeRange(value)
if isempty(value)
    rangeValue = '';
elseif ischar(value) && isrow(value)
    rangeValue = value;
elseif isstring(value) && isscalar(value) && ~ismissing(value)
    rangeValue = char(value);
else
    error('datatransfer:sendHTTPRequest:invalidRange', ...
          'Range must be a character vector, string scalar, or empty.')
end
if any(double(rangeValue) <= 31 | double(rangeValue) == 127)
    error('datatransfer:sendHTTPRequest:invalidRange', ...
          'Range cannot contain ASCII control characters.')
end
end


function headers = validateRequestHeaders(headers, rangeValue)
if isempty(headers)
    headers = matlab.net.http.HeaderField.empty;
    return
end
if ~isa(headers, 'matlab.net.http.HeaderField') || ~isvector(headers)
    error('datatransfer:sendHTTPRequest:invalidHeader', ...
          'Request headers must be a HeaderField vector.')
end
headers = reshape(headers, 1, []);
allowedNames = {'range', 'accept', 'content-type', 'tus-resumable', ...
                'upload-length', 'upload-metadata', 'upload-offset'};
headerNames = cell(1, numel(headers));
headerCount = 0;
rangeHeaderValue = '';
validatedHeaders = headers;

for index = 1:numel(headers)
    name = lower(char(headers(index).Name));
    value = char(headers(index).Value);
    if ~any(strcmp(name, allowedNames)) || ...
            any(double(value) <= 31 | double(value) == 127)
        error('datatransfer:sendHTTPRequest:invalidHeader', ...
              'Request header "%s" is unsupported or duplicated.', name)
    end
    if strcmp(name, 'range')
        if ~isempty(rangeValue)
            if ~strcmp(strtrim(value), strtrim(rangeValue))
                error('datatransfer:sendHTTPRequest:invalidHeader', ...
                      'Range option and Range header must have the same value.')
            end
            continue
        end
        if ~isempty(rangeHeaderValue)
            if strcmp(strtrim(value), strtrim(rangeHeaderValue))
                continue
            end
            error('datatransfer:sendHTTPRequest:invalidHeader', ...
                  'Request headers contain conflicting Range values.')
        end
        rangeHeaderValue = value;
    elseif any(strcmp(headerNames(1:headerCount), name))
        error('datatransfer:sendHTTPRequest:invalidHeader', ...
              'Request header "%s" is unsupported or duplicated.', name)
    end
    headerCount = headerCount + 1;
    headerNames{headerCount} = name;
    validatedHeaders(headerCount) = headers(index);
end
headers = validatedHeaders(1:headerCount);
end


function body = validateBody(body)
if isempty(body) && isequal(body, [])
    return
end
if ~isa(body, 'uint8') && ~isa(body, 'matlab.net.http.io.ContentProvider')
    error('datatransfer:sendHTTPRequest:invalidBody', ...
          'Body must be uint8 or a matlab.net.http.io.ContentProvider.')
end
end


function followRedirects = resolveFollowRedirects(value, method)
if isempty(value)
    followRedirects = any(strcmp(method, {'GET', 'HEAD', 'OPTIONS'}));
elseif islogical(value) && isscalar(value)
    followRedirects = value;
else
    error('datatransfer:sendHTTPRequest:invalidFollowRedirects', ...
          'FollowRedirects must be a logical scalar or empty.')
end
end


function factory = resolveProgressMonitor(progressMonitor)
factory = [];
if isempty(progressMonitor)
    return
end
if isa(progressMonitor, 'function_handle')
    factory = progressMonitor;
    return
end
if ~isa(progressMonitor, 'matlab.net.http.ProgressMonitor')
    error('datatransfer:sendHTTPRequest:invalidProgressMonitor', ...
          'ProgressMonitor must be a ProgressMonitor instance or factory.')
end
factory = @() progressMonitor;
end


function validateRequestURL(url)
try
    uri = matlab.net.URI(url);
catch cause
    exception = MException('datatransfer:sendHTTPRequest:invalidURL', ...
                           'Request URL must contain a valid HTTP authority.');
    exception = addCause(exception, cause);
    throw(exception)
end
if ~ismember(lower(char(uri.Scheme)), {'http', 'https'})
    error('datatransfer:sendHTTPRequest:invalidScheme', ...
          'Request URLs must use HTTP or HTTPS.')
end
host = uri.Host;
if isstring(host)
    if ~isscalar(host) || ismissing(host)
        error('datatransfer:sendHTTPRequest:invalidURL', ...
              'Request URL must contain a valid HTTP authority.')
    end
    host = char(host);
end
if ~ischar(host) || ~isrow(host) || isempty(strtrim(host))
    error('datatransfer:sendHTTPRequest:invalidURL', ...
          'Request URL must contain a valid HTTP authority.')
end
end


function tf = shouldAuthenticate(url, requestContext)
tf = false;
if ~isfield(requestContext, 'AuthenticationEligible') || ...
        ~islogical(requestContext.AuthenticationEligible) || ...
        ~isscalar(requestContext.AuthenticationEligible) || ...
        ~requestContext.AuthenticationEligible
    return
end
tf = isAllowedCookieURL(requestContext, url);
end


function tf = hasCookieForURL(requestContext, url)
tf = isfield(requestContext, 'CookieHeader') && ...
     ~isempty(requestContext.CookieHeader) && ...
     isAllowedCookieURL(requestContext, url);
end


function tf = isAllowedCookieURL(requestContext, url)
tf = false;
if ~isfield(requestContext, 'AllowedHost') || isempty(requestContext.AllowedHost)
    return
end
allowedHost = char(requestContext.AllowedHost);
tf = strcmpi(urlHost(url), allowedHost) && strcmpi(urlScheme(url), 'https');
end


function tf = isAuthenticationResponse(statusCode)
tf = statusCode == 401 || statusCode == 403;
end


function tf = isRedirect(statusCode)
tf = statusCode >= 300 && statusCode < 400;
end


function result = responseResult(response, finalURL, needsAuthentication)
result = struct('Response', response, ...
                'FinalURL', finalURL, ...
                'NeedsAuthentication', needsAuthentication);
end


function value = headerValue(response, name)
fields = response.getFields(name);
if isempty(fields)
    value = '';
else
    value = char(fields(1).Value);
end
end


function value = urlHost(url)
value = char(matlab.net.URI(url).Host);
end


function value = urlScheme(url)
value = char(matlab.net.URI(url).Scheme);
end


function value = resolveRedirectURL(baseURL, location)
location = strtrim(char(location));
if ~isempty(regexp(location, '^[A-Za-z][A-Za-z0-9+.-]*:', 'once'))
    value = location;
    return
end

baseTokens = regexp(baseURL, ...
    '^(https?://[^/?#]+)([^?#]*)(\?[^#]*)?(#.*)?$', ...
    'tokens', 'once', 'ignorecase');
if isempty(baseTokens)
    error('datatransfer:sendHTTPRequest:invalidBaseURL', ...
          'Could not resolve a redirect from "%s".', baseURL)
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