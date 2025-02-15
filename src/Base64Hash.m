classdef (Abstract) Base64Hash

    methods (Static)
        %-----------------------------------------------------------------%
        function encodedString = encode(inputString)
            % Convert the input string to a uint8 byte array
            byteArray = unicode2native(inputString, 'UTF-8');
            
            % Encode the byte array to Base64
            encodedString = matlab.net.base64encode(byteArray);
        end
        

        %-----------------------------------------------------------------%
        function decodedString = decode(encodedString)
            % Decode the Base64 string to a uint8 byte array
            byteArray = matlab.net.base64decode(encodedString);
            
            % Convert the byte array back to a string
            decodedString = native2unicode(byteArray, 'UTF-8');
        end
    end

end