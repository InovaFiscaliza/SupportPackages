classdef (Abstract, AllowedSubclasses={?ws.eFiscaliza, ?ws.Fiscaliza, ?ws.SEI}) WebServiceBase

    methods (Static = true)
        %-----------------------------------------------------------------%
        function response = request(url, method, header, body)
            arguments
                url    char
                method char {mustBeMember(method, {'GET', 'POST', 'PUT'})}
                header = {}
                body   = ''
            end

            try
                if ~isempty(header)
                    header = matlab.net.http.field.GenericField(header{:});
                end

                request  = matlab.net.http.RequestMessage(method, header, body);
                response = request.send(url);
            catch ME
                response = ME.message;
            end
        end
    end

end