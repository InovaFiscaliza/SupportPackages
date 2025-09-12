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
                ccTools.fcn.OperationSystem('terminateProcessImmediately', pidMatlab)
            end        
        end

        %-----------------------------------------------------------------%
        function beforeDeleteApp(progressDialog, tempDir, tabGroupController, executionMode)
            % TIMER
            h = timerfindall;
            if ~isempty(h)
                stop(h); delete(h); clear h
            end

            % PROGRESS DIALOG
            delete(progressDialog)

            % DELETE TEMP FILES
            if isfolder(tempDir)
                rmdir(tempDir, 's');
            end

            % DELETE APPS
            if isdeployed
                delete(findall(groot, 'Type', 'Figure'))
            else
                delete(tabGroupController)
            end

            % MATLAB RUNTIME
            % Ao fechar um webapp, o MATLAB WebServer demora uns 10 segundos para
            % fechar o Runtime que suportava a sessão do webapp. Dessa forma, a 
            % liberação do recurso, que ocorre com a inicialização de uma nova 
            % sessão do Runtime, fica comprometida.
            appUtil.killingMATLABRuntime(executionMode)
        end

        %-----------------------------------------------------------------%
        function winPosition(hFigure)
            [xPosition, yPosition] = appUtil.winXYPosition(hFigure.Position(3), hFigure.Position(4));            
            hFigure.Position(1:2)  = [xPosition, yPosition];
        end

        %-----------------------------------------------------------------%
        function [xPosition, yPosition] = winXYPosition(figWidth, figHeight)
            mainMonitor = get(0, 'MonitorPositions');
            [~, idx]    = max(mainMonitor(:,3));
            mainMonitor = mainMonitor(idx,:);

            xPosition   = mainMonitor(1)+round((mainMonitor(3)-figWidth)/2);
            yPosition   = mainMonitor(2)+round((mainMonitor(4)+18-figHeight)/2);
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
        function htmlSource = jsBackDoorHTMLSource()
            htmlSource = fullfile(fileparts(mfilename('fullpath')), 'jsBackDoor', 'Container.html');
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
        function varargout = modalWindow(hFigure, type, msg, varargin)
            arguments
                hFigure matlab.ui.Figure
                type    {mustBeMember(type, {'error', 'warning', 'info', 'success', 'progressdlg', 'uiconfirm', 'uigetfile', 'uiputfile'})}
                msg     {mustBeTextScalar} = ''
            end
        
            arguments (Repeating)
                varargin
            end
            
            if ~isempty(msg)
                msg = textFormatGUI.HTMLParagraph(msg);
            end

            switch type
                case {'error', 'warning', 'info', 'success'}
                    switch type
                        case 'error';   uialert(hFigure, msg, '', 'Interpreter', 'html', 'Icon', 'error',   varargin{:})
                        case 'warning'; uialert(hFigure, msg, '', 'Interpreter', 'html', 'Icon', 'warning', varargin{:})
                        case 'info';    uialert(hFigure, msg, '', 'Interpreter', 'html', 'Icon', 'info',    varargin{:})
                        case 'success'; uialert(hFigure, msg, '', 'Interpreter', 'html', 'Icon', 'success', varargin{:})
                    end
                    varargout = {[]};
                    beep
                    
                case 'progressdlg'
                    dlg = uiprogressdlg(hFigure, 'Indeterminate', 'on', 'Interpreter', 'html', 'Message', msg, varargin{:});
                    varargout{1} = dlg;

                case 'uiconfirm'
                    % O uiconfirm trava a execução, aguardando retorno do
                    % usuário. Diferente do uialert, por exemplo, em que
                    % continua a execução. A validação abaixo garante a
                    % emulação do uiconfirm como uialert, com a vantagem de
                    % travar a execução, caso seja esse o objetivo.
                    if isscalar(varargin{1})
                        Icon = 'warning';
                    else
                        Icon = 'question';
                    end

                    userSelection = uiconfirm(hFigure, msg, '', 'Options', varargin{1}, 'DefaultOption', varargin{2}, 'CancelOption', varargin{3}, 'Interpreter', 'html', 'Icon', Icon);
                    varargout{1} = userSelection;

                case {'uigetfile', 'uiputfile'}
                    switch type
                        case 'uigetfile'
                            fileFormats       = varargin{1};
                            lastVisitedFolder = varargin{2};
                            otherParameters   = {};
                            if nargin == 6
                                otherParameters = varargin{3};
                            end
                            [fileName, fileFolder] = uigetfile(fileFormats, '', lastVisitedFolder, otherParameters{:});

                        otherwise
                            nameFormatMap   = varargin{1};
                            defaultFilename = varargin{2};
                            [fileName, fileFolder] = uiputfile(nameFormatMap, '', defaultFilename);
                    end
                    
                    executionMode = appUtil.ExecutionMode(hFigure);
                    if ~strcmp(executionMode, 'webApp')
                        figure(hFigure)
                    end

                    if isequal(fileName, 0)
                        varargout = {[], [], [], []};
                        return
                    end

                    fileFullPath    = fullfile(fileFolder, fileName);
                    [~, ~, fileExt] = fileparts(fileName);

                    varargout = {fileFullPath, fileFolder, lower(fileExt), fileName};
            end
        end

        %-----------------------------------------------------------------%
        function hPanel = modalDockContainer(jsBackDoor, containerType, varargin)
            arguments
                jsBackDoor    (1,1) matlab.ui.control.HTML
                containerType char {mustBeMember(containerType, {'Popup', 'Popup+CloseButton'})} = 'Popup'
            end

            arguments (Repeating)
                varargin
            end

            switch containerType
                case 'Popup'
                    Padding   = varargin{1};
                    winWidth  = varargin{2};
                    winHeight = varargin{3};                    

                    hFigure = ancestor(jsBackDoor, 'figure');
                    hGrid   = uigridlayout(hFigure, ColumnWidth={'1x', winWidth, '1x'}, RowHeight={'1x', winHeight, '1x'}, Padding=Padding*[1,1,1,1], ColumnSpacing=0, RowSpacing=0);

                    hPanel  = uipanel(hGrid, Title='', AutoResizeChildren='off');
                    hPanel.Layout.Row = 2;
                    hPanel.Layout.Column = 2;
                    
                    drawnow
                    ccTools.compCustomizationV2(jsBackDoor, hGrid, 'backgroundColor', 'rgba(255,255,255,0.65)')

                    hPanelDataTag = struct(hPanel).Controller.ViewModel.Id;
                    sendEventToHTMLSource(jsBackDoor, "panelDialog", struct('componentDataTag', hPanelDataTag))

                case 'Popup+CloseButton'
                    Padding = varargin{1};
                    
                    hFigure = ancestor(jsBackDoor, 'figure');
                    hGrid   = uigridlayout(hFigure, ColumnWidth={'1x', 16}, RowHeight={20, '1x'}, Padding=Padding*[1,1,1,1], ColumnSpacing=0, RowSpacing=0);

                    hPanel  = uipanel(hGrid, Title='', AutoResizeChildren='off');
                    hPanel.Layout.Row = [1,2];
                    hPanel.Layout.Column = [1,2];                    
                    
                    hImage  = uiimage(hGrid, ImageSource='Delete_32Gray.png');
                    hImage.Layout.Row = 1;
                    hImage.Layout.Column = 2;
                    
                    drawnow
                    ccTools.compCustomizationV2(jsBackDoor, hGrid, 'backgroundColor', 'rgba(255,255,255,0.65)')
            end

            hPanel.DeleteFcn = @(~,~)DeleteModalContainer();
            function DeleteModalContainer()
                delete(hGrid)
            end
        end

        %-----------------------------------------------------------------%
        function [projectFolder, programDataFolder] = Path(appName, rootFolder)
            % ToDo: Quando migrar os arquivos de configuração de todos os apps
            % p/ a pasta "config", eliminar a validação abaixo.

            if isfolder(fullfile(rootFolder, 'config'))
                projectFolder = fullfile(rootFolder, 'config');
            else
                projectFolder = fullfile(rootFolder, 'Settings');
            end

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
             programDataFolder] = appUtil.Path(appName, rootFolder);
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
                    appUtil.copyConfigFiles(programDataFolder, programDataFolder_backup, files2Keep, 'move')
                    appUtil.copyConfigFiles(projectFolder,     programDataFolder,        files2Keep, 'copy')                
                else
                    programDataFileContent = jsondecode(fileread(programDataFilePath));
        
                    if projectFileContent.version > programDataFileContent.version
                        oldFields = fieldnames(programDataFileContent.fileFolder);
                        for ii = 1:numel(oldFields)
                            if isfield(projectFileContent.fileFolder, oldFields{ii})
                                projectFileContent.fileFolder.(oldFields{ii}) = programDataFileContent.fileFolder.(oldFields{ii});
                            end
                        end
        
                        appUtil.copyConfigFiles(programDataFolder, programDataFolder_backup, files2Keep, 'move')
                        appUtil.copyConfigFiles(projectFolder,     programDataFolder,        files2Keep, 'copy')
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
             programDataFolder] = appUtil.Path(appName, rootFolder);
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

