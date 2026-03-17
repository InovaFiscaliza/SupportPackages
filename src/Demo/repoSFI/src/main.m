function main()
    % main - Inicializa o servidor TCP repoSFI
    %
    % Servidor TCP para processamento distribuido de dados de espectro/RF
    % Recebe requisicoes JSON via socket e processa em MATLAB
    
    try
        % ===================================================================
        % INICIALIZACAO
        % ===================================================================
        printBanner()
        
        % Cria instancia do servidor
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
        
        while true
            pause(1);
            
            % Atualiza exibição periodicamente (a cada 30 segundos)
            currentLogCount = server.getLogCount();
            if currentLogCount ~= lastLogCount
                fprintf('[%s] > Requisicao processada | Total: %d | Status: OK\n', ...
                    datetime('now', 'Format', 'HH:mm:ss'), currentLogCount);
                lastLogCount = currentLogCount;
            end
        end
        
    catch ME
        % ===================================================================
        % TRATAMENTO DE ERROS
        % ===================================================================
        fprintf('\n%s\n', repmat('=', 1, 70));
        fprintf('[ERRO] Excecao capturada durante execucao\n');
        fprintf('%s\n', repmat('=', 1, 70));
        fprintf(2, '%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
        fprintf('%s\n\n', repmat('=', 1, 70));
        
        %% Aguarda entrada do usuario para sair
        fprintf('Pressione ENTER para sair...\n');
        input('');
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
    fprintf('     Host: %s\n', char(ifempty(server.General.tcpServer.IP, 'localhost (0.0.0.0)')));
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
% Funcao auxiliar para tratamento de valores vazios
%-------------------------------------------------------------------------
function result = ifempty(value, default)
    if isempty(value)
        result = default;
    else
        result = value;
    end
end
