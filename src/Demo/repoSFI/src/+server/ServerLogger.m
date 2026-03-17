classdef ServerLogger < handle
    % ServerLogger - Gerencia logging das operações do servidor
    %
    % Mantém histórico de requisições, respostas, erros e eventos
    
    properties (Access = private)
        logTable
    end
    
    methods
        %------------------------------------------------------------------
        % Construtor - inicializa tabela de log
        %------------------------------------------------------------------
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
        function table = getLogTable(obj)
            table = obj.logTable;
        end
        
        %------------------------------------------------------------------
        % Retorna número de entradas no log
        %------------------------------------------------------------------
        function count = getLogCount(obj)
            count = height(obj.logTable);
        end
        
        %------------------------------------------------------------------
        % Limpa o log
        %------------------------------------------------------------------
        function clearLog(obj)
            obj.logTable = obj.logTable(false(height(obj.logTable), 1), :);
        end
        
        %------------------------------------------------------------------
        % Retorna últimas N entradas
        %------------------------------------------------------------------
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
