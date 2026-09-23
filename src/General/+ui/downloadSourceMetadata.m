function metadata = downloadSourceMetadata(url, requestContext, checkContentDisposition)
% DOWNLOADSOURCEMETADATA Read source headers without downloading the payload.

arguments
    url (1,:) char {mustBeNonempty}
    requestContext (1,1) struct
    checkContentDisposition (1,1) logical = true
end

result = ui.downloadHTTPResponse(url, requestContext, 'HEAD');
response = result.Response;
statusCode = double(response.StatusCode);

if result.NeedsAuthentication
    metadata = struct('NeedsAuthentication', true, ...
                      'FinalURL', result.FinalURL, ...
                      'StatusCode', statusCode, ...
                      'ContentDispositionFileName', '');
    return
end

if ismember(statusCode, [405, 501])
    metadata = fallbackToRangeRequest(url, requestContext);
    return
end

if statusCode < 200 || statusCode >= 300
    error('ui:downloadSourceMetadata:httpError', ...
          'Metadata request returned HTTP %d.', statusCode)
end

metadata = metadataFromResponse(response, result.FinalURL, statusCode);
if checkContentDisposition && isempty(metadata.ContentDispositionFileName)
    metadata = fallbackToRangeRequest(url, requestContext);
end
end


function metadata = fallbackToRangeRequest(url, requestContext)
result = ui.downloadHTTPResponse(url, requestContext, 'GET', 0, 0);
response = result.Response;
statusCode = double(response.StatusCode);
if result.NeedsAuthentication
    metadata = struct('NeedsAuthentication', true, ...
                      'FinalURL', result.FinalURL, ...
                      'StatusCode', statusCode, ...
                      'ContentDispositionFileName', '');
    return
end
if statusCode < 200 || statusCode >= 300
    error('ui:downloadSourceMetadata:httpError', ...
          'Metadata request returned HTTP %d.', statusCode)
end
metadata = metadataFromResponse(response, result.FinalURL, statusCode);
end


function metadata = metadataFromResponse(response, finalURL, statusCode)
contentDisposition = headerValue(response, 'Content-Disposition');
metadata = struct('NeedsAuthentication', false, ...
                  'FinalURL', finalURL, ...
                  'StatusCode', statusCode, ...
                  'ContentDispositionFileName', ui.downloadContentDispositionFileName(contentDisposition));
end


function value = headerValue(response, name)
fields = response.getFields(name);
if isempty(fields)
    value = '';
else
    value = char(fields(1).Value);
end
end


