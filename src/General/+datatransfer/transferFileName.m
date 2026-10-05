function [fileName, isUseful] = transferFileName(url, fallbackID, options)
% TRANSFERFILENAME Derive a safe URL filename or a deterministic fallback.

arguments
    url (1,:) char {mustBeNonempty}
    fallbackID (1,:) char = ''
    options.SanitizeOnly (1,1) logical = false
end

fileName = '';
isUseful = false;

if options.SanitizeOnly && ~isempty(url)
    unsafeCharacters = ismember(double(url), [0:31, 127:159, 34, 39, 47, 58, 92]);
    sanitizedCandidate = url(~unsafeCharacters);
    if ~isempty(sanitizedCandidate) && ...
            ~ismember(sanitizedCandidate, {'.', '..'})
        fileName = sanitizedCandidate;
        isUseful = true;
    end
    return
end

% --- Original Logic (Backward Compatibility) ---
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
    % Fall through to fallback if URI parsing fails
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