classdef (Abstract) textFormatGUI

    methods (Static = true)
        %-----------------------------------------------------------------%
        function htmlSource = jsBackDoorContainer(containerName)
            arguments
                containerName char {mustBeMember(containerName, {'jsBackDoor', 'textBox'})}
            end

            MFilePath = fileparts(mfilename('fullpath'));

            switch containerName
                case 'jsBackDoor'
                    htmlSource = fullfile(MFilePath, 'jsBackDoor', 'Container.html');
                case 'textBox'
                    htmlSource = fullfile(MFilePath, 'textBox',    'Container.html');
            end
        end

        %-----------------------------------------------------------------%
        function formattedString = cellstr2ListWithQuotes(unformattedString, bracketType)
            % cellstr >> char
            % {'name1', 'name2', 'name3'} >> '["name1", "name2", "name3"]'
            arguments
                unformattedString string
                bracketType char {mustBeMember(bracketType, {'round', 'square', 'curly', 'none'})} = 'square'
            end

            formattedString = char(strjoin("""" + unformattedString + """", ', '));

            switch bracketType
                case 'round';  formattedString = ['(' formattedString ')'];
                case 'square'; formattedString = ['[' formattedString ']'];
                case 'curly';  formattedString = ['{' formattedString '}'];
            end
        end


        %-----------------------------------------------------------------%
        function formattedString = cellstr2Bullets(unformattedString)
            % cellstr >> char
            % {'name1', 'name2', 'name3'} >> sprintf('• name1\n• name2\n• name3'
            arguments
                unformattedString cell
            end

            formattedString = strjoin(strcat('•&thinsp;', unformattedString), '\n');
        end

        %-----------------------------------------------------------------%
        function formattedString = cellstr2TextField(unformattedString, Delimiter)
            % cellstr >> char
            % {'   name1 ', '   ', 'name2', '  name3', ''} >> 'name1 name2 name3'
            arguments
                unformattedString
                Delimiter char = ' '
            end
            formattedString = strtrim(unformattedString);
            formattedString(cellfun(@(x) isempty(x), formattedString)) = [];
            formattedString = strjoin(formattedString, Delimiter);
        end

        %-----------------------------------------------------------------%
        function formattedString = HTMLParagraph(unformattedString, fontSize)
            arguments
                unformattedString char
                fontSize          double = 12
            end

            unformattedString = replace(strtrim(unformattedString), newline, '<br>');
            formattedString   = sprintf('<p style="font-size: %.0fpx; text-align: justify;">%s</p>', fontSize, unformattedString);
        end

        %-----------------------------------------------------------------%
        function htmlCode = struct2PrettyPrintList(dataStruct, invalidStatus, freeInitialText, outputFormat, dataGroupStyle)
            arguments
                dataStruct      struct
                invalidStatus   char {mustBeMember(invalidStatus, {'print -1', 'delete'})} = 'print -1'
                freeInitialText char = ''
                outputFormat    char {mustBeMember(outputFormat, {'popup', 'textview'})} = 'textview'
                dataGroupStyle  char {mustBeMember(dataGroupStyle, {'upper', 'normal+gray'})} = 'upper'
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

            try
                d = class.Constants.english2portuguese();
            catch
                d = [];
            end

            switch outputFormat
                case 'textview'
                    inlineStyle = 'padding: 10px;';
                case 'popup'
                    inlineStyle = 'user-select: text; font-family: &quot;Helvetica Neue&quot;, Helvetica, Arial, sans-serif; font-size: 11px; font-weight: normal; font-style: normal; color: rgb(0, 0, 0); text-align: justify;';
            end
            
            htmlCode = sprintf('<p style="%s">%s', inlineStyle, freeInitialText);
            for ii = 1:numel(dataStruct)
                dataGroup = dataStruct(ii).group;
                if ~isempty(d) && isKey(d, dataGroup)
                    dataGroup = d(dataGroup);
                end

                switch dataGroupStyle
                    case 'upper'                        
                        dataGroup = upper(dataGroup);
                        dataGroupColor = '';
                    case 'normal+gray'
                        dataGroupColor = 'color: gray; ';
                end

                htmlCode  = sprintf('%s<font style="%sfont-size: 10px;">%s</font>', htmlCode, dataGroupColor, dataGroup);

                if isstruct(dataStruct(ii).value)
                    htmlCode = textFormatGUI.structParser(htmlCode, dataStruct(ii).value, 1, invalidStatus);
                elseif iscellstr(dataStruct(ii).value)
                    htmlCode = sprintf('%s\n%s', htmlCode, strjoin(dataStruct(ii).value, '\n'));
                else
                    htmlCode = sprintf('%s\n%s', htmlCode, dataStruct(ii).value);
                end

                if ii ~= numel(dataStruct)
                    htmlCode = sprintf('%s\n\n', htmlCode);
                end
            end
            htmlCode = replace(sprintf('%s</p>', strtrim(htmlCode)), newline, '<br>');
        end        
        
        %-----------------------------------------------------------------%
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
                        if isequal(fieldValue, -1) && strcmp(invalidStatus, 'delete')
                            continue
                        end
                        fieldValue = strjoin(string(double(fieldValue)), ', ');

                    elseif isdatetime(fieldValue)
                        if hour(fieldValue) || minute(fieldValue) || second(fieldValue)
                            fieldFormat = 'dd/mm/yyyy HH:MM:SS';
                        else
                            fieldFormat = 'dd/mm/yyyy';
                        end
                        fieldValue = datestr(fieldValue, fieldFormat);
            
                    elseif iscellstr(fieldValue) || (isstring(fieldValue) && ~isscalar(fieldValue))
                        fieldValue = strjoin(fieldValue, ', ');
            
                    elseif ismember(recurrenceLevel, [1, 2])
                        if isstruct(fieldValue) || istable(fieldValue)
                            fieldValue = textFormatGUI.array2scalar(fieldValue);
                            fieldValue = textFormatGUI.structParser('', fieldValue, recurrenceLevel+1, invalidStatus);

                        elseif textFormatGUI.isJSON(fieldValue)
                            fieldValue = textFormatGUI.structParser('', jsondecode(fieldValue), recurrenceLevel+1, invalidStatus);

                        elseif iscategorical(fieldValue) && (fieldValue == "-1")
                            continue
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

        %-----------------------------------------------------------------%
        function htmlLOG = editionTable2LOG(originalTable, editedTable, columnNames, editionColor, fontSize)
            arguments
                originalTable (1,:) table
                editedTable         table
                columnNames   (1,:) cell
                editionColor  (1,7) char = '#c94756'
                fontSize      (1,1) double = 11
            end

            if isempty(editedTable) || isequal(originalTable(1,columnNames), editedTable(1,columnNames))
                htmlLOG = 'Não identificada alteração no registro.';
            else
                htmlLOG = {};
                for ii = 1:numel(columnNames)
                    try
                        originalValue = string(originalTable.(columnNames{ii}));
                        editedValue   = string(editedTable.(columnNames{ii}));
    
                        if ~isequal(originalValue, editedValue)
                            htmlLOG{end+1} = sprintf('<b style="color:%s;">%s:</b> "%s" → "%s"', editionColor, columnNames{ii}, originalValue, editedValue);
                        end
                    catch
                    end
                end    
                htmlLOG = strjoin(htmlLOG, '; ');
            end

            htmlLOG = textFormatGUI.HTMLParagraph(htmlLOG, fontSize);
        end        
        
        %-----------------------------------------------------------------%
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
        
        %-----------------------------------------------------------------%
        function status = isJSON(value)
            status = false;
        
            try
                value = jsondecode(value);
                if isstruct(value) && isscalar(value)
                    status = true;
                end
            catch        
            end
        end

        %-----------------------------------------------------------------%
        function cellArray = struct2cellArray(dataStruct)
            structFields = fieldnames(dataStruct);
            structValues = struct2cell(dataStruct);
            
            cellMatrix   = [structFields'; structValues'];
            cellArray    = cellMatrix(:)';
        end
    end
end