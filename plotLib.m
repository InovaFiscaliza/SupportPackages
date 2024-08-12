classdef plotLib < handle

    properties
        %-----------------------------------------------------------------%
        hTiledLayout
    end


    properties (Constant)
        %-----------------------------------------------------------------%
        figureSize = [1244, 660] % antigo: [650, 800]
    end


    methods
        %-----------------------------------------------------------------%
        function obj = plotLib(varargin)





        end


        %-----------------------------------------------------------------%
        function StackingOrder(obj, hAxes, refStackingOrder)            
            stackingOrderTag = arrayfun(@(x) x.Tag, hAxes.Children, 'UniformOutput', false)';
            newOrderIndex    = [];
        
            for ii = 1:numel(refStackingOrder)
                idx = find(strcmp(stackingOrderTag, refStackingOrder{ii}));
                newOrderIndex = [newOrderIndex, idx];
            end
        
            hAxes.Children = hAxes.Children(newOrderIndex);
        end
    end
end