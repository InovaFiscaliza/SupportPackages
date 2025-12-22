function initialize(role, app, varargin)
    arguments
        role {mustBeMember(role, {'mainApp', 'secondaryApp', 'secondaryDockApp'})}
        app
    end

    arguments (Repeating)
        varargin
    end

    % This function is the initialization engine for MATLAB-based applications
    % such as appAnalise, appColeta, SCH, monitorRNI, and monitorSPED.
    %
    % To operate correctly, an application must comply with the following
    % structural and behavioral requirements:
    %
    % - A uifigure component exposed as: app.UIFigure
    % - A uigridlayout component as the child of the uifigure: app.GridLayout
    % - An HTML component used for MATLAB–JavaScript communication: app.jsBackDoor
    % - Public methods named:
    %     * ipcMainJSEventsHandler (for mainApp)
    %     * ipcSecondaryJSEventsHandler (for secondaryApp)
    %     * finalizeInitialization (for both mainApp and secondaryApp)
    %
    % The function appEngine.checkCompatibility validates these requirements
    % according to the specified application role.

    appEngine.checkCompatibility(role, app)

    switch role
        case 'mainApp'
            disableWarnings()
            initializeUI(app)
            setWindowPosition(app)
            waitForDOMReady(role, app)

        case 'secondaryApp'
            app.mainApp = varargin{1};
            
            if app.isDocked
                app.GridLayout.Padding(4)  = 30;
                app.DockModule.Visible = 1;
                app.jsBackDoor = app.mainApp.jsBackDoor;
                finalizeInitialization(app)
            else
                setWindowPosition(app)
                waitForDOMReady(role, app)
            end

        case 'secondaryDockApp'
            app.mainApp = varargin{1};
            app.callingApp = varargin{2};

            if isprop(app, 'jsBackDoor')
                app.jsBackDoor = app.callingApp.jsBackDoor;
            end
    end
end

%-------------------------------------------------------------------------%
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

%-------------------------------------------------------------------------%
function initializeUI(app)
    app.AppName.Text = sprintf('%s v. %s\n<font style="font-size: 9px;">%s</font>', class.Constants.appName, class.Constants.appVersion, class.Constants.appRelease);
end

%-----------------------------------------------------------------%
function setWindowPosition(app)
    [xPosition, yPosition] = winXYPosition(app.UIFigure.Position(3), app.UIFigure.Position(4));            
    app.UIFigure.Position(1:2) = [xPosition, yPosition];

    function [xPosition, yPosition] = winXYPosition(figWidth, figHeight)
        mainMonitor = get(0, 'MonitorPositions');
        [~, idx]    = max(mainMonitor(:,3));
        mainMonitor = mainMonitor(idx,:);
    
        xPosition   = mainMonitor(1)+round((mainMonitor(3)-figWidth)/2);
        yPosition   = mainMonitor(2)+round((mainMonitor(4)+18-figHeight)/2);
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

    app.jsBackDoor = uihtml( ...
        app.UIFigure, ...
        "HTMLSource", appUtil.jsBackDoorHTMLSource(), ...
        "HTMLEventReceivedFcn", htmlEventReceivedFcn, ...
        "Visible", "off" ...
    );
end