classdef (Abstract) Compatibility

    methods (Static = true)
        %-----------------------------------------------------------------%
        function variableTypes = resolveTableVariableTypes(t, detectCellstr)
            arguments
                t table
                detectCellstr = true
            end
            
            props = t.Properties;
        
            if isprop(t.Properties, 'VariableTypes')
                variableTypes = cellstr(props.VariableTypes);
            else
                variableTypes = varfun(@class, t, 'OutputFormat', 'cell');
            end

            if detectCellstr
                cellColumnIndexes = find(strcmp(variableTypes, 'cell'));
                for columnIndex = cellColumnIndexes
                    if iscellstr(t{:, columnIndex})
                        variableTypes{columnIndex} = 'cellstr';
                    end
                end
            end
        end
    end

end