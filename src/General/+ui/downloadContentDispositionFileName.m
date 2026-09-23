function fileName = downloadContentDispositionFileName(headerText)
% DOWNLOADCONTENTDISPOSITIONFILENAME Extract and sanitize a source filename.

fileName = '';
if isempty(headerText)
    return
end

singleQuote = char(39);
encodedPattern = ['filename\*\s*=\s*(?:[^', singleQuote, ']*', ...
                  singleQuote, singleQuote, ')?([^;]+)'];
token = regexp(headerText, encodedPattern, 'tokens', 'once', 'ignorecase');
if isempty(token)
    token = regexp(headerText, 'filename\s*=\s*([^;]+)', 'tokens', 'once', 'ignorecase');
end
if isempty(token)
    return
end

fileName = strtrim(token{1});
if numel(fileName) >= 2 && fileName(1) == '"' && fileName(end) == '"'
    fileName = fileName(2:end-1);
end
fileName = percentDecode(fileName);
fileName = regexprep(fileName, '[\\/:*?"<>|]', '_');
fileName = strtrim(fileName);
if isempty(fileName) || ismember(fileName, {'.', '..'})
    fileName = '';
end
end


function value = percentDecode(value)
decoded = '';
index = 1;
while index <= numel(value)
    if value(index) == '%' && index + 2 <= numel(value) && ...
            all(ismember(value(index + 1:index + 2), '0123456789abcdefABCDEF'))
        decoded(end+1) = char(hex2dec(value(index + 1:index + 2))); %#ok<AGROW>
        index = index + 3;
    else
        decoded(end+1) = value(index); %#ok<AGROW>
        index = index + 1;
    end
end
value = decoded;
end
