classdef tableFiltering < handle

    properties
        %-----------------------------------------------------------------%
        filterRules table = table('Size',          [0, 4],                              ...
                                  'VariableTypes', {'cell', 'cell', 'cell', 'logical'}, ...
                                  'VariableNames', {'Column', 'Operation', 'Value', 'Enable'})
    end


    properties (Constant)
        %-----------------------------------------------------------------%
        floatDiffTolerance  = 1e-5
    end

    
    methods
        %-----------------------------------------------------------------%
        function fIndex = run(obj, filterType, varargin)
            switch filterType
                case 'words2Search'
                    fIndex = stringMatchFiltering(obj, varargin{:});
                case 'filterRules'
                    fIndex = rulesOrientedFiltering(obj, varargin{:});
            end
        end


        %-----------------------------------------------------------------%
        function msgWarning = addFilterRule(obj, Column, Operation, Value)
            fHeight  = height(obj.filterRules);
            fLogical = ones(fHeight, 3, 'logical');

            fLogical(:,1) = strcmp(obj.filterRules.Column,    Column);
            fLogical(:,2) = strcmp(obj.filterRules.Operation, Operation);
            fLogical(:,3) = cellfun(@(x) isequal(x, Value), obj.filterRules.Value);

            if (fHeight == 0) || ~any(all(fLogical, 2))
                if ~ischar(Value)
                    Value = {Value};
                end
                obj.filterRules(end+1,:) = {Column, Operation, Value, true};
                obj.filterRules = sortrows(obj.filterRules, 'Column');
                msgWarning = '';
            else
                msgWarning = 'O conjunto Coluna-Operação-Valor já consta na lista de filtros secundários.';
            end
        end


        %-----------------------------------------------------------------%
        function msgWarning = removeFilterRule(obj, idx)
            try
                obj.filterRules(idx,:) = [];
                msgWarning = '';
            catch ME
                msgWarning = ME.message;
            end
        end


        %-----------------------------------------------------------------%
        function filterList = FilterList(obj, baseName)
            configValue = {};
            for ii = 1:height(obj.filterRules)
                Value = obj.filterRules.Value{ii};

                if isnumeric(Value)
                    configValue{ii,1} = sprintf('[%s]', strjoin(string(Value), ', '));

                elseif iscellstr(Value)
                    configValue{ii,1} = textAnalysis.cellstrGUIStyle(Value);

                else %ischar(Value)
                    configValue{ii,1} = sprintf('"%s"', Value);
                end
            end
            
            filterList = cellstr(string(baseName) + ".(""" + string(obj.filterRules.Column) + """) " + string(obj.filterRules.Operation) + " " + string(configValue));
        end
    end


    methods (Access = private)
        %-----------------------------------------------------------------%
        function fIndex = stringMatchFiltering(obj, varargin)
            rawTable       = varargin{1};
            columnNames    = varargin{2};
            rawCell        = rawTable{:,columnNames};
            
            sortOrder      = varargin{3};
            searchFunction = varargin{4};
            words2Search   = varargin{5};
            nWords2Search  = numel(words2Search);

            switch sortOrder
                case 'stable'
                    if nWords2Search < 150
                        switch searchFunction
                            case 'strcmp'
                                listOfIndex = cellfun(@(x) find(any(strcmp(rawCell, x), 2)),   words2Search, 'UniformOutput', false);
                            case 'contains'
                                listOfIndex = cellfun(@(x) find(any(contains(rawCell, x), 2)), words2Search, 'UniformOutput', false);
                        end
                        
                    else
                        listOfIndex = cell(1, nWords2Search);
                        parpoolCheck()
                        parfor ii = 1:nWords2Search
                            switch searchFunction
                                case 'strcmp'
                                    listOfIndex{ii} = find(any(strcmp(rawCell,   words2Search{ii}), 2));
                                case 'contains'
                                    listOfIndex{ii} = find(any(contains(rawCell, words2Search{ii}), 2));
                            end
                        end
                    end        
                    fIndex = unique(vertcat(listOfIndex{:}), 'stable');

                case 'unstable'
                    switch searchFunction
                        case 'strcmp'
                            fIndex = find(any(ismember(rawCell, words2Search), 2));
                        case 'contains'
                            fIndex = find(any(contains(rawCell, words2Search), 2));
                    end
            end
        end


        %-----------------------------------------------------------------%
        function fLogicalIndex = rulesOrientedFiltering(obj, varargin)
            rawTable = varargin{1};
            
            tHeight = height(rawTable);            
            fRules  = obj.filterRules(obj.filterRules.Enable, :);
            
            if isempty(fRules)
                fLogicalIndex = ones(tHeight, 1, 'logical');
            
            else
                [columnNames, ~, columnIndex] = unique(obj.filterRules.Column);
                nColumns = numel(columnNames);
                fLogical = zeros(tHeight, nColumns, 'logical');

                for ii = 1:nColumns
                    idx = find(columnIndex == ii)';
                    for jj = idx
                        Fcn = functionHandle(obj, fRules.Operation{jj}, fRules.Value{jj});
                        fLogical(:,ii) = or(fLogical(:,ii), Fcn(rawTable{:, fRules.Column{jj}}));
                    end
                end

                fLogicalIndex = all(fLogical, 2);
            end
        end


        %-----------------------------------------------------------------%
        function Fcn = functionHandle(obj, Operation, Value)
            if isnumeric(Value) || isdatetime(Value)
                floatTolerance = obj.floatDiffTolerance;

                switch Operation
                    case '=';  Fcn = @(x) abs(x - Value) < floatTolerance;
                    case '≠';  Fcn = @(x) abs(x - Value) > floatTolerance;
                    case '⊃';  Fcn = @(x)  ismember(x, Value);
                    case '⊅';  Fcn = @(x) ~ismember(x, Value);
                    case '<';  Fcn = @(x) x <  Value;
                    case '≤';  Fcn = @(x) x <= Value;
                    case '>';  Fcn = @(x) x >  Value;
                    case '≥';  Fcn = @(x) x >= Value;
                    case '><'; Fcn = @(x) (x > Value(1)) & (x < Value(2));
                    case '<>'; Fcn = @(x) (x < Value(1)) | (x > Value(2));
                end
        
            elseif ischar(Value) || isstring(Value) || iscellstr(Value)
                Value = cellstr(Value);

                switch Operation
                    case '=';  Fcn = @(x)   strcmpi(cellstr(x), Value);
                    case '≠';  Fcn = @(x)  ~strcmpi(cellstr(x), Value);
                    case '⊃';  Fcn = @(x)  contains(cellstr(x), Value, 'IgnoreCase', true);
                    case '⊅';  Fcn = @(x) ~contains(cellstr(x), Value, 'IgnoreCase', true);
                end

            else
                error('Unexpected filter value')
            end
        end
    end
end