classdef ServerLogger < handle
    % ServerLogger - Mantem uma trilha curta do que o servidor processou.
    %
    % O log fica em memoria para diagnostico rapido: quem chamou, o que
    % mandou, quanto foi escrito na resposta e como a operacao terminou.
    % ServerLogger - Gerencia logging das operações do servidor
    %
    % Mantém histórico de requisições, respostas, erros e eventos
    
    properties (Access = private)
        % Uma linha por transacao, sempre no mesmo schema para simplificar consulta.
        logTable
    end
    
    methods
        %------------------------------------------------------------------
        % Construtor - inicializa tabela de log
        %------------------------------------------------------------------
        % O schema fixo evita ifs especiais quando o log ainda esta vazio.
        function obj = ServerLogger()
            obj.logTable = table( ...
                'Size', [0, 8], ...
                'VariableTypes', {'string', 'string', 'double', 'string', 'string', 'string', 'double', 'string'}, ...
                'VariableNames', {'Timestamp', 'ClientAddress', 'ClientPort', 'Message', 'ClientName', 'Request', 'NumBytesWritten', 'Status'} ...
                );
        end
        
        %------------------------------------------------------------------
        % Registra uma transação no log
        %------------------------------------------------------------------
        % Guarda a mensagem crua e uma versao resumida do Request para
        % facilitar depuracao sem precisar reprocessar o JSON original.
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
            
            % Extrai ClientName
            if isfield(decodedMsg, 'ClientName')
                clientName = decodedMsg.ClientName;
            else
                clientName = '-';
            end
            
            % Extrai Request
            if isfield(decodedMsg, 'Request')
                request = jsonencode(decodedMsg.Request);
            else
                request = '-';
            end
            
            % Adiciona à tabela
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
        % Exposicao direta da tabela para diagnostico e inspecao offline.
        function table = getLogTable(obj)
            table = obj.logTable;
        end
        
        %------------------------------------------------------------------
        % Retorna número de entradas no log
        %------------------------------------------------------------------
        % Usado pelo loop principal para saber quando houve nova atividade.
        function count = getLogCount(obj)
            count = height(obj.logTable);
        end
        
        %------------------------------------------------------------------
        % Limpa o log
        %------------------------------------------------------------------
        % Limpa o conteudo sem recriar a tabela e sem perder as colunas.
        function clearLog(obj)
            obj.logTable = obj.logTable(false(height(obj.logTable), 1), :);
        end
        
        %------------------------------------------------------------------
        % Retorna últimas N entradas
        %------------------------------------------------------------------
        % Recorta so a cauda do log, mantendo a ordem cronologica original.
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
