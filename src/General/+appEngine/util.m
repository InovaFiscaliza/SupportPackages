classdef (Abstract) util
    
    methods (Static = true)
        %-----------------------------------------------------------------%
        function disableWarnings()
            warning('off', 'MATLAB:ui:javaframe:PropertyToBeRemoved')
            warning('off', 'MATLAB:subscripting:noSubscriptsSpecified')
            warning('off', 'MATLAB:structOnObject')
            warning('off', 'MATLAB:class:DestructorError')
            warning('off', 'MATLAB:modes:mode:InvalidPropertySet')
            warning('off', 'MATLAB:table:RowsAddedExistingVars')
            warning('off', 'MATLAB:table:ModifiedVarnames')
            warning('off', 'MATLAB:colon:operandsNotRealScalar')
            warning('off', 'MATLAB:opengl:unableToSelectHWGL')
        end

        %-----------------------------------------------------------------%
        function executionMode = ExecutionMode(hFigure)
            % No MATLAB, os containeres das versões desktop e webapp de 
            % um app são os arquivos "cefComponentContainer.html" e 
            % "webAppsComponentContainer.html", respectivamente.

            % >> struct(struct(struct(hFigure).Controller).PlatformHost).ReleaseHTMLFile
            % 'cefComponentContainer.html'     (MATLAB R2024a e MATLAB Runtime)
            % 'webAppsComponentContainer.html' (MATLAB R2025a e MATLAB WebServer)
            
            if ~isdeployed()
                executionMode = 'MATLABEnvironment';
            else
                htmlContainer = struct(struct(struct(hFigure).Controller).PlatformHost).ReleaseHTMLFile;
                if contains(htmlContainer, 'webapp', 'IgnoreCase', true)
                    executionMode = 'webApp';
                else
                    executionMode = 'desktopStandaloneApp';
                end
            end
        end

        %-----------------------------------------------------------------%
        function rootFolder = RootFolder(appName, MFilePath)
            rootFolder = MFilePath;

            if isdeployed
                [status, executionFolder] = appEngine.util.OperationSystem('desktopStandaloneAppFolder', appName);            
                if status
                    rootFolder = executionFolder;
                end
            end        
        end

        %-----------------------------------------------------------------%
        function killingMATLABRuntime(executionMode)
            if ismember(executionMode, {'desktopStandaloneApp', 'webapp'})
                pidMatlab = feature('getpid');
                appEngine.util.OperationSystem('terminateProcessImmediately', pidMatlab)
            end        
        end

        %-----------------------------------------------------------------%
        function setWindowPosition(hFigure)
            [xPosition, yPosition] = appEngine.util.computeWindowPosition(hFigure.Position(3), hFigure.Position(4));            
            hFigure.Position(1:2)  = [xPosition, yPosition];
        end

        %-----------------------------------------------------------------%
        function [xPosition, yPosition] = computeWindowPosition(figWidth, figHeight)
            mainMonitor = get(0, 'MonitorPositions');
            [~, idx]    = max(mainMonitor(:,3));
            mainMonitor = mainMonitor(idx,:);

            xPosition   = mainMonitor(1)+round((mainMonitor(3)-figWidth)/2);
            yPosition   = mainMonitor(2)+round((mainMonitor(4)+18-figHeight)/2);
        end
        
        %-----------------------------------------------------------------%
        function setWindowMinSize(hFigure, minSize)
            try
                webWin = struct(struct(struct(hFigure).Controller).PlatformHost).CEF;
                webWin.setMinSize(minSize)
            catch
            end
        end

        %-----------------------------------------------------------------%
        function htmlSource = jsBackDoorHTMLSource()
            htmlSource = fullfile(fileparts(mfilename('fullpath')), 'matlabJSBridge', 'matlabJSBridge.html');
        end

        %-----------------------------------------------------------------%
        function [fileFullName, fileName] = DefaultFileName(filePath, Prefix, Suffix)
            arguments
                filePath char
                Prefix   string
                Suffix   string = ""
            end

            fileName = sprintf('%s_%s', Prefix, datestr(now, 'yyyy.mm.dd_THH.MM.SS'));
            if ~ismember(Suffix, ["", "-1"])
                Suffix = "_" + Suffix;
                fileName = sprintf('%s%s', fileName, Suffix);
            end

            fileFullName = fullfile(filePath, fileName);
        end

        %-----------------------------------------------------------------%
        function [projectFolder, programDataFolder] = Path(appName, rootFolder)
            projectFolder     = fullfile(rootFolder, 'config');
            programDataFolder = fullfile(appEngine.util.OperationSystem('programData'), 'ANATEL', appName);
        end

        %-----------------------------------------------------------------%
        function userPaths = UserPaths(userPath)
            userPaths = [appEngine.util.OperationSystem('userPath'), {userPath}];
            userPaths(~isfolder(userPaths)) = [];
        
            if isempty(userPaths)
                tempFolder = tempname;
                if ~isfolder(tempFolder)
                    mkdir(tempFolder)
                end

                userPaths  = {tempFolder};
            end        
        end

        %-----------------------------------------------------------------%
        function varargout = OperationSystem(operationType, varargin)
            arguments
                operationType char {mustBeMember(operationType, {'platform',                   ...
                                                                 'ver',                        ...
                                                                 'userPath',                   ...
                                                                 'programData',                ...
                                                                 'desktopStandaloneAppFolder', ...
                                                                 'computerName',               ...
                                                                 'userName',                   ...
                                                                 'pythonExecutable',           ...
                                                                 'openFile',                   ...
                                                                 'terminateProcessImmediately'})}
            end
        
            arguments (Repeating)
                varargin
            end
        
            if ~ispc && ~ismac && ~isunix
                error('Platform not supported')
            end
        
            switch operationType
                case 'platform'
                    varargout{1} = computer('arch');
        
                case 'ver'
                    if ispc
                        [~, OS] = system('ver');
                    elseif ismac
                        [~, OS] = system('sw_vers -productVersion');
                    elseif isunix
                        [status, OS] = system('lsb_release -d');
                        if status
                            [~, OS] = system('uname -r');
                        end
                    end
                    varargout{1} = strtrim(OS);
        
                case 'userPath'
                    if ispc
                        userPaths = {fullfile(getenv('USERPROFILE'), 'Documents'), ...
                                     fullfile(getenv('USERPROFILE'), 'Downloads')};
                    else
                        userPaths = {fullfile(getenv('HOME'), 'Documents'),  ...
                                     fullfile(getenv('HOME'), 'Documentos'), ...
                                     fullfile(getenv('HOME'), 'Downloads')};
                    end
                    userPaths(~isfolder(userPaths)) = [];
        
                    varargout{1} = userPaths;
        
                case 'programData'
                    if ispc
                        programDataFolder = getenv('PROGRAMDATA');
                    elseif ismac
                        programDataFolder = '/Users/Shared';
                    else % isunix
                        programDataFolder = '/etc';
                    end
                    varargout{1} = programDataFolder;
        
                case 'desktopStandaloneAppFolder'
                    status  = false;
                    appName = varargin{1};
                    if ispc
                        [~, result]     = system('path');    
                        executionFolder = char(regexpi(result, 'Path=(.*?);', 'tokens', 'once'));
                        if isfile(fullfile(executionFolder, [appName '.exe']))
                            status = true;
                        end
                    elseif ismac
                        executionFolder = fileparts(fileparts(fileparts(fileparts(ctfroot))));
                        if isfolder(fullfile(executionFolder, [appName '.app']))
                            status = true;
                        end
                    else
                        % !! PENDENTE !!
                        error('Pendente análise de como as distribuições Linux descompactam o arquivo compilado no MATLAB. :(')
                    end
                    varargout = {status, executionFolder};
        
                case 'computerName'
                    if ispc
                        computerName = getenv('COMPUTERNAME');
                    else % ismac | isunix
                        [~, computerName] = system('hostname');
                        computerName = strtrim(computerName);
                    end
                    varargout{1} = computerName;
        
                case 'userName'
                    if ispc
                        userName = getenv('USERNAME');
                    else % ismac | isunix
                        [~, userName] = system('whoami');
                        userName = strtrim(userName);
                    end
                    varargout{1} = userName; 
        
                case 'openFile'
                    fileName = varargin{1};        
                    if ispc
                        winopen(fileName)
                    elseif ismac
                        system(sprintf('open "%s" &', fileName));
                    else
                        system(sprintf('xdg-open "%s" &', fileName));
                    end
        
                case 'terminateProcessImmediately'
                    pidMatlab = varargin{1};        
                    if ispc
                        system(sprintf('taskkill /F /PID %d', pidMatlab));
                    else
                        system(sprintf('kill -9 %d', pidMatlab));
                    end
            end
        end

        %-----------------------------------------------------------------%
        function [generalSettings, msgWarning] = generalSettingsLoad(appName, rootFolder, files2Keep)
            % Para melhor controle das customizações de operação dos apps, os arquivos 
            % de configuração serão armazenados em pasta %PROGRAMDATA%\ANATEL\%appName%
            % 
            % Caso a pasta não exista, o app a criará no seu processo de inicialização,
            % copiando os arquivos de configuração do projeto, originalmente armazenados
            % na subpasta "Settings" ou "src/config" do projeto.
            %
            % Caso a pasta exista, por outro lado, verifica-se a versão do arquivo
            % "GeneralSettings.json".
            arguments
                appName     char
                rootFolder  char
                files2Keep  cell = {}
            end
        
            generalSettings     = [];
            msgWarning          = '';
        
            [projectFolder, ...
             programDataFolder] = appEngine.util.Path(appName, rootFolder);
            projectFilePath     = fullfile(projectFolder,     'GeneralSettings.json');
            programDataFilePath = fullfile(programDataFolder, 'GeneralSettings.json');
        
            projectFileContent  = jsondecode(fileread(projectFilePath));
            try
                if ~isfolder(programDataFolder)
                    mkdir(programDataFolder)
                end

                programDataFolder_backup = fullfile(programDataFolder, '_oldFiles');
                if ~isfolder(programDataFolder_backup)
                    mkdir(programDataFolder_backup)
                end

                if ~isfile(programDataFilePath)
                    appEngine.util.copyConfigFiles(programDataFolder, programDataFolder_backup, files2Keep, 'move')
                    appEngine.util.copyConfigFiles(projectFolder,     programDataFolder,        files2Keep, 'copy')                
                else
                    programDataFileContent = jsondecode(fileread(programDataFilePath));
        
                    if projectFileContent.version > programDataFileContent.version
                        fieldsToKeepInfo = {'operationMode', 'fileFolder'};
                        for ii = 1:numel(fieldsToKeepInfo)
                            fieldToKeep = fieldsToKeepInfo{ii};

                            if ~isfield(projectFileContent, fieldToKeep)     || ...
                               ~isstruct(projectFileContent.(fieldToKeep))   || ...
                               ~isfield(programDataFileContent, fieldToKeep) || ...                               
                               ~isstruct(programDataFileContent.(fieldToKeep))
                                continue
                            end

                            subFieldsToKeepInfo = fieldnames(programDataFileContent.(fieldToKeep));
                            for jj = 1:numel(subFieldsToKeepInfo)
                                subFieldToKeep = subFieldsToKeepInfo{jj};

                                if isfield(projectFileContent.(fieldToKeep), subFieldToKeep)
                                    projectFileContent.(fieldToKeep).(subFieldToKeep) = programDataFileContent.(fieldToKeep).(subFieldToKeep);
                                end
                            end
                        end
        
                        appEngine.util.copyConfigFiles(programDataFolder, programDataFolder_backup, files2Keep, 'move')
                        appEngine.util.copyConfigFiles(projectFolder,     programDataFolder,        files2Keep, 'copy')
                        writematrix(jsonencode(projectFileContent, "PrettyPrint", true), programDataFilePath, "FileType", "text", "QuoteStrings", "none", "WriteMode", "overwrite")
                        
                        msgWarning = ['Os arquivos de configuração do app hospedado na pasta de configuração local, ' ...
                                      'incluindo "GeneralSettings.json", foram atualizados. As versões antigas dos '  ...
                                      'arquivos foram salvas na subpasta "oldFiles".'];                    
                    else
                        generalSettings = programDataFileContent;
                    end
                end
        
            catch ME
                msgWarning = ME.message;
            end
        
            if isempty(generalSettings)
                generalSettings = projectFileContent;
            end

            if ~isempty(generalSettings.fileFolder.lastVisited) && ~isfolder(generalSettings.fileFolder.lastVisited)
                generalSettings.fileFolder.lastVisited = '';
            end
        end

        %-------------------------------------------------------------------------%
        function generalSettingsSave(appName, rootFolder, appGeneral, executionMode, fields2Remove)
            % Aplicável apenas à versão desktop do app. Dessa forma, o parâmetro
            % de configuração alterado por um usuário do webapp terá efeito apenas 
            % na própria sessão do webapp.
            arguments
                appName       char
                rootFolder    char
                appGeneral    struct
                executionMode char
                fields2Remove cell = {}
            end

            if strcmp(executionMode, 'webApp')
                return
            end
        
            if ~isempty(fields2Remove)
                appGeneral = rmfield(appGeneral, fields2Remove);
            end

            appGeneral.fileFolder.MFilePath = '';
            appGeneral.fileFolder.tempPath  = '';

            switch appName
                case 'appAnalise'
                    appGeneral.Plot.ClearWrite.Visible = 'on';
                otherwise
                    % ...
            end
        
            [~, ...
             programDataFolder] = appEngine.util.Path(appName, rootFolder);
            programDataFilePath = fullfile(programDataFolder, 'GeneralSettings.json');
        
            try
                writematrix(jsonencode(appGeneral, 'PrettyPrint', true, 'ConvertInfAndNaN', false), programDataFilePath, "FileType", "text", "QuoteStrings", "none", "WriteMode", "overwrite")
            catch
            end
        end
    end


    methods (Access = private, Static = true)
        %-------------------------------------------------------------------------%
        function copyConfigFiles(oldPath, newPath, files2Keep, operationType)
            arguments
                oldPath       char
                newPath       char
                files2Keep    cell = {}
                operationType char {mustBeMember(operationType, {'copy', 'move'})} = 'copy'
            end
        
            cfgFiles = dir(oldPath);
            
            cfgFiles(ismember({cfgFiles.name}, {'.', '..', '_oldFiles'})) = [];
            if ~isempty(files2Keep)
                cfgFiles(cellfun(@(x) any(strcmpi(x, files2Keep)), {cfgFiles.name})) = [];
            end
        
            for ii = 1:numel(cfgFiles)
                oldFullPath = fullfile(cfgFiles(ii).folder, cfgFiles(ii).name);
                newFullPath = newPath;
                
                if isfolder(oldFullPath)
                    newFullPath = fullfile(newPath, cfgFiles(ii).name);
                end

                switch operationType
                    case 'copy'
                        copyfile(oldFullPath, newFullPath, 'f');
                    case 'move'
                        movefile(oldFullPath, newFullPath, 'f');
                end
            end
        end
    end
end

