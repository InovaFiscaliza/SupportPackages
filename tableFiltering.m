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
                msgWarning = '';

                if isnumeric(Value)
                    Value = num2cell(Value);
                end
                obj.Config(end+1,:) = {Column, Operation, Value, true};
            else
                msgWarning = 'The Column-Operation-Value set has already been inserted into the filter list.';
            end
        end



        %-----------------------------------------------------------------%
        function fLogical = execute(obj, Table)
            
            tHeight = height(Table);
            
            fConfig = obj.Config(obj.Config.Enable, :);
            fHeight = height(fConfig);
            
            if isempty(fConfig)
                fLogical = ones(tHeight, 1, 'logical');
            
            else
                fLogical = zeros(tHeight, fHeight, 'logical');
        
                for ii = 1:fHeight
                    Fcn = functionHandle(obj, fConfig.Operation{ii}, fConfig.Value{ii});
                    fLogical(:,ii) = Fcn(Table{:, fConfig.Column{ii}});
                end

                fLogical = any(fLogical, 2);
            end
        end
        
        
        %-------------------------------------------------------------------------%
        function Fcn = functionHandle(obj, Operation, Value)
            if isnumeric(Value)
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
                    case '=';  Fcn = @(x)   strcmpi(x, Value);
                    case '≠';  Fcn = @(x)  ~strcmpi(x, Value);
                    case '⊃';  Fcn = @(x)  contains(x, Value, 'IgnoreCase', true);
                    case '⊅';  Fcn = @(x) ~contains(x, Value, 'IgnoreCase', true);
                end

            else
                error('Unexpected filter value')
            end
        end
    end
end