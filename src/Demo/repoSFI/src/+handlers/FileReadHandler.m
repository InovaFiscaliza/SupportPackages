classdef FileReadHandler
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
            
            % Lê dados
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
        end
        
        %------------------------------------------------------------------
        % Mapeia path do RF.Fusion para MATLAB
        %------------------------------------------------------------------
        function norm_filepath = mapFilePath(filepath, generalSettings)
            repoPrefixMap = generalSettings.tcpServer.Repo_map;
            repoPath = generalSettings.tcpServer.Repo;
            
            norm_filepath = fullfile(repoPath, extractAfter(filepath, repoPrefixMap));
        end
        
        %------------------------------------------------------------------
        % Lê arquivo de espectro
        %------------------------------------------------------------------
        function specData = readFile(filepath, mode)
            arguments
                filepath (1,:) char
                mode (1,:) char {mustBeMember(mode, {'MetaData', 'SpecData', 'SingleFile'})}
            end
            
            if ~isfile(filepath)
                error('handlers:FileReadHandler:FileNotFound', ...
                    sprintf('File not found: %s', filepath))
            end
            
            specData = model.SpecDataBase.empty;
            specData = read(specData, filepath, mode);
            specData = copy(specData, {'FileMap'});
            
            % Remove GPS dados se presentes
            for ii = 1:numel(specData)
                for jj = 1:height(specData(ii).RelatedFiles)
                    specData(ii).RelatedFiles.GPS{jj} = [];
                end
            end
        end
        
        %------------------------------------------------------------------
        % Exporta dados para arquivo .mat
        %------------------------------------------------------------------
        function full_mat_path = exportMatFile(specData, original_filepath)
            if ismissing(specData)
                error('handlers:FileReadHandler:InvalidSpecData', ...
                    'SpecData is invalid or missing.')
            end
            
            out = arrayfun(@(x) struct(x), specData);
            
            [filepath, base_name, ~] = fileparts(original_filepath);
            mat_filename = base_name + ".mat";
            full_mat_path = fullfile(filepath, mat_filename);
            
            % Salva arquivo
            save(full_mat_path, "out");
            fprintf("[FileReadHandler] Arquivo salvo: %s\n", full_mat_path);
        end
        
        %------------------------------------------------------------------
        % Constrói resposta com metadados
        %------------------------------------------------------------------
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
