classdef MessageValidator
    % MessageValidator - Barra mensagens invalidas antes dos handlers.
    %
    % A ideia aqui e falhar cedo e com erro claro: validamos o envelope
    % minimo, autenticacao/autorizacao e o contrato basico do Request.

    methods (Static)
        %------------------------------------------------------------------
        % Valida uma mensagem completa
        %------------------------------------------------------------------
        function validateMessage(decodedMsg, generalSettings)
            requiredFields = {'Key', 'ClientName', 'Request'};
            if ~all(ismember(requiredFields, fields(decodedMsg)))
                error('server:MessageValidator:MissingRequiredFields', ...
                    ['Missing required fields. Expected: ', strjoin(requiredFields, ', ')])
            end

            mustBeTextScalar(decodedMsg.Key)
            mustBeTextScalar(decodedMsg.ClientName)

            if ~isstruct(decodedMsg.Request) || ~isfield(decodedMsg.Request, 'type')
                error('server:MessageValidator:InvalidRequestFormat', ...
                    'The request must be a struct containing a field named "type".')
            end

            if ~ischar(decodedMsg.Request.type) && ~isstring(decodedMsg.Request.type)
                error('server:MessageValidator:InvalidRequestType', ...
                    'Request type must be a string or char array.')
            end

            if ~strcmp(decodedMsg.Key, generalSettings.tcpServer.Key)
                error('server:MessageValidator:IncorrectKey', ...
                    'Incorrect authentication key.')
            end

            clientList = generalSettings.tcpServer.ClientList;
            if ~isempty(clientList) && ~ismember(decodedMsg.ClientName, clientList)
                error('server:MessageValidator:UnauthorizedClient', ...
                    sprintf('Client "%s" is not authorized.', decodedMsg.ClientName))
            end
        end
    end
end
