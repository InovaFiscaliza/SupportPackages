classdef SSHHandler
    % SSHHandler - CRUD remoto minimo via sftp nativo do MATLAB.
    %
    % Esta classe centraliza o acesso remoto ao /mnt/reposfi.
    % O FileReadHandler nao deve conhecer detalhes de autenticacao,
    % conexao ou comandos remotos; ele apenas pede download/upload.
    %
    % Configuracao esperada em generalSettings.tcpServer.SSH:
    %   - Host
    %   - Port
    %   - User
    %   - Password
    %   - TimeoutSeconds (opcional)

    methods (Static)
        %------------------------------------------------------------------
        % Abre cliente sftp nativo do MATLAB
        %------------------------------------------------------------------
        function client = openClient(connectionSettings, remotePath)
            connectionSettings = server.SSHHandler.validateConnectionSettings(connectionSettings);

            host = sprintf('%s:%d', ...
                server.SSHHandler.toChar(connectionSettings.Host), ...
                double(connectionSettings.Port));

            nameValues = {'ServerSystem', 'unix'};
            if isfield(connectionSettings, 'TimeoutSeconds') && ...
                    ~isempty(connectionSettings.TimeoutSeconds)
                timeoutValue = seconds(double(connectionSettings.TimeoutSeconds));
                nameValues = [nameValues, {'ConnectionTimeout', timeoutValue, 'TransferTimeout', timeoutValue}];
            end

            client = sftp(host, ...
                server.SSHHandler.toChar(connectionSettings.User), ...
                'Password', server.SSHHandler.toChar(connectionSettings.Password), ...
                nameValues{:});

            if nargin >= 2 && ~isempty(remotePath)
                [remoteFolder, ~] = server.SSHHandler.validateRemotePath(remotePath);
                cd(client, remoteFolder);
            end

        end

        %------------------------------------------------------------------
        % Baixa um arquivo remoto para uma copia local temporaria
        %------------------------------------------------------------------
        function localPath = downloadFile(client, remotePath, localFolder)
            [~, remoteFileName] = server.SSHHandler.validateRemotePath(remotePath);

            try
                mget(client, remoteFileName, localFolder);
            catch ME
                server.SSHHandler.throwMappedRemoteError( ...
                    'server:SSHHandler:DownloadFailed', ...
                    'Falha ao baixar arquivo remoto.', ...
                    remotePath, ...
                    ME);
            end

            localPath = fullfile(localFolder, remoteFileName);

            if ~isfile(localPath)
                error('server:SSHHandler:DownloadFailed', ...
                    'Arquivo baixado nao foi localizado em %s para o remoto %s.', ...
                    localFolder, remotePath);
            end
        end

        %------------------------------------------------------------------
        % Publica um arquivo local no diretorio remoto de destino
        %------------------------------------------------------------------
        function uploadFile(client, localPath)
            if ~isfile(localPath)
                error('server:SSHHandler:LocalFileNotFound', ...
                    'Arquivo local nao encontrado: %s', localPath);
            end

            try
                mput(client, localPath);
            catch ME
                server.SSHHandler.throwMappedRemoteError( ...
                    'server:SSHHandler:UploadFailed', ...
                    'Falha ao enviar arquivo remoto.', ...
                    localPath, ...
                    ME);
            end
        end

        %------------------------------------------------------------------
        % Verifica se um caminho remoto existe
        %------------------------------------------------------------------
        function tf = exists(connectionSettings, remotePath)
            connectionSettings = server.SSHHandler.validateConnectionSettings(connectionSettings);
            [~, remoteFileName] = server.SSHHandler.validateRemotePath(remotePath);

            client = server.SSHHandler.openClient(connectionSettings, remotePath);
            cleanupClient = onCleanup(@() close(client)); %#ok<NASGU>

            try
                dir(client, remoteFileName);
                tf = true;
            catch ME
                if server.SSHHandler.isRemoteNotFound(ME)
                    tf = false;
                    return;
                end

                server.SSHHandler.throwMappedRemoteError( ...
                    'server:SSHHandler:ExistsFailed', ...
                    'Falha ao verificar existencia remota.', ...
                    remotePath, ...
                    ME);
            end
        end

        %------------------------------------------------------------------
        % Remove um arquivo remoto
        %------------------------------------------------------------------
        function deleteFile(connectionSettings, remotePath)
            connectionSettings = server.SSHHandler.validateConnectionSettings(connectionSettings);
            [~, remoteFileName] = server.SSHHandler.validateRemotePath(remotePath);

            client = server.SSHHandler.openClient(connectionSettings, remotePath);
            cleanupClient = onCleanup(@() close(client)); %#ok<NASGU>

            try
                delete(client, remoteFileName);
            catch ME
                if server.SSHHandler.isRemoteNotFound(ME)
                    return;
                end

                server.SSHHandler.throwMappedRemoteError( ...
                    'server:SSHHandler:DeleteFailed', ...
                    'Falha ao remover arquivo remoto.', ...
                    remotePath, ...
                    ME);
            end
        end

    end

    methods (Static, Access = private)
        %------------------------------------------------------------------
        % Valida a configuracao de conexao sem reescrever valores
        %------------------------------------------------------------------
        function connectionSettings = validateConnectionSettings(connectionSettings)
            connectionSettings = server.SSHHandler.extractConnectionSettings(connectionSettings);
            requiredFields = {'Host', 'Port', 'User', 'Password'};
            for ii = 1:numel(requiredFields)
                fieldName = requiredFields{ii};
                if ~isstruct(connectionSettings) || ~isfield(connectionSettings, fieldName) || ...
                        isempty(connectionSettings.(fieldName))
                    error('server:SSHHandler:InvalidConnectionSettings', ...
                        'Campo obrigatorio ausente em connectionSettings: %s', fieldName);
                end
            end
        end

        %------------------------------------------------------------------
        % Extrai tcpServer.SSH quando a chamada recebe generalSettings
        %------------------------------------------------------------------
        function connectionSettings = extractConnectionSettings(connectionSettings)
            if isstruct(connectionSettings) && isfield(connectionSettings, 'tcpServer')
                if ~isstruct(connectionSettings.tcpServer)
                    error('server:SSHHandler:MissingTCPServerSettings', ...
                        'GeneralSettings.tcpServer nao foi configurado.');
                end

                if ~isfield(connectionSettings.tcpServer, 'SSH') || ...
                        ~isstruct(connectionSettings.tcpServer.SSH)
                    error('server:SSHHandler:MissingSSHSettings', ...
                        'GeneralSettings.tcpServer.SSH nao foi configurado.');
                end

                % Permite que as chamadas recebam o generalSettings inteiro,
                % sem vazar tcpServer.SSH para o FileReadHandler.
                connectionSettings = connectionSettings.tcpServer.SSH;
            end
        end

        %------------------------------------------------------------------
        % Restringe o caminho remoto ao subtree suportado
        %------------------------------------------------------------------
        function [remoteFolder, remoteFileName] = validateRemotePath(remotePath)
            remotePath = char(string(remotePath));
            [remoteFolder, remoteName, remoteExtension] = fileparts(remotePath);
            remoteFolder = strrep(remoteFolder, '\', '/');
            remoteFileName = strcat(remoteName, remoteExtension);

            if isempty(remoteFolder)
                error('server:SSHHandler:InvalidRemotePath', ...
                    'O caminho remoto deve incluir a pasta do arquivo: %s', remotePath);
            end
        end

        %------------------------------------------------------------------
        % Heuristica para erro de caminho remoto inexistente
        %------------------------------------------------------------------
        function tf = isRemoteNotFound(ME)
            messageText = lower(server.SSHHandler.toChar(ME.message));
            tf = contains(messageText, 'not found') || ...
                contains(messageText, 'no such file') || ...
                contains(messageText, 'does not exist');
        end

        %------------------------------------------------------------------
        % Mapeia erros nativos para identificadores estaveis do projeto
        %------------------------------------------------------------------
        function throwMappedRemoteError(genericIdentifier, genericMessage, remotePath, ME)
            messageText = server.SSHHandler.toChar(ME.message);
            normalizedOutput = lower(messageText);

            if contains(normalizedOutput, 'permission denied') || ...
                    contains(normalizedOutput, 'authentication failed') || ...
                    contains(normalizedOutput, 'publickey')
                error('server:SSHHandler:AuthenticationFailed', ...
                    'Falha de autenticacao SSH para %s. Saida: %s', remotePath, messageText);
            end

            if contains(normalizedOutput, 'connection refused') || ...
                    contains(normalizedOutput, 'could not resolve hostname') || ...
                    contains(normalizedOutput, 'connection timed out') || ...
                    contains(normalizedOutput, 'no route to host') || ...
                    contains(normalizedOutput, 'network is unreachable')
                error('server:SSHHandler:ConnectionFailed', ...
                    'Falha de conexao SSH para %s. Saida: %s', remotePath, messageText);
            end

            if contains(normalizedOutput, 'timed out') || contains(normalizedOutput, 'timeout')
                error('server:SSHHandler:TransferTimeout', ...
                    'Timeout durante operacao SFTP para %s. Saida: %s', remotePath, messageText);
            end

            if server.SSHHandler.isRemoteNotFound(ME)
                error('server:SSHHandler:RemoteFileNotFound', ...
                    'Arquivo remoto nao encontrado: %s. Saida: %s', remotePath, messageText);
            end

            error(genericIdentifier, ...
                '%s Path=%s Saida=%s', genericMessage, remotePath, messageText);
        end

        %------------------------------------------------------------------
        % Conversao defensiva para char
        %------------------------------------------------------------------
        function text = toChar(value)
            if ischar(value)
                text = value;
                return;
            end

            if isstring(value)
                text = char(value);
                return;
            end

            text = char(value);
        end

    end
end
