classdef ServerLogger < handle
    % ServerLogger - Historico em memoria das transacoes do protocolo.
    %
    % O objetivo desta classe e guardar uma trilha curta do que o servidor
    % efetivamente recebeu e respondeu: cliente, mensagem crua, resumo do
    % request, bytes escritos e status final.
    %
    % Papel na arquitetura:
    %   - registrar requests/responses ja processados pelo tcpServerLib
    %   - expor esse historico via getLog() e getLogCount()
    %   - apoiar diagnostico funcional do protocolo sem depender de disco
    %
    % Nao confundir com server.RuntimeLog:
    %   - ServerLogger e em memoria e orientado a transacoes
    %   - RuntimeLog e persistente em disco e orientado a saude/runtime
    %
    % Em resumo:
    %   - "quais requests entraram e como terminaram?" -> ServerLogger
    %   - "o listener caiu, o timer parou ou houve excecao?" -> RuntimeLog

    properties (Access = private)
        % Uma linha por transacao, sempre no mesmo schema, para simplificar
        % consulta, depuracao e exportacao posterior do historico.
        logTable
    end

    methods
        %------------------------------------------------------------------
        % Construtor - inicializa tabela de log
        %------------------------------------------------------------------
        % O schema fixo evita casos especiais quando o historico ainda
        % esta vazio e deixa estavel o contrato de getLog().
        function obj = ServerLogger()
            obj.logTable = table( ...
                'Size', [0, 8], ...
                'VariableTypes', {'string', 'string', 'double', 'string', 'string', 'string', 'double', 'string'}, ...
                'VariableNames', {'Timestamp', 'ClientAddress', 'ClientPort', 'Message', 'ClientName', 'Request', 'NumBytesWritten', 'Status'} ...
                );
        end

        %------------------------------------------------------------------
        % Registra uma transacao no log
        %------------------------------------------------------------------
        % Guarda a mensagem crua e um resumo do Request para facilitar
        % depuracao sem reprocessar o JSON original. Eventos de
        % infraestrutura ficam no RuntimeLog; aqui entram apenas
        % transacoes do pipeline request/response.
        function logTransaction(obj, clientAddress, clientPort, rawMsg, decodedMsg, numBytesWritten, status)
            arguments
                obj
                clientAddress (1,:) char
                clientPort (1,1) double
                rawMsg (1,:) string
                decodedMsg (1,1) struct
                numBytesWritten (1,1) double
                status (1,:) string
            end

            % Normaliza campos opcionais para manter o schema estavel,
            % mesmo quando clientes diferentes enviam estruturas distintas.
            if isfield(decodedMsg, 'ClientName')
                clientName = decodedMsg.ClientName;
            else
                clientName = '-';
            end

            if isfield(decodedMsg, 'Request')
                request = jsonencode(decodedMsg.Request);
            else
                request = '-';
            end

            % A nova linha e anexada ao final para preservar a ordem
            % cronologica de chegada e correlacionar com o RuntimeLog.
            newRow = {
                string(datestr(now)), ...
                string(clientAddress), ...
                clientPort, ...
                rawMsg, ...
                string(clientName), ...
                string(request), ...
                numBytesWritten, ...
                status
            };

            obj.logTable(end+1,:) = newRow;
        end

        %------------------------------------------------------------------
        % Retorna tabela completa de log
        %------------------------------------------------------------------
        % Exposicao direta do historico em memoria para diagnostico
        % funcional e inspecao offline.
        function table = getLogTable(obj)
            table = obj.logTable;
        end

        %------------------------------------------------------------------
        % Retorna numero de entradas no log
        %------------------------------------------------------------------
        % Usado pelo loop principal para saber quando houve nova atividade
        % de request/response registrada no historico em memoria.
        function count = getLogCount(obj)
            count = height(obj.logTable);
        end

        %------------------------------------------------------------------
        % Limpa o log
        %------------------------------------------------------------------
        % Limpa o conteudo sem recriar a tabela e sem perder o schema das
        % colunas para futuras insercoes.
        function clearLog(obj)
            obj.logTable = obj.logTable(false(height(obj.logTable), 1), :);
        end

        %------------------------------------------------------------------
        % Retorna ultimas N entradas
        %------------------------------------------------------------------
        % Recorta so a cauda do historico, mantendo a ordem cronologica
        % original para diagnostico rapido.
        function lastEntries = getLastEntries(obj, n)
            arguments
                obj
                n (1,1) double {mustBePositive, mustBeInteger}
            end

            nRows = height(obj.logTable);
            if nRows == 0
                lastEntries = obj.logTable;
            else
                startIdx = max(1, nRows - n + 1);
                lastEntries = obj.logTable(startIdx:end, :);
            end
        end
    end
end
