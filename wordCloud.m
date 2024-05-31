classdef wordCloud < handle

    properties
        %-----------------------------------------------------------------%
        parent
        executionMode
        
        Chart
        SourceTable
        NumberOfWords
        Color
    end

    methods
        %-----------------------------------------------------------------%
        function obj = wordCloud(parentPanel, executionMode, NWords)
            obj.executionMode = executionMode;
            obj.NumberOfWords = NWords;

            switch executionMode
                case 'webApp'
                    htmlFile   = fullfile(Path(obj), 'wordCloud', 'sourceCode.html');

                    obj.parent = uigridlayout(parentPanel, [1,1]);
                    obj.Chart  = uihtml(obj.parent, 'HTMLSource', htmlFile);

                otherwise % 'built-in' | 'desktopApp'
                    emptyTable = EmptyTable(obj);

                    obj.parent = tiledlayout(parentPanel, 1, 1, 'Padding', 'tight');
                    obj.Chart  = matlab.graphics.chart.WordCloudChart('Parent',          obj.parent,   ...
                                                                      'Title',           '',           ...
                                                                      'SourceTable',     emptyTable,   ...
                                                                      'WordVariable',    'Word',       ...
                                                                      'SizeVariable',    'Count',      ...
                                                                      'MaxDisplayWords', NWords,       ...
                                                                      'Units',           'normalized', ...
                                                                      'Position',        [0,0,1,1]);
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
        function set.SourceTable(obj, value)
            SourceTableUpdate(obj, value)            
        end


        %-----------------------------------------------------------------%
        function SourceTableUpdate(obj, sourceTable)
            switch obj.executionMode
                case 'webApp'
                    if ~isempty(sourceTable)
                        sendEventToHTMLSource(obj.Chart, 'drawWordCloud', struct('words', sourceTable.Word, 'weights', sourceTable.Count))
                    else
                        sendEventToHTMLSource(obj.Chart, 'eraseWordCloud')
                    end

                otherwise
                    if isempty(sourceTable)
                        sourceTable = EmptyTable(obj);
                    end
                    obj.Chart.SourceTable = sourceTable;
            end
        end


        %-----------------------------------------------------------------%
        function set.NumberOfWords(obj, value)
            NumberOfWordsUpdate(obj, value)
        end


        %-----------------------------------------------------------------%
        function NumberOfWordsUpdate(obj, nWords)
            switch obj.executionMode
                case 'webApp'
                    % pendente

                otherwise
                    obj.Chart.MaxDisplayWords = nWords;
            end
        end
    end
end