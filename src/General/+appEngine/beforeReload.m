function beforeReload(app, role)
    arguments
        app  {mustBeA(app, 'matlab.apps.AppBase')}
        role {mustBeMember(role, {'mainApp'})} = 'mainApp'
    end

    if ~app.Tab1Button.Value
        app.Tab1Button.Value = true;                    
        navigateToTab(app, app.Tab1Button)
        drawnow
    end

    if isprop(app, 'SubTabGroup')
        app.SubTabGroup.UserData.isTabInitialized(:) = false;
    end

    appTags = app.tabGroupController.Components.Tag;
    secondaryAppTags = appTags((appTags ~= "") & (app.tabGroupController.Components.Type == "External"));
    if ~isempty(secondaryAppTags)
        closeModule(app.tabGroupController, secondaryAppTags, app.General)
    end

    if ~isempty(app.popupContainer) && isvalid(app.popupContainer)
        auxDockAppName = app.popupContainer.UserData.auxDockAppName;
        deleteContextMenu(app.tabGroupController, app.UIFigure, auxDockAppName)
        delete(app.popupContainer)
    end
end