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
                            classList = {'textview'};
                            if ~isempty(varargin) && isstruct(varargin{1}) && isfield(varargin{1}, 'class')
                                classList = [classList, varargin{1}.class];
                            end

                            sendEventToHTMLSource(jsBackDoor, 'initializeComponents', { ...
                                struct('appName',    appName,                           ...
                                       'dataTag',    baseComponent.UserData.id,         ...
                                       'generation', 1,                                 ...
                                       'class',      {classList})                       ...
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
                                       'class',      {{'textview', 'textview-from-uiimage'}},              ...
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
                    jsBackDoor = varargin{1};
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

        %-----------------------------------------------------------------%
        % O MATLAB pode apresentar lentidão caso seja atualizado de forma 
        % frequente a propriedade "Text" de um uilabel. Para evitar isso, 
        % manipula-se o DOM diretamente, alterando o seu "innerHTML". Esse
        % approach pode ser adotado apenas se a propriedade "Text" não for 
        % essencial. 
        % 
        % Por exemplo, via "Text", 12409742 de caracteres são renderizados 
        % em 55 seg. Esse valor é reduzido para 8 seg quando atualização via
        % jsBackDoor.
        %-----------------------------------------------------------------%
        function setLabelInnerHTMLBypassingText(jsBackDoor, baseComponent, innerHTML)
            sendEventToHTMLSource(jsBackDoor, 'changeTextViewContent', ...
                struct('dataTag', baseComponent.UserData.id, 'innerHTML', innerHTML) ...
            );
        end

        %-----------------------------------------------------------------%
        % Cria um link HTML que, quando clicado, dispara um evento no MATLAB. O 
        % evento é tratado por meio de método público "ipcMainJSEventHandler", caso 
        % se trate do "mainApp", ou "ipcSecondaryJSEventsHandler", caso se trate de
        % um "secondaryApp". 
        %------------------------------------------------------------------%
        function htmlLink = createHTMLLink(linkType, appHandleNameInBase, eventName, varargin)
            arguments
                linkType {mustBeMember(linkType, {'link', 'question', 'edit', 'customText', 'customImage'})}
                appHandleNameInBase
                eventName
            end

            arguments (Repeating)
                varargin
            end

            try
                appRole = struct(evalin('base', appHandleNameInBase)).Role;
                switch appRole
                    case 'mainApp'
                        ipcJSEventHandlerName = 'ipcMainJSEventsHandler';    
                    case 'secondaryApp'
                        ipcJSEventHandlerName = 'ipcSecondaryJSEventsHandler';    
                    otherwise
                        error('ui:TextView:UnexpectedAppRole', 'Unexpected app role "%s"', appRole)
                end
            catch ME
                rethrow(ME)
            end

            switch linkType
                case 'link'
                    linkInnerHTML = '&#x1F517;'; % '🔗'
                case 'question'
                    linkInnerHTML = '&#x2753;'; % '❓'
                case 'edit'
                    linkInnerHTML = '&#x270F;&#xFE0F;'; % '✏️'
                case 'customText'
                    linkInnerHTML = varargin{1};
                case 'customImage'
                    imageFileName = varargin{1};
                    generalSettings = varargin{2};
                    resourceURL = replace(generalSettings.AppVersion.application.resourceStaticURL, '{resourceName}', imageFileName);
                    linkInnerHTML = sprintf('<img class="vc-imageIcon" src="%s" draggable="false" ondragstart="return false;" data-dojo-attach-point="iconNode" tabindex="-1" width="18" height="18">', resourceURL);
            end

            htmlLink = sprintf('<a href="matlab:evalin(''base'', ''%s(%s, struct(''''HTMLEventName'''', ''''%s''''))'')">%s</a>', ipcJSEventHandlerName, appHandleNameInBase, eventName, linkInnerHTML);
        end
    end

end