classdef WordCloud < handle

    properties (Access = private)
        %-----------------------------------------------------------------%
        jsBackDoor
        Panel
        Chart
    end


    properties
        %-----------------------------------------------------------------%
        Algorithm {mustBeMember(Algorithm, {'D3.js', 'MATLAB built-in'})} = 'D3.js'
        Table
    end


    properties (Constant)
        %-----------------------------------------------------------------%
        UUID = char(matlab.lang.internal.uuid())
        Type = 'ui.WordCloud'
    end

    
    methods
        %-----------------------------------------------------------------%
        function obj = WordCloud(jsBackDoor, parentPanel, algorithm)
            obj.jsBackDoor = jsBackDoor;
            obj.Panel      = parentPanel;
            obj.Algorithm  = algorithm;

            CreateCanvas(obj)
        end

        %-----------------------------------------------------------------%
        function onAlgorithmValueChanged(obj, algorithm)
            if ~strcmp(obj.Algorithm, algorithm)
                refTable = obj.Table;                
                if ~isempty(refTable)    
                    DeleteCanvas(obj)
                end

                obj.Algorithm = algorithm;
                obj.Table = [];
                CreateCanvas(obj)
                obj.Table = refTable;
            end
        end

        %-----------------------------------------------------------------%
        function set.Table(obj, value)
            if ~isequal(obj.Table, value)
                TableUpdate(obj, value)
                obj.Table = value;
            end
        end

        %-----------------------------------------------------------------%
        function delete(obj)
            DeleteCanvas(obj)
        end
    end


    methods (Access = protected)
        %-----------------------------------------------------------------%
        function path = Path(obj)
            path = fileparts(mfilename('fullpath'));
        end

        %-----------------------------------------------------------------%
        function emptyTable = EmptyTable(obj)
            emptyTable = table('Size',          [0,2],                ...
                               'VariableTypes', {'string', 'double'}, ...
                               'VariableNames', {'Word', 'Count'});
        end

        %-----------------------------------------------------------------%
        function CreateCanvas(obj)
            switch obj.Algorithm
                case 'D3.js'
                    sendEventToHTMLSource(obj.jsBackDoor, 'wordcloud')
                    obj.Chart  = [];

                case 'MATLAB built-in'
                    emptyTable = EmptyTable(obj);

                    parentGrid = tiledlayout(obj.Panel, 1, 1, 'Padding', 'tight');
                    obj.Chart  = matlab.graphics.chart.WordCloudChart('Parent',          parentGrid,   ...
                                                                      'Title',           '',           ...
                                                                      'SourceTable',     emptyTable,   ...
                                                                      'WordVariable',    'Word',       ...
                                                                      'SizeVariable',    'Count',      ...
                                                                      'MaxDisplayWords', 25);
            end
            drawnow
        end

        %-----------------------------------------------------------------%
        function DeleteCanvas(obj)
            switch obj.Algorithm
                case 'D3.js'
                    sendEventToHTMLSource(obj.jsBackDoor, 'eraseWordCloud');
                case 'MATLAB built-in'
                    if isa(obj.Chart, 'matlab.graphics.chart.WordCloudChart') && isvalid(obj.Chart)
                        delete(obj.Chart.Parent)
                    end
            end
        end

        %-----------------------------------------------------------------%
        function TableUpdate(obj, Table)
            switch obj.Algorithm
                case 'D3.js'
                    if ~isempty(Table)
                        sendEventToHTMLSource(obj.jsBackDoor, 'drawWordCloud', struct('words', Table.Word, 'weights', Table.Count));
                    else
                        sendEventToHTMLSource(obj.jsBackDoor, 'eraseWordCloud');
                    end

                case 'MATLAB built-in'
                    if isempty(Table)
                        Table = EmptyTable(obj);
                    end
                    obj.Chart.SourceTable = Table;
            end
        end
    end
end