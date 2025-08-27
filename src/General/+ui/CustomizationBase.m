classdef (Abstract) CustomizationBase

    % A customização dos elementos por meio de "compCustomization.js" é
    % possível apenas se forem conhecidos os seus identificadores únicos -
    % "data-tag" (ou "dataset.tag", via JS).

    % ToDo:
    % Migrar compononentCustomization.js para essa subpasta. Organizar
    % métodos relacionados...

    methods (Static = true)
        %-----------------------------------------------------------------%
        % function htmlSource = jsBackDoorHTMLSource()
        %     htmlSource = fullfile(fileparts(mfilename('fullpath')), 'jsBackDoor', 'Container.html');
        % end

        %-----------------------------------------------------------------%
        function [elDataTag, attempts] = getElementsDataTag(elToModify)
            elDataTag = {};
            attempts  = 0;
            
            timeout   = 10;
            fcnHandle = @(x) struct(x).Controller.ViewModel.Id;

            tStart = tic;
            while toc(tStart) < timeout
                attempts = attempts+1;
                pause(0.025)

                try
                    elDataTag = cellfun(@(x) fcnHandle(x), elToModify, 'UniformOutput', false);
                    for ii = 1:numel(elToModify)
                        elToModify{ii}.UserData.id = elDataTag{ii};
                    end
                    break
                catch
                end
            end
        end

        %-----------------------------------------------------------------%
        function propHandle = getPropertyHandle(app, propName, auxAppTag)
            arguments
                app
                propName
                auxAppTag string = ""
            end

            propHandle = [];

            if ~isempty(auxAppTag)
                if isprop(app, 'tabGroupController')
                    idxAuxApp  = app.tabGroupController.Components.Tag == auxAppTag;
                    hAuxApp    = app.tabGroupController.Components.appHandle{idxAuxApp};
    
                    if isprop(hAuxApp, propName)
                        propHandle = hAuxApp.(propName);
                    end
                end
            end

            if isempty(propHandle) && isprop(app, propName)
                propHandle = app.(propName);
            end
        end

        %-----------------------------------------------------------------%
        function propName = getPropertyName(elHandle, auxAppTag)
            arguments
                elHandle
                auxAppTag string = ""
            end

            fig = ancestor(elHandle, 'figure');
            app = fig.RunningAppInstance;
            propName = ui.CustomizationBase.findMatchingProperty(elHandle, app);

            if isempty(propName) && isprop(app, 'tabGroupController')
                idxAuxApp = app.tabGroupController.Components.Tag == auxAppTag;
                hAuxApp   = app.tabGroupController.Components.appHandle{idxAuxApp};
                propName  = ui.CustomizationBase.findMatchingProperty(elHandle, hAuxApp);
            end
        end

        %-----------------------------------------------------------------%
        function propName = findMatchingProperty(elHandle, app)
            props = properties(app);
            propName = '';            
            
            for ii = 1:numel(props)
                if isequal(app.(props{ii}), elHandle)
                    propName = props{ii};
                    return;
                end
            end
        end
    end

end