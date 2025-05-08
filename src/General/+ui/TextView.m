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
        function startup(jsBackDoor, baseComponent, varargin)
            arguments
                jsBackDoor matlab.ui.control.HTML
                baseComponent
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
                                struct('dataTag',    baseComponent.UserData.id,         ...
                                       'generation', 1,                                 ...
                                       'class',      'textview')                        ...
                            });
        
                            sendEventToHTMLSource(jsBackDoor, 'initializeComponents', { ...
                                struct('dataTag',    baseComponent.UserData.id,         ...
                                       'generation', 2,                                 ...
                                       'style',      struct('textAlign', 'justify'))    ...
                            });

                        case 'matlab.ui.control.Image'
                            textContent = varargin{1};

                            sendEventToHTMLSource(jsBackDoor, 'initializeComponents', {                     ...
                                struct('dataTag',    baseComponent.UserData.id,                             ...
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
        function update(baseComponent, textContent)
            arguments
                baseComponent
                textContent char
            end

            classComponent = ui.TextView.checkBaseComponentClass(baseComponent);

            switch classComponent
                case 'matlab.ui.control.Label'
                    baseComponent.Text = textContent;

                case 'matlab.ui.control.Image'
                    sendEventToHTMLSource(jsBackDoor, 'initializeComponents', {                  ...
                        struct('dataTag', baseComponent.UserData.id,                             ...
                               'child',   struct('dataTag', [baseComponent.UserData.id '_text'], ...
                                                 'innerHTML', textContent))                      ...
                    });
            end
        end
    end

end