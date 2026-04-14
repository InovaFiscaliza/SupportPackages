function main(varargin)
    % main - Entry-point do servidor repoSFI em MATLAB e no executavel.
    %
    % O objetivo aqui e subir o listener TCP e garantir, antes disso, que
    % nao exista outra instancia ativa na mesma maquina/VM. Sem esse
    % bloqueio, duas copias podem disputar a mesma porta e os mesmos dados.
    %
    % Sintaxe:
    %   main()                - Inicia normalmente e bloqueia segunda instancia
    %   main('force-restart') - Substitui a instancia atual em cenarios controlados
    
    server = [];
    serverLock = createEmptyLockState();
    forceRestart = false;
    % Esse modo existe para automacoes controladas, como Task Scheduler.

    % O startup principal fica concentrado neste entry-point unico.
    
    % Verifica parametro de forÃ§a restart
    if ~isempty(varargin) && ischar(varargin{1}) && strcmp(varargin{1}, 'force-restart')
        forceRestart = true;
    end

    % Cria um log persistente fora do diretorio atual para suportar
    % execucao em Task Scheduler e sessoes sem desktop interativo.
    runtimeLog = startRuntimeLogging();
    
    try
        % ===================================================================
        % INICIALIZACAO
        % ===================================================================
        printBanner()
        fprintf('[INFO] Diretorio de trabalho atual: %s\n', pwd);
        if runtimeLog.isEnabled
            fprintf('[INFO] %s\n', runtimeLog.message);
        elseif ~isempty(runtimeLog.message)
            fprintf('[AVISO] %s\n', runtimeLog.message);
        end
        
        % ===================================================================
        % VERIFICACAO DE INSTANCIA JA ABERTA (mutex global + lock file)
        % ===================================================================
        [canStart, serverLock, message] = acquireServerRuntimeLock(forceRestart);
        if ~canStart
            fprintf('\n%s\n', repmat('=', 1, 70));
            fprintf('[FALHA] %s\n', message);
            fprintf('%s\n\n', repmat('=', 1, 70));
            return;
        end
        
        if ~isempty(message)
            fprintf('\n%s\n', repmat('=', 1, 70));
            fprintf('[INFO] %s\n', message);
            fprintf('%s\n\n', repmat('=', 1, 70));
        end
        
        % A partir daqui esta copia ja e dona do mutex global.
        fprintf('\n[%s] Inicializando servidor TCP...\n', datetime('now', 'Format', 'HH:mm:ss'));
        server = tcpServerLib();
        
        % ===================================================================
        % EXIBICAO DE CONFIGURACOES
        % ===================================================================
        server.GeneralSettingsPrint()
        
        % ===================================================================
        % STATUS INICIAL
        % ===================================================================
        printServerStatus(server);
        
        % ===================================================================
        % LOOP PRINCIPAL
        % ===================================================================
        fprintf('\n%s\n', repmat('=', 1, 70));
        fprintf('STATUS: Servidor aguardando requisicoes...\n');
        fprintf('INSTRUCOES:\n');
        fprintf('  - Pressione Ctrl+C para parar o servidor\n');
        fprintf('  - Clientes podem conectar em: %s:%d\n', ...
            server.General.tcpServer.IP, server.General.tcpServer.Port);
        fprintf('%s\n\n', repmat('=', 1, 70));
        
        lastLogCount = 0;
        lastCleanupCheck = datetime('now');
        lastLogMaintenanceCheck = datetime('now');
        lastHeartbeatCheck = datetime('now');
        lastWatchdogCheck = datetime('now');
        pendingRuntimeRecycleReason = "";
        
        while true
            pause(1);
            currentTime = datetime('now');
            currentTime.Format = 'HH:mm:ss';
            % So escreve no console quando o contador muda para nao poluir
            % a saida com um heartbeat por segundo.
            
            % Atualiza exibiÃ§Ã£o periodicamente
            currentLogCount = server.getLogCount();
            if currentLogCount ~= lastLogCount
                fprintf('[%s] > Requisicao processada | Total: %d | Status: OK\n', ...
                    char(currentTime), currentLogCount);
                lastLogCount = currentLogCount;
            end
            
            % A cada 5 minutos, verifica se existem locks obsoletos de outros processos
            % Crashs podem deixar o arquivo auxiliar para tras; o cleanup e
            % so de diagnostico, porque o mutex continua sendo a trava real.
            if minutes(currentTime - lastCleanupCheck) > 5
                cleanupServerRuntimeLock();
                lastCleanupCheck = currentTime;
            end

            % Watchdog leve de infraestrutura: tenta recuperar listener e
            % timer quando o processo ainda esta vivo, mas a porta deixou
            % de aceitar conexoes. O objetivo e reduzir a janela de
            % indisponibilidade sem depender apenas do timer de 300 s.
            if seconds(currentTime - lastWatchdogCheck) >= runtimeLog.watchdogIntervalSeconds
                try
                    watchdogHealth = server.runHealthWatchdog();
                    [pendingRuntimeRecycleReason, recycleScheduleMessage] = ...
                        updatePendingRuntimeRecycle(runtimeLog, watchdogHealth, pendingRuntimeRecycleReason);
                    if strlength(recycleScheduleMessage) > 0
                        appendRuntimeLog(runtimeLog, sprintf('[%s] %s\n', ...
                            char(datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss')), ...
                            char(recycleScheduleMessage)));
                    end
                catch watchdogError
                    appendRuntimeLog(runtimeLog, sprintf('[%s] Falha no watchdog do servidor: [%s] %s\n', ...
                        char(datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss')), ...
                        watchdogError.identifier, ...
                        watchdogError.message));
                end

                lastWatchdogCheck = currentTime;
            end

            % Se o watchdog ou a politica de uptime pedirem uma reciclagem
            % completa, esperamos apenas a janela segura: nenhuma request
            % ativa no callback unico do MATLAB. Assim voltamos ao estado
            % inicial sem interromper um processamento em andamento.
            if strlength(pendingRuntimeRecycleReason) > 0
                runtimeHealth = server.getRuntimeHealth();
                if ~runtimeHealth.CurrentRequest.IsActive
                    [server, lastLogCount] = recycleServerInstance(server, runtimeLog, pendingRuntimeRecycleReason);
                    pendingRuntimeRecycleReason = "";
                    lastHeartbeatCheck = datetime('now');
                    lastWatchdogCheck = datetime('now');
                end
            end

            % Heartbeat leve para diagnostico de travamentos: se o processo
            % morrer sem excecao capturada, o ultimo heartbeat ajuda a
            % delimitar a janela da falha.
            if seconds(currentTime - lastHeartbeatCheck) >= runtimeLog.heartbeatIntervalSeconds
                try
                    appendRuntimeLog(runtimeLog, sprintf('[%s] Heartbeat | %s\n', ...
                        char(datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss')), ...
                        jsonencode(server.getRuntimeHealth())));
                catch heartbeatError
                    appendRuntimeLog(runtimeLog, sprintf('[%s] Falha ao registrar heartbeat: [%s] %s\n', ...
                        char(datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss')), ...
                        heartbeatError.identifier, ...
                        heartbeatError.message));
                end

                lastHeartbeatCheck = currentTime;
            end

            % Mantem o arquivo de log sob um teto de tamanho para evitar
            % crescimento indefinido em execucoes longas no agendador.
            if seconds(currentTime - lastLogMaintenanceCheck) >= runtimeLog.maintenanceIntervalSeconds
                maintainRuntimeLog(runtimeLog);
                lastLogMaintenanceCheck = currentTime;
            end
        end
        
    catch ME
        % ===================================================================
        % TRATAMENTO DE ERROS E INTERRUPCAO
        % ===================================================================
        % Ctrl+C lanca excecao com ID 'MATLAB:interrupted'
        % No MATLAB interativo, Ctrl+C chega aqui como excecao.
        if strcmp(ME.identifier, 'MATLAB:interrupted')
            fprintf('\n%s\n', repmat('=', 1, 70));
            fprintf('[INFO] Servidor interrompido pelo usuario\n');
            fprintf('%s\n\n', repmat('=', 1, 70));
            appendRuntimeLog(runtimeLog, sprintf('[%s] Servidor interrompido pelo usuario.\n', ...
                char(datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss'))));
        else
            errorReport = getReport(ME, 'extended', 'hyperlinks', 'off');
            fprintf('\n%s\n', repmat('=', 1, 70));
            fprintf('[ERRO] Excecao capturada durante execucao\n');
            fprintf('%s\n', repmat('=', 1, 70));
            fprintf(2, '%s\n', errorReport);
            fprintf('%s\n\n', repmat('=', 1, 70));
            appendRuntimeLog(runtimeLog, sprintf('%s\n[%s] Excecao capturada durante execucao\n%s\n%s\n%s\n', ...
                repmat('=', 1, 70), ...
                char(datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss')), ...
                repmat('=', 1, 70), ...
                errorReport, ...
                repmat('=', 1, 70)));
        end
        
    finally
        % Encerra servidor e libera lock global ao sair
        % O servidor e destruido antes de soltar o mutex para evitar uma
        % janela onde outra copia entra enquanto a porta ainda fecha.
        if ~isempty(server)
            try
                delete(server);
            catch
            end
        end
        releaseServerLock(serverLock);
        stopRuntimeLogging(runtimeLog);
    end
    
end

%-------------------------------------------------------------------------
% Novo controle de instancia unica usando mutex global do Windows
%-------------------------------------------------------------------------
function [canStart, lockState, message] = acquireServerRuntimeLock(forceRestart)
    % O mutex e o bloqueio real entre sessoes/usuarios desta maquina.
    % O lock file existe so para dizer quem era o dono da instancia e para
    % permitir um force-restart sem confiar apenas em PID solto.
    %
    % Resumo do fluxo:
    %   1. Monta a estrutura local do lock (mutex + lock file).
    %   2. Tenta criar/abrir o mutex global do sistema operacional.
    %   3. Tenta assumir a posse imediatamente.
    %   4. Se ja houver dono:
    %        - sem forceRestart: aborta startup com mensagem amigavel
    %        - com forceRestart: tenta encerrar a instancia anterior
    %   5. Se assumiu a posse, escreve o lock file com metadados do dono.
    %
    % A saida canStart=true so acontece quando esta copia realmente ficou
    % dona do mutex e conseguiu registrar isso no lock file auxiliar.
    arguments
        forceRestart (1,1) logical = false
    end

    % Estado default: otimista. Vamos derrubar canStart para false assim
    % que qualquer etapa obrigatoria de sincronizacao falhar.
    canStart = true;
    message = '';
    lockState = createEmptyLockState();
    lockState.lockFile = getServerRuntimeLockFilePath();
    lockState.mutexName = getServerRuntimeMutexName();

    % O mutex nomeado e a trava principal entre usuarios/sessoes.
    % Se essa criacao falhar, nao faz sentido continuar, porque a
    % aplicacao perderia sua garantia de instancia unica.
    [lockState.mutex, errorMessage] = createServerRuntimeMutex(lockState.mutexName);
    if isempty(lockState.mutex)
        canStart = false;
        message = sprintf('Erro ao criar bloqueio global da instancia: %s', errorMessage);
        return;
    end

    % Tentativa imediata (timeout zero): no startup normal queremos saber
    % agora se esta copia conseguiu ou nao assumir a instancia.
    [ownsMutex, mutexWasAbandoned, errorMessage] = tryAcquireServerRuntimeMutex(lockState.mutex, 0);
    if ~isempty(errorMessage)
        canStart = false;
        message = sprintf('Erro ao adquirir bloqueio global da instancia: %s', errorMessage);
        return;
    end

    % O lock file e apenas um rastro operacional. Ele ajuda a explicar
    % quem parecia ser o dono anterior e tambem orienta o force-restart.
    existingLockData = readServerRuntimeLockFile(lockState.lockFile);

    % Se nao pegamos o mutex, outra instancia ainda e a dona real do
    % servico. A partir daqui decidimos se abortamos ou se tentamos
    % substituir essa instancia antiga de forma controlada.
    if ~ownsMutex
        if forceRestart
            % Force-restart e um caminho excepcional: tentamos encerrar a
            % instancia antiga apenas quando conseguimos identificar seu
            % processo com seguranca usando PID, nome e StartTime.
            [stopped, stopMessage] = stopExistingServerRuntime(lockState, existingLockData);
            if ~stopped
                canStart = false;
                message = stopMessage;
                return;
            end

            % Depois de mandar a instancia anterior embora, esperamos um
            % pequeno intervalo para porta, handles e mutex estabilizarem.
            pause(2);

            % Aqui ja nao basta timeout zero: damos alguns segundos para o
            % processo antigo concluir o release do mutex global.
            [ownsMutex, ~, errorMessage] = tryAcquireServerRuntimeMutex(lockState.mutex, 5000);
            if ~ownsMutex
                canStart = false;
                if isempty(errorMessage)
                    errorMessage = 'a instancia anterior nao liberou o bloqueio dentro do tempo esperado';
                end

                if isempty(stopMessage)
                    message = sprintf('Force-restart falhou: %s.', errorMessage);
                else
                    message = sprintf('%s Em seguida, %s.', stopMessage, errorMessage);
                end
                return;
            end

            message = stopMessage;
        else
            % Startup normal: se ja existe outro dono do mutex, a resposta
            % correta e sair sem competir pela porta nem pelos arquivos.
            canStart = false;
            message = buildServerRuntimeAlreadyRunningMessage(existingLockData);
            return;
        end
    elseif mutexWasAbandoned
        % Esse caso ocorre quando a copia anterior morreu sem cleanup
        % formal. O Windows nos entrega a posse do mutex abandonado e
        % podemos seguir, apenas registrando que houve recuperacao.
        message = 'Instancia anterior finalizou de forma inesperada. O bloqueio foi recuperado com sucesso.';
    end

    % A partir daqui esta copia realmente possui o mutex global.
    lockState.ownsMutex = true;

    % Se havia um lock file velho apontando para processo morto, limpamos
    % esse rastro antes de escrever os metadados da instancia atual.
    if ~isempty(existingLockData) && ~isServerRuntimeLockOwnerActive(existingLockData)
        safeDeleteServerRuntimeFile(lockState.lockFile);
    end

    % O lock file nao participa da exclusao mutua. Ele existe para
    % observabilidade, suporte operacional e force-restart seguro.
    lockData = buildCurrentServerRuntimeLockData(lockState.mutexName);
    [writeOk, errorMessage] = writeServerRuntimeLockFile(lockState.lockFile, lockData);
    if ~writeOk
        % Se nao conseguimos persistir o rastro da instancia atual,
        % voltamos atras: liberamos o mutex para nao ficar com uma
        % instancia "sem identidade" rodando parcialmente.
        releaseServerLock(lockState);
        lockState = createEmptyLockState();
        canStart = false;
        message = sprintf('Erro ao criar lock file: %s', errorMessage);
    end
end

%-------------------------------------------------------------------------
% Libera lock global e lock file ao encerrar
%-------------------------------------------------------------------------
function releaseServerLock(lockState)
    % Remove o rastro da instancia e so depois solta o mutex. Essa ordem
    % evita que a proxima copia leia um lock file stale logo ao entrar.
    if isempty(lockState)
        return;
    end

    if isstruct(lockState) && isfield(lockState, 'ownsMutex') && lockState.ownsMutex
        if isfield(lockState, 'lockFile') && ~isempty(lockState.lockFile)
            if safeDeleteServerRuntimeFile(lockState.lockFile)
                fprintf('[INFO] Lock file removido. Servidor parado.\n');
            else
                fprintf('[AVISO] Falha ao remover lock file.\n');
            end
        end

        if isfield(lockState, 'mutex') && ~isempty(lockState.mutex)
            try
                lockState.mutex.ReleaseMutex();
            catch
            end
        end
    end

    if isstruct(lockState) && isfield(lockState, 'mutex') && ~isempty(lockState.mutex)
        try
            lockState.mutex.Close();
        catch
        end
    end
end

%-------------------------------------------------------------------------
% Estrutura padrao do lock em memoria
%-------------------------------------------------------------------------
function lockState = createEmptyLockState()
    % Struct unica para levar mutex e metadados ate o finally.
    lockState = struct( ...
        'lockFile', '', ...
        'mutexName', '', ...
        'mutex', [], ...
        'ownsMutex', false);
end

%-------------------------------------------------------------------------
% Caminho do lock file compartilhado entre usuarios
%-------------------------------------------------------------------------
function lockFile = getServerRuntimeLockFilePath()
    % ProgramData e compartilhado por sessoes/usuarios, entao o lock file
    % fica visivel para qualquer copia do executavel na mesma maquina.
    programDataFolder = getServerRuntimeSharedDataFolder();
    lockFile = fullfile(programDataFolder, '.server.lock');
end

%-------------------------------------------------------------------------
% Pasta compartilhada da aplicacao em ProgramData
%-------------------------------------------------------------------------
function sharedFolder = getServerRuntimeSharedDataFolder()
    % Mantem artefatos operacionais em um local estavel, independente do
    % diretorio atual e da sessao do Windows que iniciou o processo.
    sharedFolder = fullfile(getenv('PROGRAMDATA'), 'ANATEL', class.Constants.appName);
    if ~isfolder(sharedFolder)
        mkdir(sharedFolder);
    end
end

%-------------------------------------------------------------------------
% Inicializa log persistente da aplicacao
%-------------------------------------------------------------------------
function runtimeLog = startRuntimeLogging()
    % O log proprio evita depender do -logfile relativo do MATLAB Compiler,
    % que pode apontar para outro working directory no Task Scheduler.
    runtimeSettings = server.RuntimeSettings.loadRuntimeSettings();
    runtimeLog = struct( ...
        'filePath', '', ...
        'isEnabled', false, ...
        'message', '', ...
        'maxBytes', 100 * 1024 * 1024, ...
        'maintenanceIntervalSeconds', runtimeSettings.LogMaintenanceIntervalSeconds, ...
        'heartbeatIntervalSeconds', runtimeSettings.HeartbeatIntervalSeconds, ...
        'watchdogIntervalSeconds', runtimeSettings.WatchdogIntervalSeconds, ...
        'serverRecycleIntervalSeconds', runtimeSettings.ServerRecycleIntervalSeconds, ...
        'maxConsecutiveWatchdogRecoveriesBeforeRecycle', runtimeSettings.MaxConsecutiveWatchdogRecoveriesBeforeRecycle);

    logFolder = getServerRuntimeLogFolder();
    if isempty(logFolder)
        runtimeLog.message = 'Nao foi possivel resolver a pasta de log persistente.';
        return;
    end

    logFile = server.RuntimeLog.getFilePath();
    if isempty(logFile)
        logFile = getServerRuntimePrimaryLogFilePath();
    end
    [canWrite, errorMessage] = touchRuntimeLogFile(logFile);
    if ~canWrite
        runtimeLog.message = sprintf('Falha ao preparar o log persistente em "%s": %s', logFile, errorMessage);
        return;
    end

    runtimeLog.filePath = logFile;
    runtimeLog.isEnabled = true;
    maintainRuntimeLog(runtimeLog);
    runtimeLog.message = sprintf('Log persistente configurado em "%s" com limite de %.0f MB.', ...
        logFile, runtimeLog.maxBytes / (1024 * 1024));

    appendRuntimeLog(runtimeLog, sprintf('\n%s\n', repmat('=', 1, 70)));
    appendRuntimeLog(runtimeLog, sprintf('[%s] Processo iniciado | PID: %d | Usuario: %s | Computador: %s | Deployed: %d\n', ...
        char(datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss')), ...
        getCurrentProcessId(), ...
        safeGetEnv('USERNAME'), ...
        safeGetEnv('COMPUTERNAME'), ...
        isdeployed));
    appendRuntimeLog(runtimeLog, sprintf('[INFO] Diretorio de trabalho inicial: %s\n', pwd));
    appendRuntimeLog(runtimeLog, sprintf('%s\n', repmat('=', 1, 70)));
end

%-------------------------------------------------------------------------
% Avalia se a instancia deve ser reciclada por politica de runtime
%-------------------------------------------------------------------------
function [pendingReason, message] = updatePendingRuntimeRecycle(runtimeLog, health, currentPendingReason)
    % Existem dois gatilhos complementares:
    %   1. Reciclagem preventiva por uptime alto quando a instancia ficar
    %      muito tempo viva.
    %   2. Reciclagem corretiva quando o watchdog precisou recuperar a
    %      infraestrutura varias vezes seguidas.
    %
    % O helper nao recicla nada diretamente; ele so agenda o motivo para o
    % loop principal executar isso na proxima janela segura.
    pendingReason = string(currentPendingReason);
    message = "";

    if strlength(pendingReason) > 0
        return;
    end

    if isfield(health, 'ConsecutiveWatchdogRecoveryCount') && ...
            health.ConsecutiveWatchdogRecoveryCount >= runtimeLog.maxConsecutiveWatchdogRecoveriesBeforeRecycle
        pendingReason = sprintf([ ...
            'Watchdog precisou recuperar listener/timer em %d ciclos consecutivos. ', ...
            'A instancia sera reciclada para voltar ao estado inicial.'], ...
            health.ConsecutiveWatchdogRecoveryCount);

    elseif runtimeLog.serverRecycleIntervalSeconds > 0 && ...
            isfield(health, 'UptimeSeconds') && ...
            isfinite(health.UptimeSeconds) && ...
            health.UptimeSeconds >= runtimeLog.serverRecycleIntervalSeconds
        pendingReason = sprintf([ ...
            'Instancia atingiu %.0f segundos de uptime. ', ...
            'A instancia sera reciclada preventivamente para reduzir degradacao acumulada.'], ...
            double(health.UptimeSeconds));
    end

    if strlength(pendingReason) == 0
        return;
    end

    if isfield(health, 'CurrentRequest') && isstruct(health.CurrentRequest) && health.CurrentRequest.IsActive
        message = "Reciclagem completa do servidor agendada apos a request atual. " + pendingReason;
    else
        message = "Reciclagem completa do servidor agendada imediatamente. " + pendingReason;
    end
end

%-------------------------------------------------------------------------
% Recicla a instancia do servidor mantendo o processo principal vivo
%-------------------------------------------------------------------------
function [server, lastLogCount] = recycleServerInstance(server, runtimeLog, reason)
    % Esse reset e mais forte do que o watchdog do listener: destruimos e
    % recriamos toda a infraestrutura do tcpServerLib, preservando apenas
    % o processo principal e o lock global da instancia.
    timestamp = char(datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss'));
    fprintf('\n[%s] Reciclando infraestrutura do servidor...\n', timestamp);
    appendRuntimeLog(runtimeLog, sprintf('[%s] Iniciando reciclagem completa do servidor. Motivo: %s\n', ...
        timestamp, char(reason)));

    try
        delete(server);
    catch recycleDeleteError
        appendRuntimeLog(runtimeLog, sprintf('[%s] Aviso ao destruir instancia anterior durante reciclagem: [%s] %s\n', ...
            char(datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss')), ...
            recycleDeleteError.identifier, ...
            recycleDeleteError.message));
    end

    % Pequena folga para o Windows liberar porta e handles antes de subir
    % uma nova instancia do listener dentro do mesmo processo.
    pause(1);
    server = tcpServerLib();
    printServerStatus(server);
    lastLogCount = server.getLogCount();

    appendRuntimeLog(runtimeLog, sprintf('[%s] Reciclagem completa concluida. Novo estado: %s\n', ...
        char(datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss')), ...
        jsonencode(server.getRuntimeHealth())));
end

%-------------------------------------------------------------------------
% Encerra log persistente da aplicacao
%-------------------------------------------------------------------------
function stopRuntimeLogging(runtimeLog)
    % Registra o fechamento sem deixar o log interferir no shutdown.
    if ~isstruct(runtimeLog)
        return;
    end

    if isfield(runtimeLog, 'isEnabled') && runtimeLog.isEnabled
        appendRuntimeLog(runtimeLog, sprintf('[%s] Processo finalizado.\n', ...
            char(datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss'))));
    end
end

%-------------------------------------------------------------------------
% Caminho principal do log persistente
%-------------------------------------------------------------------------
function logFile = getServerRuntimePrimaryLogFilePath()
    % Mantem um unico arquivo de log para permitir reset ao atingir o teto.
    logFile = fullfile(getServerRuntimeLogFolder(), 'repoSFI-runtime.log');
end

%-------------------------------------------------------------------------
% Pasta do log persistente
%-------------------------------------------------------------------------
function logFolder = getServerRuntimeLogFolder()
    % Guarda logs em ProgramData para manter o path estavel no agendador.
    logFolder = '';

    try
        logFolder = fullfile(getServerRuntimeSharedDataFolder(), 'logs');
        if ~isfolder(logFolder)
            mkdir(logFolder);
        end
    catch
        logFolder = '';
    end
end

%-------------------------------------------------------------------------
% Reinicia o log quando excede o teto configurado
%-------------------------------------------------------------------------
function maintainRuntimeLog(runtimeLog)
    % Faz manutencao best-effort: se o arquivo crescer demais, zera e
    % continua escrevendo no mesmo caminho para simplificar o Scheduler.
    if ~isstruct(runtimeLog) || ~isfield(runtimeLog, 'isEnabled') || ~runtimeLog.isEnabled
        return;
    end

    currentSize = getRuntimeLogFileSize(runtimeLog.filePath);
    if currentSize < 0 || currentSize <= runtimeLog.maxBytes
        return;
    end

    resetReason = sprintf(['[%s] Log reiniciado automaticamente apos exceder o limite de %.0f MB ', ...
        '(tamanho anterior: %.2f MB).\n'], ...
        char(datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss')), ...
        runtimeLog.maxBytes / (1024 * 1024), ...
        currentSize / (1024 * 1024));

    [resetOk, errorMessage] = overwriteRuntimeLogFile(runtimeLog.filePath, resetReason);

    if resetOk
        fprintf('[INFO] Log persistente reiniciado ao exceder %.0f MB.\n', ...
            runtimeLog.maxBytes / (1024 * 1024));
    else
        fprintf('[AVISO] Falha ao reiniciar log persistente: %s\n', errorMessage);
    end
end

%-------------------------------------------------------------------------
% Garante que o arquivo de log existe e aceita append
%-------------------------------------------------------------------------
function [canWrite, errorMessage] = touchRuntimeLogFile(logFile)
    % Abertura em append valida permissao antes da aplicacao depender dele.
    canWrite = false;
    errorMessage = '';
    fid = -1;

    try
        fid = fopen(logFile, 'a');
        if fid == -1
            error('repoSFI:RuntimeLogOpenFailed', 'Nao foi possivel abrir o arquivo de log para append.');
        end

        fclose(fid);
        fid = -1;
        canWrite = true;
    catch ME
        errorMessage = ME.message;
        if fid ~= -1
            fclose(fid);
        end
    end
end

%-------------------------------------------------------------------------
% Sobrescreve o arquivo inteiro com um novo cabecalho
%-------------------------------------------------------------------------
function [writeOk, errorMessage] = overwriteRuntimeLogFile(logFile, text)
    % Reabre em modo write para truncar o arquivo quando ele excede o teto.
    writeOk = false;
    errorMessage = '';
    fid = -1;

    try
        fid = fopen(logFile, 'w');
        if fid == -1
            error('repoSFI:RuntimeLogRewriteFailed', 'Nao foi possivel sobrescrever o arquivo de log.');
        end

        fprintf(fid, '%s', char(text));
        fclose(fid);
        fid = -1;
        writeOk = true;
    catch ME
        errorMessage = ME.message;
        if fid ~= -1
            fclose(fid);
        end
    end
end

%-------------------------------------------------------------------------
% Escreve texto diretamente no log persistente
%-------------------------------------------------------------------------
function appendRuntimeLog(runtimeLog, text)
    % Escrita best-effort para nao interromper o servidor por causa do log.
    if ~isstruct(runtimeLog) || ~isfield(runtimeLog, 'isEnabled') || ~runtimeLog.isEnabled
        return;
    end

    maintainRuntimeLog(runtimeLog);

    fid = -1;
    try
        fid = fopen(runtimeLog.filePath, 'a');
        if fid == -1
            return;
        end

        fprintf(fid, '%s', char(text));
        fclose(fid);
    catch
        if fid ~= -1
            fclose(fid);
        end
    end
end

%-------------------------------------------------------------------------
% Tamanho atual do arquivo de log
%-------------------------------------------------------------------------
function fileSize = getRuntimeLogFileSize(logFile)
    % Leitura isolada para simplificar a politica de manutencao.
    fileSize = -1;

    if isempty(logFile) || ~isfile(logFile)
        fileSize = 0;
        return;
    end

    try
        fileInfo = dir(logFile);
        fileSize = fileInfo.bytes;
    catch
        fileSize = -1;
    end
end

%-------------------------------------------------------------------------
% PID do processo atual
%-------------------------------------------------------------------------
function pid = getCurrentProcessId()
    % Encapsula o acesso ao PID para startup log e lock file.
    pid = feature('getpid');
end

%-------------------------------------------------------------------------
% getenv com fallback amigavel para diagnostico
%-------------------------------------------------------------------------
function value = safeGetEnv(name)
    % Evita campos vazios no log de diagnostico.
    value = getenv(name);
    if isempty(value)
        value = '-';
    end
end

%-------------------------------------------------------------------------
% Nome do mutex global de instancia unica
%-------------------------------------------------------------------------
function mutexName = getServerRuntimeMutexName()
    % Global\ faz o mutex atravessar sessoes do Windows na mesma maquina.
    if ispc
        mutexName = 'Global\ANATEL_repoSFI_ServerInstance';
    else
        mutexName = 'ANATEL_repoSFI_ServerInstance';
    end
end

%-------------------------------------------------------------------------
% Cria mutex nomeado do sistema operacional
%-------------------------------------------------------------------------
function [mutexObj, errorMessage] = createServerRuntimeMutex(mutexName)
    % Abrir o mesmo nome devolve acesso ao mesmo mutex do sistema.
    mutexObj = [];
    errorMessage = '';

    try
        mutexObj = System.Threading.Mutex(false, mutexName);
    catch ME
        errorMessage = ME.message;
    end
end

%-------------------------------------------------------------------------
% Tenta obter posse do mutex
%-------------------------------------------------------------------------
function [ownsMutex, mutexWasAbandoned, errorMessage] = tryAcquireServerRuntimeMutex(mutexObj, timeoutMs)
    % Se a instancia anterior morreu sem cleanup, o Windows sinaliza um
    % abandoned mutex; nesse caso a posse e recuperada pelo processo atual.
    ownsMutex = false;
    mutexWasAbandoned = false;
    errorMessage = '';

    try
        ownsMutex = logical(mutexObj.WaitOne(int32(timeoutMs)));
    catch ME
        exceptionText = ME.message;
        try
            exceptionText = getReport(ME, 'basic', 'hyperlinks', 'off');
        catch
        end

        if contains(exceptionText, 'AbandonedMutexException')
            ownsMutex = true;
            mutexWasAbandoned = true;
        else
            errorMessage = ME.message;
        end
    end
end

%-------------------------------------------------------------------------
% Le lock file atual, se existir
%-------------------------------------------------------------------------
function lockData = readServerRuntimeLockFile(lockFile)
    % Leitura best-effort: se o arquivo estiver corrompido, o mutex ainda
    % continua sendo a fonte de verdade para decidir concorrencia.
    lockData = [];

    if isempty(lockFile) || ~isfile(lockFile)
        return;
    end

    try
        fileContent = fileread(lockFile);
        if ~isempty(strtrim(fileContent))
            lockData = jsondecode(fileContent);
        end
    catch
        lockData = [];
    end
end

%-------------------------------------------------------------------------
% Escreve lock file com metadados da instancia atual
%-------------------------------------------------------------------------
function [writeOk, errorMessage] = writeServerRuntimeLockFile(lockFile, lockData)
    % O arquivo nao impede concorrencia; ele so documenta quem segurava a
    % instancia para mensagem de erro, suporte e force-restart.
    writeOk = false;
    errorMessage = '';

    fid = -1;
    try
        fid = fopen(lockFile, 'w');
        if fid == -1
            error('repoSFI:LockFileOpenFailed', 'Nao foi possivel abrir o lock file para escrita.');
        end

        fprintf(fid, '%s', jsonencode(lockData, 'PrettyPrint', true));
        fclose(fid);
        fid = -1;
        writeOk = true;
    catch ME
        errorMessage = ME.message;
        if fid ~= -1
            fclose(fid);
        end
    end
end

%-------------------------------------------------------------------------
% Monta metadados da instancia atual
%-------------------------------------------------------------------------
function lockData = buildCurrentServerRuntimeLockData(mutexName)
    % Nome do processo e StartTime entram no lock para evitar matar um PID
    % reciclado por outro processo durante um force-restart posterior.
    processInfo = getCurrentServerRuntimeProcessInfo();

    lockData = struct();
    lockData.pid = processInfo.pid;
    lockData.processName = processInfo.name;
    lockData.startTimeUtc = processInfo.startTimeUtc;
    lockData.timestamp = char(datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss'));
    lockData.user = getenv('USERNAME');
    lockData.computer = getenv('COMPUTERNAME');
    lockData.mutexName = mutexName;
end

%-------------------------------------------------------------------------
% Retorna informacoes do processo atual
%-------------------------------------------------------------------------
function processInfo = getCurrentServerRuntimeProcessInfo()
    % Coleta exatamente os campos usados depois para comparar identidade
    % entre lock file e processo vivo.
    processInfo = struct( ...
        'pid', getCurrentProcessId(), ...
        'name', char(class.Constants.appName), ...
        'startTimeUtc', '');

    if ispc
        processObj = [];
        try
            processObj = System.Diagnostics.Process.GetCurrentProcess();
            processInfo.pid = double(processObj.Id);
            processInfo.name = char(processObj.ProcessName);
            processInfo.startTimeUtc = char(processObj.StartTime.ToUniversalTime().ToString('o'));
        catch
        end

        if ~isempty(processObj)
            try
                processObj.Dispose();
            catch
            end
        end
    end
end

%-------------------------------------------------------------------------
% Consulta se um PID especifico ainda esta ativo
%-------------------------------------------------------------------------
function processInfo = queryServerRuntimeProcessInfo(pid)
    % PID sozinho nao basta; tambem capturamos StartTime para diferenciar
    % "mesmo PID, processo novo" de "mesma instancia ainda viva".
    processInfo = struct( ...
        'isActive', false, ...
        'pid', double(pid), ...
        'name', '', ...
        'startTimeUtc', '');

    if isempty(pid) || ~isfinite(pid)
        return;
    end

    if ispc
        processObj = [];
        try
            processObj = System.Diagnostics.Process.GetProcessById(int32(pid));
            if ~processObj.HasExited
                processInfo.isActive = true;
                processInfo.pid = double(processObj.Id);
                processInfo.name = char(processObj.ProcessName);
                try
                    processInfo.startTimeUtc = char(processObj.StartTime.ToUniversalTime().ToString('o'));
                catch
                end
            end
        catch
            processInfo.isActive = false;
        end

        if ~isempty(processObj)
            try
                processObj.Dispose();
            catch
            end
        end
    else
        try
            [status, ~] = system(sprintf('ps -p %d > /dev/null 2>&1', pid));
            processInfo.isActive = status == 0;
        catch
            processInfo.isActive = false;
        end
    end
end

%-------------------------------------------------------------------------
% Verifica se o lock file pertence a um processo ainda ativo
%-------------------------------------------------------------------------
function isActive = isServerRuntimeLockOwnerActive(lockData)
    % A comparacao cruza PID, nome e StartTime porque o Windows pode
    % reciclar PIDs e isso seria perigoso para o force-restart.
    isActive = false;

    if isempty(lockData) || ~isfield(lockData, 'pid')
        return;
    end

    processInfo = queryServerRuntimeProcessInfo(lockData.pid);
    if ~processInfo.isActive
        return;
    end

    if isfield(lockData, 'processName') && ~isempty(lockData.processName)
        if ~strcmpi(normalizeServerRuntimeProcessName(lockData.processName), normalizeServerRuntimeProcessName(processInfo.name))
            return;
        end
    end

    if isfield(lockData, 'startTimeUtc') && ~isempty(lockData.startTimeUtc) && ~isempty(processInfo.startTimeUtc)
        if ~strcmp(char(lockData.startTimeUtc), char(processInfo.startTimeUtc))
            return;
        end
    end

    isActive = true;
end

%-------------------------------------------------------------------------
% Mensagem exibida quando a instancia ja esta aberta
%-------------------------------------------------------------------------
function message = buildServerRuntimeAlreadyRunningMessage(lockData)
    % A mensagem inclui dados do lock file para ajudar quem esta operando
    % a identificar rapidamente quem esta segurando a instancia.
    message = 'Outra instancia do repoSFI ja esta em execucao neste computador. Feche a instancia atual antes de abrir outra.';

    if isempty(lockData)
        return;
    end

    infoParts = {};

    if isfield(lockData, 'pid') && ~isempty(lockData.pid)
        infoParts{end+1} = sprintf('PID: %d', lockData.pid);
    end
    if isfield(lockData, 'processName') && ~isempty(lockData.processName)
        infoParts{end+1} = sprintf('Processo: %s', char(lockData.processName));
    end
    if isfield(lockData, 'user') && ~isempty(lockData.user)
        infoParts{end+1} = sprintf('Usuario: %s', char(lockData.user));
    end
    if isfield(lockData, 'computer') && ~isempty(lockData.computer)
        infoParts{end+1} = sprintf('Computador: %s', char(lockData.computer));
    end
    if isfield(lockData, 'timestamp') && ~isempty(lockData.timestamp)
        infoParts{end+1} = sprintf('Iniciado: %s', char(lockData.timestamp));
    end

    if ~isempty(infoParts)
        infoText = strjoin(infoParts, ', ');
        message = sprintf(['Outra instancia do repoSFI ja esta em execucao neste computador ', ...
            '(%s). Use main(''force-restart'') apenas se precisar substituir a instancia atual.'], infoText);
    end
end

%-------------------------------------------------------------------------
% Tenta encerrar a instancia anterior de forma segura
%-------------------------------------------------------------------------
function [stopped, message] = stopExistingServerRuntime(lockState, lockData)
    % O kill so acontece quando lock file e processo vivo batem entre si;
    % isso evita derrubar um PID reciclado por outro aplicativo.
    stopped = false;

    if isempty(lockData) || ~isfield(lockData, 'pid') || isempty(lockData.pid)
        message = 'Force-restart indisponivel: nao foi possivel identificar a instancia atual pelo lock file.';
        return;
    end

    currentProcess = getCurrentServerRuntimeProcessInfo();
    if double(lockData.pid) == double(currentProcess.pid)
        message = 'Force-restart cancelado: o lock file aponta para o processo atual.';
        return;
    end

    processInfo = queryServerRuntimeProcessInfo(lockData.pid);
    if ~processInfo.isActive
        stopped = true;
        message = sprintf('Instancia anterior (PID: %d) ja nao estava ativa.', lockData.pid);
        return;
    end

    if ~canSafelyTerminateServerRuntime(lockData, processInfo)
        message = sprintf(['Force-restart bloqueado por seguranca: o PID %d esta ativo, mas nao foi possivel ', ...
            'confirmar com seguranca que ele pertence a mesma instancia do repoSFI.'], lockData.pid);
        return;
    end

    killProcess(lockData.pid);
    pause(2);

    processInfo = queryServerRuntimeProcessInfo(lockData.pid);
    if processInfo.isActive
        message = sprintf('Force-restart falhou: nao foi possivel encerrar a instancia anterior (PID: %d).', lockData.pid);
        return;
    end

    safeDeleteServerRuntimeFile(lockState.lockFile);
    stopped = true;
    message = sprintf('Force-restart: instancia anterior (PID: %d) encerrada.', lockData.pid);
end
%-------------------------------------------------------------------------
% Verifica se e seguro finalizar o PID registrado
%-------------------------------------------------------------------------
function canTerminate = canSafelyTerminateServerRuntime(lockData, processInfo)
    % Nome e StartTime precisam bater. PID sozinho seria inseguro porque
    % pode apontar para outro processo iniciado depois.
    canTerminate = false;

    if ~processInfo.isActive
        return;
    end

    hasProcessName = isfield(lockData, 'processName') && ~isempty(lockData.processName);
    hasStartTime = isfield(lockData, 'startTimeUtc') && ~isempty(lockData.startTimeUtc);

    if ~hasProcessName || ~hasStartTime || isempty(processInfo.startTimeUtc)
        return;
    end

    sameName = strcmpi(normalizeServerRuntimeProcessName(lockData.processName), ...
        normalizeServerRuntimeProcessName(processInfo.name));
    sameStartTime = strcmp(char(lockData.startTimeUtc), char(processInfo.startTimeUtc));

    canTerminate = sameName && sameStartTime;
end

%-------------------------------------------------------------------------
% Normaliza nome do processo para comparacoes
%-------------------------------------------------------------------------
function normalizedName = normalizeServerRuntimeProcessName(processName)
    % Alguns caminhos devolvem nome com .exe e outros sem; normalizamos
    % para comparar os dois lados com a mesma regra.
    normalizedName = lower(strtrim(char(processName)));
    if numel(normalizedName) >= 4 && strcmpi(normalizedName(end-3:end), '.exe')
        normalizedName = normalizedName(1:end-4);
    end
end

%-------------------------------------------------------------------------
% Limpa lock files obsoletos do novo mecanismo
%-------------------------------------------------------------------------
function cleanupServerRuntimeLock()
    % O mutex ja caiu quando ha crash, mas o lock file stale atrapalha a
    % diagnostica; aqui limpamos esse resto em background.
    try
        lockFile = getServerRuntimeLockFilePath();
        lockData = readServerRuntimeLockFile(lockFile);

        if isempty(lockData)
            return;
        end

        if ~isServerRuntimeLockOwnerActive(lockData)
            safeDeleteServerRuntimeFile(lockFile);
        end
    catch
        % Falha silenciosa em cleanup
    end
end

%-------------------------------------------------------------------------
% Remove arquivo ignorando falhas
%-------------------------------------------------------------------------
function deleted = safeDeleteServerRuntimeFile(filePath)
    % Falhar ao apagar o arquivo nao pode impedir shutdown nem startup.
    deleted = true;

    if isempty(filePath) || ~isfile(filePath)
        return;
    end

    try
        delete(filePath);
    catch
        deleted = false;
    end
end

% =========================================================================
%                            FUNCOES AUXILIARES
% =========================================================================

%-------------------------------------------------------------------------
% Exibe banner de inicializacao
%-------------------------------------------------------------------------
function printBanner()
    fprintf('\n');
    fprintf('  =====================================================================\n');
    fprintf('                                                                       \n');
    fprintf('                   SERVER TCP - repoSFI                               \n');
    fprintf('                                                                       \n');
    fprintf('         Processamento Distribuido de Dados de RF/Espectro           \n');
    fprintf('                                                                       \n');
    appVer = class.Constants.appVersion;
    appRel = class.Constants.appRelease;
    appTime = datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss');
    fprintf('  Versao: %s | Release: %s\n', appVer, appRel);
    fprintf('  Iniciado em: %s\n', appTime);
    fprintf('                                                                       \n');
    fprintf('  =====================================================================\n');
    fprintf('\n');
end

%-------------------------------------------------------------------------
% Exibe status do servidor
%-------------------------------------------------------------------------
function printServerStatus(server)
    fprintf('\n%s\n', repmat('-', 1, 70));
    fprintf('STATUS DO SERVIDOR\n');
    fprintf('%s\n\n', repmat('-', 1, 70));
    
    %% Informacoes de conexao
    fprintf('  CONEXAO TCP\n');
    host = server.General.tcpServer.IP;
    if isempty(host)
        host = 'localhost (0.0.0.0)';
    end
    fprintf('     Host: %s\n', char(host));
    fprintf('     Porta: %d\n', server.General.tcpServer.Port);
    fprintf('     Status: [ATIVO]\n\n');
    
    %% Clientes autorizados
    fprintf('  CLIENTES AUTORIZADOS\n');
    clientList = server.General.tcpServer.ClientList;
    if isempty(clientList)
        fprintf('     (Sem restricao de whitelist)\n');
    else
        for i = 1:numel(clientList)
            fprintf('     - %s\n', clientList{i});
        end
    end
    fprintf('\n');
    
    %% Repositorios
    fprintf('  REPOSITORIOS\n');
    fprintf('     Repo MATLAB: %s\n', server.General.tcpServer.Repo);
    fprintf('     Repo Map: %s\n', server.General.tcpServer.Repo_map);
    
end

%-------------------------------------------------------------------------
% Mata processo via taskkill (Windows) ou kill (Linux/Mac)
%-------------------------------------------------------------------------
function killProcess(pid)
    % Forca o encerramento de um PID quando o force-restart e autorizado.
    try
        if ispc
            system(sprintf('taskkill /F /PID %d >nul 2>&1', pid));
        else
            system(sprintf('kill -9 %d >/dev/null 2>&1', pid));
        end
    catch
    end
end
