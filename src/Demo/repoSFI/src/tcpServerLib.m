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
    %   - RequestFactory: decide qual handler atende cada Request
    %   - ServerLogger: mantem em memoria o historico request/response
    %   - RuntimeLog: persiste em disco eventos de saude, excecoes e
    %     problemas do listener/timer
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
        
        % Historico em memoria das transacoes processadas.
        % Nao e o mesmo papel do RuntimeLog persistente em disco.
        Logger
        
        % Estado da requisicao em andamento
        CurrentRequestState

        % Ultima requisicao concluida
        LastRequestState

        % Timestamp de inicializacao
        Time
    end

    properties (Access = private)
        % Ultimo resumo de saude observado pelo watchdog
        LastHealthStateKey = ""

        % Bucket em minutos da ultima requisicao longa ja avisada
        LastLongRunningRequestBucket = -1
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
            obj.CurrentRequestState = obj.createEmptyRequestState();
            obj.LastRequestState = obj.createEmptyRequestState();
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
                'ServerValid', obj.isServerValid(), ...
                'ServerConnected', obj.isServerConnected(), ...
                'TimerValid', obj.isTimerValid(), ...
                'TimerRunning', string(obj.safeTimerRunningState()), ...
                'ConfiguredIP', string(obj.safeGeneralField('IP')), ...
                'ConfiguredPort', obj.safeGeneralPort(), ...
                'CurrentLogCount', obj.getLogCount(), ...
                'CurrentRequest', obj.getCurrentRequestSnapshot(), ...
                'CurrentRequestAgeSeconds', obj.getCurrentRequestAgeSeconds(), ...
                'LastRequest', obj.getLastRequestSnapshot(), ...
                'NumBytesAvailable', obj.safeNumBytesAvailable(), ...
                'NumBytesWritten', obj.safeNumBytesWritten());
        end

        %------------------------------------------------------------------
        % Watchdog leve de auto-recuperacao do listener
        %------------------------------------------------------------------
        % O processo principal pode continuar vivo mesmo quando o listener
        % TCP ou o timer de reconexao se degradam. Esse watchdog tenta
        % detectar esse estado "processo vivo, porta morta", registrar a
        % transicao no log e aplicar a recuperacao mais simples possivel.
        function health = runHealthWatchdog(obj)
            health = obj.getRuntimeHealth();
            issues = strings(0, 1);

            if ~health.TimerValid
                issues(end+1) = "TimerInvalid"; %#ok<AGROW>
            elseif ~strcmpi(char(health.TimerRunning), 'on')
                issues(end+1) = "TimerStopped"; %#ok<AGROW>
            end

            if ~health.ServerValid
                issues(end+1) = "ServerInvalid"; %#ok<AGROW>
            elseif ~health.ServerConnected
                issues(end+1) = "ServerDisconnected"; %#ok<AGROW>
            end

            health.Issues = issues;
            obj.logHealthStateTransition(health);
            obj.logLongRunningRequestIfNeeded(health);

            if isempty(issues)
                return
            end

            recoveryDetails = obj.recoverRuntimeHealth(health);
            if ~isempty(recoveryDetails.Actions)
                server.RuntimeLog.logWarning( ...
                    'tcpServerLib.Watchdog', ...
                    'Watchdog detectou listener degradado e aplicou tentativa de recuperacao.', ...
                    recoveryDetails);
            end
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
                "Period", obj.TimerPeriod, ...
                "TimerFcn", @obj.ConnectAttempt, ...
                "ErrorFcn", @obj.HandleTimerError ...
                );
            
            start(obj.Timer)
            server.RuntimeLog.logInfo( ...
                'tcpServerLib.TimerCreation', ...
                sprintf('Timer de reconexao iniciado com periodo de %d segundos.', obj.TimerPeriod), ...
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
            end
        end
        
        %------------------------------------------------------------------
        % Processa uma mensagem raw único
        %------------------------------------------------------------------
        % Faz o pipeline completo: decode, validate, dispatch e log.
        function processRawMessage(obj, rawMsg)
            requestTimer = tic;
            requestDetails = struct();

            try
                % Decodifica JSON
                decodedMsg = jsondecode(rawMsg);
                requestDetails = obj.buildRequestDetails(decodedMsg);
                obj.markRequestStarted(requestDetails);
                requestCleanup = onCleanup(@() obj.clearCurrentRequestState());
                server.RuntimeLog.logInfo( ...
                    'tcpServerLib.processRawMessage', ...
                    'Requisicao recebida para processamento.', ...
                    requestDetails);
                
                % Valida mensagem (fields, tipos, auth, authz)
                server.MessageValidator.validateMessage(decodedMsg, obj.General);
                
                % Processa requisição
                requestType = decodedMsg.Request.type;
                answer = handlers.RequestFactory.process(requestType, decodedMsg.Request, obj.General);
                
                % Envia resposta
                obj.sendMessageToClient(struct('Request', decodedMsg.Request, 'Answer', answer))
                
                % Log bem-sucedido
                obj.Logger.logTransaction( ...
                    obj.safeClientAddress(), ...
                    obj.safeClientPort(), ...
                    string(rawMsg), ...
                    decodedMsg, ...
                    obj.safeNumBytesWritten(), ...
                    "success" ...
                    )
                requestDetails.DurationSeconds = toc(requestTimer);
                obj.markRequestFinished(requestDetails, requestDetails.DurationSeconds, "success");
                server.RuntimeLog.logInfo( ...
                    'tcpServerLib.processRawMessage', ...
                    sprintf('Requisicao processada com sucesso em %.3f s.', requestDetails.DurationSeconds), ...
                    requestDetails);
                
            catch ME
                if isempty(fieldnames(requestDetails))
                    obj.markRequestStarted(struct( ...
                        'RequestType', "", ...
                        'ClientName', "", ...
                        'FilePath', "", ...
                        'Export', false));
                    requestCleanup = onCleanup(@() obj.clearCurrentRequestState());
                end

                errorDetails = obj.buildExceptionDetails(ME, rawMsg);
                errorDetails.Request = requestDetails;
                errorDetails.DurationSeconds = toc(requestTimer);
                obj.markRequestFinished(requestDetails, errorDetails.DurationSeconds, obj.buildErrorStatus(ME));

                % Envia erro
                try
                    obj.sendMessageToClient(struct('Request', rawMsg, 'Answer', ME.identifier))
                catch replyError
                    server.RuntimeLog.logException( ...
                        'tcpServerLib.processRawMessage.reply', ...
                        replyError, ...
                        obj.buildExceptionDetails(replyError, rawMsg));
                end
                
                % Log com erro
                try
                    obj.Logger.logTransaction( ...
                        obj.safeClientAddress(), ...
                        obj.safeClientPort(), ...
                        string(rawMsg), ...
                        struct('Request', rawMsg), ...
                        obj.safeNumBytesWritten(), ...
                        obj.buildErrorStatus(ME) ...
                        )
                catch logError
                    server.RuntimeLog.logException( ...
                        'tcpServerLib.processRawMessage.logTransaction', ...
                        logError, ...
                        obj.buildExceptionDetails(logError, rawMsg));
                end

                server.RuntimeLog.logWarning( ...
                    'tcpServerLib.processRawMessage', ...
                    obj.buildErrorStatus(ME), ...
                    errorDetails);
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
        % Resumo da requisicao atual para correlacao no log
        %------------------------------------------------------------------
        function details = buildRequestDetails(~, decodedMsg)
            details = struct( ...
                'RequestType', "", ...
                'ClientName', "", ...
                'FilePath', "", ...
                'Export', false);

            try
                if isfield(decodedMsg, 'ClientName')
                    details.ClientName = string(decodedMsg.ClientName);
                end

                if isfield(decodedMsg, 'Request') && isstruct(decodedMsg.Request)
                    if isfield(decodedMsg.Request, 'type')
                        details.RequestType = string(decodedMsg.Request.type);
                    end

                    if isfield(decodedMsg.Request, 'filepath')
                        details.FilePath = string(decodedMsg.Request.filepath);
                    end

                    if isfield(decodedMsg.Request, 'export')
                        details.Export = logical(decodedMsg.Request.export);
                    end
                end
            catch
            end
        end

        %------------------------------------------------------------------
        % Estado padrao de requisicao para heartbeat e ultimo estado
        %------------------------------------------------------------------
        function requestState = createEmptyRequestState(~)
            requestState = struct( ...
                'IsActive', false, ...
                'StartedAt', "", ...
                'CompletedAt', "", ...
                'DurationSeconds', NaN, ...
                'Status', "", ...
                'Details', struct());
        end

        %------------------------------------------------------------------
        % Marca a requisicao como ativa
        %------------------------------------------------------------------
        function markRequestStarted(obj, requestDetails)
            currentState = obj.createEmptyRequestState();
            currentState.IsActive = true;
            currentState.StartedAt = string(datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss'));
            currentState.Status = "running";
            currentState.Details = requestDetails;
            obj.CurrentRequestState = currentState;
        end

        %------------------------------------------------------------------
        % Marca a requisicao como concluida
        %------------------------------------------------------------------
        function markRequestFinished(obj, requestDetails, durationSeconds, status)
            lastState = obj.createEmptyRequestState();
            lastState.IsActive = false;
            lastState.StartedAt = string(obj.getCurrentRequestStartedAt());
            lastState.CompletedAt = string(datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss'));
            lastState.DurationSeconds = durationSeconds;
            lastState.Status = string(status);
            lastState.Details = requestDetails;
            obj.LastRequestState = lastState;
        end

        %------------------------------------------------------------------
        % Limpa o estado da requisicao ativa
        %------------------------------------------------------------------
        function clearCurrentRequestState(obj)
            obj.CurrentRequestState = obj.createEmptyRequestState();
        end

        %------------------------------------------------------------------
        % Snapshot da requisicao atual
        %------------------------------------------------------------------
        function currentState = getCurrentRequestSnapshot(obj)
            currentState = obj.createEmptyRequestState();

            try
                if ~isempty(obj.CurrentRequestState)
                    currentState = obj.CurrentRequestState;
                end
            catch
                currentState = obj.createEmptyRequestState();
            end
        end

        %------------------------------------------------------------------
        % Snapshot da ultima requisicao concluida
        %------------------------------------------------------------------
        function lastState = getLastRequestSnapshot(obj)
            lastState = obj.createEmptyRequestState();

            try
                if ~isempty(obj.LastRequestState)
                    lastState = obj.LastRequestState;
                end
            catch
                lastState = obj.createEmptyRequestState();
            end
        end

        %------------------------------------------------------------------
        % Timestamp de inicio da requisicao atual
        %------------------------------------------------------------------
        function startedAt = getCurrentRequestStartedAt(obj)
            startedAt = "";

            try
                if ~isempty(obj.CurrentRequestState) && isfield(obj.CurrentRequestState, 'StartedAt')
                    startedAt = obj.CurrentRequestState.StartedAt;
                end
            catch
                startedAt = "";
            end
        end

        %------------------------------------------------------------------
        % Idade da requisicao atual em segundos
        %------------------------------------------------------------------
        function ageSeconds = getCurrentRequestAgeSeconds(obj)
            ageSeconds = NaN;

            try
                currentState = obj.getCurrentRequestSnapshot();
                if currentState.IsActive && strlength(string(currentState.StartedAt)) > 0
                    startedAt = datetime(char(currentState.StartedAt), 'InputFormat', 'dd/MM/yyyy HH:mm:ss');
                    ageSeconds = seconds(datetime('now') - startedAt);
                end
            catch
                ageSeconds = NaN;
            end
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
        % Monta status conciso de erro
        %------------------------------------------------------------------
        function status = buildErrorStatus(~, ME)
            if isempty(ME.identifier)
                status = string(ME.message);
            else
                status = sprintf('[%s] %s', ME.identifier, ME.message);
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
        % O watchdog pode recriar o listener e, em alguns cenarios de
        % reconexao, vale garantir explicitamente que o callback continua
        % apontando para receivedMessage.
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
        % handle permite que o watchdog ou o timer recriem a porta.
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
        % Recria o timer de reconexao
        %------------------------------------------------------------------
        function recreateTimer(obj, reason)
            server.RuntimeLog.logWarning( ...
                'tcpServerLib.Watchdog', ...
                reason, ...
                obj.buildConnectionContext());
            obj.disposeTimer();
            obj.TimerCreation()
        end

        %------------------------------------------------------------------
        % Loga mudancas de saude do listener/timer
        %------------------------------------------------------------------
        function logHealthStateTransition(obj, health)
            currentStateKey = obj.buildHealthStateKey(health);
            if strlength(obj.LastHealthStateKey) == 0
                obj.LastHealthStateKey = currentStateKey;
                return
            end

            if strcmp(obj.LastHealthStateKey, currentStateKey)
                return
            end

            obj.LastHealthStateKey = currentStateKey;
            if isempty(health.Issues)
                server.RuntimeLog.logInfo( ...
                    'tcpServerLib.Watchdog', ...
                    'Saude do listener voltou ao estado normal.', ...
                    health);
            else
                server.RuntimeLog.logWarning( ...
                    'tcpServerLib.Watchdog', ...
                    'Mudanca de saude detectada no listener/timer.', ...
                    health);
            end
        end

        %------------------------------------------------------------------
        % Resume a saude atual em uma chave comparavel
        %------------------------------------------------------------------
        function stateKey = buildHealthStateKey(~, health)
            stateKey = sprintf('SV:%d|SC:%d|TV:%d|TR:%s', ...
                logical(health.ServerValid), ...
                logical(health.ServerConnected), ...
                logical(health.TimerValid), ...
                char(string(health.TimerRunning)));
        end

        %------------------------------------------------------------------
        % Registra requisicoes excessivamente longas em buckets de minuto
        %------------------------------------------------------------------
        % Isso melhora a visibilidade dos casos em que o listener continua
        % vivo, mas uma operacao fica muito tempo ocupando o callback.
        function logLongRunningRequestIfNeeded(obj, health)
            if ~isfield(health, 'CurrentRequest') || ~isstruct(health.CurrentRequest)
                obj.LastLongRunningRequestBucket = -1;
                return
            end

            if ~health.CurrentRequest.IsActive || ~isfinite(health.CurrentRequestAgeSeconds)
                obj.LastLongRunningRequestBucket = -1;
                return
            end

            if health.CurrentRequestAgeSeconds < 120
                return
            end

            currentBucket = floor(double(health.CurrentRequestAgeSeconds) / 60);
            if currentBucket <= obj.LastLongRunningRequestBucket
                return
            end

            obj.LastLongRunningRequestBucket = currentBucket;
            server.RuntimeLog.logWarning( ...
                'tcpServerLib.Watchdog', ...
                sprintf('Requisicao permanece ativa ha %.0f segundos.', double(health.CurrentRequestAgeSeconds)), ...
                health);
        end

        %------------------------------------------------------------------
        % Tenta recuperar timer e listener quando degradados
        %------------------------------------------------------------------
        function details = recoverRuntimeHealth(obj, health)
            actions = strings(0, 1);
            details = struct( ...
                'Before', health, ...
                'Actions', actions, ...
                'After', struct());

            if ~health.TimerValid
                obj.recreateTimer('Timer invalido detectado pelo watchdog.');
                actions(end+1) = "TimerRecreated"; %#ok<AGROW>
            elseif ~strcmpi(char(health.TimerRunning), 'on')
                try
                    start(obj.Timer)
                    actions(end+1) = "TimerStarted"; %#ok<AGROW>
                catch
                    obj.recreateTimer('Timer parado detectado pelo watchdog; o timer sera recriado.');
                    actions(end+1) = "TimerRecreated"; %#ok<AGROW>
                end
            end

            if ~health.ServerValid
                obj.disposeServer();
                obj.ConnectAttempt();
                actions(end+1) = "ListenerRecreated"; %#ok<AGROW>
            elseif ~health.ServerConnected
                obj.ConnectAttempt();
                actions(end+1) = "ListenerReconnectAttempted"; %#ok<AGROW>
            end

            details.Actions = actions;
            details.After = obj.getRuntimeHealth();
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
