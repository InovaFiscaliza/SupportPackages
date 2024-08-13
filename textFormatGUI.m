classdef (Abstract) textFormatGUI

    methods (Static = true)
        %-----------------------------------------------------------------%
        function formattedString = cellstr2ListWithQuotes(unformattedString)
            % cellstr >> char
            % {'name1', 'name2', 'name3'} >> '["name1", "name2", "name3"]'
            arguments
                unformattedString string
            end
            
            formattedString = char("[" + strjoin("""" + unformattedString + """", ', ') + "]");
        end


        %-----------------------------------------------------------------%
        function formattedString = HTMLParagraph(unformattedString)
            arguments
                unformattedString char
            end

            unformattedString = replace(strtrim(unformattedString), newline, '<br>');
            formattedString   = sprintf('<p style="font-size: 12px; text-align: justify;">%s</p>', unformattedString);
        end


        %-----------------------------------------------------------------%
        function htmlCode = struct2PrettyPrintList(dataStruct, invalidStatus, fontSize)
            arguments
                dataStruct    struct
                invalidStatus char {mustBeMember(invalidStatus, {'print -1', 'delete'})} = 'print -1'
                fontSize      char {mustBeMember(fontSize, {'10px', '11px', '12px'})}    = '11px'
            end

            % dataStruct é uma estrutura com os campos "group" e "value". O
            % campo "group" registra apenas uma string com o nome do grupo.
            % O campo "value", por outro lado, é uma estrutura cujos valores
            % dos campos podem ser numéricos, textuais, cellstr ou estruturas 
            % aninhadas (limitada a duas pois cada uma terá o seu próprio 
            % marcador).
            % - Nível 1: •
            % - Nível 2: ○
            % - Nível 3: □

            % Por exemplo:
            % dataStruct    = struct('group', 'COMPUTADOR',            'value', struct('Machine', appVersion.Machine, 'Mode', sprintf('%s - %s', executionMode, appMode)));
            % dataStruct(2) = struct('group', upper(appName),          'value', appVersion.(appName));
            % dataStruct(3) = struct('group', [upper(appName) 'Data'], 'value', struct('releasedData', releasedData, 'numberOfRows', height(rawDataTable), 'numberOfUniqueHom', numel(unique(rawDataTable.("Homologação"))), 'cacheColumns', cacheColumns));
            % dataStruct(4) = struct('group', 'MATLAB',                'value', appVersion.Matlab);
            
            htmlCode = sprintf('<p style="font-family: Helvetica, Arial, sans-serif; font-size: %s; text-align: justify; line-height: 12px; margin: 5px;">', fontSize);
            for ii = 1:numel(dataStruct)
                htmlCode = sprintf('%s<font style="font-size: 10px;"><b>%s</b></font>', htmlCode, dataStruct(ii).group);
                htmlCode = textFormatGUI.structParser(htmlCode, dataStruct(ii).value, 1, invalidStatus);
                htmlCode = sprintf('%s\n\n', htmlCode);
            end
            htmlCode = replace(sprintf('%s</p>', strtrim(htmlCode)), newline, '<br>');
        end
        
        
        %-------------------------------------------------------------------------%
        function htmlCode = structParser(htmlCode, dataStruct, recurrenceLevel, invalidStatus)        
            % Cada projeto deve ter o seu próprio dicionário english2portuguese
            % na classe "Constants". Caso não tenha, não será feito ajuste
            % dos nomes das chaves.
            try
                d = class.Constants.english2portuguese();
            catch
                d = [];
            end
        
            fieldNames = fields(dataStruct);
            for jj = 1:numel(fieldNames)
                fieldName = fieldNames{jj};
                fieldValue = dataStruct.(fieldName);
        
                try
                    if isempty(fieldValue)
                        if strcmp(invalidStatus, 'delete')
                            continue
                        end
                        fieldValue = "-1";
            
                    elseif isnumeric(fieldValue) || islogical(fieldValue)
                        if (fieldValue == -1) && strcmp(invalidStatus, 'delete')
                            continue
                        end
                        fieldValue = strjoin(string(double(fieldValue)), ', ');

                    elseif isdatetime(fieldValue)
                        fieldValue = datestr(fieldValue, 'dd/mm/yyyy');
            
                    elseif iscellstr(fieldValue) || (isstring(fieldValue) && ~isscalar(fieldValue))
                        fieldValue = strjoin(fieldValue, ', ');
            
                    elseif ismember(recurrenceLevel, [1, 2])
                        if isstruct(fieldValue) || istable(fieldValue)
                            fieldValue = textFormatGUI.array2scalar(fieldValue);
                            fieldValue = textFormatGUI.structParser('', fieldValue, recurrenceLevel+1, invalidStatus);

                        elseif textFormatGUI.isJSON(fieldValue) && (recurrenceLevel == 1)
                            fieldValue = textFormatGUI.structParser('', jsondecode(fieldValue), recurrenceLevel+1, invalidStatus);                
                        end
                    end
                    
                catch
                    continue
                end
        
                if ~isempty(d) && isKey(d, fieldName)
                    fieldName = d(fieldName);
                end
                
                switch recurrenceLevel
                    case 1; htmlCode = sprintf('%s\n•&thinsp;<font style="color: gray; font-size: 10px;">%s:</font> %s',                                 htmlCode, fieldName, fieldValue);
                    case 2; htmlCode = sprintf('%s\n&thinsp;&thinsp;○&thinsp;<font style="color: gray; font-size: 10px;">%s:</font> %s',                 htmlCode, fieldName, fieldValue);
                    case 3; htmlCode = sprintf('%s\n&thinsp;&thinsp;&thinsp;&thinsp;□&thinsp;<font style="color: gray; font-size: 10px;">%s:</font> %s', htmlCode, fieldName, fieldValue);
                end
            end
        end
        
        
        %-------------------------------------------------------------------------%
        function editedValue = array2scalar(rawValue)
            if istable(rawValue)
                rawValue = table2struct(rawValue);
            end
        
            if numel(rawValue) > 1
                fieldNames = fields(rawValue);
                if numel(fieldNames) == 2
                    for ii = 1:numel(rawValue)
                        editedValue.(matlab.lang.makeValidName(rawValue(ii).(fieldNames{1}))) = rawValue(ii).(fieldNames{2});
                    end
                else
                    editedValue = -1;
                end
            else
                editedValue = rawValue;
            end
        end
        
        
        %-------------------------------------------------------------------------%
        function status = isJSON(value)
            status = false;
        
            try
                if isstruct(jsondecode(value))
                    status = true;
                end
            catch        
            end
        end
    end
end