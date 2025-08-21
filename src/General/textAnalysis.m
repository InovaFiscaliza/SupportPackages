classdef (Abstract) textAnalysis

    properties (Constant)
        %-----------------------------------------------------------------%
        stopWords    = {'a', 'as', 'e', 'o', 'os', 'da', 'das', 'de', 'do', 'dos', 'em', 'um', 'uma', 'para', 'com', 'que', 'na', 'nas', 'no', 'nos', 'mas'}
        
        specialChars = {'ç', 'ã', 'á', 'à', 'â', 'ê', 'é', 'í', 'î', 'ì', 'ó', 'ò', 'ô', 'õ', 'ú', 'ù', 'û', 'ü', '´', '`'}
        replaceChars = {'c', 'a', 'a', 'a', 'a', 'e', 'e', 'i', 'i', 'i', 'o', 'o', 'o', 'o', 'u', 'u', 'u', 'u'}

        decodeChars  = {'ç', '~', '^', '´', '`'}
    end

    methods (Static = true)
        %-----------------------------------------------------------------%
        function editedWords = normalizeWords(rawWords)        
            editedWords = replace(lower(rawWords), textAnalysis.specialChars, textAnalysis.replaceChars);
        end

        %-----------------------------------------------------------------%
        function [uniqueData, referenceData] = preProcessedData(rawData)
            classData = class(rawData);
            switch classData
                case 'cell'
                    referenceData = rawData;
                case 'categorical'
                    referenceData = cellstr(rawData);
                case {'char', 'string'}
                    referenceData = char(rawData);
                otherwise
                    error('Unexpected datatype')
            end
          
            referenceData = textAnalysis.normalizeWords(referenceData);
            referenceData = replace(referenceData, {',', ';', '.', ':', '?', '!', '"', '''', '(', ')', '[', ']', '{', '}'}, ...
                                                   {' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '});
            referenceData = strtrim(referenceData);
        
            switch classData
                case {'cell', 'categorical'}
                    uniqueData = unique(referenceData, 'stable');
                    uniqueData(cellfun(@(x) isempty(x), uniqueData)) = [];
        
                case {'char', 'string'}
                    uniqueData = referenceData;
            end
        end

        %-----------------------------------------------------------------%
        function [content, encoding] = fileread(fileFullName, regexPattern, encodingList)
            arguments
                fileFullName char
                regexPattern char = ''
                encodingList cell = {'UTF-8', 'ISO-8859-1', 'windows-1251', 'windows-1252'}
            end

            fileID = fopen(fileFullName, 'r');
            if fileID == -1
                error('File not found.');
            end
            
            rawContent = fread(fileID, [1, inf], 'uint8=>uint8');
            fclose(fileID);

            specialChars = strjoin(textAnalysis.decodeChars, '');
            encodingInfo = struct('name', encodingList, 'count', 0);

            if numel(encodingList) > 1
                for ii = 1:numel(encodingList)
                    rawDecoded  = native2unicode(rawContent, encodingList{ii});
                    if ~isempty(regexPattern)
                        rawDecoded = strjoin(regexp(rawDecoded, regexPattern, 'match', 'lineanchors'), '');
                    end
    
                    encodingInfo(ii).count = numel(regexp(rawDecoded, ['[' specialChars ']'], 'match', 'ignorecase'));
                end
            end
            
            [~, idx] = max([encodingInfo.count]);
            encoding = encodingList{idx};
            content  = native2unicode(rawContent, encoding);
        end
    end

end