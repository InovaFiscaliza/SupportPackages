classdef FileReadHandler
    % FileReadHandler - Executa leitura/exportacao com origem remota via SSH.
    %
    % Fluxo principal:
    %   caminho remoto -> copia temporaria local -> leitura local ->
    %   exportacao local opcional -> publicacao remota opcional -> resposta

    methods (Static)
        %------------------------------------------------------------------
        % Processa requisicao FileRead
        %------------------------------------------------------------------
        function answer = handle(requestData, generalSettings)
            arguments
                requestData (1,1) struct
                generalSettings (1,1) struct
            end

            timerId = tic;
            remoteFilePath = handlers.FileReadHandler.getRequestedRemoteFilePath(requestData);
            exportRequested = isfield(requestData, 'export') && logical(requestData.export);
            tempFolder = handlers.FileReadHandler.createRequestTempFolder(handlers.FileReadHandler.getTempRoot());
            cleanupTempFolder = onCleanup(@() handlers.FileReadHandler.tryDeleteFolder(tempFolder)); %#ok<NASGU>

            client = [];
            localTempPath = '';
            localOutputPath = '';
            answerPath = remoteFilePath;

            try
                client = server.SSHHandler.openClient(generalSettings,remoteFilePath);
                cleanupClient = onCleanup(@() close(client)); %#ok<NASGU>
                localTempPath = server.SSHHandler.downloadFile(client, remoteFilePath, tempFolder);
                if exportRequested
                    specData = handlers.FileReadHandler.readFile(localTempPath, 'SingleFile');
                    localOutputPath = handlers.FileReadHandler.exportMatFile(specData, localTempPath);
                    answerPath = handlers.FileReadHandler.buildRemoteMatPath(remoteFilePath);
                    server.SSHHandler.uploadFile(client, localOutputPath);
                else
                    specData = handlers.FileReadHandler.readFile(localTempPath, 'MetaData');
                    localOutputPath = localTempPath;
                end

                answer = handlers.FileReadHandler.buildMetadataResponse(specData, answerPath);
            catch ME
                server.RuntimeLog.logWarning( ...
                    'handlers.FileReadHandler.handle', ...
                        'Falha durante o processamento de FileRead.', ...
                        struct( ...
                            'RequestedFilePath', string(requestData.filepath), ...
                            'RemoteFilePath', string(remoteFilePath), ...
                            'LocalTempPath', string(localTempPath), ...
                            'LocalOutputPath', string(localOutputPath), ...
                            'RemoteOutputPath', string(answerPath), ...
                            'Export', exportRequested, ...
                        'DurationSeconds', toc(timerId), ...
                        'Identifier', string(ME.identifier), ...
                        'ErrorMessage', string(ME.message)));
                rethrow(ME)
            end
        end

        %------------------------------------------------------------------
        % Le arquivo de espectro
        %------------------------------------------------------------------
        function specData = readFile(filepath, mode)
            arguments
                filepath (1,:) char
                mode (1,:) char {mustBeMember(mode, {'MetaData', 'SpecData', 'SingleFile'})}
            end

            timerId = tic;

            try
                if ~isfile(filepath)
                    error('handlers:FileReadHandler:FileNotFound', ...
                        'File not found: %s', filepath)
                end

                lastwarn('');
                specData = model.SpecDataBase.empty;
                specData = read(specData, filepath, mode);

                if isempty(specData)
                    error('handlers:FileReadHandler:EmptySpecData', ...
                        ['Nenhum espectro foi lido do arquivo: %s (%s). ', ...
                         'A leitura terminou sem erro explicito, mas retornou resultado vazio.'], ...
                        filepath, mode)
                end

                for ii = 1:numel(specData)
                    specData(ii).FileMap = [];
                end

                [warningMessage, warningIdentifier] = lastwarn;
                if ~isempty(warningMessage)
                    server.RuntimeLog.logWarning( ...
                        'handlers.FileReadHandler.readFile', ...
                        'Leitura concluida com warning.', ...
                        struct( ...
                            'FilePath', string(filepath), ...
                            'Mode', string(mode), ...
                            'SpectraCount', numel(specData), ...
                            'DurationSeconds', toc(timerId), ...
                            'WarningIdentifier', string(warningIdentifier), ...
                            'WarningMessage', string(warningMessage)));
                end
            catch ME
                server.RuntimeLog.logWarning( ...
                    'handlers.FileReadHandler.readFile', ...
                    'Falha durante a leitura do arquivo de espectro.', ...
                    struct( ...
                        'FilePath', string(filepath), ...
                        'Mode', string(mode), ...
                        'DurationSeconds', toc(timerId), ...
                        'Identifier', string(ME.identifier), ...
                        'ErrorMessage', string(ME.message)));
                rethrow(ME)
            end
        end

        %------------------------------------------------------------------
        % Exporta dados para arquivo .mat
        %------------------------------------------------------------------
        function full_mat_path = exportMatFile(specData, original_filepath)
            if isempty(specData)
                error('handlers:FileReadHandler:EmptySpecData', ...
                    'SpecData is empty and cannot be exported.')
            end

            timerId = tic;
            out = arrayfun(@(x) struct(x), specData);

            [folderPath, baseName, ~] = fileparts(original_filepath);
            full_mat_path = fullfile(folderPath, baseName + ".mat");
            exportDetails = struct( ...
                'SourceFilePath', string(original_filepath), ...
                'TargetMatPath', string(full_mat_path), ...
                'SpectraCount', numel(specData));

            try
                lastwarn('');
                save(full_mat_path, "out");
                exportDetails.DurationSeconds = toc(timerId);

                [warningMessage, warningIdentifier] = lastwarn;
                if ~isempty(warningMessage)
                    exportDetails.WarningIdentifier = string(warningIdentifier);
                    exportDetails.WarningMessage = string(warningMessage);
                    server.RuntimeLog.logWarning( ...
                        'handlers.FileReadHandler.exportMatFile', ...
                        'Exportacao MAT concluida com warning.', ...
                        exportDetails);
                end

                server.RuntimeLog.logInfo( ...
                    'handlers.FileReadHandler.exportMatFile', ...
                    sprintf('Exportacao MAT concluida em %.3f s.', exportDetails.DurationSeconds), ...
                    exportDetails);
            catch ME
                exportDetails.DurationSeconds = toc(timerId);
                exportDetails.Identifier = string(ME.identifier);
                exportDetails.ErrorMessage = string(ME.message);
                server.RuntimeLog.logWarning( ...
                    'handlers.FileReadHandler.exportMatFile', ...
                    'Falha durante a exportacao do arquivo MAT.', ...
                    exportDetails);
                rethrow(ME)
            end
        end

        %------------------------------------------------------------------
        % Constroi resposta com metadados
        %------------------------------------------------------------------
        function answer = buildMetadataResponse(specData, remoteOutputPath)
            if isempty(specData)
                error('handlers:FileReadHandler:EmptySpecData', ...
                    'SpecData is empty.')
            end

            [folderPath, fileName, extension] = fileparts(remoteOutputPath);

            spectra = specData;
            for ii = 1:numel(spectra)
                if isprop(spectra(ii), 'Data')
                    spectra(ii).Data = [];
                    spectra(ii).RelatedFiles.GPS = [];
                end
            end

            answer = struct( ...
                'General', struct( ...
                    'FilePath', strrep(folderPath, '\', '/'), ...
                    'FileName', strcat(fileName, extension), ...
                    'Extension', extension ...
                ), ...
                'Spectra', spectra);
        end
    end

    methods (Static, Access = private)
        %------------------------------------------------------------------
        % Obtem caminho remoto pedido na requisicao
        %------------------------------------------------------------------
        function remoteFilePath = getRequestedRemoteFilePath(requestData)
            if ~isfield(requestData, 'filepath') || isempty(requestData.filepath)
                error('handlers:FileReadHandler:MissingFilePath', ...
                    'Request must contain a filepath.')
            end

            remoteFilePath = char(requestData.filepath);
        end

        % Raiz temporaria dedicada do repoSFI
        %------------------------------------------------------------------
        function tempRoot = getTempRoot()
            tempRoot = fullfile(tempdir, 'repoSFI');
            if ~isfolder(tempRoot)
                mkdir(tempRoot);
            end
        end

        %------------------------------------------------------------------
        % Cria pasta temporaria por requisicao
        %------------------------------------------------------------------
        function requestTempFolder = createRequestTempFolder(tempRoot)
            requestTempFolder = tempname(tempRoot);
            mkdir(requestTempFolder);
        end

        % Caminho remoto de saida para .mat
        %------------------------------------------------------------------
        function remoteMatPath = buildRemoteMatPath(remoteFilePath)
            [folderPath, fileName, ~] = fileparts(remoteFilePath);
            remoteMatPath = [strrep(folderPath, '\', '/') '/' fileName '.mat'];
        end

        %------------------------------------------------------------------
        % Remove pasta temporaria sem propagar erro
        %------------------------------------------------------------------
        function tryDeleteFolder(folderPath)
            if isempty(folderPath) || ~isfolder(folderPath)
                return;
            end

            try
                rmdir(folderPath, 's');
            catch
            end
        end
    end
end
