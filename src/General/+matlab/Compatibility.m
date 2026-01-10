classdef (Abstract) Compatibility

    methods (Static = true)
        %-----------------------------------------------------------------%
        function variableTypes = resolveTableVariableTypes(t)
            arguments
                t table
            end
            
            props = t.Properties;
        
            if isprop(t.Properties, 'VariableTypes')
                variableTypes = cellstr(props.VariableTypes);
            else
                variableTypes = varfun(@class, t, 'OutputFormat', 'cell');
            end
        end
    end

end