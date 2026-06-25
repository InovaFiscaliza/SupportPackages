classdef DiagnosticHandler
    % DiagnosticHandler - Consolida informacoes de diagnostico do ambiente.
    %
    % O handler devolve um snapshot curto do ambiente de execucao para
    % suporte operacional e verificacoes simples de diagnostico.

    methods (Static)
        %------------------------------------------------------------------
        % Processa requisicao Diagnostic
        %------------------------------------------------------------------
        function answer = handle()
            envFields = ["COMPUTERNAME", "MATLAB_ARCH", "MODEL", ...
                "PROCESSOR_ARCHITECTURE", "PROCESSOR_IDENTIFIER", ...
                "PROCESSOR_LEVEL", "SERIAL", "TYPE2"];
            envVariables = getenv();
            envKeys = keys(envVariables, 'uniform');
            envValues = values(envVariables, 'uniform');
            [~, idx] = ismember(envFields, envKeys);
            idx(~idx) = [];

            answer = struct( ...
                'App', struct( ...
                    'name', class.Constants.appName, ...
                    'release', class.Constants.appRelease, ...
                    'version', class.Constants.appVersion ...
                ), ...
                'EnvVariables', table(), ...
                'SystemInfo', handlers.DiagnosticHandler.getSystemInfo(), ...
                'LogicalDisk', handlers.DiagnosticHandler.getLogicalDiskInfo() ...
                );

            if ~isempty(idx)
                answer.EnvVariables = table(envKeys(idx), envValues(idx), ...
                    'VariableNames', {'env', 'value'});
            end
        end

        %------------------------------------------------------------------
        % Coleta informacoes de sistema (via systeminfo)
        %------------------------------------------------------------------
        function systemInfo = getSystemInfo()
            systemInfo = struct('parameter', {}, 'value', {});

            try
                [status, cmdout] = system('systeminfo');
                if status ~= 0
                    return;
                end

                cmdout = strtrim(splitlines(cmdout));
                cmdout(cellfun(@(x) isempty(x), cmdout)) = [];

                sysNames = [...
                    "Host Name", "OS Name", "OS Version", "Product ID", ...
                    "Original Install Date", "System Boot Time", ...
                    "System Manufacturer", "System Model", "System Type", ...
                    "BIOS Version", "Total Physical Memory", ...
                    "Available Physical Memory", "Virtual Memory: Max Size", ...
                    "Virtual Memory: Available", "Virtual Memory: In Use"];
                sysDict = dictionary(sysNames, ...
                    replace(sysNames(1:15), {' ', ':'}, {'', ''}));

                cmdoutCell = cellfun(@(x) regexp(x, ...
                    '(?<parameter>[A-Z]\D+)[:]\s+(?<value>.+)', 'names'), ...
                    cmdout, 'UniformOutput', false);

                for ii = 1:numel(cmdoutCell)
                    if isempty(cmdoutCell{ii})
                        continue
                    end

                    keyName = cmdoutCell{ii}.parameter;
                    if isKey(sysDict, keyName)
                        systemInfo(end+1) = struct( ... %#ok<AGROW>
                            'parameter', sysDict(keyName), ...
                            'value', cmdoutCell{ii}.value);
                    end
                end
            catch ME
                server.RuntimeLog.logWarning( ...
                    'handlers.DiagnosticHandler.getSystemInfo', ...
                    'Falha ao coletar informacoes de sistema.', ...
                    struct('Identifier', string(ME.identifier), 'Message', string(ME.message)));
            end
        end

        %------------------------------------------------------------------
        % Coleta informacoes de discos logicos
        %------------------------------------------------------------------
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
            catch ME
                server.RuntimeLog.logWarning( ...
                    'handlers.DiagnosticHandler.getLogicalDiskInfo', ...
                    'Falha ao coletar informacoes de discos logicos.', ...
                    struct('Identifier', string(ME.identifier), 'Message', string(ME.message)));
            end
        end
    end
end
