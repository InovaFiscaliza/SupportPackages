classdef (Abstract) textAnalysis

    % Processamento textual orientado à LÍNGUA PORTUGUESA

    properties (Constant)
        %-----------------------------------------------------------------%
        stopWords    = {'a', 'as', 'e', 'o', 'os', 'da', 'das', 'de', 'do', 'dos', 'em', 'um', 'uma', 'para', 'com', 'que', 'na', 'nas', 'no', 'nos', 'mas'}
        
        specialChars = {'ç', 'ã', 'á', 'à', 'â', 'ê', 'é', 'í', 'î', 'ì', 'ó', 'ò', 'ô', 'õ', 'ú', 'ù', 'û', 'ü'}
        replaceChars = {'c', 'a', 'a', 'a', 'a', 'e', 'e', 'i', 'i', 'i', 'o', 'o', 'o', 'o', 'u', 'u', 'u', 'u'}

        specialPont  = {',', ';', '.', ':', '?', '!', '"', '''', '(', ')', '[', ']', '{', '}'}
        replacePont  = {' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',  ' ', ' ', ' ', ' ', ' ', ' '}
    end

    methods (Static = true)
        %-----------------------------------------------------------------%
        function editedWords = normalizeWords(rawWords)
            editedWords = strtrim(replace(lower(rawWords), [textAnalysis.specialChars, textAnalysis.specialPont], ...
                                                           [textAnalysis.replaceChars, textAnalysis.replacePont]));
        end

        %-----------------------------------------------------------------%
        function [uniqueData, referenceData] = preProcessedData(rawData, listFlag, uniqueFlag)
            arguments
                rawData
                listFlag   (1,1) logical = true
                uniqueFlag (1,1) logical = true
            end

            if listFlag
                referenceData = cellstr(rawData);
            else
                referenceData = char(rawData);
            end
          
            referenceData = textAnalysis.normalizeWords(referenceData);

            if listFlag && uniqueFlag
                uniqueData = unique(referenceData, 'stable');
                uniqueData(cellfun(@(x) isempty(x), uniqueData)) = [];
            else
                uniqueData = referenceData;
            end
        end
    end

end