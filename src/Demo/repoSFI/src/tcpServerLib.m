classdef tcpServerLib < handle
    % tcpServerLib - Encapsula a infraestrutura de socket do repoSFI.
    %
    % A classe concentra configuracao, reconexao do listener, validacao das
    % mensagens recebidas, delegacao para handlers e registro de log.
    
    properties (Access = public)
        % Servidor TCP
        Server
        
        % Configuracao
        RootFolder
        General
        
        % Timer para reconexao
        Timer
        
        % Historico em memoria das transacoes processadas.
        % Nao e o mesmo papel do RuntimeLog persistente em disco.
        Logger
        
        % Timestamp de inicializacao
        Time

        % Periodo configurado para o timer de reconexao do listener.
        TimerPeriodSeconds = 300
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
            server.RuntimeLog.logInfo( ...
                'tcpServerLib.constructor', ...
                'Instancia do servidor criada.', ...
                obj.buildConnectionContext());
            
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
                try
                    stop(obj.Timer)
                catch ME
                    server.RuntimeLog.logWarning( ...
                        'tcpServerLib.delete', ...
                        'Falha ao interromper o timer durante o encerramento.', ...
                        obj.buildExceptionDetails(ME));
                end

                try
                    delete(obj.Timer)
                catch ME
                    server.RuntimeLog.logWarning( ...
                        'tcpServerLib.delete', ...
                        'Falha ao deletar o timer durante o encerramento.', ...
                        obj.buildExceptionDetails(ME));
                end
            end
            
            % Fecha socket se estiver ativo
            if isa(obj.Server, 'tcpserver.internal.TCPServer') && isvalid(obj.Server)
                try
                    hTransport = struct(struct(struct(obj.Server).Client).ClientImpl).Transport;
                    if hTransport.Connected
                        hTransport.disconnect()
                    end
                catch ME
                    server.RuntimeLog.logWarning( ...
                        'tcpServerLib.delete', ...
                        'Falha ao desconectar o transporte TCP durante o encerramento.', ...
                        obj.buildExceptionDetails(ME));
                end

                try
                    delete(obj.Server)
                catch ME
                    server.RuntimeLog.logWarning( ...
                        'tcpServerLib.delete', ...
                        'Falha ao deletar o servidor TCP durante o encerramento.', ...
                        obj.buildExceptionDetails(ME));
                end
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

        %------------------------------------------------------------------
        % Retorna snapshot resumido da saude do servidor
        %------------------------------------------------------------------
        function health = getRuntimeHealth(obj)
            health = struct( ...
                'Timestamp', string(datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss')), ...
                'UptimeSeconds', obj.getUptimeSeconds(), ...
                'ServerValid', obj.isServerValid(), ...
                'ServerConnected', obj.isServerConnected(), ...
                'TimerValid', obj.isTimerValid(), ...
                'TimerRunning', string(obj.safeTimerRunningState()), ...
                'ReadyForRequest', obj.isReadyForRequest(), ...
                'ConfiguredIP', string(obj.safeGeneralField('IP')), ...
                'ConfiguredPort', obj.safeGeneralPort(), ...
                'CurrentLogCount', obj.getLogCount(), ...
                'NumBytesAvailable', obj.safeNumBytesAvailable(), ...
                'NumBytesWritten', obj.safeNumBytesWritten());
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
                server.RuntimeLog.logWarning( ...
                    'tcpServerLib.GeneralSettingsRead', ...
                    'Aviso ao carregar configuracoes gerais.', ...
                    struct('WarningMessage', string(msgWarning), 'RootFolder', string(rootFolder)));
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
                "Period", obj.TimerPeriodSeconds, ...
                "TimerFcn", @obj.ConnectAttempt, ...
                "ErrorFcn", @obj.HandleTimerError ...
                );
            
            start(obj.Timer)
            server.RuntimeLog.logInfo( ...
                'tcpServerLib.TimerCreation', ...
                sprintf('Timer de reconexao iniciado com periodo de %d segundos.', obj.TimerPeriodSeconds), ...
                obj.buildConnectionContext());
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
                    reconnected = false;
                    if ~hTransport.Connected
                        hTransport.connect()
                        reconnected = true;
                    end

                    obj.configureServerListener()
                    if reconnected
                        server.RuntimeLog.logInfo( ...
                            'tcpServerLib.ConnectAttempt', ...
                            'Listener TCP reconectado com sucesso.', ...
                            obj.buildConnectionContext());
                    end
                else
                    % Cria novo socket
                    obj.disposeServer()

                    % A instancia unica e controlada no main.m; nao derruba
                    % outro processo para tomar a porta.
                    if ~isempty(ip)
                        obj.Server = tcpserver(ip, port);
                    else
                        obj.Server = tcpserver(port);
                    end
                    obj.configureServerListener()
                    server.RuntimeLog.logInfo( ...
                        'tcpServerLib.ConnectAttempt', ...
                        'Listener TCP criado com sucesso.', ...
                        obj.buildConnectionContext());
                end
                
            catch ME
                server.RuntimeLog.logException( ...
                    'tcpServerLib.ConnectAttempt', ...
                    ME, ...
                    obj.buildExceptionDetails(ME));
                % O proximo ciclo do timer fara uma nova tentativa.
            end
        end
        
        %------------------------------------------------------------------
        % Processa mensagens recebidas do cliente
        %------------------------------------------------------------------
        % Consome todas as mensagens pendentes na fila do socket atual.
        function receivedMessage(obj)
            try
                while obj.Server.NumBytesAvailable
                    rawMsg = readline(obj.Server);
                    rawMessages = obj.normalizeRawMessages(rawMsg);

                    if isempty(rawMessages)
                        obj.handleEmptyMessage()
                        continue
                    end

                    % Processa cada mensagem recebida
                    for ii = 1:numel(rawMessages)
                        if strlength(rawMessages{ii}) == 0
                            obj.handleEmptyMessage()
                        else
                            obj.processRawMessage(rawMessages{ii});
                        end
                    end
                end
            catch ME
                server.RuntimeLog.logException( ...
                    'tcpServerLib.receivedMessage', ...
                    ME, ...
                    obj.buildExceptionDetails(ME));
                obj.disposeServer();
                obj.attemptImmediateReconnect( ...
                    'Falha no callback de leitura; listener sera recriado imediatamente.');
            end
        end
        
        %------------------------------------------------------------------
        % Processa uma mensagem raw único
        %------------------------------------------------------------------
        % Faz o pipeline completo: decode, validate, dispatch e log.
        function processRawMessage(obj, rawMsg)
            try
                decodedMsg = jsondecode(rawMsg);
                server.MessageValidator.validateMessage(decodedMsg, obj.General);

                requestType = string(decodedMsg.Request.type);
                switch lower(requestType)
                    case "diagnostic"
                        answer = handlers.DiagnosticHandler.handle();

                    case "fileread"
                        answer = handlers.FileReadHandler.handle(decodedMsg.Request, obj.General);

                    otherwise
                        error('tcpServerLib:UnknownRequestType', ...
                            sprintf('Unknown request type: "%s"', requestType))
                end

                obj.sendMessageToClient(struct('Request', decodedMsg.Request, 'Answer', answer))
                obj.Logger.logTransaction( ...
                    obj.safeClientAddress(), ...
                    obj.safeClientPort(), ...
                    string(rawMsg), ...
                    decodedMsg, ...
                    obj.safeNumBytesWritten(), ...
                    "success" ...
                    )
            catch ME
                try
                    obj.sendMessageToClient(struct('Request', rawMsg, 'Answer', ME.identifier))
                catch replyError
                    server.RuntimeLog.logException( ...
                        'tcpServerLib.processRawMessage.reply', ...
                        replyError, ...
                        obj.buildExceptionDetails(replyError, rawMsg));
                end

                try
                    obj.Logger.logTransaction( ...
                        obj.safeClientAddress(), ...
                        obj.safeClientPort(), ...
                        string(rawMsg), ...
                        struct('Request', rawMsg), ...
                        obj.safeNumBytesWritten(), ...
                        string(ME.identifier) ...
                        )
                catch logError
                    server.RuntimeLog.logException( ...
                        'tcpServerLib.processRawMessage.logTransaction', ...
                        logError, ...
                        obj.buildExceptionDetails(logError, rawMsg));
                end
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
                    obj.safeClientAddress(), ...
                    obj.safeClientPort(), ...
                    "", ...
                    struct(), ...
                    obj.safeNumBytesWritten(), ...
                    "Empty request" ...
                    )
            catch ME
                server.RuntimeLog.logException( ...
                    'tcpServerLib.handleEmptyMessage', ...
                    ME, ...
                    obj.buildExceptionDetails(ME));
            end
        end
        
        %------------------------------------------------------------------
        % Envia mensagem para cliente (encapsulation JSON)
        %------------------------------------------------------------------
        % Encapsula a resposta em <JSON>...</JSON> antes de escrever.
        function sendMessageToClient(obj, structMsg)
            try
                writeline(obj.Server, ['<JSON>' jsonencode(structMsg) '</JSON>'])
            catch ME
                server.RuntimeLog.logException( ...
                    'tcpServerLib.sendMessageToClient', ...
                    ME, ...
                    obj.buildExceptionDetails(ME));
                obj.disposeServer();
                obj.attemptImmediateReconnect( ...
                    'Falha ao responder cliente; listener sera recriado imediatamente.');
                rethrow(ME)
            end
        end

        %------------------------------------------------------------------
        % Registra erro disparado pelo timer
        %------------------------------------------------------------------
        function HandleTimerError(obj, ~, eventData)
            server.RuntimeLog.logException( ...
                'tcpServerLib.TimerError', ...
                obj.extractTimerException(eventData), ...
                obj.buildTimerErrorDetails(eventData));
            obj.recreateTimer('Erro no timer de reconexao detectado pelo MATLAB timer.');
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

        %------------------------------------------------------------------
        % Normaliza retorno de readline para uma celula de strings
        %------------------------------------------------------------------
        function rawMessages = normalizeRawMessages(~, rawMsg)
            rawMessages = {};

            if isempty(rawMsg)
                return;
            end

            if iscell(rawMsg)
                rawMessages = cellfun(@string, rawMsg, 'UniformOutput', false);
            elseif isstring(rawMsg)
                rawMessages = arrayfun(@(msg) string(msg), rawMsg, 'UniformOutput', false);
            elseif ischar(rawMsg)
                rawMessages = {string(rawMsg)};
            else
                rawMessages = {string(rawMsg)};
            end
        end

        %------------------------------------------------------------------
        % Contexto resumido de conexao para diagnostico
        %------------------------------------------------------------------
        function details = buildConnectionContext(obj)
            details = struct( ...
                'RootFolder', string(obj.RootFolder), ...
                'IP', string(obj.safeGeneralField('IP')), ...
                'Port', obj.safeGeneralPort(), ...
                'ServerValid', obj.isServerValid(), ...
                'TimerValid', obj.isTimerValid(), ...
                'TimerRunning', string(obj.safeTimerRunningState()));
        end

        %------------------------------------------------------------------
        % Detalhes padrao de excecao
        %------------------------------------------------------------------
        function details = buildExceptionDetails(obj, ME, rawMsg)
            if nargin < 3
                rawMsg = "";
            end

            details = struct( ...
                'Identifier', string(ME.identifier), ...
                'Message', string(ME.message), ...
                'StackTop', string(obj.describeExceptionTopFrame(ME)), ...
                'ClientAddress', string(obj.safeClientAddress()), ...
                'ClientPort', obj.safeClientPort(), ...
                'NumBytesAvailable', obj.safeNumBytesAvailable(), ...
                'NumBytesWritten', obj.safeNumBytesWritten(), ...
                'RawMessage', obj.truncateText(string(rawMsg), 4000), ...
                'Connection', obj.buildConnectionContext());
        end

        %------------------------------------------------------------------
        % Detalhes do erro do timer
        %------------------------------------------------------------------
        function details = buildTimerErrorDetails(obj, eventData)
            details = obj.buildConnectionContext();

            try
                if isstruct(eventData) && isfield(eventData, 'Type')
                    details.TimerEventType = string(eventData.Type);
                elseif isobject(eventData) && isprop(eventData, 'Type')
                    details.TimerEventType = string(eventData.Type);
                else
                    details.TimerEventType = "";
                end
            catch
                details.TimerEventType = "";
            end
        end

        %------------------------------------------------------------------
        % Extrai excecao do evento do timer
        %------------------------------------------------------------------
        function exceptionOrMessage = extractTimerException(~, eventData)
            exceptionOrMessage = 'Erro sem detalhes fornecidos pelo timer.';

            try
                if isstruct(eventData) && isfield(eventData, 'Data') && isa(eventData.Data, 'MException')
                    exceptionOrMessage = eventData.Data;
                elseif isobject(eventData) && isprop(eventData, 'Data') && isa(eventData.Data, 'MException')
                    exceptionOrMessage = eventData.Data;
                end
            catch
                exceptionOrMessage = 'Falha ao extrair detalhes do erro do timer.';
            end
        end

        %------------------------------------------------------------------
        % Retorna campo de configuracao do bloco tcpServer
        %------------------------------------------------------------------
        function value = safeGeneralField(obj, fieldName)
            value = '';

            try
                if isstruct(obj.General) && isfield(obj.General, 'tcpServer') && isfield(obj.General.tcpServer, fieldName)
                    value = obj.General.tcpServer.(fieldName);
                end
            catch
                value = '';
            end
        end

        %------------------------------------------------------------------
        % Porta configurada, quando disponivel
        %------------------------------------------------------------------
        function port = safeGeneralPort(obj)
            port = NaN;

            try
                if isstruct(obj.General) && isfield(obj.General, 'tcpServer') && isfield(obj.General.tcpServer, 'Port')
                    port = double(obj.General.tcpServer.Port);
                end
            catch
                port = NaN;
            end
        end

        %------------------------------------------------------------------
        % Indica se o servidor TCP esta valido
        %------------------------------------------------------------------
        function tf = isServerValid(obj)
            tf = false;

            try
                tf = isa(obj.Server, 'tcpserver.internal.TCPServer') && isvalid(obj.Server);
            catch
                tf = false;
            end
        end

        %------------------------------------------------------------------
        % Indica se o transporte TCP esta conectado
        %------------------------------------------------------------------
        function tf = isServerConnected(obj)
            tf = false;

            try
                if obj.isServerValid()
                    hTransport = struct(struct(struct(obj.Server).Client).ClientImpl).Transport;
                    tf = logical(hTransport.Connected);
                end
            catch
                tf = false;
            end
        end

        %------------------------------------------------------------------
        % Indica se o timer esta valido
        %------------------------------------------------------------------
        function tf = isTimerValid(obj)
            tf = false;

            try
                tf = ~isempty(obj.Timer) && isvalid(obj.Timer);
            catch
                tf = false;
            end
        end

        %------------------------------------------------------------------
        % Estado atual do timer
        %------------------------------------------------------------------
        function runningState = safeTimerRunningState(obj)
            runningState = '';

            try
                if obj.isTimerValid()
                    runningState = char(obj.Timer.Running);
                end
            catch
                runningState = '';
            end
        end

        %------------------------------------------------------------------
        % Indica se a instancia esta pronta para nova requisicao
        %------------------------------------------------------------------
        % Esse sinal exige listener e timer saudaveis.
        function tf = isReadyForRequest(obj)
            tf = false;

            try
                timerRunning = strcmpi(obj.safeTimerRunningState(), 'on');
                tf = obj.isServerValid() && ...
                    obj.isServerConnected() && ...
                    obj.isTimerValid() && ...
                    timerRunning;
            catch
                tf = false;
            end
        end

        %------------------------------------------------------------------
        % Uptime em segundos da instancia atual
        %------------------------------------------------------------------
        % O uptime ajuda a decidir reciclages preventivas sem depender de
        % log externo ou PID.
        function uptimeSeconds = getUptimeSeconds(obj)
            uptimeSeconds = NaN;

            try
                if ~isempty(obj.Time)
                    uptimeSeconds = seconds(datetime('now') - obj.Time);
                end
            catch
                uptimeSeconds = NaN;
            end
        end

        %------------------------------------------------------------------
        % Endereco do cliente, se disponivel
        %------------------------------------------------------------------
        function clientAddress = safeClientAddress(obj)
            clientAddress = '-';

            try
                if obj.isServerValid()
                    clientAddress = char(obj.Server.ClientAddress);
                end
            catch
                clientAddress = '-';
            end
        end

        %------------------------------------------------------------------
        % Porta do cliente, se disponivel
        %------------------------------------------------------------------
        function clientPort = safeClientPort(obj)
            clientPort = NaN;

            try
                if obj.isServerValid()
                    clientPort = double(obj.Server.ClientPort);
                end
            catch
                clientPort = NaN;
            end
        end

        %------------------------------------------------------------------
        % Bytes disponiveis no socket
        %------------------------------------------------------------------
        function numBytesAvailable = safeNumBytesAvailable(obj)
            numBytesAvailable = NaN;

            try
                if obj.isServerValid()
                    numBytesAvailable = double(obj.Server.NumBytesAvailable);
                end
            catch
                numBytesAvailable = NaN;
            end
        end

        %------------------------------------------------------------------
        % Bytes escritos no socket
        %------------------------------------------------------------------
        function numBytesWritten = safeNumBytesWritten(obj)
            numBytesWritten = NaN;

            try
                if obj.isServerValid()
                    numBytesWritten = double(obj.Server.NumBytesWritten);
                end
            catch
                numBytesWritten = NaN;
            end
        end

        %------------------------------------------------------------------
        % Descreve o topo da stack para facilitar diagnostico
        %------------------------------------------------------------------
        function topFrame = describeExceptionTopFrame(~, ME)
            topFrame = '';

            try
                if ~isempty(ME.stack)
                    topFrame = sprintf('%s:%d', ME.stack(1).name, ME.stack(1).line);
                end
            catch
                topFrame = '';
            end
        end

        %------------------------------------------------------------------
        % Limita textos muito grandes no log persistente
        %------------------------------------------------------------------
        function text = truncateText(~, text, maxLength)
            text = string(text);

            if strlength(text) > maxLength
                text = extractBefore(text, maxLength + 1) + " [truncated]";
            end
        end

        %------------------------------------------------------------------
        % Reaplica terminador e callback ao listener atual
        %------------------------------------------------------------------
        % Em alguns cenarios de reconexao, vale garantir explicitamente
        % que o callback continua apontando para receivedMessage.
        function configureServerListener(obj)
            if ~obj.isServerValid()
                return
            end

            configureTerminator(obj.Server, "CR/LF")
            configureCallback(obj.Server, "terminator", @(~, ~) obj.receivedMessage)
        end

        %------------------------------------------------------------------
        % Descarta o objeto tcpserver atual, se existir
        %------------------------------------------------------------------
        % Quando um callback de leitura/escrita falha em baixo nivel, o
        % processo pode continuar vivo com um listener inutil. Limpar o
        % handle permite recriar a porta com o caminho de reconexao.
        function disposeServer(obj)
            if isempty(obj.Server)
                obj.Server = [];
                return
            end

            if obj.isServerValid()
                try
                    hTransport = struct(struct(struct(obj.Server).Client).ClientImpl).Transport;
                    if hTransport.Connected
                        hTransport.disconnect()
                    end
                catch
                end
            end

            try
                delete(obj.Server)
            catch
            end

            obj.Server = [];
        end

        %------------------------------------------------------------------
        % Descarta o timer atual, se existir
        %------------------------------------------------------------------
        function disposeTimer(obj)
            if isempty(obj.Timer)
                obj.Timer = [];
                return
            end

            if obj.isTimerValid()
                try
                    stop(obj.Timer)
                catch
                end
            end

            try
                delete(obj.Timer)
            catch
            end

            obj.Timer = [];
        end

        %------------------------------------------------------------------
        % Tenta restabelecer o listener logo apos falha de transporte
        %------------------------------------------------------------------
        % Esse caminho reduz a janela em que o cliente veria
        % "connection refused" apos um erro de leitura/escrita.
        function attemptImmediateReconnect(obj, reason)
            server.RuntimeLog.logWarning( ...
                'tcpServerLib.ImmediateReconnect', ...
                reason, ...
                obj.buildConnectionContext());

            try
                obj.ConnectAttempt();
            catch reconnectError
                server.RuntimeLog.logException( ...
                    'tcpServerLib.ImmediateReconnect', ...
                    reconnectError, ...
                    obj.buildExceptionDetails(reconnectError));
            end
        end

        %------------------------------------------------------------------
        % Recria o timer de reconexao
        %------------------------------------------------------------------
        function recreateTimer(obj, reason)
            server.RuntimeLog.logWarning( ...
                'tcpServerLib.Timer', ...
                reason, ...
                obj.buildConnectionContext());
            obj.disposeTimer();
            obj.TimerCreation()
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
