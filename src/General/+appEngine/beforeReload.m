function beforeReload(app, role)

    % Quando ocorre o recarregamento do webapp (por exemplo, via F5, CTRL+F5 ou
    % mecanismo equivalente do navegador), o aplicativo retorna ao seu estado
    % nativo (built-in), sem as customizações de estilo e de comportamento
    % injetadas dinamicamente pelo "matlab-js-bridge" por meio de uihtml.
    %
    % Para garantir a consistência do estado da interface após o reload, este
    % método executa as seguintes ações:
    %   - Força a navegação para a aba inicial do aplicativo (Tab1);
    %   - Reinicializa o estado de customização de eventuais SubTabGroups
    %     associados à Tab1;
    %   - Remove e descarta contêineres de popups eventualmente existentes;
    %   - Encerra módulos auxiliares (aplicações externas) que estejam abertos.
    %
    % O objetivo é assegurar que o aplicativo retorne a um estado conhecido,
    % estável e coerente antes que as customizações sejam reaplicadas.

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

    deletePopUpContainer(app.tabGroupController, app)

    appTags = app.tabGroupController.Components.Tag;
    secondaryAppTags = appTags((appTags ~= "") & (app.tabGroupController.Components.Type == "External"));
    if ~isempty(secondaryAppTags)
        closeModule(app.tabGroupController, secondaryAppTags, app.General, 'normal')
    end
end