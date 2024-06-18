classdef wordCloud < handle

    properties
        %-----------------------------------------------------------------%
        Algorithm        
        Chart
        Table
    end

    methods
        %-----------------------------------------------------------------%
        function obj = wordCloud(parentPanel, executionMode)
            obj.Algorithm = executionMode;

            switch obj.Algorithm
                case 'D3.js'
                    htmlFile   = fullfile(Path(obj), 'wordCloud', 'Container.html');

                    parentGrid = uigridlayout(parentPanel, [1,1], 'BackgroundColor', [1,1,1]);
                    obj.Chart  = uihtml(parentGrid, 'HTMLSource', htmlFile);

                case 'MATLAB built-in'
                    emptyTable = EmptyTable(obj);

                    parentGrid = tiledlayout(parentPanel, 1, 1, 'Padding', 'tight');
                    obj.Chart  = matlab.graphics.chart.WordCloudChart('Parent',          parentGrid,   ...
                                                                      'Title',           '',           ...
                                                                      'SourceTable',     emptyTable,   ...
                                                                      'WordVariable',    'Word',       ...
                                                                      'SizeVariable',    'Count',      ...
                                                                      'MaxDisplayWords', 25);
            end
        end


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
        function set.Table(obj, value)
            TableUpdate(obj, value)            
        end


        %-----------------------------------------------------------------%
        function TableUpdate(obj, Table)
            switch obj.Algorithm
                case 'D3.js'
                    if ~isempty(Table)
                        sendEventToHTMLSource(obj.Chart, 'drawWordCloud', struct('words', Table.Word, 'weights', Table.Count))
                    else
                        sendEventToHTMLSource(obj.Chart, 'eraseWordCloud')
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