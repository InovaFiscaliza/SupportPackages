function modalWindowEffect(fig, opacityType)
%MODALWINDOWEFFECT
% For use with modal windows, trying to create the same visual aspect 
% created by uialert, uiconfirm and uiprogressdlg.

% Author.: Eric Magalhães Delgado
% Date...: June 16, 2023
% Version: 1.00

    arguments
        fig
        opacityType {mustBeMember(opacityType, {'modalWindow', 'none'})}
    end

    if ~isa(fig, 'matlab.ui.Figure')
        fig = ancestor(fig, 'figure');
    end

    if ~isempty(fig)
        h = findobj(fig, 'Tag', 'StandByMode');
        
        switch opacityType
            case 'modalWindow'
                if isempty(h)
                    color = ccTools.fcn.defaultBackgroundColor();        
                    uihtml(fig, 'HTMLSource', sprintf('<!DOCTYPE html>\n<html>\n<body style="background-color: %s;"></body>\n</html>', color), ...
                                'Tag',        'StandByMode',                                  ...
                                'UserData',   struct('ID', char(java.rmi.server.UID),         ...
                                                     'WindowResize', char(fig.Resize)), ...
                                'Position',   [1, 1, fig.Position(3:4)]);
                    fig.Resize = 'off';
                end
    
            case 'none'            
                if ~isempty(h)
                    if strcmp(h(1).UserData.WindowResize, 'on')
                        fig.Resize = 'on';
                    end
                    delete(h)
                end
        end
    end
end