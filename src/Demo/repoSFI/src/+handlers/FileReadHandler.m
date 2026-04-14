classdef FileReadHandler
    % FileReadHandler - Executa o fluxo de leitura e exportacao de espectro.
    %
    % O fluxo foi simplificado para ficar o mais proximo possivel do
    % comportamento natural de model.SpecDataBase.read.
    %
    % Hoje, a protecao contra travamento do reader da CellPlan ja fica em
    % model.fileReader.CellPlanDBM. Por isso o repoSFI nao precisa mais
    % manter um reader paralelo para .dbm.
    %
    % O repoSFI agora fica responsavel apenas pela cola do servico:
    % mapeamento de caminho, exportacao opcional, montagem da resposta e
    % observabilidade do fluxo.
    %
    % A classe encapsula o mapeamento de caminho entre RF.Fusion e MATLAB,
    % a leitura via appColeta e a montagem da resposta devolvida ao cliente.
    % FileReadHandler - Processa requisicoes de leitura de arquivo
    %
    % Responsavel por:
    %   - Mapear paths (RF.Fusion -> MATLAB)
    %   - Ler dados de espectro
    %   - Exportar em diferentes formatos (.mat, metadados)
    
    methods (Static)
        %------------------------------------------------------------------
        % Processa requisicao FileRead
        %------------------------------------------------------------------
        % requestData define o arquivo e se a resposta exige exportacao.
        function answer = handle(requestData, generalSettings)
            arguments
                requestData (1,1) struct
                generalSettings (1,1) struct
            end
            
            % Valida presenca de filepath
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
            
            % Le dados
            try
                if needsExport
                    specData = handlers.FileReadHandler.readFile(norm_filepath, 'SingleFile');
                    full_mat_path = handlers.FileReadHandler.exportMatFile(specData, norm_filepath);
                else
                    specData = handlers.FileReadHandler.readFile(norm_filepath, 'MetaData');
                    full_mat_path = norm_filepath;
                end
            
            % Prepara metadata para devolucao
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
        % Le arquivo de espectro
        %------------------------------------------------------------------
        % mode controla se a leitura retorna apenas metadados ou o conteudo.
        % O caminho de leitura delega diretamente para model.SpecDataBase.read.
        % As protecoes de ZIP e do reader da CellPlan ficam concentradas no
        % proprio ecossistema Spectrum.
        % Resumo do fluxo:
        %   - valida se o arquivo existe
        %   - delega a leitura para a Spectrum
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

                % before_read:
                % O arquivo existe e a proxima etapa e a leitura em si.
                % A partir daqui a leitura segue para a Spectrum, que hoje
                % concentra tanto a tolerancia de ZIP quanto a protecao do
                % reader da CellPlan.
                currentStage = "before_read";
                readDetails.Stage = currentStage;
                lastwarn('');
                handlers.FileReadHandler.logReadStage( ...
                    'handlers.FileReadHandler.readFile', ...
                    'Iniciando leitura do arquivo.', ...
                    readDetails, readTimer);
                specData = handlers.FileReadHandler.readPath(filepath, mode);

                % after_read_non_empty_check:
                % Alguns readers podem terminar sem excecao, mas tambem sem
                % produzir qualquer espectro. Esse caso precisa falhar aqui,
                % antes de exportar MAT vazio ou montar resposta invalida.
                currentStage = "after_read_non_empty_check";
                readDetails.Stage = currentStage;
                handlers.FileReadHandler.assertNonEmptySpecData(specData, filepath, mode);

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
        % Leitura por caminho
        %------------------------------------------------------------------
        % O comportamento padrao do repoSFI agora volta a ser delegar a
        % leitura diretamente para model.SpecDataBase.read. A tolerancia
        % de ZIP e a protecao do reader da CellPlan passaram a viver no
        % proprio ecossistema Spectrum.
        function specData = readPath(filepath, mode)
            arguments
                filepath (1,:) char
                mode (1,:) char {mustBeMember(mode, {'MetaData', 'SpecData', 'SingleFile'})}
            end

            specData = model.SpecDataBase.empty;
            specData = read(specData, filepath, mode);
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
        % Garante que a leitura produziu pelo menos um espectro
        %------------------------------------------------------------------
        % Esse guard evita um falso sucesso em que o parser termina sem
        % erro, mas retorna objeto vazio. Sem isso, o fluxo poderia salvar
        % um MAT vazio e so falhar mais tarde ao montar a resposta.
        function assertNonEmptySpecData(specData, filepath, mode)
            if isempty(specData)
                error('handlers:FileReadHandler:EmptySpecData', ...
                    ['Nenhum espectro foi lido do arquivo: %s (%s). ', ...
                     'A leitura terminou sem erro explicito, mas retornou resultado vazio.'], ...
                    filepath, mode)
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
        % O default agora vem do bloco runtime do GeneralSettings, com
        % compatibilidade para override legado por variavel de ambiente.
        function enabled = shouldLogVerboseReadFlow()
            runtimeSettings = server.RuntimeSettings.loadRuntimeSettings();
            enabled = runtimeSettings.VerboseReadLogs;
        end
        
        %------------------------------------------------------------------
        % Exporta dados para arquivo .mat
        %------------------------------------------------------------------
        % Persiste o objeto lido em um .mat ao lado do arquivo original.
        function full_mat_path = exportMatFile(specData, original_filepath)
            % O save de um MAT vazio mascara falhas reais do parser e
            % empurra o erro para etapas posteriores. Validamos isso logo
            % na entrada para manter o fluxo consistente.
            if isempty(specData)
                error('handlers:FileReadHandler:EmptySpecData', ...
                    'SpecData is empty and cannot be exported.')
            end

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
        % Constroi resposta com metadados
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

