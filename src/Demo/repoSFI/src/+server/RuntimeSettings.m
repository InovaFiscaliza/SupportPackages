classdef RuntimeSettings
    % RuntimeSettings - Centraliza defaults e leitura de runtime.
    %
    % O repoSFI hoje tem parametros operacionais usados por main,
    % tcpServerLib e FileReadHandler. Esta classe concentra:
    %   - defaults seguros
    %   - leitura do bloco "runtime" do GeneralSettings.json
    %   - compatibilidade com override legado de verbose por variavel
    %     de ambiente, para diagnostico em producao

    methods (Static)
        %------------------------------------------------------------------
        % Defaults do runtime
        %------------------------------------------------------------------
        function runtimeSettings = defaults()
            runtimeSettings = struct( ...
                'VerboseReadLogs', false, ...
                'LogMaintenanceIntervalSeconds', 30, ...
                'HeartbeatIntervalSeconds', 60, ...
                'WatchdogIntervalSeconds', 15, ...
                'ServerRecycleIntervalSeconds', 12 * 60 * 60, ...
                'MaxConsecutiveWatchdogRecoveriesBeforeRecycle', 3, ...
                'TcpReconnectTimerPeriodSeconds', 300);
        end

        %------------------------------------------------------------------
        % Normaliza GeneralSettings e injeta defaults de runtime
        %------------------------------------------------------------------
        function generalSettings = normalizeGeneralSettings(generalSettings)
            runtimeDefaults = server.RuntimeSettings.defaults();
            runtimeSettings = runtimeDefaults;

            if isstruct(generalSettings) && isfield(generalSettings, 'runtime') && isstruct(generalSettings.runtime)
                configuredRuntime = generalSettings.runtime;
            else
                configuredRuntime = struct();
            end

            runtimeSettings.VerboseReadLogs = ...
                server.RuntimeSettings.sanitizeLogical( ...
                    configuredRuntime, 'VerboseReadLogs', runtimeDefaults.VerboseReadLogs);
            runtimeSettings.LogMaintenanceIntervalSeconds = ...
                server.RuntimeSettings.sanitizePositiveNumber( ...
                    configuredRuntime, 'LogMaintenanceIntervalSeconds', runtimeDefaults.LogMaintenanceIntervalSeconds);
            runtimeSettings.HeartbeatIntervalSeconds = ...
                server.RuntimeSettings.sanitizePositiveNumber( ...
                    configuredRuntime, 'HeartbeatIntervalSeconds', runtimeDefaults.HeartbeatIntervalSeconds);
            runtimeSettings.WatchdogIntervalSeconds = ...
                server.RuntimeSettings.sanitizePositiveNumber( ...
                    configuredRuntime, 'WatchdogIntervalSeconds', runtimeDefaults.WatchdogIntervalSeconds);
            runtimeSettings.ServerRecycleIntervalSeconds = ...
                server.RuntimeSettings.sanitizeNonNegativeNumber( ...
                    configuredRuntime, 'ServerRecycleIntervalSeconds', runtimeDefaults.ServerRecycleIntervalSeconds);
            runtimeSettings.MaxConsecutiveWatchdogRecoveriesBeforeRecycle = ...
                server.RuntimeSettings.sanitizePositiveInteger( ...
                    configuredRuntime, 'MaxConsecutiveWatchdogRecoveriesBeforeRecycle', runtimeDefaults.MaxConsecutiveWatchdogRecoveriesBeforeRecycle);
            runtimeSettings.TcpReconnectTimerPeriodSeconds = ...
                server.RuntimeSettings.sanitizePositiveNumber( ...
                    configuredRuntime, 'TcpReconnectTimerPeriodSeconds', runtimeDefaults.TcpReconnectTimerPeriodSeconds);

            % Mantemos compatibilidade com os overrides legados de ambiente
            % apenas para as chaves que ja existiam antes.
            runtimeSettings = server.RuntimeSettings.applyLegacyEnvironmentOverrides(runtimeSettings);
            generalSettings.runtime = runtimeSettings;
        end

        %------------------------------------------------------------------
        % Retorna runtime normalizado a partir do GeneralSettings
        %------------------------------------------------------------------
        function runtimeSettings = getRuntimeSettings(generalSettings)
            if nargin < 1 || isempty(generalSettings)
                runtimeSettings = server.RuntimeSettings.loadRuntimeSettings();
                return;
            end

            generalSettings = server.RuntimeSettings.normalizeGeneralSettings(generalSettings);
            runtimeSettings = generalSettings.runtime;
        end

        %------------------------------------------------------------------
        % Carrega runtime do GeneralSettings corrente
        %------------------------------------------------------------------
        function runtimeSettings = loadRuntimeSettings()
            persistent cachedRuntimeSettings isInitialized

            if isempty(isInitialized)
                appName = class.Constants.appName;
                rootFolder = appEngine.util.RootFolder(appName, server.RuntimeSettings.getProjectRootFolder());
                [generalSettings, ~] = appEngine.util.generalSettingsLoad(appName, rootFolder);
                generalSettings = server.RuntimeSettings.normalizeGeneralSettings(generalSettings);
                cachedRuntimeSettings = generalSettings.runtime;
                isInitialized = true;
            end

            runtimeSettings = cachedRuntimeSettings;
        end

    end

    methods (Static, Access = private)
        %------------------------------------------------------------------
        % Aplica overrides legados de ambiente
        %------------------------------------------------------------------
        function runtimeSettings = applyLegacyEnvironmentOverrides(runtimeSettings)
            verboseEnv = lower(strtrim(char(string(getenv('REPOSFI_VERBOSE_READ_LOGS')))));
            if ~isempty(verboseEnv)
                runtimeSettings.VerboseReadLogs = ismember(verboseEnv, {'1', 'true', 'on', 'yes'});
            end
        end

        %------------------------------------------------------------------
        % Pasta raiz do projeto repoSFI
        %------------------------------------------------------------------
        function projectRoot = getProjectRootFolder()
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
        end

        %------------------------------------------------------------------
        % Sanitizers numericos
        %------------------------------------------------------------------
        function numericValue = sanitizePositiveNumber(configStruct, fieldName, defaultValue)
            numericValue = server.RuntimeSettings.sanitizeNumber( ...
                configStruct, fieldName, defaultValue, false, true);
        end

        function numericValue = sanitizeNonNegativeNumber(configStruct, fieldName, defaultValue)
            numericValue = server.RuntimeSettings.sanitizeNumber( ...
                configStruct, fieldName, defaultValue, true, false);
        end

        function numericValue = sanitizePositiveInteger(configStruct, fieldName, defaultValue)
            numericValue = server.RuntimeSettings.sanitizePositiveNumber(configStruct, fieldName, defaultValue);
            numericValue = max(1, round(numericValue));
        end

        function numericValue = sanitizeNumber(configStruct, fieldName, defaultValue, allowZero, mustBePositive)
            numericValue = defaultValue;

            if ~isstruct(configStruct) || ~isfield(configStruct, fieldName)
                return;
            end

            rawValue = configStruct.(fieldName);
            if isstring(rawValue) || ischar(rawValue)
                candidateValue = str2double(strtrim(char(string(rawValue))));
            elseif isnumeric(rawValue) || islogical(rawValue)
                candidateValue = double(rawValue);
            else
                return;
            end

            if ~isscalar(candidateValue) || ~isfinite(candidateValue)
                return;
            end

            if mustBePositive && candidateValue <= 0
                return;
            end

            if allowZero && candidateValue < 0
                return;
            end

            numericValue = candidateValue;
        end

        %------------------------------------------------------------------
        % Sanitizer logico
        %------------------------------------------------------------------
        function logicalValue = sanitizeLogical(configStruct, fieldName, defaultValue)
            logicalValue = defaultValue;

            if ~isstruct(configStruct) || ~isfield(configStruct, fieldName)
                return;
            end

            rawValue = configStruct.(fieldName);
            if islogical(rawValue) || isnumeric(rawValue)
                logicalValue = logical(rawValue);
                return;
            end

            rawText = lower(strtrim(char(string(rawValue))));
            if ismember(rawText, {'1', 'true', 'on', 'yes'})
                logicalValue = true;
            elseif ismember(rawText, {'0', 'false', 'off', 'no'})
                logicalValue = false;
            end
        end
    end
end
