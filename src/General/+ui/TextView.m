classdef (Abstract) TextView

    % Cria um textview a partir do uilabel ou uiimage (MATLAB Built-in), 
    % agregando uma borda externa, barra de rolagem na direção vertical e 
    % seleção de texto (aspectos hoje não contemplados no uilabel e uiimage).

    methods (Static = true)
        %-----------------------------------------------------------------%
        function classComponent = checkBaseComponentClass(baseComponent)
            classComponent = class(baseComponent);
            if ~ismember(classComponent, {'matlab.ui.control.Label', 'matlab.ui.control.Image'})
                error('Unexpected base component class')
            end
        end

        %-----------------------------------------------------------------%
        function startup(jsBackDoor, baseComponent, appName, varargin)
            arguments
                jsBackDoor matlab.ui.control.HTML
                baseComponent
                appName
            end

            arguments (Repeating)
                varargin
            end

            classComponent = ui.TextView.checkBaseComponentClass(baseComponent);

            numAttempt = 0;
            maxAttemps = 10;

            while true
                numAttempt = numAttempt+1;

                try
                    baseComponent.UserData.id = struct(baseComponent).Controller.ViewModel.Id;

                    switch classComponent
                        case 'matlab.ui.control.Label'        
                            sendEventToHTMLSource(jsBackDoor, 'initializeComponents', { ...
                                struct('appName',    appName,                           ...
                                       'dataTag',    baseComponent.UserData.id,         ...
                                       'generation', 1,                                 ...
                                       'class',      'textview')                        ...
                            });
        
                            sendEventToHTMLSource(jsBackDoor, 'initializeComponents', { ...
                                struct('appName',    appName,                           ...
                                       'dataTag',    baseComponent.UserData.id,         ...
                                       'generation', 2,                                 ...
                                       'style',      struct('textAlign', 'justify'))    ...
                            });

                        case 'matlab.ui.control.Image'
                            textContent = varargin{1};

                            sendEventToHTMLSource(jsBackDoor, 'initializeComponents', {                     ...
                                struct('appName',    appName,                                               ...
                                       'dataTag',    baseComponent.UserData.id,                             ...
                                       'generation', 1,                                                     ...
                                       'class',      {{'textview', 'textview--from-uiimage'}},              ...
                                       'child',      struct('dataTag', [baseComponent.UserData.id '_text'], ...
                                                            'innerHTML', textContent))                      ...
                            });
                    end
                    break

                catch
                    if numAttempt >= maxAttemps
                        break
                    end
                    pause(.050)
                end
            end
        end

        %-----------------------------------------------------------------%
        function update(baseComponent, textContent, userData, varargin)
            arguments
                baseComponent
                textContent char
                userData = []
            end

            arguments (Repeating)
                varargin
            end

            classComponent = ui.TextView.checkBaseComponentClass(baseComponent);

            switch classComponent
                case 'matlab.ui.control.Label'
                    baseComponent.Text = textContent;

                    if ~isempty(varargin)
                        baseComponentBackgroundImage = varargin{1};
                        if isempty(textContent)
                            baseComponentBackgroundImage.Visible = 1;
                        else
                            baseComponentBackgroundImage.Visible = 0;
                        end
                    end

                case 'matlab.ui.control.Image'
                    sendEventToHTMLSource(jsBackDoor, 'initializeComponents', {                  ...
                        struct('dataTag', baseComponent.UserData.id,                             ...
                               'child',   struct('dataTag', [baseComponent.UserData.id '_text'], ...
                                                 'innerHTML', textContent))                      ...
                    });
            end

            if ~isempty(userData)
                baseComponent.UserData = userData;
            end
        end
    end

end