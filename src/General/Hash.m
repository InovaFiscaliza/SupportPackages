classdef (Abstract) Hash

    methods (Static)
        %-----------------------------------------------------------------%
        % BASE64
        % Função de hash bidirecional.
        %-----------------------------------------------------------------%
        function encodedString = base64encode(inputString)
            % Convert the input string to a uint8 byte array
            byteArray = unicode2native(inputString, 'UTF-8');
            
            % Encode the byte array to Base64
            encodedString = matlab.net.base64encode(byteArray);
        end        

        %-----------------------------------------------------------------%
        function decodedString = base64decode(encodedString)
            % Decode the Base64 string to a uint8 byte array
            byteArray = matlab.net.base64decode(encodedString);
            
            % Convert the byte array back to a string
            decodedString = native2unicode(byteArray, 'UTF-8');
        end


        %-----------------------------------------------------------------%
        % SHA-1
        % Função de hash unidirecional, limitado a tipos de dados que possam
        % ser convertidos para "uint8". Em resumo, aceita-se qualquer tipo 
        % numérico ("double", "single", "uint32" etc), "logical" e "char".
        %-----------------------------------------------------------------%
        function hashHex = sha1(input)
            arguments
                input uint8
            end

            md = java.security.MessageDigest.getInstance('SHA-1');
            md.update(input(:));
            
            hashBytes = typecast(md.digest(), 'uint8'); 
            hashHex = sprintf('%02x', hashBytes);
        end
    end

end