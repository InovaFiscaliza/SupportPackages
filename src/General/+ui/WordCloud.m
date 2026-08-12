classdef WordCloud < handle

    properties (Access = private)
        %-----------------------------------------------------------------%
        jsBackDoor
        Container
    end


    properties
        %-----------------------------------------------------------------%
        Table = table('Size', [0,2], 'VariableTypes', {'string', 'double'}, 'VariableNames', {'Word', 'Count'})
    end


    properties (Constant)
        %-----------------------------------------------------------------%
        UUID = char(matlab.lang.internal.uuid())
        Type = 'ui.WordCloud'
        Algorithm = 'D3.js'
    end

    
    methods
        %-----------------------------------------------------------------%
        function obj = WordCloud(jsBackDoor, gridContainer)
            arguments
                jsBackDoor    matlab.ui.control.HTML
                gridContainer matlab.ui.container.GridLayout
            end

            obj.jsBackDoor = jsBackDoor;
            obj.Container = gridContainer;

            ui.CustomizationBase.getElementsDataTag({gridContainer});
            createCanvas(obj)
        end

        %-----------------------------------------------------------------%
        function set.Table(obj, tbl)
            if ~isequal(obj.Table, tbl)
                updateCanvas(obj, tbl)
                obj.Table = tbl;
            end
        end

        %-----------------------------------------------------------------%
        function delete(obj)
            eraseCanvas(obj)
        end
    end


    methods (Access = protected)
        %-----------------------------------------------------------------%
        function createCanvas(obj)
            sendEventToHTMLSource(obj.jsBackDoor, 'wordcloud', struct('dataTag', obj.Container.UserData.id))
        end

        %-----------------------------------------------------------------%
        function eraseCanvas(obj)
            sendEventToHTMLSource(obj.jsBackDoor, 'eraseWordCloud', struct('dataTag', obj.Container.UserData.id));
        end

        %-----------------------------------------------------------------%
        function updateCanvas(obj, tbl)
            if isempty(tbl)
                sendEventToHTMLSource(obj.jsBackDoor, 'drawWordCloud', struct('dataTag', obj.Container.UserData.id, 'words', {{}}, 'weights', {{}}));
            else
                sendEventToHTMLSource(obj.jsBackDoor, 'drawWordCloud', struct('dataTag', obj.Container.UserData.id, 'words', tbl.Word, 'weights', tbl.Count));
            end
        end
    end
end