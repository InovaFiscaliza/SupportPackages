function PopUpContainer(callingApp, screenWidth, screenHeight)
    arguments
        callingApp
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
        popupContainer = uipanel(hFig, "Title", "", "Tag", "popupContainer", "Position", [1, 1, screenWidth, screenHeight], "Visible", "off");
        pause(1)    
    else
        popupContainer.Position(3:4) = [screenWidth, screenHeight];
    end

    callingApp.popupContainer = popupContainer;
end