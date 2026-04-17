classdef MessageValidator
    % MessageValidator - Barra mensagens invalidas antes dos handlers.
    %
    % A ideia aqui e falhar cedo e com erro claro: primeiro validamos o
    % envelope minimo, depois autenticacao/autorizacao e so entao o handler.
    % MessageValidator - Valida mensagens JSON recebidas do cliente
    %
    % Responsável por verificar:
    %   - Estrutura JSON (presença de campos obrigatórios)
    %   - Tipos de dados
    %   - Autenticação (chave)
    %   - Autorização (cliente na whitelist)
    
    properties (Constant)
        % Campos minimos para autenticar, identificar o cliente e despachar.
        REQUIRED_FIELDS = {'Key', 'ClientName', 'Request'}
        % Campo que define para onde o Request sera roteado.
        REQUEST_FIELD = 'type'
    end
    
    methods (Static)
        %------------------------------------------------------------------
        % Valida una mensagem completa
        %------------------------------------------------------------------
        % A ordem e proposital para devolver erros mais especificos cedo.
        function validateMessage(decodedMsg, generalSettings)
            % Validate required fields
            server.MessageValidator.validateFields(decodedMsg);
            
            % Validate data types
            server.MessageValidator.validateDataTypes(decodedMsg);
            
            % Validate request structure
            server.MessageValidator.validateRequestStructure(decodedMsg);
            
            % Validate authentication
            server.MessageValidator.validateAuthentication(decodedMsg, generalSettings);
            
            % Validate authorization
            server.MessageValidator.validateAuthorization(decodedMsg, generalSettings);
        end
        
        %------------------------------------------------------------------
        % Valida presença de campos obrigatórios
        %------------------------------------------------------------------
        % Sem esses campos nao da nem para autenticar nem para despachar.
        function validateFields(decodedMsg)
            if ~all(ismember(server.MessageValidator.REQUIRED_FIELDS, fields(decodedMsg)))
                error('server:MessageValidator:MissingRequiredFields', ...
                    ['Missing required fields. Expected: ', strjoin(server.MessageValidator.REQUIRED_FIELDS, ', ')])
            end
        end
        
        %------------------------------------------------------------------
        % Valida tipos de dados
        %------------------------------------------------------------------
        % Protege as etapas seguintes contra mensagens estruturalmente ruins.
        function validateDataTypes(decodedMsg)
            mustBeTextScalar(decodedMsg.Key)
            mustBeTextScalar(decodedMsg.ClientName)
            
            if ~isstruct(decodedMsg.Request) || ~isfield(decodedMsg.Request, server.MessageValidator.REQUEST_FIELD)
                error('server:MessageValidator:InvalidRequestFormat', ...
                    'The request must be a struct containing a field named "type".')
            end
        end
        
        %------------------------------------------------------------------
        % Valida estrutura da requisição
        %------------------------------------------------------------------
        % Aqui validamos so o contrato minimo comum a qualquer Request.
        function validateRequestStructure(decodedMsg)
            % Este método pode ser expandido para validações específicas
            % de cada tipo de requisição
            if ~ischar(decodedMsg.Request.type) && ~isstring(decodedMsg.Request.type)
                error('server:MessageValidator:InvalidRequestType', ...
                    'Request type must be a string or char array.')
            end
        end
        
        %------------------------------------------------------------------
        % Valida autenticação (chave)
        %------------------------------------------------------------------
        % A chave e a primeira barreira antes de qualquer processamento.
        function validateAuthentication(decodedMsg, generalSettings)
            correctKey = generalSettings.tcpServer.Key;
            if ~strcmp(decodedMsg.Key, correctKey)
                error('server:MessageValidator:IncorrectKey', ...
                    'Incorrect authentication key.')
            end
        end
        
        %------------------------------------------------------------------
        % Valida autorização (cliente na whitelist)
        %------------------------------------------------------------------
        % Whitelist vazia significa "sem restricao"; caso contrario, o
        % cliente precisa estar explicitamente liberado.
        function validateAuthorization(decodedMsg, generalSettings)
            clientList = generalSettings.tcpServer.ClientList;
            
            if ~isempty(clientList) && ~ismember(decodedMsg.ClientName, clientList)
                error('server:MessageValidator:UnauthorizedClient', ...
                    sprintf('Client "%s" is not authorized.', decodedMsg.ClientName))
            end
        end
    end
end
