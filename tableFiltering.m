classdef tableFiltering < handle

    properties
        %-----------------------------------------------------------------%
        Config = table('Size',          [0, 4],                              ...
                       'VariableTypes', {'cell', 'cell', 'cell', 'logical'}, ...
                       'VariableNames', {'Column', 'Operation', 'Value', 'Enable'})
    end


    properties (Constant)
        %-----------------------------------------------------------------%
        floatDiffTolerance  = 1e-5
    end

    
    methods
        %-----------------------------------------------------------------%
        function msgWarning = addFilter(obj, Column, Operation, Value)


            fHeight  = height(obj.Config);
            fLogical = ones(fHeight, 3, 'logical');

            fLogical(:,1) = strcmp(obj.Config.Column,    Column);
            fLogical(:,2) = strcmp(obj.Config.Operation, Operation);
            fLogical(:,3) = cellfun(@(x) isequal(x, Value), obj.Config.Value);

            if (fHeight == 0) || ~any(all(fLogical, 2))
                if ~ischar(Value)
                    Value = {Value};
                end
                obj.Config(end+1,:) = {Column, Operation, Value, true};
                obj.Config = sortrows(obj.Config, 'Column');
                msgWarning = '';
            else
                msgWarning = 'O conjunto Coluna-Operação-Valor já consta na lista de filtros secundários.';
            end
        end


        %-----------------------------------------------------------------%
        function msgWarning = removeFilter(obj, idx)
            try
                obj.Config(idx,:) = [];
                msgWarning = '';
            catch ME
                msgWarning = ME.message;
            end
        end


        %-----------------------------------------------------------------%
        function fLogical = execute(obj, Table)
            
            tHeight = height(Table);            
            fConfig = obj.Config(obj.Config.Enable, :);
            
            if isempty(fConfig)
                fLogical = ones(tHeight, 1, 'logical');
            
            else
                [columnNames, ~, columnIndex] = unique(obj.Config.Column);
                NN = numel(columnNames);

                fLogical = zeros(tHeight, NN, 'logical');
        
                for ii = 1:NN
                    idx = find(columnIndex == ii)';
                    for jj = idx
                        Fcn = functionHandle(obj, fConfig.Operation{jj}, fConfig.Value{jj});
                        fLogical(:,ii) = or(fLogical(:,ii), Fcn(Table{:, fConfig.Column{jj}}));
                    end
                end

                fLogical = all(fLogical, 2);
            end
        end
        
        
        %-------------------------------------------------------------------------%
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