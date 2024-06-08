classdef (Abstract) textAnalysis

    properties (Constant)
        %-----------------------------------------------------------------%
        stopWords = {'a', 'as', 'e', 'o', 'os', 'da', 'das', 'de', 'do', 'dos', 'em', 'um', 'uma', 'para', 'com', 'que', 'na', 'nas', 'no', 'nos', 'mas'}

    end


    methods (Static = true)
        %-----------------------------------------------------------------%
        function editedWords = normalizeWords(rawWords)        
            editedWords = replace(lower(rawWords), {'ç', 'ã', 'á', 'à', 'â', 'ê', 'é', 'í', 'î', 'ì', 'ó', 'ò', 'ô', 'õ', 'ú', 'ù', 'û', 'ü'}, ...
                                                   {'c', 'a', 'a', 'a', 'a', 'e', 'e', 'i', 'i', 'i', 'o', 'o', 'o', 'o', 'u', 'u', 'u', 'u'});        
        end


        %-----------------------------------------------------------------%
        function formattedString = cellstrGUIStyle(unformattedString)
            % cellstr >> char
            % {'name1', 'name2', 'name3'} >> '["name1", "name2", "name3"]'
            arguments
                unformattedString string
            end
            formattedString = char("[" + strjoin("""" + unformattedString + """", ', ') + "]");
        end
    end

end