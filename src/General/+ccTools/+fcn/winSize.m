function [winWidth,  winHeight] = winSize(comp, msg, p)

    winWidth  = str2double(extractBefore(p.winWidth,  'px'));
    winHeight = str2double(extractBefore(p.winHeight, 'px'));

    % The window size will be adjustable, depending on the text content, 
    % only if the parameters winWidth and winHeight are not configured.
    if isequal([winWidth, winHeight], [302, 162])
        winSize     = ContainerSize(comp);

        iconWidth   = str2double(extractBefore(p.iconWidth,    'px'));
        btnHeight   = str2double(extractBefore(p.buttonHeight, 'px'));        
        msgFontSize = str2double(extractBefore(p.msgFontSize,  'px'));

        % Number of characters supported in a single line (winColSize) and 
        % number of lines (winRowSize), considering the initial window size
        % (302x106 pixels).
        k1 = 0.67;
        k2 = 1.25;

        winColSize  = floor((winWidth-iconWidth-30)  / (k1*msgFontSize));
        winRowSize  = floor((winHeight-btnHeight-30) / (k2*msgFontSize));
        
        % Splitting the text content into lines (msgSplit), identifying the 
        % number of characters in the line with the most characters (msgColumns).
        msgSplit    = cellfun(@(x) regexprep(x, '<.*?>', ''), splitlines(msg), 'UniformOutput', false);
        msgColumns  = max(cellfun(@(x) numel(x), msgSplit));
        if msgColumns > winColSize
            % New width of the window.
            winWidth = min([.5*winSize(1), 0.67*msgFontSize*msgColumns+iconWidth+30]);
            
            winWidth(winWidth < 302) = 302;
            winWidth(winWidth > 480) = 480;

            % Updates the number of characters supported in a single line.
            winColSize  = floor((winWidth-iconWidth-30)  / (k1*msgFontSize));
        end
        
        % Number of lines required to display the information on the screen.
        msgRows = numel(msgSplit) + sum(floor(cellfun(@(x) numel(x), msgSplit) / winColSize));
        if msgRows > winRowSize
            % New height of the window.
            winHeight = min([.8*winSize(2), k2*msgFontSize*msgRows+btnHeight+30]);

            winHeight(winHeight < 162) = 162;
            winHeight(winHeight > 480) = 480;
        end
    end

    winWidth  = sprintf('%.0fpx', winWidth);
    winHeight = sprintf('%.0fpx', winHeight);
end


%-------------------------------------------------------------------------%
function compSize = ContainerSize(comp)
    switch class(comp)
        case 'matlab.ui.container.internal.AppContainer'; compSize = comp.WindowBounds(3:4);
        case 'matlab.ui.Figure';                          compSize = comp.Position(3:4);
    end
end