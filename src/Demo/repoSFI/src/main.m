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
    
    % Verifica parametro de forÃ§a restart
    if ~isempty(varargin) && ischar(varargin{1}) && strcmp(varargin{1}, 'force-restart')
        forceRestart = true;
    end
    
    try
        % ===================================================================
        % INICIALIZACAO
        % ===================================================================
        printBanner()
        
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
        end
        
    catch ME
        % ===================================================================
        % TRATAMENTO DE ERROS E INTERRUPCAO
        % ===================================================================
        % Ctrl+C lanÃ§a exceÃ§Ã£o com ID 'MATLAB:interrupted'
        % No MATLAB interativo, Ctrl+C chega aqui como excecao.
        if strcmp(ME.identifier, 'MATLAB:interrupted')
            fprintf('\n%s\n', repmat('=', 1, 70));
            fprintf('[INFO] Servidor interrompido pelo usuario\n');
            fprintf('%s\n\n', repmat('=', 1, 70));
        else
            fprintf('\n%s\n', repmat('=', 1, 70));
            fprintf('[ERRO] Excecao capturada durante execucao\n');
            fprintf('%s\n', repmat('=', 1, 70));
            fprintf(2, '%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
            fprintf('%s\n\n', repmat('=', 1, 70));
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
    end
    
end

%-------------------------------------------------------------------------
% Novo controle de instancia unica usando mutex global do Windows
%-------------------------------------------------------------------------
function [canStart, lockState, message] = acquireServerRuntimeLock(forceRestart)
    % O mutex e o bloqueio real entre sessoes/usuarios desta maquina.
    % O lock file existe so para dizer quem era o dono da instancia e para
    % permitir um force-restart sem confiar apenas em PID solto.
    arguments
        forceRestart (1,1) logical = false
    end

    canStart = true;
    message = '';
    lockState = createEmptyLockState();
    lockState.lockFile = getServerRuntimeLockFilePath();
    lockState.mutexName = getServerRuntimeMutexName();

    [lockState.mutex, errorMessage] = createServerRuntimeMutex(lockState.mutexName);
    if isempty(lockState.mutex)
        canStart = false;
        message = sprintf('Erro ao criar bloqueio global da instancia: %s', errorMessage);
        return;
    end

    [ownsMutex, mutexWasAbandoned, errorMessage] = tryAcquireServerRuntimeMutex(lockState.mutex, 0);
    if ~isempty(errorMessage)
        canStart = false;
        message = sprintf('Erro ao adquirir bloqueio global da instancia: %s', errorMessage);
        return;
    end

    existingLockData = readServerRuntimeLockFile(lockState.lockFile);

    if ~ownsMutex
        if forceRestart
            [stopped, stopMessage] = stopExistingServerRuntime(lockState, existingLockData);
            if ~stopped
                canStart = false;
                message = stopMessage;
                return;
            end

            pause(2);
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
            canStart = false;
            message = buildServerRuntimeAlreadyRunningMessage(existingLockData);
            return;
        end
    elseif mutexWasAbandoned
        message = 'Instancia anterior finalizou de forma inesperada. O bloqueio foi recuperado com sucesso.';
    end

    lockState.ownsMutex = true;

    if ~isempty(existingLockData) && ~isServerRuntimeLockOwnerActive(existingLockData)
        safeDeleteServerRuntimeFile(lockState.lockFile);
    end

    lockData = buildCurrentServerRuntimeLockData(lockState.mutexName);
    [writeOk, errorMessage] = writeServerRuntimeLockFile(lockState.lockFile, lockData);
    if ~writeOk
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
    programDataFolder = fullfile(getenv('PROGRAMDATA'), 'ANATEL', 'repoSFI');
    if ~isfolder(programDataFolder)
        mkdir(programDataFolder);
    end

    lockFile = fullfile(programDataFolder, '.server.lock');
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
        'pid', feature('getpid'), ...
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
