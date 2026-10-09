function report = checkUploadPreflight
% CHECKUPLOADPREFLIGHT Verify protocol selection from upload capability headers.

addpath(fileparts(mfilename('fullpath')))
projectFolder = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(projectFolder, 'src', 'General'))

headers = [matlab.net.http.HeaderField('Tus-Version', '1.0.0'), ...
           matlab.net.http.HeaderField('Tus-Extension', 'creation'), ...
           matlab.net.http.HeaderField('Tus-Max-Size', '4096')];
response = matlab.net.http.ResponseMessage( ...
    matlab.net.http.StatusCode.OK, headers);
request = struct('Protocol', 'auto', 'Method', 'POST', 'LocalBytes', 12);
requestContext = struct('CookieHeader', '', ...
                        'AllowedHost', '', ...
                        'AuthenticationEligible', false, ...
                        'Authenticated', false);
senderCallCount = 0;
capabilities = datatransfer.uploadCapabilities( ...
    'http://containerhost.hv:8080/upload/', requestContext, request, @sendResponse);

assert(senderCallCount == 1)
assert(isempty(capabilities.AllowedMethods))
assert(strcmp(capabilities.ResolvedProtocol, 'tus'))
assert(capabilities.IsResumable)
assert(capabilities.TusMaxSize == 4096)

report = struct('OptionsCalls', senderCallCount, ...
                'AllowedMethods', {capabilities.AllowedMethods}, ...
                'ResolvedProtocol', capabilities.ResolvedProtocol, ...
                'IsResumable', capabilities.IsResumable, ...
                'TusMaxSize', capabilities.TusMaxSize);

    function result = sendResponse(~, ~, method, options)
        assert(strcmp(method, 'OPTIONS'))
        assert(isempty(options.Headers))
        senderCallCount = senderCallCount + 1;
        result = response;
    end
end