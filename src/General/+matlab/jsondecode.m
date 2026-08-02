function [s, d] = jsondecode(jsonStr, outputFormat)
    arguments
        jsonStr
        outputFormat {mustBeMember(outputFormat, {'struct', 'table'})} = 'struct'
    end

    s = jsondecode(jsonStr);
    d = buildKeyMap(jsonStr);

    if strcmp(outputFormat, 'table')
        s = structToFieldValueTable(s, d);
    end
end


%-------------------------------------------------------------------------%
function d = buildKeyMap(jsonStr)
    keyList = extractKeysFromJson(jsonStr);
    keyList = string(keyList);
    d = dictionary(keyList, matlab.lang.makeValidName(keyList));
end


%-------------------------------------------------------------------------%
function t = structToFieldValueTable(s, d)
    if ~isscalar(s)
        error('A entrada deve ser uma estrutura escalar.')
    end

    convertedFields = fieldnames(s);
    originalFields = convertedFields;
    
    keyList = keys(d);
    valueList = values(d);

    for ii = 1:numel(convertedFields)
        idx = find(strcmp(valueList, convertedFields{ii}), 1);
        if ~isempty(idx)
            originalFields{ii} = char(keyList(idx));
        end
    end

    valueCell = struct2cell(s);
    t = table(originalFields, valueCell, 'VariableNames', {'field', 'value'});

end


%-------------------------------------------------------------------------%
function keyList = extractKeysFromJson(jsonStr)
    jsonStr = strtrim(char(jsonStr));
    keyList = {};

    if jsonStr(1) == '{'
        jsonStr = ['{' strtrim(jsonStr(2:end))];
        idx = 2; % Pular o '{'

            while idx <= numel(jsonStr) || (idx < numel(jsonStr) && jsonStr(idx) == '}')
                % Procurar a próxima chave
                if jsonStr(idx) == '"'
                    % Encontrar o final da chave
                    idx1 = idx + 1;
                    idx2 = find(jsonStr(idx1:end) == '"', 1) + idx1 - 2;                
                    key  = jsonStr(idx1:idx2);
                    
                    if ~ismember(key, keyList)
                        keyList{end+1} = key;
                    end
                    
                    % Mover o índice para depois da chave
                    idx = idx2 + 1;
                    
                    % Pular o próximo ':' e o valor
                    [idx, keyList] = skipValue(jsonStr, idx + 1, keyList);
    
                else
                    idx = idx + 1;
                end
            end

    else
        error('A string JSON fornecida não começa com um objeto.');
    end
end


%-------------------------------------------------------------------------%
function [idx, keyList] = skipValue(jsonStr, idx, keyList)    
    % Pular espaços
    while jsonStr(idx) == ' ' || jsonStr(idx) == ':'
        idx = idx + 1;
    end
    
    % Pular o valor com base no tipo
    if jsonStr(idx) == '"'
        % String
        idx = idx + 1;
        while jsonStr(idx) ~= '"'
            if jsonStr(idx) == '\'
                idx = idx + 2; % Pular escape character
            else
                idx = idx + 1;
            end
        end
        idx = idx + 1; % Pular o '"'

    elseif jsonStr(idx) == '{'
        keyList = unique([keyList, extractKeysFromJson(jsonStr(idx:end))], 'stable');

        % Objeto
        idx = idx + 1;
        braceCount = 1;
        while braceCount > 0
            if jsonStr(idx) == '{'
                braceCount = braceCount + 1;

            elseif jsonStr(idx) == '}'
                braceCount = braceCount - 1;

            elseif jsonStr(idx) == '"'
                idx = idx + 1;
                while jsonStr(idx) ~= '"'
                    if jsonStr(idx) == '\'
                        idx = idx + 2; % Pular escape character
                    else
                        idx = idx + 1;
                    end
                end
            end
            idx = idx + 1;
        end

    elseif jsonStr(idx) == '['
        % Array
        idx = idx + 1;
        bracketCount = 1;
        while bracketCount > 0
            if jsonStr(idx) == '['
                bracketCount = bracketCount + 1;

            elseif jsonStr(idx) == ']'
                bracketCount = bracketCount - 1;

            elseif jsonStr(idx) == '"'
                idx = idx + 1;
                while jsonStr(idx) ~= '"'
                    if jsonStr(idx) == '\'
                        idx = idx + 2; % Pular escape character
                    else
                        idx = idx + 1;
                    end
                end
            end
            idx = idx + 1;
        end

    else
        % Número ou outro valor simples
        while idx <= length(jsonStr) && ~any(jsonStr(idx) == [',', '}', ']'])
            idx = idx + 1;
        end
    end
    
    % Pular qualquer espaço ou vírgula após o valor
    while idx <= length(jsonStr) && any(jsonStr(idx) == [',', ' '])
        idx = idx + 1;
    end
end