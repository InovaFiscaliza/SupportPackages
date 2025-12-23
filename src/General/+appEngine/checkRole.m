function checkRole(app, role)
    arguments
        app  {mustBeA(app, 'matlab.apps.AppBase')}
        role {mustBeMember(role, {'mainApp', 'secondaryApp', 'secondaryDockApp'})}
    end

    switch role
        case 'mainApp'
            requiredProps = {
                'UIFigure';             % matlab.ui.Figure
                'GridLayout';           % matlab.ui.container.GridLayout
                'AppName';              % matlab.ui.control.Label
                'TabGroup';             % matlab.ui.container.TabGroup
                'tabGroupController';   % ui.TabNavigator
                'Tab1Button';           % matlab.ui.control.StateButton
                'jsBackDoor';           % matlab.ui.control.HTML
                'FigurePosition';       % matlab.ui.control.Image
                'General';              % struct
                'rootFolder';           % char
                'renderCount';          % double
                'executionMode';        % char {mustBeMember(executionMode, {'built-in', 'desktopApp', 'webApp'})}
                'progressDialog';       % ui.ProgressDialog
                'popupContainer'        % double.empty → matlab.ui.container.Panel
            };
            requiredMethods = {
                'navigateToTab';
                'ipcMainJSEventsHandler';
                'applyJSCustomizations';
                'loadConfigurationFile';
                'initializeAppProperties';
                'initializeUIComponents';
                'applyInitialLayout'
            };

        case 'secondaryApp'
            requiredProps = {
                'UIFigure';             % matlab.ui.Figure
                'GridLayout';           % matlab.ui.container.GridLayout
                'Container';            % matlab.ui.Figure (HANDLE)
                'isDocked';             % logical
                'DockModule';           % matlab.ui.container.GridLayout
                'jsBackDoor';           % matlab.ui.control.HTML
                'progressDialog';       % ui.ProgressDialog
                'mainApp'               % matlab.apps.AppBase (HANDLE)
            };
            requiredMethods = {
                'ipcSecondaryJSEventsHandler';
                'applyJSCustomizations';
                'initializeAppProperties';
                'initializeUIComponents';
                'applyInitialLayout'
            };

        case 'secondaryDockApp'
            requiredProps = {
                'UIFigure';             % matlab.ui.Figure
                'GridLayout';           % matlab.ui.container.GridLayout
                'Container';            % matlab.ui.Figure (HANDLE)
                'isDocked';             % logical
                'mainApp';              % matlab.apps.AppBase (HANDLE)
                'callingApp'            % matlab.apps.AppBase (HANDLE)
            };
            requiredMethods = {};
    end

    missingProps   = requiredProps(~cellfun(@(x) isprop(app, x), requiredProps));
    missingMethods = requiredMethods(~cellfun(@(x) ismethod(app, x), requiredMethods));

    if ~isempty(missingProps) || ~isempty(missingMethods)
        error( ...
            'App compatibility check failed for role "%s". Missing properties: [%s]. Missing methods: [%s].', ...
            role, ...
            strjoin(missingProps, ', '), ...
            strjoin(missingMethods, ', ') ...
        );
    end
end