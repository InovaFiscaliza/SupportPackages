classdef (Abstract) textAnalysis

    % Processamento textual orientado à LÍNGUA PORTUGUESA

    properties (Constant)
        %-----------------------------------------------------------------%
        stopWords = struct( ...
            'pt', {{'a', 'as', 'e', 'o', 'os', 'da', 'das', 'de', 'do', 'dos', 'em', 'um', 'uma', 'para', 'com', 'que', 'na', 'nas', 'no', 'nos', 'mas'}}, ...
            'pt_eng', {{'ao', 'aos', 'com', 'como', 'da', 'das', 'de', 'do', 'dos', 'em', 'na', 'nas', 'no', 'nos', 'ou', 'para', 'por', 'que', 'to', 'for', 'in', 'and'}} ...
        )

        accentedChars = {'á', 'à', 'â', 'ã', 'ä', 'é', 'è', 'ê', 'ë', 'í', 'ì', 'î', 'ï', 'ó', 'ò', 'ô', 'õ', 'ö', 'ú', 'ù', 'û', 'ü', 'ç', 'ñ'}
        plainChars = {'a', 'a', 'a', 'a', 'a', 'e', 'e', 'e', 'e', 'i', 'i', 'i', 'i', 'o', 'o', 'o', 'o', 'o', 'u', 'u', 'u', 'u', 'c', 'n'}
        
        commonAccentedChars = {'ç', 'ã', 'á', 'é', 'í', 'ó', 'ú'}
    end

    methods (Static = true)
        %-----------------------------------------------------------------%
        function normalizedWords = normalizeWords(rawWords, stopWordsLanguage)
            arguments
                rawWords
                stopWordsLanguage {mustBeMember(stopWordsLanguage, {'', 'pt', 'pt_eng'})} = ''
            end

            text = lower(rawWords);
            text = replace(text, textAnalysis.accentedChars, textAnalysis.plainChars);
            text = regexprep(text, '[^a-z0-9 ]', ' ');

            if ~isempty(stopWordsLanguage)
                text = regexprep(text, ['\<(' strjoin(textAnalysis.stopWords.(stopWordsLanguage), '|') ')\>'], ' ');
            end
            
            text = regexprep(text, '\s+', ' ');

            normalizedWords = strtrim(text);
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

        %-----------------------------------------------------------------%
        function [list, index] = sort(list)
            if ~iscellstr(list)
                list = cellstr(list);
            end

            normalizedList = textAnalysis.normalizeWords(list);
            [~, index] = sort(normalizedList);
            list = list(index);
        end

        %-----------------------------------------------------------------%
        function words = getStopWords(language, englishContext)
            arguments
                language {mustBeMember(language, {'pt', 'pt_eng'})} = 'pt'
                englishContext {mustBeMember(englishContext, {'', 'MATLAB Built-in'})} = ''
            end

            words = textAnalysis.stopWords.(language);
            if ~isempty(englishContext)
                englishWords = cellstr(stopWords('Language', 'en'));
                words = unique([words, englishWords], 'stable');
            end
        end
    end

end