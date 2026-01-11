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
        FLOAT_COMPARISON_TOLERANCE = 1e-5

        FILTER_TYPE_MAPPING = dictionary( ...
            ["uint8", "uint16", "uint32", "uint64", "int8", "int16", "int32", "int64", "single", "double", "logical", "char", "string", "cell", "categorical", "datetime"], ...
            [repmat("numeric", 1, 10), "logical", repmat("cellstr", 1, 3), "categorical", "datetime"] ...
        )

        FILTER_SYMBOLS = dictionary( ...
            ["uint8", "uint16", "uint32", "uint64", "int8", "int16", "int32", "int64", "single", "double", "logical", "char", "string", "cell", "categorical", "datetime"], ...
            [repmat("🔢", 1, 10), "🔘", repmat("🔤", 1, 3), "🏷️", "📅"] ...
        )

        FILTER_CAPABILITIES = dictionary( ...
            ["numeric", "logical", "cellstr", "categorical", "datetime"], ...
            [ ...
                struct( ...
                    'symbol', '🔢', ...
                    'operations', {{'=', '≠', '<', '≤', '>', '≥'}} ...
                ), ...
                struct( ...
                    'symbol', '🔘', ...
                    'operations', {{'=', '≠'}} ...
                ), ...
                struct( ...
                    'symbol', '🔤', ...
                    'operations', {{ ...
                        '=', '≠', ...
                        'begins with', 'does not begin with', ...
                        'ends with', 'does not end with', ...
                        'contains', 'does not contain' ...
                    }} ...
                ), ...
                struct( ...
                    'symbol', '🏷️', ...
                    'operations', {{ ...
                        '=', '≠', ...
                        'begins with', 'does not begin with', ...
                        'ends with', 'does not end with', ...
                        'contains', 'does not contain' ...
                    }} ...
                ), ...
                struct( ...
                    'symbol', '📅', ...
                    'operations', {{'=', '≠', '<', '≤', '>', '≥'}} ...
                ) ...
            ] ...
        )
    end

    
    methods (Access = public)
        %-----------------------------------------------------------------%
        function fIndex = run(obj, filterType, varargin)
            switch filterType
                case 'wordsToSearch'
                    fIndex = tableFiltering.stringMatchFiltering(varargin{:});
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
                        filterList{ii} = sprintf('%s.("%s") %s %s', baseName, Field, Operators{jj}, tableFiltering.stringifyFilterValue(Values{jj}));
                    else
                        switch Connector
                            case {'and', 'e'}
                                operatorSymbol = '&&';
                            case {'or', 'ou'}
                                operatorSymbol = '||';
                        end
                        filterList{ii} = sprintf('%s %s %s.("%s") %s %s', filterList{ii}, operatorSymbol, baseName, Field, Operators{jj}, tableFiltering.stringifyFilterValue(Values{jj}));
                    end
                end
            end
        end
    end


    methods (Access = private)
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
                            Fcn = tableFiltering.functionHandle(Operators{kk}, Values{kk});

                            if kk == 1
                                fTempLogical = Fcn(rawTable{:, Field});
                            else
                                switch Connector
                                    case {'and', 'e'}
                                        fTempLogical = and(fTempLogical, Fcn(rawTable{:, Field}));
                                    case {'or', 'ou'}
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
    end


    methods (Static = true)
        %-----------------------------------------------------------------%
        function symbolicNames = mergedSymbolWithColumnNames(columnNames, columnTypes)
            if ~iscellstr(columnNames)
                columnNames = cellstr(columnNames);
            end

            if ~iscellstr(columnTypes)
                columnTypes = cellstr(columnTypes);
            end

            symbols = cellstr(cellfun(@(x) tableFiltering.FILTER_SYMBOLS(x), columnTypes));
            symbolicNames = strcat(symbols, {' '}, columnNames);
        end

        %-----------------------------------------------------------------%
        function pseudoClasses = getPseudoClasses(columnTypes)
            pseudoClasses = cellstr(cellfun(@(x) tableFiltering.FILTER_TYPE_MAPPING(x), columnTypes));
        end

        %-----------------------------------------------------------------%
        function [operations, symbol] = getFilterCapabilities(pseudoClass)
            caps = tableFiltering.FILTER_CAPABILITIES;
    
            if isKey(caps, pseudoClass)
                entry      = caps(pseudoClass);
                operations = entry.operations;
                symbol     = entry.symbol;                
            else
                error('Unsupported column class: %s', pseudoClass);
            end
        end

        %-----------------------------------------------------------------%
        function value = stringifyFilterValue(value)
            if isnumeric(value) || islogical(value)
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
        function matchedRows = stringMatchFiltering(unfilteredTable, filterColumns, sortOrder, searchFunction, wordsToSearch)
            cellData = unfilteredTable{:, filterColumns};
            numWordsToSearch = numel(wordsToSearch);

            switch sortOrder
                case 'stable'
                    if numWordsToSearch < 150
                        switch searchFunction
                            case 'strcmp'
                                indexes = cellfun(@(x) find(any(strcmp(cellData, x), 2)),   wordsToSearch, 'UniformOutput', false);
                            case 'contains'
                                indexes = cellfun(@(x) find(any(contains(cellData, x), 2)), wordsToSearch, 'UniformOutput', false);
                        end
                        
                    else
                        indexes = cell(1, numWordsToSearch);
                        parpoolCheck()
                        parfor ii = 1:numWordsToSearch
                            switch searchFunction
                                case 'strcmp'
                                    indexes{ii} = find(any(strcmp(cellData,   wordsToSearch{ii}), 2));
                                case 'contains'
                                    indexes{ii} = find(any(contains(cellData, wordsToSearch{ii}), 2));
                            end
                        end
                    end        
                    matchedRows = unique(vertcat(indexes{:}), 'stable');

                case 'unstable'
                    switch searchFunction
                        case 'strcmp'
                            matchedRows = find(any(ismember(cellData, wordsToSearch), 2));
                        case 'contains'
                            matchedRows = find(any(contains(cellData, wordsToSearch), 2));
                    end
            end
        end

        %-----------------------------------------------------------------%
        function fcn = functionHandle(operator, value)
            if isnumeric(value) || isdatetime(value)
                floatTolerance = tableFiltering.FLOAT_COMPARISON_TOLERANCE;

                switch operator
                    case '='
                        fcn = @(x) abs(x - value) < floatTolerance;
                    case '≠'
                        fcn = @(x) abs(x - value) > floatTolerance;
                    case {'⊃', 'contains'}
                        fcn = @(x)  ismember(x, value);
                    case {'⊅', 'does not contain'}
                        fcn = @(x) ~ismember(x, value);
                    case '<'
                        fcn = @(x) x <  value;
                    case '≤'
                        fcn = @(x) x <= value;
                    case '>'
                        fcn = @(x) x >  value;
                    case '≥'
                        fcn = @(x) x >= value;
                    case '><'
                        fcn = @(x) (x > value(1)) & (x < value(2));
                    case '<>'
                        fcn = @(x) (x < value(1)) | (x > value(2));
                    otherwise
                        error('Unsupported operator: %s', operator);
                end

            elseif islogical(value)
                switch operator
                    case '='
                        fcn = @(x) x == value;
                    case '≠'
                        fcn = @(x) x ~= value;
                    otherwise
                        error('Unsupported operator: %s', operator);
                end
        
            elseif ischar(value) || isstring(value) || iscellstr(value) || iscategorical(value)
                value = cellstr(value);

                switch operator
                    case '='
                        fcn = @(x) strcmpi(cellstr(x), value);                    
                    case '≠'
                        fcn = @(x) ~strcmpi(cellstr(x), value);                    
                    case {'⊃', 'contains'}
                        fcn = @(x) contains(cellstr(x), value, 'IgnoreCase', true);
                    case {'⊅', 'does not contain'}
                        fcn = @(x) ~contains(cellstr(x), value, 'IgnoreCase', true);                    
                    case 'begins with'
                        fcn = @(x) startsWith(cellstr(x), value, 'IgnoreCase', true);
                    case 'does not begin with'
                        fcn = @(x) ~startsWith(cellstr(x), value, 'IgnoreCase', true);                    
                    case 'ends with'
                        fcn = @(x) endsWith(cellstr(x), value, 'IgnoreCase', true);
                    case 'does not end with'
                        fcn = @(x) ~endsWith(cellstr(x), value, 'IgnoreCase', true);
                    otherwise
                        error('Unsupported operator: %s', operator);
                end

            else
                error('Unexpected filter value')
            end
        end
    end

end