classdef tableFiltering < handle

    properties
        %-----------------------------------------------------------------%
        filterRules = table( ...
            'Size', [0, 6], ...
            'VariableTypes', {'cell', 'cell', 'cell', 'cell', 'cell', 'logical'}, ...
            'VariableNames', {'Hash', 'Field', 'Operators', 'Values', 'Connector', 'Enable'} ...
        )
    end


    properties (Constant)
        %-----------------------------------------------------------------%
        floatDiffTolerance = 1e-5
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
        function addFilterRule(obj, Field, Operators, Values, Connector)
            arguments
                obj 
                Field     (1,:) char
                Operators (1,:) cell
                Values    (1,:) cell
                Connector (1,:) char
            end

            hash = Hash.base64encode(sprintf('%s - %s - %s - %s', Field, strjoin(Operators, '+'), strjoin(cellfun(@string, Values), '+'), Connector));
            if ismember(hash, obj.filterRules.("Hash"))
                error('Filter already exists')
            end

            obj.filterRules(end+1,:) = {hash, Field, {Operators}, {Values}, Connector, true};
            obj.filterRules = sortrows(obj.filterRules, 'Field');
        end


        %-----------------------------------------------------------------%
        function removeFilterRule(obj, idx)
            obj.filterRules(idx, :) = [];
        end


        %-----------------------------------------------------------------%
        function toogleFilterRule(obj, enableArray)
            obj.filterRules.Enable = enableArray;
        end


        %-----------------------------------------------------------------%
        function filterList = getFilterList(obj, baseName, status)
            arguments
                obj
                baseName
                status char {mustBeMember(status, {'all', 'on'})} = 'all'
            end
            filterList = {};

            switch status
                case 'all'
                    fRules = obj.filterRules;
                case 'on'
                    fRules = obj.filterRules(obj.filterRules.Enable, :);
            end

            for ii = 1:height(fRules)
                Field     = fRules.Field{ii};
                Operators = fRules.Operators{ii};
                Values    = fRules.Values{ii};
                Connector = lower(fRules.Connector{ii});

                for jj = 1:numel(Operators)
                    if jj == 1
                        filterList{ii} = sprintf('%s.("%s") %s %s', baseName, Field, Operators{jj}, stringifyFilterValue(obj, Values{jj}));
                    else
                        switch Connector
                            case 'and'
                                operatorSymbol = '&&';
                            case 'or'
                                operatorSymbol = '||';
                        end
                        filterList{ii} = sprintf('%s %s %s.("%s") %s %s', filterList{ii}, operatorSymbol, baseName, Field, Operators{jj}, stringifyFilterValue(obj, Values{jj}));
                    end
                end
            end
        end
    end


    methods (Access = private)
        %-----------------------------------------------------------------%
        function value = stringifyFilterValue(obj, value)
            if isnumeric(value)
                if isscalar(value)
                    value = string(value);
                else
                    value = sprintf('[%s]', strjoin(string(value), ', '));
                end
            elseif iscellstr(value)
                value = textFormatGUI.cellstr2ListWithQuotes(value);
            else
                value = sprintf('"%s"', value);
            end
        end


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
        function fLogicalIndex = rulesOrientedFiltering(obj, rawTable)            
            fRules  = obj.filterRules(obj.filterRules.Enable, :);
            tHeight = height(rawTable);

            if isempty(fRules)
                fLogicalIndex = ones(tHeight, 1, 'logical');
            
            else
                [fieldNames, ~, fieldIndexes] = unique(fRules.Field);
                numFields = numel(fieldNames);
                fLogical  = zeros(tHeight, numFields, 'logical');

                for ii = 1:numFields
                    idx = find(fieldIndexes == ii)';
                    
                    for jj = idx
                        Field     = fRules.Field{jj};
                        Operators = fRules.Operators{jj}; % cell
                        Values    = fRules.Values{jj};    % cell
                        Connector = lower(fRules.Connector{jj});

                        for kk = 1:numel(Operators)
                            Fcn = functionHandle(obj, Operators{kk}, Values{kk});

                            if kk == 1
                                fTempLogical = Fcn(rawTable{:, Field});
                            else
                                switch Connector
                                    case 'and'
                                        fTempLogical = and(fTempLogical, Fcn(rawTable{:, Field}));
                                    case 'or'
                                        fTempLogical =  or(fTempLogical, Fcn(rawTable{:, Field}));
                                end
                            end
                        end

                        fLogical(:,ii) = or(fLogical(:,ii), fTempLogical);
                    end
                end

                fLogicalIndex = all(fLogical, 2);
            end
        end


        %-----------------------------------------------------------------%
        function Fcn = functionHandle(obj, Operator, Value)
            if isnumeric(Value) || isdatetime(Value)
                floatTolerance = obj.floatDiffTolerance;

                switch Operator
                    case '='
                        Fcn = @(x) abs(x - Value) < floatTolerance;
                    case '≠'
                        Fcn = @(x) abs(x - Value) > floatTolerance;
                    case {'⊃', 'contains'}
                        Fcn = @(x)  ismember(x, Value);
                    case {'⊅', 'does not contain'}
                        Fcn = @(x) ~ismember(x, Value);
                    case '<'
                        Fcn = @(x) x <  Value;
                    case '≤'
                        Fcn = @(x) x <= Value;
                    case '>'
                        Fcn = @(x) x >  Value;
                    case '≥'
                        Fcn = @(x) x >= Value;
                    case '><'
                        Fcn = @(x) (x > Value(1)) & (x < Value(2));
                    case '<>'
                        Fcn = @(x) (x < Value(1)) | (x > Value(2));
                    otherwise
                        error('UnexpectedOperation')
                end
        
            elseif ischar(Value) || isstring(Value) || iscellstr(Value)
                Value = cellstr(Value);

                switch Operator
                    case '='
                        Fcn = @(x) strcmpi(cellstr(x), Value);                    
                    case '≠'
                        Fcn = @(x) ~strcmpi(cellstr(x), Value);                    
                    case {'⊃', 'contains'}
                        Fcn = @(x) contains(cellstr(x), Value, 'IgnoreCase', true);
                    case {'⊅', 'does not contain'}
                        Fcn = @(x) ~contains(cellstr(x), Value, 'IgnoreCase', true);                    
                    case 'begins with'
                        Fcn = @(x) startsWith(cellstr(x), Value, 'IgnoreCase', true);
                    case 'does not begin with'
                        Fcn = @(x) ~startsWith(cellstr(x), Value, 'IgnoreCase', true);                    
                    case 'ends with'
                        Fcn = @(x) endsWith(cellstr(x), Value, 'IgnoreCase', true);
                    case 'does not end with'
                        Fcn = @(x) ~endsWith(cellstr(x), Value, 'IgnoreCase', true);
                    otherwise
                        error('UnexpectedOperation')
                end

            else
                error('Unexpected filter value')
            end
        end
    end
end