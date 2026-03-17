classdef tcpServerLib < handle
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
        function logTable = getLog(obj)
            logTable = obj.Logger.getLogTable();
        end
        
        %------------------------------------------------------------------
        % Retorna número de transações logadas
        %------------------------------------------------------------------
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
        function GeneralSettingsRead(obj)
            appName    = class.Constants.appName;
            rootFolder = obj.RootFolder;
            
            try
                % Resolve caminhos
                [projectFolder, programDataFolder] = appEngine.util.Path(appName, rootFolder);
                
                projectFilePath     = fullfile(projectFolder,     'GeneralSettings.json');
                programDataFilePath = fullfile(programDataFolder, 'GeneralSettings.json');
                
                % Garante pasta ProgramData
                if ~isfolder(programDataFolder)
                    mkdir(programDataFolder);
                end
                
                % Valida que arquivo default existe
                if ~isfile(projectFilePath)
                    error("Arquivo default nao encontrado: %s", projectFilePath);
                end
                
                %% Logica de sincronizacao de versoes
                shouldCopyFile = false;
                
                if ~isfile(programDataFilePath)
                    %% Primeira execucao - arquivo nao existe em ProgramData
                    shouldCopyFile = true;
                else
                    %% Arquivo existe - compara versoes
                    try
                        projectConfig = jsondecode(fileread(projectFilePath));
                        programDataConfig = jsondecode(fileread(programDataFilePath));
                        
                        projectVersion = projectConfig.version;
                        programDataVersion = programDataConfig.version;
                        
                        %% Se versao do projeto e mais recente, atualiza
                        if projectVersion > programDataVersion
                            shouldCopyFile = true;
                        end
                    catch
                        %% Se houver erro ao comparar, copia o arquivo
                        shouldCopyFile = true;
                    end
                end
                
                %% Copia arquivo se necessario
                if shouldCopyFile
                    copyfile(projectFilePath, programDataFilePath);
                end
                
                % Sempre le ProgramData
                generalSettings = jsondecode(fileread(programDataFilePath));
                msgWarning = '';
                
            catch ME
                generalSettings = [];
                msgWarning = ME.message;
            end
            
            if ~isempty(msgWarning)
                warning(msgWarning)
            end
            
            obj.General = generalSettings;
        end
        
        %------------------------------------------------------------------
        % Cria e inicia timer para reconexão automática
        %------------------------------------------------------------------
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
                    
                    util.portRelease(port)
                    
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
        function sendMessageToClient(obj, structMsg)
            writeline(obj.Server, ['<JSON>' jsonencode(structMsg) '</JSON>'])
        end
        
        %------------------------------------------------------------------
        % Exibe estrutura formatada (configurações)
        %------------------------------------------------------------------
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
        function path = Path()
            path = fileparts(mfilename('fullpath'));
        end
    end
    
end
