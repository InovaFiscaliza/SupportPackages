function checkCompatibility(role, app)
    arguments
        role {mustBeMember(role, {'mainApp', 'secondaryApp', 'secondaryDockApp'})}
        app
    end

    switch role
        case 'mainApp'
            requiredProps   = {'UIFigure', 'GridLayout', 'AppName', 'jsBackDoor'};
            requiredMethods = {'ipcMainJSEventsHandler'};

        case 'secondaryApp'
            requiredProps   = {'UIFigure', 'GridLayout', 'DockModule', 'Container', 'isDocked', 'mainApp', 'jsBackDoor'};
            requiredMethods = {'ipcSecondaryJSEventsHandler'};

        case 'secondaryDockApp'
            requiredProps   = {'UIFigure', 'GridLayout', 'Container', 'isDocked', 'mainApp', 'callingApp'};
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