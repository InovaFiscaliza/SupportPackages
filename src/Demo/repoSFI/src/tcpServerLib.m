classdef tcpServerLib < handle
    % tcpServerLib - Encapsula a infraestrutura de socket do repoSFI.
    %
    % A classe concentra configuracao, reconexao do listener, validacao das
    % mensagens recebidas, delegacao para handlers e registro de log.
    % tcpServerLib - Servidor TCP para processamento de requisicoes
    %
    % Gerencia comunicacao TCP com clientes, recebe requisicoes JSON,
    % processa e retorna respostas. Mantem log de todas as operacoes.
    %
    % Arquitetura:
    %   - MessageValidator: valida mensagens recebidas
    %   - RequestFactory: distribui para handlers especificos
    %   - ServerLogger: mantem historico de operacoes
    %
    % Uso:
    %   server = tcpServerLib()
    %   server.GeneralSettingsPrint()
    %   % Servidor executa em background via timer
    %   while true; pause(1); end
    
    properties (Access = public)
        % Servidor TCP
        Server
        
        % Configuracao
        RootFolder
        General
        
        % Timer para reconexao
        Timer
        
        % Logger
        Logger
        
        % Timestamp de inicializacao
        Time
    end
    
    properties (Constant)
        % Período do timer em segundos
        TimerPeriod = 300
    end
    
    methods (Access = public)
        %==================================================================
        %                         CONSTRUTOR
        %==================================================================
        % Prepara configuracao, logger e timer de conexao do servidor.
        function obj = tcpServerLib()
            appEngine.util.disableWarnings()
            
            % Inicializa paths e configuração
            obj.RootFolder = appEngine.util.RootFolder(class.Constants.appName, tcpServerLib.Path());
            GeneralSettingsRead(obj)
            
            % Inicializa logger
            obj.Logger = server.ServerLogger();
            
            % Inicializa timer para reconexão automática
            obj.TimerCreation()
            
            % Registra timestamp de inicialização
            obj.Time = datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss');
        end
        
        %==================================================================
        %                         DESTRUTOR
        %==================================================================
        % Libera timer e socket para evitar handles pendurados no MATLAB.
        function delete(obj)
            % Para e deleta timer
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer)
                delete(obj.Timer)
            end
            
            % Fecha socket se estiver ativo
            if isa(obj.Server, 'tcpserver.internal.TCPServer') && isvalid(obj.Server)
                hTransport = struct(struct(struct(obj.Server).Client).ClientImpl).Transport;
                if hTransport.Connected
                    hTransport.disconnect()
                end
                delete(obj.Server)
            end
        end
        
        %==================================================================
        %                      MÉTODOS PÚBLICOS
        %==================================================================
        
        %------------------------------------------------------------------
        % Exibe configurações gerais
        %------------------------------------------------------------------
        % Exibe em console a arvore de configuracao carregada do JSON.
        function GeneralSettingsPrint(obj)
            disp("========================================")
            disp("     CONFIGURAÇÕES DO SERVIDOR TCP      ")
            disp("========================================")
            obj.printStruct(obj.General, 0)
            disp("========================================")
        end
        
        %------------------------------------------------------------------
        % Retorna log completo
        %------------------------------------------------------------------
        % Entrega o historico completo acumulado pelo ServerLogger.
        function logTable = getLog(obj)
            logTable = obj.Logger.getLogTable();
        end
        
        %------------------------------------------------------------------
        % Retorna número de transações logadas
        %------------------------------------------------------------------
        % Retorna a quantidade de requisicoes registradas ate o momento.
        function count = getLogCount(obj)
            count = obj.Logger.getLogCount();
        end
        
    end
    
    methods (Access = protected)
        %==================================================================
        %                      MÉTODOS PROTEGIDOS
        %==================================================================
        
        %------------------------------------------------------------------
        % Carrega e valida configurações do JSON
        %------------------------------------------------------------------
        % Carrega configuracoes persistidas e propaga warnings de leitura.
        function GeneralSettingsRead(obj)
            appName    = class.Constants.appName;
            rootFolder = obj.RootFolder;

            [generalSettings, msgWarning] = appEngine.util.generalSettingsLoad(appName, rootFolder);
            if ~isempty(msgWarning)
                warning(msgWarning)
            end

            obj.General = generalSettings;
        end
        
        %------------------------------------------------------------------
        % Cria e inicia timer para reconexão automática
        %------------------------------------------------------------------
        % Cria o timer responsavel por conectar e reconectar o listener TCP.
        function TimerCreation(obj)
            obj.Timer = timer( ...
                "ExecutionMode", "fixedSpacing", ...
                "BusyMode", "queue", ...
                "StartDelay", 0, ...
                "Period", obj.TimerPeriod, ...
                "TimerFcn", @obj.ConnectAttempt ...
                );
            
            start(obj.Timer)
        end
        
        %------------------------------------------------------------------
        % Tenta conectar ou reconectar socket
        %------------------------------------------------------------------
        % Garante que exista um listener ativo ou tenta recria-lo.
        function ConnectAttempt(obj, ~, ~)
            ip = obj.General.tcpServer.IP;
            port = obj.General.tcpServer.Port;
            
            try
                if isa(obj.Server, 'tcpserver.internal.TCPServer') && isvalid(obj.Server)
                    % Se socket existe, tenta reconectar se desconectado
                    hTransport = struct(struct(struct(obj.Server).Client).ClientImpl).Transport;
                    if ~hTransport.Connected
                        hTransport.connect()
                    end
                else
                    % Cria novo socket
                    if ~isempty(obj.Server)
                        delete(obj.Server)
                        obj.Server = [];
                    end

                    % A instancia unica e controlada no main.m; nao derruba
                    % outro processo para tomar a porta.
                    if ~isempty(ip)
                        obj.Server = tcpserver(ip, port);
                    else
                        obj.Server = tcpserver(port);
                    end
                    
                    configureTerminator(obj.Server, "CR/LF")
                    configureCallback(obj.Server, "terminator", @(~, ~) obj.receivedMessage)
                end
                
            catch
                % Silenciosamente tenta novamente no próximo período
            end
        end
        
        %------------------------------------------------------------------
        % Processa mensagens recebidas do cliente
        %------------------------------------------------------------------
        % Consome todas as mensagens pendentes na fila do socket atual.
        function receivedMessage(obj)
            while obj.Server.NumBytesAvailable
                rawMsg = readline(obj.Server);
                
                if isempty(rawMsg)
                    obj.handleEmptyMessage()
                    continue
                end
                
                % Processa cada mensagem recebida
                for ii = 1:numel(rawMsg)
                    obj.processRawMessage(rawMsg{ii});
                end
            end
        end
        
        %------------------------------------------------------------------
        % Processa uma mensagem raw único
        %------------------------------------------------------------------
        % Faz o pipeline completo: decode, validate, dispatch e log.
        function processRawMessage(obj, rawMsg)
            try
                % Decodifica JSON
                decodedMsg = jsondecode(rawMsg);
                
                % Valida mensagem (fields, tipos, auth, authz)
                server.MessageValidator.validateMessage(decodedMsg, obj.General);
                
                % Processa requisição
                requestType = decodedMsg.Request.type;
                answer = handlers.RequestFactory.process(requestType, decodedMsg.Request, obj.General);
                
                % Envia resposta
                obj.sendMessageToClient(struct('Request', decodedMsg.Request, 'Answer', answer))
                
                % Log bem-sucedido
                obj.Logger.logTransaction( ...
                    obj.Server.ClientAddress, ...
                    obj.Server.ClientPort, ...
                    string(rawMsg), ...
                    decodedMsg, ...
                    obj.Server.NumBytesWritten, ...
                    "success" ...
                    )
                
            catch ME
                % Envia erro
                obj.sendMessageToClient(struct('Request', rawMsg, 'Answer', ME.identifier))
                
                % Log com erro
                obj.Logger.logTransaction( ...
                    obj.Server.ClientAddress, ...
                    obj.Server.ClientPort, ...
                    string(rawMsg), ...
                    struct('Request', rawMsg), ...
                    obj.Server.NumBytesWritten, ...
                    string(ME.message) ...
                    )
            end
        end
        
        %------------------------------------------------------------------
        % Manipula mensagem vazia
        %------------------------------------------------------------------
        % Trata leituras vazias para manter o protocolo previsivel.
        function handleEmptyMessage(obj)
            try
                obj.sendMessageToClient(struct('Request', '', 'Answer', 'Invalid request'))
                obj.Logger.logTransaction( ...
                    obj.Server.ClientAddress, ...
                    obj.Server.ClientPort, ...
                    "", ...
                    struct(), ...
                    obj.Server.NumBytesWritten, ...
                    "Empty request" ...
                    )
            catch
            end
        end
        
        %------------------------------------------------------------------
        % Envia mensagem para cliente (encapsulation JSON)
        %------------------------------------------------------------------
        % Encapsula a resposta em <JSON>...</JSON> antes de escrever.
        function sendMessageToClient(obj, structMsg)
            writeline(obj.Server, ['<JSON>' jsonencode(structMsg) '</JSON>'])
        end
        
        %------------------------------------------------------------------
        % Exibe estrutura formatada (configurações)
        %------------------------------------------------------------------
        % Imprime structs aninhadas em formato amigavel para console.
        function printStruct(obj, s, indent)
            fields = fieldnames(s);
            for i = 1:numel(fields)
                name = fields{i};
                value = s.(name);
                prefix = repmat(' ', 1, indent*2);
                
                if isstruct(value)
                    fprintf("%s%s:\n", prefix, name);
                    obj.printStruct(value, indent+1);
                    
                elseif ischar(value) || isstring(value)
                    fprintf("%s%s: %s\n", prefix, name, string(value));
                    
                elseif isnumeric(value) || islogical(value)
                    fprintf("%s%s: %s\n", prefix, name, mat2str(value));
                    
                else
                    fprintf("%s%s: [%s]\n", prefix, name, class(value));
                end
            end
        end
        
    end
    
    methods (Static)
        %==================================================================
        %                      MÉTODOS ESTÁTICOS
        %==================================================================
        
        %------------------------------------------------------------------
        % Retorna path do arquivo atual (usa para resolução de paths)
        %------------------------------------------------------------------
        % Retorna o diretorio do arquivo para resolucao de paths relativos.
        function path = Path()
            path = fileparts(mfilename('fullpath'));
        end
    end
    
end
