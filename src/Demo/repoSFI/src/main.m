function main(varargin)
    % main - Entry-point minimo do repoSFI.
    %
    % O main existe apenas para:
    %   - impedir segunda instancia na mesma maquina
    %   - criar o tcpServerLib
    %   - manter o processo vivo
    %   - registrar inicio, fim e crash no RuntimeLog

    if ~isempty(varargin)
        error('repoSFI:main:UnsupportedArguments', ...
            ['main nao aceita mais argumentos. O modo "force-restart" foi removido ', ...
             'porque era fragil e adicionava complexidade demais ao bootstrap.']);
    end

    tcpServer = [];
    instanceLock = createEmptyLockState();

    try
        % O banner e propositalmente simples: so identifica versao e
        % deixa claro que a instancia iniciou.
        printBanner();

        % O mutex global e a unica trava de concorrencia que mantemos.
        instanceLock = acquireServerInstanceLock();

        fprintf('[INFO] Inicializando servidor TCP...\n');
        tcpServer = tcpServerLib();
        printServerStatus(tcpServer);

        server.RuntimeLog.logInfo( ...
            'main', ...
            'Servidor inicializado com sucesso.', ...
            buildRuntimeDetails(tcpServer));

        while true
            pause(1);
        end

    catch ME
        % Outra instancia aberta nao e erro operacional; tratamos como
        % saida limpa com mensagem simples.
        if strcmp(ME.identifier, 'repoSFI:main:AlreadyRunning')
            fprintf('[INFO] %s\n', ME.message);
            server.RuntimeLog.logInfo('main', ME.message, basicProcessDetails());

        % Ctrl+C no MATLAB interativo cai aqui como excecao.
        elseif strcmp(ME.identifier, 'MATLAB:interrupted')
            fprintf('\n[INFO] Servidor interrompido pelo usuario.\n');
            server.RuntimeLog.logInfo( ...
                'main', ...
                'Servidor interrompido pelo usuario.', ...
                buildRuntimeDetails(tcpServer));

        % Qualquer outra falha sobe para o console e para o RuntimeLog.
        else
            fprintf(2, '\n[ERRO] Excecao capturada durante execucao.\n');
            fprintf(2, '%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
            server.RuntimeLog.logException( ...
                'main', ...
                ME, ...
                buildRuntimeDetails(tcpServer));
        end

    finally
        if ~isempty(tcpServer)
            try
                delete(tcpServer);
            catch deleteError
                server.RuntimeLog.logWarning( ...
                    'main', ...
                    'Falha ao destruir tcpServerLib durante o encerramento.', ...
                    struct( ...
                        'Identifier', string(deleteError.identifier), ...
                        'Message', string(deleteError.message)));
            end
        end

        releaseServerInstanceLock(instanceLock);
        server.RuntimeLog.logInfo('main', 'Processo finalizado.', basicProcessDetails());
    end
end

% acquireServerInstanceLock - Garante que apenas uma instancia fique ativa.
%
% O fluxo aqui e deliberadamente curto:
%   1. cria/abre o mutex global
%   2. tenta adquirir posse imediata
%   3. falha se outra instancia ainda estiver viva
function lockState = acquireServerInstanceLock()
    lockState = createEmptyLockState();
    lockState.mutexName = getServerInstanceMutexName();

    [lockState.mutex, errorMessage] = createServerInstanceMutex(lockState.mutexName);
    if isempty(lockState.mutex)
        error('repoSFI:main:MutexCreateFailed', ...
            'Nao foi possivel criar o mutex global da instancia: %s', errorMessage);
    end

    [ownsMutex, mutexWasAbandoned, errorMessage] = tryAcquireServerInstanceMutex(lockState.mutex, 0);
    if ~isempty(errorMessage)
        releaseServerInstanceLock(lockState);
        error('repoSFI:main:MutexAcquireFailed', ...
            'Nao foi possivel adquirir o mutex global da instancia: %s', errorMessage);
    end

    if ~ownsMutex
        releaseServerInstanceLock(lockState);
        error('repoSFI:main:AlreadyRunning', ...
            'Outra instancia do repoSFI ja esta em execucao neste computador.');
    end

    lockState.ownsMutex = true;

    if mutexWasAbandoned
        server.RuntimeLog.logWarning( ...
            'main', ...
            'Mutex abandonado recuperado pelo processo atual.', ...
            basicProcessDetails());
    end
end

% releaseServerInstanceLock - Libera o mutex global, se esta copia o possui.
function releaseServerInstanceLock(lockState)
    if isempty(lockState) || ~isstruct(lockState)
        return;
    end

    if isfield(lockState, 'ownsMutex') && lockState.ownsMutex && ...
            isfield(lockState, 'mutex') && ~isempty(lockState.mutex)
        try
            lockState.mutex.ReleaseMutex();
        catch
        end
    end

    if isfield(lockState, 'mutex') && ~isempty(lockState.mutex)
        try
            lockState.mutex.Close();
        catch
        end
    end
end

% createEmptyLockState - Estado minimo para carregar o mutex ate o finally.
function lockState = createEmptyLockState()
    lockState = struct( ...
        'mutexName', '', ...
        'mutex', [], ...
        'ownsMutex', false);
end

% getServerInstanceMutexName - Nome estavel do mutex de instancia unica.
function mutexName = getServerInstanceMutexName()
    if ispc
        mutexName = 'Global\ANATEL_repoSFI_ServerInstance';
    else
        mutexName = 'ANATEL_repoSFI_ServerInstance';
    end
end

% createServerInstanceMutex - Abre o mutex nomeado do sistema operacional.
function [mutexObj, errorMessage] = createServerInstanceMutex(mutexName)
    mutexObj = [];
    errorMessage = '';

    try
        mutexObj = System.Threading.Mutex(false, mutexName);
    catch ME
        errorMessage = ME.message;
    end
end

% tryAcquireServerInstanceMutex - Tenta adquirir posse do mutex sem bloquear.
%
% Em caso de abandoned mutex, o Windows devolve a posse para o processo
% atual. Isso nao e falha; apenas registramos que houve recuperacao.
function [ownsMutex, mutexWasAbandoned, errorMessage] = tryAcquireServerInstanceMutex(mutexObj, timeoutMs)
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

% buildRuntimeDetails - Contexto leve para enriquecer o RuntimeLog.
function details = buildRuntimeDetails(tcpServer)
    details = basicProcessDetails();

    if isempty(tcpServer)
        return;
    end

    try
        details.RuntimeHealth = tcpServer.getRuntimeHealth();
    catch
    end
end

% basicProcessDetails - Metadados simples do processo atual.
function details = basicProcessDetails()
    details = struct( ...
        'PID', feature('getpid'), ...
        'User', string(getEnvOrDefault('USERNAME', '-')), ...
        'Computer', string(getEnvOrDefault('COMPUTERNAME', '-')), ...
        'WorkingDirectory', string(pwd), ...
        'Deployed', logical(isdeployed));
end

% getEnvOrDefault - Le variavel de ambiente com fallback amigavel.
function value = getEnvOrDefault(name, defaultValue)
    value = getenv(name);
    if isempty(value)
        value = defaultValue;
    end
end

% printBanner - Cabecalho curto exibido no startup.
function printBanner()
    fprintf('\nrepoSFI TCP Server\n');
    fprintf('==================\n');
    fprintf('Versao: %s | Release: %s\n', class.Constants.appVersion, class.Constants.appRelease);
end

% printServerStatus - Resume no console onde o listener ficou disponivel.
function printServerStatus(tcpServer)
    host = tcpServer.General.tcpServer.IP;
    if isempty(host)
        host = '0.0.0.0';
    end

    fprintf('[INFO] Servidor pronto em %s:%d\n', char(host), tcpServer.General.tcpServer.Port);
    fprintf('[INFO] Pressione Ctrl+C para encerrar.\n');
end
