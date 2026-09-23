function result = downloadHTTPResponse(url, requestContext, method, firstByte, lastByte)
% DOWNLOADHTTPRESPONSE Send one HTTP request with safe redirect handling.

arguments
    url (1,:) char {mustBeNonempty}
    requestContext (1,1) struct
    method (1,:) char {mustBeMember(method, {'GET', 'HEAD'})} = 'GET'
    firstByte double = []
    lastByte double = []
end

maxRedirects = 5;
currentURL = url;
redirectCount = 0;

while true
    validateRequestURL(currentURL, requestContext)
    response = sendRequest(currentURL, requestContext, method, firstByte, lastByte);
    statusCode = double(response.StatusCode);

    if isAuthenticationResponse(statusCode) && shouldAuthenticate(currentURL, requestContext)
        result = responseResult(response, currentURL, true);
        return
    end

    if isRedirect(statusCode)
        location = headerValue(response, 'Location');
        if isempty(location)
            error('download:downloadHTTPResponse:missingRedirect', ...
                  'HTTP redirect from "%s" did not provide a Location header.', currentURL)
        end

        redirectURL = resolveRedirectURL(currentURL, location);
        if shouldAuthenticate(currentURL, requestContext) && ...
                ~hasCookieForURL(requestContext, redirectURL)
            result = responseResult(response, currentURL, true);
            return
        end
        if redirectCount >= maxRedirects
            error('download:downloadHTTPResponse:tooManyRedirects', ...
                  'The download source redirected more than %d times.', maxRedirects)
        end

        redirectCount = redirectCount + 1;
        currentURL = redirectURL;
        continue
    end

    result = responseResult(response, currentURL, false);
    return
end
end


function response = sendRequest(url, requestContext, method, firstByte, lastByte)
headers = matlab.net.http.HeaderField.empty;
if hasCookieForURL(requestContext, url)
    headers(end+1) = matlab.net.http.HeaderField('Cookie', requestContext.CookieHeader);
end
if strcmp(method, 'GET') && ~isempty(firstByte) && ~isempty(lastByte)
    headers(end+1) = matlab.net.http.HeaderField('Range', sprintf('bytes=%d-%d', firstByte, lastByte));
end

if isempty(headers)
    request = matlab.net.http.RequestMessage(method);
else
    request = matlab.net.http.RequestMessage(method, headers);
end
options = matlab.net.http.HTTPOptions('MaxRedirects', 0, ...
                                      'ConnectTimeout', 30, ...
                                      'ConvertResponse', false);
response = request.send(url, options);
end


function validateRequestURL(url, ~)
uri = matlab.net.URI(url);
if ~ismember(lower(char(uri.Scheme)), {'http', 'https'})
    error('download:downloadHTTPResponse:invalidScheme', ...
          'Download URLs must use HTTP or HTTPS.')
end

end


function tf = shouldAuthenticate(url, requestContext)
tf = false;
if ~isfield(requestContext, 'AuthenticationEligible') || ...
        ~requestContext.AuthenticationEligible
    return
end
if ~isfield(requestContext, 'AllowedHost') || isempty(requestContext.AllowedHost)
    return
end
tf = strcmpi(urlHost(url), char(requestContext.AllowedHost)) && ...
     strcmpi(urlScheme(url), 'https');
end


function tf = hasCookieForURL(requestContext, url)
tf = isfield(requestContext, 'CookieHeader') && ...
     ~isempty(requestContext.CookieHeader) && ...
     isfield(requestContext, 'AllowedHost') && ...
    strcmpi(urlHost(url), char(requestContext.AllowedHost)) && ...
    strcmpi(urlScheme(url), 'https');
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
if startsWith(location, 'http://', 'IgnoreCase', true) || ...
        startsWith(location, 'https://', 'IgnoreCase', true)
    value = location;
    return
end

baseTokens = regexp(baseURL, '^(https?://[^/]+)(/[^?#]*)?', 'tokens', 'once', 'ignorecase');
if isempty(baseTokens)
    error('download:downloadHTTPResponse:invalidBaseURL', ...
          'Could not resolve a redirect from "%s".', baseURL)
end
origin = baseTokens{1};
basePath = '';
if numel(baseTokens) > 1 && ~isempty(baseTokens{2})
    basePath = baseTokens{2};
end

if startsWith(location, '//')
    scheme = regexp(baseURL, '^([^:]+):', 'tokens', 'once', 'ignorecase');
    value = [scheme{1}, ':', location];
elseif startsWith(location, '/')
    value = [origin, location];
elseif startsWith(location, '?')
    value = [origin, basePath, location];
else
    slashIndex = find(basePath == '/', 1, 'last');
    if isempty(slashIndex)
        directory = '/';
    else
        directory = basePath(1:slashIndex);
    end
    value = [origin, directory, location];
end
end