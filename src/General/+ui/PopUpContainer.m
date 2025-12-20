function PopUpContainer(callingApp, appName, screenWidth, screenHeight)
    arguments
        callingApp
        appName
        screenWidth
        screenHeight
    end

    if ~isprop(callingApp, 'popupContainer')
        % Aplicações construídas no AppDesigner são instâncias de uma classe 
        % que NÃO possibilita a criação de uma propriedade de forma dinâmica. 
        % Por essa razão, "popupContainer" já deve constar na lista de propriedades.
        % da classe. O comando a seguir retornará ERRO, caso se esqueça de
        % criar essa propriedade.
        addprop(callingApp, 'popupContainer');
    end

    hFig = callingApp.UIFigure;
    popupContainer = findobj(hFig.Children, 'Type', 'uipanel', 'Tag', 'popupContainer');

    if isempty(popupContainer) || ~isvalid(popupContainer)        
        popupContainerGrid = uigridlayout(hFig, [1, 1], "BackgroundColor", "white", "ColumnWidth", {'1x', screenWidth, '1x'}, "RowHeight", {'1x', screenHeight, '1x'}, "Visible", "off");
        popupContainer = uipanel(popupContainerGrid, "Title", "", "Tag", "popupContainer");
        popupContainer.Layout.Row = 2;
        popupContainer.Layout.Column = 2;
        drawnow

        elToModify = {...
            popupContainerGrid, ...
            popupContainer ...
        };
        elDataTag  = ui.CustomizationBase.getElementsDataTag(elToModify);
        popupContainer.UserData.auxDockAppName = '';

        if ~isempty(elDataTag)
            sendEventToHTMLSource(callingApp.jsBackDoor, 'initializeComponents', { ...
                struct('appName', appName, 'dataTag', elDataTag{1}, 'generation', 0, 'style',    struct('backgroundColor', 'rgba(255,255,255,0.65)')), ...
                struct('appName', appName, 'dataTag', elDataTag{2}, 'generation', 0, 'style',    struct('borderRadius', '5px', 'boxShadow', '0 2px 5px 1px #a6a6a6')), ...
                struct('appName', appName, 'dataTag', elDataTag{2}, 'generation', 1, 'style',    struct('borderRadius', '5px', 'borderColor', '#bfbfbf')) ...
            });
        end
        pause(1)
    
    else
        set(popupContainer.Parent, "ColumnWidth", {'1x', screenWidth, '1x'}, "RowHeight", {'1x', screenHeight, '1x'})
    end

    callingApp.popupContainer = popupContainer;
end