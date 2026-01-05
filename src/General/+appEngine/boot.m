function boot(app, role, varargin)
    arguments
        app  {mustBeA(app, 'matlab.apps.AppBase')}
        role {mustBeMember(role, {'mainApp', 'secondaryApp', 'secondaryDockApp'})}
    end

    arguments (Repeating)
        varargin
    end

    % This function is the initialization engine for MATLAB-based applications
    % such as appAnalise, appColeta, SCH, monitorRNI, and monitorSPED. To 
    % operate correctly, an application must comply the requirementsdescribed 
    % in appEngine.checkRole.

    appEngine.checkRole(app, role)
    initializeUI(app)

    switch role
        case 'mainApp'
            appEngine.util.disableWarnings()            
            appEngine.util.setWindowPosition(app.UIFigure)
            waitForDOMReady(role, app)

        case 'secondaryApp'
            app.mainApp = varargin{1};
            
            if app.isDocked
                app.GridLayout.Padding(4) = 30;
                app.DockModule.Visible = 1;
                app.jsBackDoor = app.mainApp.jsBackDoor;
                appEngine.activate(app, role)
            else
                appEngine.util.setWindowPosition(app.UIFigure)
                waitForDOMReady(role, app)
            end

        case 'secondaryDockApp'
            app.mainApp = varargin{1};
            app.callingApp = varargin{2};

            if isprop(app, 'projectData') && isprop(app.mainApp, 'projectData')
                app.projectData = app.mainApp.projectData;
            end

            if isprop(app, 'jsBackDoor') && isprop(app.callingApp, 'jsBackDoor')
                app.jsBackDoor = app.callingApp.jsBackDoor;
            end

            if isprop(app, 'progressDialog') && isprop(app.callingApp, 'progressDialog')
                app.progressDialog = app.callingApp.progressDialog;
            end
    end
end

%-------------------------------------------------------------------------%
function initializeUI(app)
    if isprop(app, 'AppName')
        app.AppName.Text = sprintf('%s v. %s\n<font style="font-size: 9px;">%s</font>', class.Constants.appName, class.Constants.appVersion, class.Constants.appRelease);
    end

    if isprop(app, 'SubTabGroup')
        app.SubTabGroup.UserData.isTabInitialized = false(1, numel(app.SubTabGroup.Children));
    end
end

%-----------------------------------------------------------------%
function waitForDOMReady(role, app)
    timerObj = timer( ...
        "ExecutionMode", "fixedSpacing", ...
        "StartDelay", 1.5, ...
        "Period", .1, ...
        "TimerFcn", @(src, evt)onDOMReady(src, role, app) ...
    );
    start(timerObj)
end

%-----------------------------------------------------------------%
function onDOMReady(src, role, app)
    if ui.FigureRenderStatus(app.UIFigure)
        stop(src)
        delete(src)

        initializeJSBridge(role, app)
    end
end

%-----------------------------------------------------------------%
function initializeJSBridge(role, app)
    switch role
        case 'mainApp'
            htmlEventReceivedFcn = @(~, evt)ipcMainJSEventsHandler(app, evt);
        otherwise
            htmlEventReceivedFcn = @(~, evt)ipcSecondaryJSEventsHandler(app, evt);
    end

    if isempty(app.jsBackDoor)
        app.jsBackDoor = uihtml(app.UIFigure);
    end
    set(app.jsBackDoor, "HTMLSource", appEngine.util.jsBackDoorHTMLSource(), "HTMLEventReceivedFcn", htmlEventReceivedFcn);
end