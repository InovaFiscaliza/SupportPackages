classdef FileReadHandler
    % FileReadHandler - Executa o fluxo de leitura e exportacao de espectro.
    %
    % O fluxo parece mais complexo porque precisou tratar um problema de
    % producao: alguns arquivos .dbm invalidos faziam o processo externo
    % da CellPlan travar com popup modal. Nesse caso, um try/catch simples
    % ao redor da leitura do ZIP nao bastava, porque o controle nem
    % chegava a voltar para o MATLAB.
    %
    % A divisao atual separa duas preocupacoes:
    %   - ZIP membro a membro, para falhas recuperaveis nao invalidarem
    %     todos os arquivos do pacote.
    %   - DBM protegido com timeout, para falhas travantes nao prenderem
    %     o servico inteiro.
    %
    % A classe encapsula o mapeamento de caminho entre RF.Fusion e MATLAB,
    % a leitura via appColeta e a montagem da resposta devolvida ao cliente.
    % FileReadHandler - Processa requisições de leitura de arquivo
    %
    % Responsável por:
    %   - Mapear paths (RF.Fusion → MATLAB)
    %   - Ler dados de espectro
    %   - Exportar em diferentes formatos (.mat, metadados)
    
    methods (Static)
        %------------------------------------------------------------------
        % Processa requisição FileRead
        %------------------------------------------------------------------
        % requestData define o arquivo e se a resposta exige exportacao.
        function answer = handle(requestData, generalSettings)
            arguments
                requestData (1,1) struct
                generalSettings (1,1) struct
            end
            
            % Valida presença de filepath
            if ~isfield(requestData, 'filepath') || isempty(requestData.filepath)
                error('handlers:FileReadHandler:MissingFilePath', ...
                    'Request must contain a filepath.')
            end
            
            % Mapeia path do RF.Fusion para MATLAB
            norm_filepath = handlers.FileReadHandler.mapFilePath( ...
                requestData.filepath, generalSettings);
            
            % Verifica se precisa exportar
            needsExport = isfield(requestData, 'export') && requestData.export;
            requestTimer = tic;
            requestDetails = struct( ...
                'RequestedFilePath', string(requestData.filepath), ...
                'MappedFilePath', string(norm_filepath), ...
                'Export', logical(needsExport));
            server.RuntimeLog.logInfo( ...
                'handlers.FileReadHandler.handle', ...
                'Iniciando processamento de FileRead.', ...
                requestDetails);
            
            % Lê dados
            try
                if needsExport
                    specData = handlers.FileReadHandler.readFile(norm_filepath, 'SingleFile');
                    full_mat_path = handlers.FileReadHandler.exportMatFile(specData, norm_filepath);
                else
                    specData = handlers.FileReadHandler.readFile(norm_filepath, 'MetaData');
                    full_mat_path = norm_filepath;
                end
            
            % Prepara metadata para devolução
                answer = handlers.FileReadHandler.buildMetadataResponse( ...
                    specData, full_mat_path, generalSettings);

                requestDetails.OutputFilePath = string(full_mat_path);
                requestDetails.SpectraCount = numel(specData);
                requestDetails.DurationSeconds = toc(requestTimer);
                server.RuntimeLog.logInfo( ...
                    'handlers.FileReadHandler.handle', ...
                    sprintf('FileRead concluido em %.3f s.', requestDetails.DurationSeconds), ...
                    requestDetails);
            catch ME
                requestDetails.DurationSeconds = toc(requestTimer);
                requestDetails.Identifier = string(ME.identifier);
                requestDetails.ErrorMessage = string(ME.message);
                server.RuntimeLog.logWarning( ...
                    'handlers.FileReadHandler.handle', ...
                    'Falha durante o processamento de FileRead.', ...
                    requestDetails);
                rethrow(ME)
            end
        end
        
        %------------------------------------------------------------------
        % Mapeia path do RF.Fusion para MATLAB
        %------------------------------------------------------------------
        % Converte o path publicado ao cliente para o repositorio local.
        function norm_filepath = mapFilePath(filepath, generalSettings)
            repoPrefixMap = generalSettings.tcpServer.Repo_map;
            repoPath = generalSettings.tcpServer.Repo;
            
            norm_filepath = fullfile(repoPath, extractAfter(filepath, repoPrefixMap));
        end
        
        %------------------------------------------------------------------
        % Lê arquivo de espectro
        %------------------------------------------------------------------
        % mode controla se a leitura retorna apenas metadados ou o conteudo.
        % O fluxo abaixo privilegia estabilidade do servico: o caminho de
        % leitura passa por um roteador protegido para impedir que ZIPs ou
        % DBMs problemáticos congelem o processo principal.
        % Resumo do fluxo:
        %   - valida se o arquivo existe
        %   - roteia por extensao (.zip, .dbm ou reader legado)
        %   - copia apenas o necessario do objeto resultante
        function specData = readFile(filepath, mode)
            arguments
                filepath (1,:) char
                mode (1,:) char {mustBeMember(mode, {'MetaData', 'SpecData', 'SingleFile'})}
            end

            readTimer = tic;
            currentStage = "before_isfile";
            readDetails = struct( ...
                'FilePath', string(filepath), ...
                'Mode', string(mode), ...
                'Stage', currentStage, ...
                'FileExtension', "", ...
                'SpectraCount', [], ...
                'DurationSeconds', []);

            try
                % before_isfile:
                % Ainda nao entramos no parser. Este estado indica apenas a
                % validacao inicial do caminho recebido na requisicao.
                handlers.FileReadHandler.logReadStage( ...
                    'handlers.FileReadHandler.readFile', ...
                    'Validando existencia do arquivo.', ...
                    readDetails, readTimer);
                if ~isfile(filepath)
                    error('handlers:FileReadHandler:FileNotFound', ...
                        'File not found: %s', filepath)
                end

                [~, ~, fileExt] = fileparts(filepath);
                readDetails.FileExtension = string(lower(fileExt));

                % before_guarded_read:
                % O arquivo existe e a proxima etapa e o roteador de leitura.
                % Aqui o fluxo decide entre ZIP tolerante, DBM protegido ou
                % reader legado para formatos que ja eram estaveis.
                currentStage = "before_guarded_read";
                readDetails.Stage = currentStage;
                lastwarn('');
                handlers.FileReadHandler.logReadStage( ...
                    'handlers.FileReadHandler.readFile', ...
                    'Entrando no roteador protegido de leitura.', ...
                    readDetails, readTimer);
                specData = handlers.FileReadHandler.readPathGuarded(filepath, mode);

                % before_strip_filemap:
                % A leitura principal terminou. Agora removemos apenas o
                % FileMap temporario, que nao precisa sair deste handler.
                currentStage = "before_strip_filemap";
                readDetails.Stage = currentStage;
                readDetails.SpectraCount = numel(specData);
                handlers.FileReadHandler.logReadStage( ...
                    'handlers.FileReadHandler.readFile', ...
                    'Removendo FileMap temporario do resultado.', ...
                    readDetails, readTimer);
                specData = handlers.FileReadHandler.stripFileMap(specData);

                readDetails.Stage = "completed";
                readDetails.SpectraCount = numel(specData);
                readDetails.DurationSeconds = toc(readTimer);

                [warningMessage, warningIdentifier] = lastwarn;
                if ~isempty(warningMessage)
                    readDetails.WarningIdentifier = string(warningIdentifier);
                    readDetails.WarningMessage = string(warningMessage);
                    server.RuntimeLog.logWarning( ...
                        'handlers.FileReadHandler.readFile', ...
                        'Leitura concluida com warning.', ...
                        readDetails);
                end

                handlers.FileReadHandler.logReadStage( ...
                    'handlers.FileReadHandler.readFile', ...
                    sprintf('Leitura concluida em %.3f s.', readDetails.DurationSeconds), ...
                    readDetails, readTimer);
            catch ME
                readDetails.Stage = currentStage;
                readDetails.DurationSeconds = toc(readTimer);
                readDetails.Identifier = string(ME.identifier);
                readDetails.ErrorMessage = string(ME.message);
                server.RuntimeLog.logWarning( ...
                    'handlers.FileReadHandler.readFile', ...
                    'Falha durante a leitura do arquivo de espectro.', ...
                    readDetails);
                rethrow(ME)
            end
        end

        %------------------------------------------------------------------
        % Leitura protegida por tipo de arquivo
        %------------------------------------------------------------------
        % Mantem os formatos estaveis no fluxo antigo e isola apenas os
        % casos onde houve historico de travamento do servico.
        %
        % Se o arquivo nao e .zip nem .dbm, o comportamento e quase o
        % mesmo de antes: delega diretamente para model.SpecDataBase.read.
        function specData = readPathGuarded(filepath, mode)
            arguments
                filepath (1,:) char
                mode (1,:) char {mustBeMember(mode, {'MetaData', 'SpecData', 'SingleFile'})}
            end

            [~, ~, fileExt] = fileparts(filepath);
            switch lower(fileExt)
                case '.zip'
                    specData = handlers.FileReadHandler.readZipFileTolerant(filepath, mode);

                case '.dbm'
                    specData = model.SpecDataBase.empty;
                    specData = handlers.internal.ProtectedCellPlanDBM(specData, filepath, mode);

                otherwise
                    specData = model.SpecDataBase.empty;
                    specData = read(specData, filepath, mode);
            end
        end

        %------------------------------------------------------------------
        % Leitura tolerante de ZIP
        %------------------------------------------------------------------
        % Processa os membros do ZIP individualmente para que um unico DBM
        % ruim nao invalide toda a requisicao.
        %
        % Isso responde a pergunta "nao bastava um try/catch no ZIP?".
        % Parcialmente sim, mas so para falhas que realmente retornam
        % excecao ao MATLAB. O problema observado em producao incluia .dbm
        % que travavam o executavel externo da CellPlan, sem devolver o
        % controle. Por isso:
        %   - este loop trata erros recuperaveis por membro
        %   - o wrapper ProtectedCellPlanDBM trata travamentos do processo
        function specData = readZipFileTolerant(zipFilePath, mode)
            arguments
                zipFilePath (1,:) char
                mode (1,:) char {mustBeMember(mode, {'MetaData', 'SpecData', 'SingleFile'})}
            end

            zipTimer = tic;
            zipDetails = struct( ...
                'ZipFilePath', string(zipFilePath), ...
                'Mode', string(mode), ...
                'TotalEntries', 0, ...
                'ProcessedEntries', 0, ...
                'SkippedEntries', 0);
            handlers.FileReadHandler.logVerboseReadInfo( ...
                'handlers.FileReadHandler.readZipFileTolerant', ...
                'Iniciando leitura tolerante de arquivo ZIP.', ...
                zipDetails);

            [fileList, tempFolder] = model.fileReader.zipUtils.Zip.extractToWorkspace(zipFilePath);
            cleanupFolder = onCleanup(@() model.fileReader.zipUtils.Zip.safeCleanup(tempFolder));

            zipDetails.TotalEntries = numel(fileList);
            handlers.FileReadHandler.logVerboseReadInfo( ...
                'handlers.FileReadHandler.readZipFileTolerant', ...
                'Conteudo do ZIP extraido para workspace temporario.', ...
                zipDetails);

            specData = model.SpecDataBase.empty;
            skippedFiles = strings(numel(fileList), 1);
            skippedCount = 0;
            firstFailureIdentifier = "";
            firstFailureMessage = "";

            for kk = 1:numel(fileList)
                memberPath = fileList{kk};
                memberDetails = struct( ...
                    'ZipFilePath', string(zipFilePath), ...
                    'EntryPath', string(memberPath), ...
                    'EntryIndex', kk, ...
                    'TotalEntries', numel(fileList), ...
                    'Mode', string(mode));

                handlers.FileReadHandler.logVerboseReadInfo( ...
                    'handlers.FileReadHandler.readZipFileTolerant', ...
                    'Iniciando processamento de membro extraido do ZIP.', ...
                    memberDetails);

                % O try/catch abaixo isola erros recuperaveis por membro.
                % Ele sozinho nao resolveria o travamento historico do .dbm;
                % por isso os membros .dbm passam antes pelo wrapper
                % ProtectedCellPlanDBM via readPathGuarded.
                try
                    memberSpecData = handlers.FileReadHandler.readPathGuarded(memberPath, mode);
                    if isempty(memberSpecData)
                        zipDetails.SkippedEntries = zipDetails.SkippedEntries + 1;
                        skippedCount = skippedCount + 1;
                        skippedFiles(skippedCount) = string(memberPath);
                        memberDetails.SkipReason = "empty_or_unsupported";
                        handlers.FileReadHandler.logVerboseReadInfo( ...
                            'handlers.FileReadHandler.readZipFileTolerant', ...
                            'Membro do ZIP ignorado por nao produzir espectro.', ...
                            memberDetails);
                        continue
                    end

                    specData = handlers.FileReadHandler.appendSpecData(specData, memberSpecData);
                    zipDetails.ProcessedEntries = zipDetails.ProcessedEntries + 1;
                    memberDetails.SpectraCount = numel(memberSpecData);
                    handlers.FileReadHandler.logVerboseReadInfo( ...
                        'handlers.FileReadHandler.readZipFileTolerant', ...
                        'Membro do ZIP processado com sucesso.', ...
                        memberDetails);
                catch ME
                    zipDetails.SkippedEntries = zipDetails.SkippedEntries + 1;
                    skippedCount = skippedCount + 1;
                    skippedFiles(skippedCount) = string(memberPath);
                    % Mantemos a primeira falha para devolver um erro final
                    % mais acionavel quando o ZIP inteiro nao produzir saida.
                    if strlength(firstFailureIdentifier) == 0
                        firstFailureIdentifier = string(ME.identifier);
                        firstFailureMessage = string(ME.message);
                    end
                    memberDetails.Identifier = string(ME.identifier);
                    memberDetails.ErrorMessage = string(ME.message);
                    server.RuntimeLog.logWarning( ...
                        'handlers.FileReadHandler.readZipFileTolerant', ...
                        'Falha ao processar membro do ZIP; arquivo sera ignorado.', ...
                        memberDetails);
                end
            end

            zipDetails.DurationSeconds = toc(zipTimer);
            zipDetails.SpectraCount = numel(specData);
            if skippedCount > 0
                zipDetails.SkippedFiles = skippedFiles(1:skippedCount);
            end

            if isempty(specData)
                server.RuntimeLog.logWarning( ...
                    'handlers.FileReadHandler.readZipFileTolerant', ...
                    'ZIP concluido sem nenhum arquivo legivel.', ...
                    zipDetails);
                if strlength(firstFailureIdentifier) > 0
                    error('handlers:FileReadHandler:NoReadableFilesInZip', ...
                        ['Nenhum arquivo suportado e legivel foi encontrado no ZIP: %s\n', ...
                         'Primeira falha identificada: [%s] %s'], ...
                        zipFilePath, firstFailureIdentifier, firstFailureMessage);
                end
                error('handlers:FileReadHandler:NoReadableFilesInZip', ...
                    'Nenhum arquivo suportado e legivel foi encontrado no ZIP: %s', zipFilePath);
            end

            handlers.FileReadHandler.logVerboseReadInfo( ...
                'handlers.FileReadHandler.readZipFileTolerant', ...
                sprintf('Leitura tolerante do ZIP concluida em %.3f s.', zipDetails.DurationSeconds), ...
                zipDetails);
        end

        %------------------------------------------------------------------
        % Agrega lotes de specData mantendo semantica do reader original
        %------------------------------------------------------------------
        % Preserva o comportamento anterior de concatenar os objetos lidos
        % sem alterar a estrutura esperada por quem consome FileRead.
        function specData = appendSpecData(specData, newSpecData)
            arguments
                specData
                newSpecData
            end

            if isempty(newSpecData)
                return
            end

            if isempty(specData)
                specData = newSpecData;
            else
                specData = [specData newSpecData];
            end
        end

        %------------------------------------------------------------------
        % Remove apenas campos temporarios apos a leitura
        %------------------------------------------------------------------
        % O FileMap serve para o parser montar os blocos de leitura, mas nao
        % precisa ser mantido no retorno final. Fazemos isso em lugar para
        % evitar a copia profunda e custosa de todo o objeto SpecData.
        function specData = stripFileMap(specData)
            for ii = 1:numel(specData)
                specData(ii).FileMap = [];
            end
        end

        %------------------------------------------------------------------
        % Log informativo apenas quando verbose estiver habilitado
        %------------------------------------------------------------------
        function logVerboseReadInfo(source, message, details)
            if nargin < 3
                details = [];
            end

            if handlers.FileReadHandler.shouldLogVerboseReadFlow()
                server.RuntimeLog.logInfo(source, message, details);
            end
        end

        %------------------------------------------------------------------
        % Registra um Stage apenas quando o verbose fino estiver ligado
        %------------------------------------------------------------------
        function logReadStage(source, message, details, readTimer)
            if nargin < 4
                readTimer = [];
            end

            if ~handlers.FileReadHandler.shouldLogVerboseReadFlow()
                return
            end

            if ~isempty(readTimer)
                details.ElapsedSeconds = toc(readTimer);
            end

            server.RuntimeLog.logInfo(source, message, details);
        end

        %------------------------------------------------------------------
        % Flag de verbose para diagnostico fino do pipeline de leitura
        %------------------------------------------------------------------
        % O default e "off" para reduzir overhead no caminho feliz. Quando
        % precisar rastrear uma leitura dificil, habilite a variavel de
        % ambiente REPOSFI_VERBOSE_READ_LOGS.
        function enabled = shouldLogVerboseReadFlow()
            persistent cachedEnabled isInitialized

            if isempty(isInitialized)
                envValue = lower(strtrim(char(string(getenv('REPOSFI_VERBOSE_READ_LOGS')))));
                cachedEnabled = ismember(envValue, {'1', 'true', 'on', 'yes'});
                isInitialized = true;
            end

            enabled = cachedEnabled;
        end
        
        %------------------------------------------------------------------
        % Exporta dados para arquivo .mat
        %------------------------------------------------------------------
        % Persiste o objeto lido em um .mat ao lado do arquivo original.
        function full_mat_path = exportMatFile(specData, original_filepath)
            if ismissing(specData)
                error('handlers:FileReadHandler:InvalidSpecData', ...
                    'SpecData is invalid or missing.')
            end
            
            exportTimer = tic;
            exportDetails = struct( ...
                'SourceFilePath', string(original_filepath), ...
                'TargetMatPath', "", ...
                'SpectraCount', numel(specData));
            exportDetails.Stage = "before_struct_conversion";
            exportDetails.ElapsedSeconds = toc(exportTimer);
            server.RuntimeLog.logInfo( ...
                'handlers.FileReadHandler.exportMatFile', ...
                'Iniciando conversao do SpecData para struct.', ...
                exportDetails);

            out = arrayfun(@(x) struct(x), specData);

            exportDetails.Stage = "after_struct_conversion";
            exportDetails.ElapsedSeconds = toc(exportTimer);
            server.RuntimeLog.logInfo( ...
                'handlers.FileReadHandler.exportMatFile', ...
                'Conversao do SpecData para struct concluida.', ...
                exportDetails);
            
            [filepath, base_name, ~] = fileparts(original_filepath);
            mat_filename = base_name + ".mat";
            full_mat_path = fullfile(filepath, mat_filename);
            exportDetails.TargetMatPath = string(full_mat_path);
            server.RuntimeLog.logInfo( ...
                'handlers.FileReadHandler.exportMatFile', ...
                'Iniciando exportacao do arquivo MAT.', ...
                exportDetails);
            
            try
                % Salva arquivo
                lastwarn('');
                exportDetails.Stage = "before_save";
                exportDetails.ElapsedSeconds = toc(exportTimer);
                server.RuntimeLog.logInfo( ...
                    'handlers.FileReadHandler.exportMatFile', ...
                    'Iniciando save do arquivo MAT.', ...
                    exportDetails);

                save(full_mat_path, "out");
                fprintf("[FileReadHandler] Arquivo salvo: %s\n", full_mat_path);

                exportDetails.Stage = "after_save";
                exportDetails.ElapsedSeconds = toc(exportTimer);
                server.RuntimeLog.logInfo( ...
                    'handlers.FileReadHandler.exportMatFile', ...
                    'Save do arquivo MAT concluido.', ...
                    exportDetails);

                exportDetails.DurationSeconds = toc(exportTimer);
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
                exportDetails.DurationSeconds = toc(exportTimer);
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
        % Constrói resposta com metadados
        %------------------------------------------------------------------
        % Monta uma resposta leve, removendo dados pesados dos espectros.
        function answer = buildMetadataResponse(specData, full_mat_path, generalSettings)
            if isempty(specData)
                error('handlers:FileReadHandler:EmptySpecData', ...
                    'SpecData is empty.')
            end
            
            [filepath, filename, ext] = fileparts(full_mat_path);
            
            % Mapeia path de volta para RF.Fusion
            repoPrefixMap = generalSettings.tcpServer.Repo_map;
            repoPath = generalSettings.tcpServer.Repo;
            rffusion_filepath = fullfile(repoPrefixMap, extractAfter(filepath, repoPath));
            rffusion_filepath = strrep(rffusion_filepath, "\", "/");
            
            % Copia spectra e remove dados pesados
            spectra = specData;
            for ii = 1:numel(spectra)
                if isprop(spectra(ii), 'Data')
                    spectra(ii).Data = [];
                    spectra(ii).RelatedFiles.GPS = [];
                end
            end
            
            % Estrutura de retorno
            answer = struct();
            answer.General = struct( ...
                'FilePath', rffusion_filepath, ...
                'FileName', strcat(filename, ext), ...
                'Extension', ext ...
                );
            answer.Spectra = spectra;
        end
    end
end
