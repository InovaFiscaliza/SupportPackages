function activate(app, role, varargin)
    arguments
        app  {mustBeA(app, 'matlab.apps.AppBase')}
        role {mustBeMember(role, {'mainApp', 'secondaryApp'})}
    end

    arguments (Repeating)
        varargin
    end

    switch role
        case 'mainApp'
            app.progressDialog = ui.ProgressDialog(app.jsBackDoor);
            requestVisibilityChange(app.progressDialog, 'visible', 'locked')
            drawnow

            if ~app.renderCount
                MFilePath   = varargin{1};
                parpoolFlag = varargin{2};

                % Essa propriedade registra o tipo de execução da aplicação, podendo
                % ser: 'built-in', 'desktopApp' ou 'webApp'.
                app.executionMode  = appEngine.util.ExecutionMode(app.UIFigure);
                if ~strcmp(app.executionMode, 'webApp')
                    app.FigurePosition.Visible = 1;
                    appEngine.util.setWindowMinSize(app.UIFigure, class.Constants.windowMinSize)
                end
        
                % Identifica o local deste arquivo .MLAPP, caso se trate das versões 
                % "built-in" ou "webapp", ou do .EXE relacionado, caso se trate da
                % versão executável (neste caso, o ctfroot indicará o local do .MLAPP).
                appName = class.Constants.appName;
                app.rootFolder = appEngine.util.RootFolder(appName, MFilePath);
        
                % Customizações...
                JSCustomizations(app)
        
                % Inicia módulo de operação paralelo...
                if parpoolFlag
                    parpoolCheck()
                end
        
                loadConfigurationFile(app, appName, MFilePath)
                initializeAppProperties(app)
                initializeUIComponents(app)
                applyInitialLayout(app)
        
            else
                JSCustomizations(app)
            end

            pause(.100)
            requestVisibilityChange(app.progressDialog, 'hidden', 'locked')

        case 'secondaryApp'
            drawnow
            JSCustomizations(app)

            requestVisibilityChange(app.progressDialog, 'visible', 'unlocked')

            initializeAppProperties(app)
            initializeUIComponents(app)
            applyInitialLayout(app)

            requestVisibilityChange(app.progressDialog, 'hidden', 'unlocked')
    end
end

%-------------------------------------------------------------------------%
function JSCustomizations(app)
    applyJSCustomizations(app, 0)

    if isprop(app, 'TabGroup')
        applyJSCustomizations(app, 1)
    end

    pause(.100)
end