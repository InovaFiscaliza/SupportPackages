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
        
            numBytes = numel(input);

            try
                dotNetModule = System.Security.Cryptography.SHA1Managed;
                dotNetModule.Initialize();

                offset = 1;
                while offset <= numBytes
                    last = min(offset + 2^20 - 1, numBytes);
                    chunk = input(offset:last);

                    if last < numBytes
                        dotNetModule.TransformBlock(chunk, 0, numel(chunk), chunk, 0);
                    else
                        dotNetModule.TransformFinalBlock(chunk, 0, numel(chunk));
                    end

                    offset = last + 1;
                end
                hashBytes = uint8(dotNetModule.Hash);
            
            catch dotNetError
                try
                    javaModule = java.security.MessageDigest.getInstance('SHA-1');
        
                    offset = 1;        
                    while offset <= numBytes
                        last = min(offset + 2^30 - 1, numBytes);
                        javaModule.update(input(offset:last));
                        offset = last + 1;
                    end        
                    hashBytes = typecast(javaModule.digest(), 'uint8');
                
                catch javaError
                    error('Hash:sha1:UnexpectedError', 'Both SHA-1 backends failed. DotNet error: "%s", Java error: "%s"', dotNetError.message, javaError.message);
                end
            end

            hashHex = sprintf('%02x', hashBytes);
        end


        % MD5
        function hash = md5(input)

            numBytes = numel(input);

            try
                dotNetModule = System.Security.Cryptography.MD5CryptoServiceProvider;
                dotNetModule.Initialize();

                offset = 1;
                while offset <= numBytes
                    last = min(offset + 2^20 - 1, numBytes);
                    chunk = input(offset:last);

                    if last < numBytes
                        dotNetModule.TransformBlock(chunk, 0, numel(chunk), chunk, 0);
                    else
                        dotNetModule.TransformFinalBlock(chunk, 0, numel(chunk));
                    end

                    offset = last + 1;
                end
                hashBytes = sprintf('%02x', uint8(dotNetModule.Hash));


            catch dotNetError
                try
                    md5 = java.security.MessageDigest.getInstance('MD5');
                    md5.update(typecast(input, 'int8')); % reinterpreta os bits, sem saturar valores >= 128
                    hashBytes = lower(sprintf('%02x', typecast(md5.digest(), 'uint8')));

               catch javaError
                    error('Hash:sha1:UnexpectedError', 'Both MD5 backends failed. DotNet error: "%s", Java error: "%s"', dotNetError.message, javaError.message);
               end
            end
            hash = hashBytes;
        end
    end

end