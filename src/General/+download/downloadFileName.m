function [fileName, isUseful] = downloadFileName(url, fallbackID)
% DOWNLOADFILENAME Derive a safe URL filename or a deterministic fallback.

arguments
    url (1,:) char {mustBeNonempty}
    fallbackID (1,:) char = ''
end

fileName = '';
isUseful = false;
try
    pathSegments = matlab.net.URI(url).Path;
    if ~isempty(pathSegments) && strlength(pathSegments(end)) > 0
        candidate = char(pathSegments(end));
        candidate = regexprep(candidate, '[\\/:*?"<>|]', '_');
        if ~isempty(candidate) && ~ismember(candidate, {'.', '..'})
            fileName = candidate;
            isUseful = true;
        end
    end
catch
end

if isUseful
    return
end

if isempty(fallbackID)
    fallbackID = char(matlab.lang.internal.uuid());
    fallbackID = regexprep(fallbackID, '-', '');
    fallbackID = fallbackID(1:min(8, numel(fallbackID)));
end

domain = 'source';
try
    domain = char(matlab.net.URI(url).Host);
catch
end
domain = strrep(domain, '.', '-');
domain = regexprep(domain, '[\\/:*?"<>|]', '-');
domain = regexprep(domain, '-+', '-');
if isempty(domain)
    domain = 'source';
end

fileName = sprintf('%s_%s_%s.download', datestr(now, 'yymmdd_HHMM'), domain, fallbackID);
end