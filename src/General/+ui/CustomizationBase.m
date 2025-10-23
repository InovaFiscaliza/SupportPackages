classdef (Abstract) CustomizationBase

    % A customização dos elementos por meio de "compCustomization.js" é
    % possível apenas se forem conhecidos os seus identificadores únicos -
    % "data-tag" (ou "dataset.tag", via JS).

    % ToDo:
    % Migrar componentCustomization.js para essa subpasta. Organizar
    % métodos relacionados...

    methods (Static = true)
        %-----------------------------------------------------------------%
        % function htmlSource = jsBackDoorHTMLSource()
        %     htmlSource = fullfile(fileparts(mfilename('fullpath')), 'jsBackDoor', 'Container.html');
        % end

        %-----------------------------------------------------------------%
        function elDataTag = getElementsDataTag(elToModify)
            fcnHandle = @(x) struct(x).Controller.ViewModel.Id;

            timeout = 10;
            tStart = tic;
            while toc(tStart) < timeout
                pause(0.025)

                try
                    elDataTag = {};
                    for ii = 1:numel(elToModify)
                        if isvalid(elToModify{ii})
                            if isempty(elToModify{ii}.UserData) || ~isfield(elToModify{ii}.UserData, 'id') || isempty(elToModify{ii}.UserData.id)
                                elToModify{ii}.UserData.id = fcnHandle(elToModify{ii});
                            end
                            elDataTag{ii} = elToModify{ii}.UserData.id;
                        else
                            elDataTag{ii} = '';
                        end
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