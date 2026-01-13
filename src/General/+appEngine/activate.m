function activate(app, role, varargin)
    arguments
        app  {mustBeA(app, 'matlab.apps.AppBase')}
        role {mustBeMember(role, {'mainApp', 'secondaryApp'})}
    end

    arguments (Repeating)
        varargin
    end

    drawnow

    switch role
        case 'mainApp'
            if isempty(app.progressDialog)
                app.progressDialog = ui.ProgressDialog(app.jsBackDoor);
            end
            requestVisibilityChange(app.progressDialog, 'visible', 'locked')
            
            if ~app.renderCount
                MFilePath   = varargin{1};
                parpoolFlag = varargin{2};

                % Essa propriedade registra o tipo de execução da aplicação, podendo
                % ser: 'built-in', 'desktopApp' ou 'webApp'.
                app.executionMode = appEngine.util.ExecutionMode(app.UIFigure);

                % Customizações...
                JSCustomizations(app, role)

                if ~strcmp(app.executionMode, 'webApp')
                    app.FigurePosition.Visible = 1;
                    appEngine.util.setWindowMinSize(app.UIFigure, class.Constants.windowMinSize)
                end
        
                % Identifica o local deste arquivo .MLAPP, caso se trate das versões 
                % "built-in" ou "webapp", ou do .EXE relacionado, caso se trate da
                % versão executável (neste caso, o ctfroot indicará o local do .MLAPP).
                appName = class.Constants.appName;
                app.rootFolder = appEngine.util.RootFolder(appName, MFilePath);
        
                % Inicia módulo de operação paralelo...
                if parpoolFlag
                    parpoolCheck()
                end
        
                loadConfigurationFile(app, appName, MFilePath)
                initializeAppProperties(app)
                initializeUIComponents(app)
                applyInitialLayout(app)
        
            else
                JSCustomizations(app, role)
            end

            if app.tabGroupController.inlineSVG
                convertToInlineSVG(app.tabGroupController, app.jsBackDoor)
            end

            pause(.100)
            requestVisibilityChange(app.progressDialog, 'hidden', 'locked')

        case 'secondaryApp'
            JSCustomizations(app, role)

            requestVisibilityChange(app.progressDialog, 'visible', 'unlocked')

            initializeAppProperties(app)
            initializeUIComponents(app)
            applyInitialLayout(app)

            requestVisibilityChange(app.progressDialog, 'hidden', 'unlocked')
    end
end

%-------------------------------------------------------------------------%
function JSCustomizations(app, role)
    switch role
        case 'mainApp'
            sendEventToHTMLSource(app.jsBackDoor, 'startup', app.executionMode);

        case 'secondaryApp'
            if app.isDocked
                app.progressDialog = app.mainApp.progressDialog;

                elDataTag  = ui.CustomizationBase.getElementsDataTag({app.DockModule});
                if ~isempty(elDataTag)
                    sendEventToHTMLSource(app.jsBackDoor, 'initializeComponents', { ...
                        struct('appName', class(app), 'dataTag', elDataTag{1}, 'style', struct('transition', 'opacity 2s ease', 'opacity', '0.5')) ...
                    });
                end

            else
                sendEventToHTMLSource(app.jsBackDoor, 'startup', app.mainApp.executionMode);
                app.progressDialog = ui.ProgressDialog(app.jsBackDoor);                        
            end
    end

    % O "mainApp" sempre terá um "TabGroup" como propriedade e, eventualmente,
    % um "SubTabGroup". Por outro lado, um "secondaryApp" pode, ou não, possuir 
    % um "SubTabGroup", a depender da sua complexidade. A validação abaixo 
    % garante a customização dos elementos renderizados na primeira aba do 
    % uitabgroup.
    if isprop(app, 'SubTabGroup')
        applyJSCustomizations(app, 1)
    end

    pause(.100)
end