classdef (Abstract) Zip

    methods (Static)
        %-----------------------------------------------------------------%
        function [fileList, tempFolder] = extractToWorkspace(zipFilePath)
            % Extrai o conteúdo do arquivo .zip para um diretório
            % temporário.
            %
            % Após a extração, todos os arquivos são movidos para a
            % raiz do diretório temporário (flatten), eliminando
            % subpastas e reduzindo o comprimento dos caminhos.

            if ~isfile(zipFilePath)
                error('Zip:FileNotFound','ZIP file not found.');
            end

            tempFolder = tempname;
            mkdir(tempFolder);

            % Extração normal
            unzip(zipFilePath, tempFolder);

            % Localiza todos os arquivos extraídos
            fileStruct = dir(fullfile(tempFolder,'**','*'));
            fileStruct = fileStruct(~[fileStruct.isdir]);

            % Move todos os arquivos para a raiz do tempFolder
            for k = 1:numel(fileStruct)
                oldPath = fullfile(fileStruct(k).folder, fileStruct(k).name);
                newPath = fullfile(tempFolder, fileStruct(k).name);

                % Se já existir arquivo com mesmo nome, adiciona sufixo
                if exist(newPath,'file')
                    [~,name,ext] = fileparts(fileStruct(k).name);
                    newPath = fullfile(tempFolder, ...
                        sprintf('%s_%d%s', name, k, ext));
                end

                if ~strcmp(oldPath,newPath)
                    movefile(oldPath,newPath);
                end
            end

            % Remove subpastas vazias
            subFolders = dir(tempFolder);
            subFolders = subFolders([subFolders.isdir]);
            subFolders = subFolders(~ismember({subFolders.name},{'.','..'}));

            for k = 1:numel(subFolders)
                rmdir(fullfile(tempFolder,subFolders(k).name),'s');
            end

            % Lista final apenas na raiz
            fileStruct = dir(fullfile(tempFolder,'*'));
            fileStruct = fileStruct(~[fileStruct.isdir]);

            fileList = fullfile({fileStruct.folder},{fileStruct.name});
        end

        %-----------------------------------------------------------------%
        function safeCleanup(folderPath)
            try
                if isfolder(folderPath)
                    rmdir(folderPath,'s');
                end
            catch
            end
        end
    end

end