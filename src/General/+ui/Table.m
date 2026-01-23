classdef (Abstract) Table

    methods (Static = true)
        %-----------------------------------------------------------------%
        % Esta função exporta o handle de um app construído no AppDesigner
        % para o workspace "base". Ideia é possibilitar que expressões 
        % executadas por hyperlinks em uitables possam chamar métodos do
        % app.
        %-----------------------------------------------------------------%
        function varName = exportAppHandleToBaseWorkspace(app)
            baseVars = evalin('base', 'who');
            varName  = matlab.lang.makeUniqueStrings('app', baseVars);
            assignin('base', varName, app);
        end

        %-----------------------------------------------------------------%
        % Remove do workspace base a variável que armazena o handle do app,
        % liberando a referência e evitando conflitos após o app ser fechado.
        %-----------------------------------------------------------------%
        function deleteAppHandleFromBaseWorkspace(varName)
            evalin('base', ['clear ', varName]);
        end

        %-----------------------------------------------------------------%
        % Esta função identifica se a tabela a ser apresentada em um uitable
        % pode ser customizada em relação ao seu formato.
        %-----------------------------------------------------------------%
        function status = hasCustomizableColumnFormat(t)
            arguments
                t table
            end

            columnTypes = matlab.Compatibility.resolveTableVariableTypes(t);
            allowedTypes = {
                'cellstr', ... % 'char'
                'logical', ... 
                'uint8','uint16','uint32','uint64', ...
                'int8','int16','int32','int64', ...
                'single','double' ...
            };

            status = all(ismember(columnTypes, allowedTypes));
        end
    end

end