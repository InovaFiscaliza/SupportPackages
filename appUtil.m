classdef (Abstract) appUtil
    
    methods (Static = true)
        %-----------------------------------------------------------------%
        function disablingWarningMessages()
            warning('off', 'MATLAB:ui:javaframe:PropertyToBeRemoved')
            warning('off', 'MATLAB:subscripting:noSubscriptsSpecified')
            warning('off', 'MATLAB:structOnObject')
            warning('off', 'MATLAB:class:DestructorError')
            warning('off', 'MATLAB:modes:mode:InvalidPropertySet')
            warning('off', 'MATLAB:table:RowsAddedExistingVars')
            warning('off', 'MATLAB:colon:operandsNotRealScalar')            
        end


        %-----------------------------------------------------------------%
        function executionMode = ExecutionMode(hFigure)
            % No MATLAB R2024a, o container da figura de uma aplicação desktop é o arquivo "cefComponentContainer.html"
            % 'https://127.0.0.1:31517/toolbox/matlab/uitools/uifigureappjs/cefComponentContainer.html?channel=/uifigure/45562d91-459d-4a9e-bafc-4f51c6940e09&websocket=on&syncMode=MF0ViewModel&snc=FV5YKZ'

            % Já o container de uma aplicação webapp, por outro lado, é o arquivo "webAppContainer.html".
            % 'http://df6963612dtn:9988/services/static/24.1/toolbox/compiler/mdwas/client/session/webAppContainer.html?MDWAS-Connection-Id=5d9ffe85-3824-419b-bedb-1ad678c5ac4b'

            figureURL = struct(struct(hFigure).Controller).PeerModelInfo.URL;
            if contains(figureURL, 'webAppContainer.html', 'IgnoreCase', true)
                executionMode = 'webApp';
            else
                if isdeployed
                    executionMode = 'desktopStandaloneApp';
                else
                    executionMode = 'MATLABEnvironment';
                end
            end
        end


        %-----------------------------------------------------------------%
        function rootFolder = RootFolder(appName, MFilePath)
            rootFolder = MFilePath;

            if isdeployed
                [status, executionFolder] = ccTools.fcn.OperationSystem('desktopStandaloneAppFolder', appName);            
                if status
                    rootFolder = executionFolder;
                end
            end        
        end


        %-----------------------------------------------------------------%
        function killingMATLABRuntime(executionMode)
            if ismember(executionMode, {'desktopStandaloneApp', 'webapp'})
                pidMatlab = feature('getpid');
                system(sprintf('taskkill /F /PID %d', pidMatlab));
            end        
        end


        %-----------------------------------------------------------------%
        function winPosition(hFigure)
            mainMonitor = get(0, 'MonitorPositions');
            [~, idx]    = max(mainMonitor(:,3));
            mainMonitor = mainMonitor(idx,:);
            
            hFigure.Position(1:2) = [mainMonitor(1)+round((mainMonitor(3)-hFigure.Position(3))/2), ...
                                     mainMonitor(2)+round((mainMonitor(4)+48-hFigure.Position(4)-30)/2)];
        end


        %-----------------------------------------------------------------%
        function d = modalWindow(hFigure, type, msg, varargin)
            arguments
                hFigure matlab.ui.Figure
                type    {mustBeMember(type, {'error', 'warning', 'info', 'progressdlg'})}
                msg     {mustBeTextScalar} = ''
            end
        
            arguments (Repeating)
                varargin
            end
            
            d = [];
            switch type
                case {'error', 'warning', 'info'}
                    msg = sprintf('<p style="font-size:12px; text-align: justify;">%s</p>', msg);
                    switch type
                        case 'error';   uialert(hFigure, msg, '', 'Interpreter', 'html', 'Icon', 'error',   varargin{:})
                        case 'warning'; uialert(hFigure, msg, '', 'Interpreter', 'html', 'Icon', 'warning', varargin{:})
                        case 'info';    uialert(hFigure, msg, '', 'Interpreter', 'html', 'Icon', 'info',    varargin{:})
                    end
                    beep
                    
                case 'progressdlg'
                    msg = sprintf('<p style="font-size:12px; text-align: justify;">%s</p>', msg);
                    d = uiprogressdlg(hFigure, 'Indeterminate', 'on', 'Interpreter', 'html', 'Message', msg, varargin{:});
            end
        end


        %-----------------------------------------------------------------%
        function [projectFolder, programDataFolder] = Path(appName, rootFolder)
            projectFolder     = fullfile(rootFolder, 'Settings');
            programDataFolder = fullfile(ccTools.fcn.OperationSystem('programData'), 'ANATEL', appName);
        end


        %-----------------------------------------------------------------%
        function userPaths = UserPaths(userPath)
            userPaths = [ccTools.fcn.OperationSystem('userPath'), {userPath}];
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
        function [generalSettings, msgWarning] = generalSettingsLoad(appName, rootFolder, files2Keep)
            % Para melhor controle das customizações de operação dos apps, os arquivos 
            % de configuração serão armazenados em pasta %PROGRAMDATA%\ANATEL\%appName%
            % 
            % Caso a pasta não exista, o app a criará no seu processo de inicialização,
            % copiando os arquivos de configuração do projeto, originalmente armazenados
            % na subpasta "Settings" do projeto.
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
             programDataFolder] = appUtil.Path(appName, rootFolder);
            projectFilePath     = fullfile(projectFolder,     'GeneralSettings.json');
            programDataFilePath = fullfile(programDataFolder, 'GeneralSettings.json');
        
            projectFileContent  = jsondecode(fileread(projectFilePath));
            try
                if ~isfile(programDataFilePath)
                    if ~isfolder(programDataFolder)
                        mkdir(programDataFolder)
                    end
                    appUtil.copyConfigFiles(projectFolder, programDataFolder)
                
                else
                    programDataFileContent = jsondecode(fileread(programDataFilePath));
        
                    if projectFileContent.version > programDataFileContent.version
                        oldFields = fieldnames(programDataFileContent.fileFolder);
                        for ii = 1:numel(oldFields)
                            if isfield(projectFileContent.fileFolder, oldFields{ii})
                                projectFileContent.fileFolder.(oldFields{ii}) = programDataFileContent.fileFolder.(oldFields{ii});
                            end
                        end
        
                        programDataFolder_backup = fullfile(programDataFolder, 'oldFiles');
                        if ~isfolder(programDataFolder_backup)
                            mkdir(programDataFolder_backup)
                        end
        
                        appUtil.copyConfigFiles(programDataFolder, programDataFolder_backup, files2Keep)
                        appUtil.copyConfigFiles(projectFolder,     programDataFolder)
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

            folderFields = fieldnames(generalSettings.fileFolder);
            for kk = 1:numel(folderFields)
                if ~isfolder(generalSettings.fileFolder.(folderFields{kk}))
                    generalSettings.fileFolder.(folderFields{kk}) = '';
                end
            end
        end


        %-------------------------------------------------------------------------%
        function generalSettingsSave(appName, rootFolder, appGeneral, fields2Remove)
            arguments
                appName       char
                rootFolder    char
                appGeneral    struct
                fields2Remove cell = {}
            end
        
            if ~isempty(fields2Remove)
                appGeneral = rmfield(appGeneral, fields2Remove);
            end
            
            appGeneral.fiscaliza.lastHTMLDocFullPath = '';
            appGeneral.fiscaliza.lastTableFullPath   = '';
        
            [~, ...
             programDataFolder] = appUtil.Path(appName, rootFolder);
            programDataFilePath = fullfile(programDataFolder, 'GeneralSettings.json');
        
            try
                writematrix(jsonencode(appGeneral, 'PrettyPrint', true), programDataFilePath, "FileType", "text", "QuoteStrings", "none", "WriteMode", "overwrite")
            catch
            end
        end
    end


    methods (Access = private, Static = true)
        %-------------------------------------------------------------------------%
        function copyConfigFiles(oldPath, newPath, files2Keep)
            arguments
                oldPath     char
                newPath     char
                files2Keep  cell = {}
            end
        
            cfgFiles = dir(oldPath);
            cfgFiles([cfgFiles.isdir]) = [];
            if ~isempty(files2Keep)
                cfgFiles(cellfun(@(x) any(strcmpi(x, files2Keep)), {cfgFiles.name})) = [];
            end
        
            for ii = 1:numel(cfgFiles)
                jsonFilePath = fullfile(cfgFiles(ii).folder, cfgFiles(ii).name);
                copyfile(jsonFilePath, newPath, 'f');
            end
        end
    end
end

