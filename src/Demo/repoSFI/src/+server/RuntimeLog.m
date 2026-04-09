classdef RuntimeLog
    % RuntimeLog - Escrita best-effort no log persistente da aplicacao.
    %
    % O helper permite que callbacks, timers e o processo principal
    % registrem diagnosticos no mesmo arquivo de log em ProgramData.
    %
    % Papel na arquitetura:
    %   - persiste eventos operacionais em disco
    %   - sobrevive enquanto o processo estiver vivo
    %   - e pensado para diagnostico de excecoes, watchdog, timer,
    %     listener TCP e falhas que nao ficam visiveis no console
    %
    % Nao confundir com server.ServerLogger:
    %   - RuntimeLog escreve em arquivo
    %   - ServerLogger guarda em memoria um historico curto das
    %     transacoes request/response do protocolo
    %
    % Em outras palavras: RuntimeLog responde "o processo estava saudavel
    % e o listener caiu?" enquanto ServerLogger responde "quais requests o
    % servidor conseguiu processar e devolver?".

    properties (Constant, Access = private)
        MaxBytes = 100 * 1024 * 1024
        LogFileName = 'repoSFI-runtime.log'
    end

    methods (Static)
        %------------------------------------------------------------------
        % Caminho do arquivo persistente
        %------------------------------------------------------------------
        function logFile = getFilePath()
            logFile = '';

            try
                % Centraliza a resolucao do caminho do log para que os
                % chamadores nao precisem conhecer ProgramData, fallback
                % em tempdir ou detalhes de criacao da pasta.
                logFolder = server.RuntimeLog.getLogFolder();
                if isempty(logFolder)
                    return;
                end

                logFile = fullfile(logFolder, server.RuntimeLog.LogFileName);
            catch
                % Logging e opcional do ponto de vista do runtime. Se a
                % resolucao do caminho falhar, devolvemos vazio e o
                % chamador segue sem interromper o servico principal.
                logFile = '';
            end
        end

        %------------------------------------------------------------------
        % Registro simples informativo
        %------------------------------------------------------------------
        % Esse caminho atende eventos operacionais esperados, como
        % inicializacao, heartbeat, reconexao e milestones do runtime.
        function logInfo(source, message, details)
            if nargin < 3
                details = [];
            end

            server.RuntimeLog.writeEntry('INFO', source, message, details);
        end

        %------------------------------------------------------------------
        % Registro simples de aviso
        %------------------------------------------------------------------
        % Warnings aqui normalmente indicam degradacao ou recuperacao
        % parcial do processo, mas sem interromper a execucao inteira.
        function logWarning(source, message, details)
            if nargin < 3
                details = [];
            end

            server.RuntimeLog.writeEntry('WARN', source, message, details);
        end

        %------------------------------------------------------------------
        % Registro detalhado de excecao
        %------------------------------------------------------------------
        % Esse metodo e o ponto de entrada para erros relevantes do
        % runtime. Ele aceita tanto MException quanto mensagens simples
        % para manter um contrato unico de escrita no log persistente.
        function logException(source, exceptionOrMessage, details)
            if nargin < 3
                details = [];
            end

            % MException recebe tratamento especial para incluir stack e
            % report extendido. Para mensagens simples, reutilizamos o
            % proprio texto como report final.
            if isa(exceptionOrMessage, 'MException')
                message = exceptionOrMessage.message;
                report = server.RuntimeLog.getExceptionReport(exceptionOrMessage);
            else
                message = char(string(exceptionOrMessage));
                report = char(string(exceptionOrMessage));
            end

            logText = sprintf('[%s] [ERROR] [%s] %s\n', ...
                server.RuntimeLog.getTimestamp(), ...
                char(string(source)), ...
                char(string(message)));

            detailsText = server.RuntimeLog.formatDetails(details);
            if ~isempty(detailsText)
                logText = sprintf('%s[DETAILS] %s\n', logText, detailsText);
            end

            % O report extendido e especialmente util para diagnosticar
            % falhas em callbacks, timers e codigo compilado sem console.
            if ~isempty(strtrim(report))
                logText = sprintf('%s%s\n', logText, char(report));
            end

            server.RuntimeLog.appendText(logText);
        end

        %------------------------------------------------------------------
        % Append bruto de texto
        %------------------------------------------------------------------
        function appendText(text)
            logFile = server.RuntimeLog.getFilePath();
            if isempty(logFile)
                return;
            end

            % Antes de cada append aplicamos a politica simples de teto de
            % tamanho. Quando o arquivo cresce demais, ele e reiniciado no
            % mesmo caminho para manter o suporte operacional previsivel.
            server.RuntimeLog.maintainFile(logFile);

            fid = -1;
            try
                % Nao mantemos handle aberto entre chamadas para evitar
                % estado compartilhado desnecessario em callbacks/timers.
                fid = fopen(logFile, 'a');
                if fid == -1
                    return;
                end

                fprintf(fid, '%s', char(text));
                fclose(fid);
            catch
                % O logger e best-effort: erro de disco/permissao nao pode
                % derrubar o servico. Ainda assim, se o arquivo abriu,
                % garantimos fechamento antes de sair.
                if fid ~= -1
                    fclose(fid);
                end
            end
        end
    end

    methods (Static, Access = private)
        %------------------------------------------------------------------
        % Monta e grava uma linha simples de log
        %------------------------------------------------------------------
        function writeEntry(level, source, message, details)
            % Padroniza o formato das linhas simples para facilitar grep,
            % ordenacao visual e comparacao entre INFO/WARN/ERROR.
            logText = sprintf('[%s] [%s] [%s] %s\n', ...
                server.RuntimeLog.getTimestamp(), ...
                char(string(level)), ...
                char(string(source)), ...
                char(string(message)));

            detailsText = server.RuntimeLog.formatDetails(details);
            if ~isempty(detailsText)
                logText = sprintf('%s[DETAILS] %s\n', logText, detailsText);
            end

            server.RuntimeLog.appendText(logText);
        end

        %------------------------------------------------------------------
        % Pasta do log persistente
        %------------------------------------------------------------------
        function logFolder = getLogFolder()
            logFolder = '';

            try
                % Separamos os logs em uma subpasta dedicada para nao
                % misturar diagnostico com outros artefatos operacionais.
                logFolder = fullfile(server.RuntimeLog.getSharedDataFolder(), 'logs');
                if ~isfolder(logFolder)
                    mkdir(logFolder);
                end
            catch
                % Falha em permissao/criacao aqui apenas desabilita o log.
                logFolder = '';
            end
        end

        %------------------------------------------------------------------
        % Pasta base compartilhada
        %------------------------------------------------------------------
        function sharedFolder = getSharedDataFolder()
            programDataFolder = getenv('PROGRAMDATA');
            if isempty(programDataFolder)
                % Em Windows esperamos ProgramData. Se a variavel nao
                % estiver disponivel, tempdir preserva ao menos algum
                % nivel de diagnostico sem impedir a execucao.
                programDataFolder = tempdir;
            end

            sharedFolder = fullfile(programDataFolder, 'ANATEL', class.Constants.appName);
            if ~isfolder(sharedFolder)
                mkdir(sharedFolder);
            end
        end

        %------------------------------------------------------------------
        % Reinicia o arquivo se ultrapassar o tamanho maximo
        %------------------------------------------------------------------
        function maintainFile(logFile)
            fileSize = server.RuntimeLog.getFileSize(logFile);
            if fileSize < 0 || fileSize <= server.RuntimeLog.MaxBytes
                return;
            end

            % A estrategia aqui e deliberadamente simples: ao exceder o
            % limite, sobrescrevemos o mesmo arquivo com um cabecalho que
            % explica o reset. Isso evita proliferacao de arquivos rotacionados.
            resetHeader = sprintf(['[%s] [INFO] [RuntimeLog] Log reiniciado automaticamente apos exceder ', ...
                'o limite de %.0f MB (tamanho anterior: %.2f MB).\n'], ...
                server.RuntimeLog.getTimestamp(), ...
                server.RuntimeLog.MaxBytes / (1024 * 1024), ...
                fileSize / (1024 * 1024));

            fid = -1;
            try
                % Modo write recria o log do zero, preservando apenas o
                % contexto minimo de por que o historico foi truncado.
                fid = fopen(logFile, 'w');
                if fid == -1
                    return;
                end

                fprintf(fid, '%s', char(resetHeader));
                fclose(fid);
            catch
                if fid ~= -1
                    fclose(fid);
                end
            end
        end

        %------------------------------------------------------------------
        % Tamanho atual do arquivo
        %------------------------------------------------------------------
        function fileSize = getFileSize(logFile)
            fileSize = -1;

            if isempty(logFile) || ~isfile(logFile)
                % Arquivo ausente nao e considerado erro; tratamos como
                % tamanho zero para permitir o primeiro append normalmente.
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

        %------------------------------------------------------------------
        % Horario padrao do log
        %------------------------------------------------------------------
        function timestamp = getTimestamp()
            timestamp = char(datetime('now', 'Format', 'dd/MM/yyyy HH:mm:ss'));
        end

        %------------------------------------------------------------------
        % Converte detalhes para texto de diagnostico
        %------------------------------------------------------------------
        function detailsText = formatDetails(details)
            detailsText = '';

            if isempty(details)
                return;
            end

            if ischar(details) || (isstring(details) && isscalar(details))
                % Texto simples entra direto no log, sem serializacao extra.
                detailsText = char(string(details));
            else
                try
                    % JSON e o formato preferido porque produz uma linha
                    % mais estavel para leitura humana e parse automatizado.
                    detailsText = jsonencode(details);
                catch
                    try
                        % Alguns tipos MATLAB nao serializam bem em JSON.
                        % O fallback com disp(...) tenta preservar algum
                        % diagnostico util em vez de perder os detalhes.
                        detailsText = strtrim(evalc('disp(details)'));
                    catch
                        detailsText = '<detalhes indisponiveis>';
                    end
                end
            end

            % Mantemos os detalhes em uma unica linha para facilitar busca
            % com rg/grep e leitura rapida no tail do arquivo.
            detailsText = strrep(detailsText, newline, ' | ');
            detailsText = strtrim(detailsText);
        end

        %------------------------------------------------------------------
        % Gera report estendido de excecao
        %------------------------------------------------------------------
        function report = getExceptionReport(ME)
            report = '';

            try
                % Preferimos o report extendido porque ele preserva stack e
                % contexto, que fazem falta no ambiente compilado.
                report = getReport(ME, 'extended', 'hyperlinks', 'off');
            catch
                try
                    % Se getReport falhar, registramos ao menos a mensagem
                    % curta da excecao original.
                    report = char(string(ME.message));
                catch
                    report = 'Falha ao obter detalhes da excecao.';
                end
            end
        end
    end
end
