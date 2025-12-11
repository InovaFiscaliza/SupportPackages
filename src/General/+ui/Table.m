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
    end

end