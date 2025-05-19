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
    end

end