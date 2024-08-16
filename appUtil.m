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
            % No MATLAB R2024, os containeres das versões desktop e webapp
            % de um app são os arquivos "cefComponentContainer.html" e 
            % "webAppsComponentContainer.html", respectivamente.

            % >> struct(struct(hFigure).Controller).PeerModelInfo.URL
            % 'https://127.0.0.1:31517/toolbox/matlab/uitools/uifigureappjs/cefComponentContainer.html?channel=/uifigure/45562d91-459d-4a9e-bafc-4f51c6940e09&websocket=on&syncMode=MF0ViewModel&snc=FV5YKZ' (MATLAB)
            % 'https://127.0.0.1:31517/toolbox/matlab/uitools/uifigureappjs/cefComponentContainer.html?channel=/uifigure/04fb3193-a2cb-405a-9eac-8e3e38486454&websocket=on&syncMode=MF0ViewModel&snc=JOZ8GB' (MATLAB Runtime)
            % 'http://df6963612dtn:9988/services/static/24.1/toolbox/compiler/mdwas/client/session/webAppContainer.html?MDWAS-Connection-Id=5d9ffe85-3824-419b-bedb-1ad678c5ac4b'                            (MATLAB WebServer - DEPLOY)
            % 'https://fiscalizacao.anatel.gov.br/services/static/24.1/toolbox/compiler/mdwas/client/session/webAppContainer.html?MDWAS-Connection-Id=2240b1cf-15c0-4894-9ee0-6b52508f1b44'                  (MATLAB WebServer)

            % >> struct(struct(struct(hFigure).Controller).PlatformHost).ReleaseHTMLFile
            % 'cefComponentContainer.html'     (MATLAB, e MATLAB Runtime)
            % 'webAppsComponentContainer.html' (MATLAB WebServer)
            
            htmlAppContainer = struct(struct(struct(hFigure).Controller).PlatformHost).ReleaseHTMLFile;
            if contains(htmlAppContainer, 'webApp', 'IgnoreCase', true)
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
        function winMinSize(hFigure, minSize)
            try
                webWin = struct(struct(struct(hFigure).Controller).PlatformHost).CEF;
                webWin.setMinSize(minSize)
            catch
            end
        end


        %-----------------------------------------------------------------%
        function dlg = modalWindow(hFigure, type, msg, varargin)
            arguments
                hFigure matlab.ui.Figure
                type    {mustBeMember(type, {'error', 'warning', 'info', 'progressdlg', 'uiconfirm'})}
                msg     {mustBeTextScalar} = ''
            end
        
            arguments (Repeating)
                varargin
            end
            
            dlg = [];
            msg = textFormatGUI.HTMLParagraph(msg);

            switch type
                case {'error', 'warning', 'info'}
                    switch type
                        case 'error';   uialert(hFigure, msg, '', 'Interpreter', 'html', 'Icon', 'error',   varargin{:})
                        case 'warning'; uialert(hFigure, msg, '', 'Interpreter', 'html', 'Icon', 'warning', varargin{:})
                        case 'info';    uialert(hFigure, msg, '', 'Interpreter', 'html', 'Icon', 'info',    varargin{:})
                    end
                    beep
                    
                case 'progressdlg'
                    dlg = uiprogressdlg(hFigure, 'Indeterminate', 'on', 'Interpreter', 'html', 'Message', msg, varargin{:});

                case 'uiconfirm'
                    dlg = uiconfirm(hFigure, msg, '', 'Options', varargin{1}, 'DefaultOption', varargin{2}, 'CancelOption', varargin{3}, 'Interpreter', 'html', 'Icon', 'question');
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

