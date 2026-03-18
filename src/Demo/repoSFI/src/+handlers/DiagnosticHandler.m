classdef DiagnosticHandler
    % DiagnosticHandler - Consolida informacoes de diagnostico do ambiente.
    %
    % O handler e usado para suporte operacional e verificacoes de saude,
    % reunindo metadados da aplicacao, variaveis de ambiente e dados do host.
    % DiagnosticHandler - Processa requisições de diagnóstico
    %
    % Retorna informações de sistema, ambiente e configuração
    
    methods (Static)
        %------------------------------------------------------------------
        % Processa requisição Diagnostic
        %------------------------------------------------------------------
        % Retorna um snapshot enxuto do ambiente de execucao.
        function answer = handle()
            answer = struct( ...
                'App', struct( ...
                    'name', class.Constants.appName, ...
                    'release', class.Constants.appRelease, ...
                    'version', class.Constants.appVersion ...
                ), ...
                'EnvVariables', [], ...
                'SystemInfo', [], ...
                'LogicalDisk', [] ...
                );
            
            % Coleta variáveis de ambiente
            answer.EnvVariables = handlers.DiagnosticHandler.getEnvVariables();
            
            % Coleta info de sistema
            answer.SystemInfo = handlers.DiagnosticHandler.getSystemInfo();
            
            % Coleta info de discos
            answer.LogicalDisk = handlers.DiagnosticHandler.getLogicalDiskInfo();
        end
        
        %------------------------------------------------------------------
        % Coleta variáveis de ambiente relevantes
        %------------------------------------------------------------------
        % Filtra apenas variaveis relevantes para suporte e inventario.
        function envTable = getEnvVariables()
            envFields = ["COMPUTERNAME", "MATLAB_ARCH", "MODEL", ...
                "PROCESSOR_ARCHITECTURE", "PROCESSOR_IDENTIFIER", ...
                "PROCESSOR_LEVEL", "SERIAL", "TYPE2"];
            
            envVariables = getenv();
            envKeys      = keys(envVariables, 'uniform');
            envValues    = values(envVariables, 'uniform');
            
            [~, idx] = ismember(envFields, envKeys);
            idx(~idx) = [];
            
            if isempty(idx)
                envTable = table();
            else
                envTable = table(envKeys(idx), envValues(idx), ...
                    'VariableNames', {'env', 'value'});
            end
        end
        
        %------------------------------------------------------------------
        % Coleta informações de sistema (via systeminfo)
        %------------------------------------------------------------------
        % Faz o parse da saida do comando systeminfo em pares chave/valor.
        function systemInfo = getSystemInfo()
            systemInfo = struct('parameter', {}, 'value', {});
            
            try
                [status, cmdout] = system('systeminfo');
                if status ~= 0
                    return;
                end
                
                cmdout = strtrim(splitlines(cmdout));
                cmdout(cellfun(@(x) isempty(x), cmdout)) = [];
                
                % Mapa de nomes de parâmetros
                sysNames = [...
                    "Host Name", "OS Name", "OS Version", "Product ID", ...
                    "Original Install Date", "System Boot Time", ...
                    "System Manufacturer", "System Model", "System Type", ...
                    "BIOS Version", "Total Physical Memory", ...
                    "Available Physical Memory", "Virtual Memory: Max Size", ...
                    "Virtual Memory: Available", "Virtual Memory: In Use"];
                
                sysDict = dictionary(sysNames, ...
                    replace(sysNames(1:15), {' ', ':'}, {'', ''}));
                
                % Parse da saída
                cmdout_Cell = cellfun(@(x) regexp(x, ...
                    '(?<parameter>[A-Z]\D+)[:]\s+(?<value>.+)', 'names'), ...
                    cmdout, 'UniformOutput', false);
                
                for ii = 1:numel(cmdout_Cell)
                    if ~isempty(cmdout_Cell{ii})
                        keyName = cmdout_Cell{ii}.parameter;
                        if isKey(sysDict, keyName)
                            systemInfo(end+1) = struct( ...
                                'parameter', sysDict(keyName), ...
                                'value', cmdout_Cell{ii}.value);
                        end
                    end
                end
            catch
                % Silenciosamente ignora erros
            end
        end
        
        %------------------------------------------------------------------
        % Coleta informações de discos lógicos
        %------------------------------------------------------------------
        % Extrai capacidade e espaco livre das unidades logicas visiveis.
        function logicalDisk = getLogicalDiskInfo()
            logicalDisk = struct.empty;
            
            try
                [status, cmdout] = system("wmic LOGICALDISK get DeviceID,FileSystem,FreeSpace,Size");
                if status ~= 0
                    return;
                end
                
                cmdout = strtrim(splitlines(cmdout));
                cmdout(cellfun(@(x) isempty(x), cmdout)) = [];
                
                if numel(cmdout) > 1
                    logicalDisk = cellfun(@(x) regexp(x, ...
                        '(?<DeviceID>[A-Z]:)\s+(?<FileSystem>\w+)\s+(?<FreeSpace>\d+)\s+(?<Size>\d+)', ...
                        'names'), cmdout(2:end));
                end
            catch
                % Silenciosamente ignora erros
            end
        end
    end
end
