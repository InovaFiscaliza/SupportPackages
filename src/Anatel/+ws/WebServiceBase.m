classdef (Abstract, AllowedSubclasses={?ws.eFiscaliza, ?ws.Fiscaliza, ?ws.SEI, ?ws.ReceitaFederal}) WebServiceBase

    methods (Static = true)
        %-----------------------------------------------------------------%
        function response = request(url, method, header, body)
            arguments
                url    char
                method char {mustBeMember(method, {'GET', 'POST', 'PUT'})}
                header = {}
                body   = ''
            end

            if ~isempty(header)
                header = matlab.net.http.field.GenericField(header{:});
            end

            request  = matlab.net.http.RequestMessage(method, header, body);
            response = request.send(url);

            if ~isa(response, 'matlab.net.http.ResponseMessage')
                error('Unexpected response type')
            end
        end
    end


    methods
        %-----------------------------------------------------------------%
        function encodedString = base64encode(obj, inputString)
            byteArray = unicode2native(inputString, 'UTF-8');
            encodedString = matlab.net.base64encode(byteArray);
        end

        %-----------------------------------------------------------------%
        function decodedString = base64decode(obj, encodedString)
            byteArray = matlab.net.base64decode(encodedString);
            decodedString = native2unicode(byteArray, 'UTF-8');
        end
    end

end