function jsonStr = jsonencode(jsonObject)
    jsonCompact = jsonencode(jsonObject);

    try
        nChars = numel(jsonCompact);
        buffer = char(zeros(1, nChars*2)); % buffer inicial com folga
        idx = 1;
        
        insideString = false;
        
        for ii = 1:nChars
            currentChar = jsonCompact(ii);
            
            if currentChar == '"' && (ii == 1 || jsonCompact(ii-1) ~= '\')
                insideString = ~insideString;
            end
            
            spaceBefore = '';
            spaceAfter  = '';
            
            if ~insideString
                switch currentChar
                    case {'{', ':', ','}
                        spaceAfter = ' ';
                    case '}'
                        spaceBefore = ' ';
                end
            end
            
            for ch = [spaceBefore currentChar spaceAfter]
                if idx > numel(buffer)
                    buffer = [buffer, char(zeros(1, numel(buffer)))]; 
                end

                buffer(idx) = ch;
                idx = idx + 1;
            end
        end        
        jsonStr = strtrim(buffer(1:idx-1));
        
    catch
        jsonStr = jsonCompact;
    end
end