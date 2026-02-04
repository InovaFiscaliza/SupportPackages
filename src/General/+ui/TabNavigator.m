classdef TabNavigator < handle

    % Trata-se de classe que relaciona o TabGroup principal de um app com 
    % o menu gráfico que o controla. Para que essa classe seja operacional,
    % devem ser seguidas algumas premissas:

    % - O Grid que contém os botões de estado deve possuir, nas suas duas
    %   últimas colunas, imagem que possibilitam fechar um app auxiliar
    %   (caso aberto no modo DOCK) ou mudar o modo de visualização do app
    %   auxiliar em evidência de DOCK para UNDOCK. Opcionalmente, esses
    %   imagens podem estar em um grid auxiliar com TAG "MenuSubGrid".

    % - Cada botão de estado deve possuir um único TAG.
    
    % - Os arquivos .MLAPP dos apps auxiliares devem ser exportados em arquivos
    %   .M, seguindo métrica estabelecida em "preCompile.m".
    
    % - A primeira aba do TabGroup deve conter um módulo construído
    %   diretamente no app principal. Dessa forma, essa primeira aba não
    %   pode ser container para um app secundário.

    properties
        %-----------------------------------------------------------------%
        Components    table = table('Size',          [0, 9],                                                                                                ...
                                    'VariableNames', {'Tag', 'Type', 'File', 'appHandle', 'btnHandle', 'btnStatus', 'btnIcon', 'btnRefHandle', 'tabIndex'}, ...
                                    'VariableTypes', {'string', 'categorical', 'string', 'cell', 'matlab.ui.control.StateButton', 'categorical', 'struct', 'matlab.ui.control.StateButton', 'double'})
        inlineSVG = false
    end


    properties (Access = private)
        %-----------------------------------------------------------------%
        UIFigure      matlab.ui.Figure
        MenuGrid      matlab.ui.container.GridLayout
        MenuSubGrid
        TabGroup      matlab.ui.container.TabGroup
        progressDialog
        executionMode
        jsBackDoor
    end


    methods
        %-----------------------------------------------------------------%
        function obj = TabNavigator(menuGrid, tabGroup, progressDialog)
            obj.UIFigure        = ancestor(menuGrid, 'figure');
            obj.MenuGrid        = menuGrid;
            obj.TabGroup        = tabGroup;
            obj.executionMode   = obj.UIFigure.RunningAppInstance.executionMode;
            obj.progressDialog  = progressDialog;
            obj.MenuSubGrid     = findobj(menuGrid.Children, 'Tag', 'MenuSubGrid');

            % Delimitar os valores que são aceitos em algumas das colunas.
            obj.Components.Type = categorical(obj.Components.Type, {'Built-in', 'External'});
            obj.Components.btnStatus = categorical(obj.Components.btnStatus, {'AlwaysOn', 'On/Off'});
            obj.Components.btnIcon   = struct('On', {}, 'Off', {});
        end

        %-----------------------------------------------------------------%
        function addComponent(obj, auxAppType, auxAppFile, btnHandle, btnStatus, btnIcon, btnRefHandle, tabIndex)
            auxAppTag = btnHandle.Tag;

            if ~ismember(auxAppTag, obj.Components.Tag)
                obj.Components(end+1, [1:3, 5:end]) = {auxAppTag,    ...
                                                       auxAppType,   ...
                                                       auxAppFile,   ...
                                                       btnHandle,    ...
                                                       btnStatus,    ...
                                                       btnIcon,      ...
                                                       btnRefHandle, ...
                                                       tabIndex};
            end
        end

        %-----------------------------------------------------------------%
        function convertToInlineSVG(obj, jsBackDoor)
            obj.inlineSVG = true;
            obj.jsBackDoor = jsBackDoor;

            listOfButtons = obj.Components.btnHandle';
            tabConfig = struct( ...
                'operation', 'convertToInlineSVG', ...
                'buttons', struct('dataTag', {}, 'value', {}, 'svgContent', {}) ...
            );

            for btn = listOfButtons
                tabConfig.buttons(end+1) = struct('dataTag', btn.UserData.id, 'value', btn.Value, 'svgContent', fileread(btn.Icon));
            end
            sendEventToHTMLSource(obj.jsBackDoor, 'tabNavigator', tabConfig);
        end

        %-----------------------------------------------------------------%
        function openModule(obj, clickedButton, clickedButtonPreviousValue, appGeneral, varargin)
            % Inicialmente, verifica se o botão, que já estava ativado, foi 
            % clicado novamente. Neste caso, apenas mantém o estado ativo do 
            % botão.
            if clickedButtonPreviousValue
                clickedButton.Value = true;
                return
            end

            % Verifica se o app auxiliar está aberto por meio da validade do 
            % handle. Caso sim, apenas coloca-se em evidência a figura do app 
            % secundário (caso aberto no modo UNDOCK), ou da aba específica 
            % (caso aberto no modo DOCK).
            [~, idx]  = ismember(clickedButton, obj.Components.btnHandle);
            appHandle = obj.Components.appHandle{idx};
            tabIndex  = obj.Components.tabIndex(idx);
            nonClickedButtons = findobj(obj.MenuGrid, 'Type', 'uistatebutton', '-not', 'Tag', clickedButton.Tag);

            if ~isempty(appHandle) && isvalid(appHandle) 
                if appHandle.isDocked
                    switchingMode(obj, clickedButton, nonClickedButtons, tabIndex, 20)
                else
                    clickedButton.Value = false;
                    figure(appHandle.UIFigure)
                end
                return
            end            
            
            switch obj.Components.Type(idx)
                case 'Built-in'
                    switchingMode(obj, clickedButton, nonClickedButtons, tabIndex, 0)                  

                case 'External'
                    obj.progressDialog.Visible = 'visible';

                    FileHandle_MLAPP = eval(sprintf('@%s',          obj.Components.File(idx)));
                    FileHandle_MFILE = eval(sprintf('@%s_exported', obj.Components.File(idx)));

                    if appGeneral.operationMode.Dock                        
                        obj.Components.appHandle{idx} = FileHandle_MFILE(obj.TabGroup.Children(tabIndex), varargin{:});
                        switchingMode(obj, clickedButton, nonClickedButtons, tabIndex, 20)

                    else
                        if ~isempty(obj.MenuSubGrid)
                            obj.MenuSubGrid.ColumnWidth(end-1:end) = {0, 0};
                        end
                        clickedButton.Value = false;
                        
                        if appGeneral.operationMode.Debug
                            obj.Components.appHandle{idx} = FileHandle_MLAPP(varargin{:});
                        else
                            obj.Components.appHandle{idx} = FileHandle_MFILE([], varargin{:});
                        end
                    end

                    obj.progressDialog.Visible = 'hidden';
            end            
            drawnow
        end

        %-----------------------------------------------------------------%
        function closeModule(obj, auxAppTags, appGeneral, operationType)
            arguments
                obj 
                auxAppTags string
                appGeneral struct
                operationType char {mustBeMember(operationType, {'normal', 'undock'})} = 'normal'
            end

            obj.progressDialog.Visible = 'visible';

            for ii = 1:numel(auxAppTags)
                [~, idx]  = ismember(auxAppTags(ii), obj.Components.Tag);
                if ~idx
                    continue
                end

                appHandle = obj.Components.appHandle{idx};
                btnHandle = obj.Components.btnHandle(idx);    
                if obj.Components.btnStatus(idx) == "On/Off"
                    btnHandle.Enable = 0;
                end

                if strcmp(operationType, 'undock')
                    btnHandle.Value = 1;
                end
        
                if btnHandle.Value
                    btnRefHandle = obj.Components.btnRefHandle(idx);
    
                    if ~btnRefHandle.Enable
                        [~, idxRefButton]  = find(obj.Components.tabIndex == 1, 1);
                        btnRefHandle = obj.Components.btnHandle(idxRefButton);
                    end
    
                    btnRefHandle.Value = 1;
                    openModule(obj, btnRefHandle, false, appGeneral)
                end

                deleteContextMenu(obj, obj.UIFigure, obj.Components.File{idx})
                
                if strcmp(operationType, 'normal')
                    deletePopUpContainer(obj, appHandle)
                    delete(appHandle)
                    obj.Components.appHandle{idx} = [];
                end
            end

            obj.progressDialog.Visible = 'hidden';
        end

        %-----------------------------------------------------------------%
        function deletePopUpContainer(obj, appHandle)
            if ~isempty(appHandle) && isprop(appHandle, 'popupContainer') && ~isempty(appHandle.popupContainer) && isvalid(appHandle.popupContainer)
                auxDockAppName = appHandle.popupContainer.UserData.auxDockAppName;
                deleteContextMenu(obj, appHandle.UIFigure, auxDockAppName)
                delete(appHandle.popupContainer.Parent)
            end
        end

        %-----------------------------------------------------------------%
        function deleteContextMenu(obj, hFigure, contextMenuTag)
            contextMenuHandle = findobj(hFigure.Children, 'Type', 'uicontextmenu', 'Tag', contextMenuTag);
            if ~isempty(contextMenuHandle)
                delete(contextMenuHandle)
            end
        end

        %-----------------------------------------------------------------%
        function appHandle = getAppHandle(obj, auxAppTag)
            [~, idx]  = ismember(auxAppTag, obj.Components.Tag);
            appHandle = obj.Components.appHandle{idx};
        end

        %-----------------------------------------------------------------%
        function [idx, appTag, btnHandle] = getAppInfoFromHandle(obj, auxAppHandle)
            idx       = find(cellfun(@(x) isequal(auxAppHandle, x), obj.Components.appHandle));
            appTag    = obj.Components.Tag{idx};
            btnHandle = obj.Components.btnHandle(idx);
        end

        %-----------------------------------------------------------------%
        function [status, appHandle] = checkStatusModule(obj, auxAppTag)
            appHandle = getAppHandle(obj, auxAppTag);
            status = ~isempty(appHandle) && isvalid(appHandle);
        end

        %-----------------------------------------------------------------%
        function delete(obj)
            cellfun(@(x) delete(x), obj.Components.appHandle)
        end
    end


    methods (Access = private)
        %-----------------------------------------------------------------%
        function switchingMode(obj, clickedButton, nonClickedButtons, tabIndex, dockControlWidth)
            changingButtonsIcon(obj, clickedButton, nonClickedButtons)
            obj.TabGroup.SelectedTab = obj.TabGroup.Children(tabIndex);
            
            if ~isempty(obj.MenuSubGrid)
                switch obj.executionMode
                    case 'webApp'
                        obj.MenuSubGrid.ColumnWidth(end-1:end) = {0, dockControlWidth};
                    otherwise
                        obj.MenuSubGrid.ColumnWidth(end-1:end) = {dockControlWidth, dockControlWidth};
                end
            end
        end

        %-----------------------------------------------------------------%
        function changingButtonsIcon(obj, clickedButton, nonClickedButtons)
            listOfButtons = [clickedButton; nonClickedButtons]';

            if obj.inlineSVG
                tabConfig = struct( ...
                    'operation', 'setIconColor', ...
                    'buttons', struct('dataTag', {}, 'value', {}) ...
                );
    
                for btn = listOfButtons
                    if btn ~= clickedButton
                        btn.Value = false;
                    end
                    tabConfig.buttons(end+1) = struct('dataTag', btn.UserData.id, 'value', btn.Value);
                end    
                sendEventToHTMLSource(obj.jsBackDoor, 'tabNavigator', tabConfig);

            else
                for btn = listOfButtons
                    [~, idx] = ismember(btn, obj.Components.btnHandle);
                    switch btn
                        case clickedButton
                            set(btn, 'Icon', obj.Components.btnIcon(idx).On)
                        otherwise
                            set(btn, 'Icon', obj.Components.btnIcon(idx).Off, 'Value', 0)
                    end
                end
            end
        end
    end
end