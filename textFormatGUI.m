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
        function formattedString = struct2PrettyPrintList(unformattedString)
            % !! PENDENTE !!
            % Copiar htmlCode_appsStyle.m (SCH)
        end
    end

end