classdef fiscalizaGUI < fiscalizaLib

    properties
        BackgroundColor (1,3) {mustBeInRange(BackgroundColor, 0, 1)} = [1,1,1]
    end


    properties (Access = private)
        %-----------------------------------------------------------------%
        hFigure
        hGrid
        hGridRow

        fields2Render
        fields2Ignore  = {'precisa_reservar_instrumentos', '0',   'precisa_reservar_instrumentos'; ...
                          'utilizou_algum_instrumento',    '0',   'utilizou_algum_instrumento';    ...
                          'ha_outras_fontes_interfer',     'Não', 'foi_constatada_interferencia'}
        fields2Integer = {'horas_de_preparacao'   ...
                          'horas_de_deslocamento' ...
                          'horas_de_execucao'     ...
                          'horas_de_conclusao'    ...
                          'qtd_de_emissoes'       ...
                          'qtd_identificadas'     ...
                          'qtd_licenciadas'       ...
                          'qnt_produt_lacradosapreend'}
        
        fieldsTriggerJSEffect = {}
        fieldsTriggedJSEffect = {}

        reportFilePath = ''
        autoFillStruct
        
        jsBackDoor
        progressDialog
    end


    methods
        %-----------------------------------------------------------------%
        function obj = fiscalizaGUI(userName, userPass, testFlag, hGrid, issueNumber)
            arguments
                userName    (1,:) char
                userPass    (1,:) char
                testFlag    (1,1) logical
                hGrid       (1,1) matlab.ui.container.GridLayout
                issueNumber (1,1) {mustBeInteger, mustBePositive}
            end

            if ~isvalid(hGrid)
                error('Grid component is not valid!')
            end

            obj = obj@fiscalizaLib(userName, userPass, testFlag);
            
            obj.hFigure = ancestor(hGrid, 'figure');
            obj.hGrid = hGrid;

            jsBackDoorInitialization(obj)
            progressDialogInitialization(obj)

            try
                getIssue(obj, issueNumber)
                Data2GUI(obj)
            catch ME
                UIAlert(obj, ME.message, 'error')
            end
        end


        %-----------------------------------------------------------------%
        function RefreshGUI(obj)
            refreshIssue(obj)
            Data2GUI(obj)
        end


        %-----------------------------------------------------------------%
        function UploadFiscaliza(obj)
            [status, guiData] = GUI2Data(obj);
            
            if status
                if ~isempty(guiData)
                    msg = char(updateIssue(obj, guiData));
                    obj.reportFilePath = '';
                    Data2GUI(obj)
                else
                    msg = 'Não identificada edição de campo da Inspeção';
                end
                
                UIAlert(obj, msg, 'warning')
            end
        end


        %-----------------------------------------------------------------%
        function Data2GUI(obj)
            % Validações iniciais:
            msg = '';
            if isempty(obj.issueID)
                msg = 'The "getIssue" method must be called before the "Data2GUI" method.';
            else
                if isfield(obj.issueInfo, 'tracker')
                    if ~strcmp(obj.issueInfo.tracker, 'Atividade de Inspeção')
                        msg = sprintf('A <i>issue</i> nº %s não é uma "Atividade de Inspeção", mas uma "%s".', obj.issueID, obj.issueInfo.tracker); 
                    end
                end
    
                if isfield(obj.issueInfo, 'status')
                    if ~ismember(obj.issueInfo.status, {'Rascunho', 'Aguardando Execução', 'Em andamento', 'Relatando'})
                        msg = sprintf('A Inspeção nº %s está no estado "%s", o que impede a atualização por meio desta lib.', obj.issueID, obj.issueInfo.status); 
                    end
                end
            end           

            if ~isempty(msg)
                UIAlert(obj, msg, 'error')
                return
            end

            % Identificando os campos a renderizar em tela:
            obj.fields2Render = struct(getPythonAttribute(obj, obj.Issue, 'editable_fields'));
            obj.fieldsTriggerJSEffect = fieldnames(struct(getPythonAttribute(obj, obj.Issue, 'conditional_fields')));

            % Renderizando os elementos (após a reinicialização da GUI):
            GridInitialization(obj, true)
            
            renderComponents(obj, 'TITLE');
            renderComponents(obj, 'GENERAL');
            renderComponents(obj, 'HOURS');
            renderComponents(obj, 'REPORT')
            renderComponents(obj, 'OTHERS_EDITABLE_FIELDS');
            addJSListenerEffect(obj)
            drawnow

            % Customizando alguns dos elementos:
            hTextArea = findobj(obj.hGrid, 'Type', 'uitextarea');
            arrayfun(@(x) ccTools.compCustomizationV2(obj.jsBackDoor, x, 'textAlign', 'justify'), hTextArea)
        end


        %-----------------------------------------------------------------%
        function [status, guiData] = GUI2Data(obj)
            status  = true;
            guiData = readDataFromComponents(obj);

            % Avaliar se o campo "html_path" está preenchido, o que acarretará na 
            % criação de um novo documento no SEI.
            if isfield(guiData, 'html_path')
                HTMLDocFullPath = guiData.html_path;

                if isfile(HTMLDocFullPath)
                    [filePath, fileName, fileExt] = fileparts(HTMLDocFullPath);

                    % Avalia se existe um nº SEI de outro relatório...
                    % nesse caso, questionar usuário se quer continuar, o
                    % que fará 
                    if ~strcmpi(fileExt, '.html')
                        error('O documento a ser submetido ao FISCALIZA precisa ser no formato "HTML".')
                        
                    elseif isfield(obj.issueInfo, 'no_sei_relatorio_de_atividades') && isfield(obj.issueInfo.no_sei_relatorio_de_atividades, 'numero') && ~isempty(obj.issueInfo.no_sei_relatorio_de_atividades.numero)
                        obj.progressDialog.Visible = 'hidden';

                        msgQuestion = sprintf('A Inspeção nº %s já está relacionado ao Relatório de Atividades SEI nº %s.\n\nCaso seja submetido ao FISCALIZA o arquivo abaixo, o FISCALIZA criará no SEI um novo documento.\n• %s\n\nDeseja continuar?', obj.issueID, obj.issueInfo.no_sei_relatorio_de_atividades.numero, [fileName fileExt]);
                        selection   = uiconfirm(obj.hFigure, HTMLSyntax(obj, msgQuestion), '', 'Interpreter', 'html', 'Options', {'Sim', 'Não'}, 'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'question');

                        if strcmp(selection, 'Não')
                            status = false;
                            return
                        end

                        obj.progressDialog.Visible = 'visible';
                    end

                    % Trigger para criação do relatório...
                    guiData.gerar_relatorio = '1';

                    % Agora avalia os arquivos que serão anexados à issue...
                    % Eles precisam ter o mesmo nome do que o HTML, mas extensão 
                    % diferente.
                    fileList = dir(fullfile(filePath, [fileName '.*']));

                    uploads = {};
                    for ii = 1:numel(fileList)
                        [~, ~, fileListExt] = fileparts(fileList(ii).name);
                        if all(~strcmpi(fileListExt, {'.html', '.mat'}))
                            uploads{end+1} = struct('path', fullfile(fileList(ii).folder, fileList(ii).name), 'filename', fileList(ii).name);
                        end
                    end

                    if ~isempty(uploads)
                        guiData.uploads = uploads;
                    end

                else
                    guiData = rmfield(guiData, 'html_path');
                end
            end

            % Atualiza relação de campos de guiData, haja vista a possível
            % exclusão de campos nos passos anteriores de validação...
            fieldNames = fieldnames(guiData);
            if isempty(fieldNames)
                error('Não identificada alteração em algum dos campos da Inspeção nº %s', obj.issueID)
            end

            % Por fim, os campos ignorados - atualmente "precisa_reservar_instrumentos"
            % e "utilizou_algum_instrumento" - são relatados com os seus valores padrões,
            % caso estejam vazios.
            field2IgnoreName         = obj.fields2Ignore(:,1);
            field2IgnoreDefaultValue = obj.fields2Ignore(:,2);
            field2IgnoreTrigger      = obj.fields2Ignore(:,3);

            for kk = 1:numel(field2IgnoreName)
                fieldTrigger = field2IgnoreTrigger{kk};

                if (isfield(obj.issueInfo, fieldTrigger) && isempty(obj.issueInfo.(fieldTrigger))) || ...
                        (isfield(guiData, fieldTrigger) && ismember(guiData.(fieldTrigger), {'1', 'Sim'}))
                    guiData.(field2IgnoreName{kk}) = field2IgnoreDefaultValue{kk};
                end
            end
        end


        %-----------------------------------------------------------------%
        function AutoFillFields(obj, newData, recurrenceIndex)
            fieldNames   = fieldnames(newData);
            hComponents  = FindComponents(obj);

            if recurrenceIndex == 1
                obj.fieldsTriggedJSEffect = {};
            end

            JSEffectFlag = false;
            
            for ii = 1:numel(fieldNames)
                hComponent = findobj(hComponents, 'Tag', fieldNames{ii});
                if ~isempty(hComponent)
                    setComponentFieldValue(obj, hComponent, newData.(fieldNames{ii}))
                    
                    if ismember(fieldNames{ii}, setdiff(obj.fieldsTriggerJSEffect, obj.fieldsTriggedJSEffect))
                        JSEffectFlag = true;
                        obj.fieldsTriggedJSEffect = [obj.fieldsTriggedJSEffect; fieldNames{ii}];
                    end
                end
            end

            if JSEffectFlag
                Listener(obj, [], [], 'JSEffect')
                AutoFillFields(obj, newData, recurrenceIndex+1)
            end
        end


        %-----------------------------------------------------------------%
        function currentUser = getCurrentUser(obj)
            try
                currentUser = char(getPythonAttribute(obj, obj.Issue, 'current_user'));
            catch
                currentUser = '';
            end
        end


        %-----------------------------------------------------------------%
        function GridInitialization(obj, placeHolderFlag)
            if placeHolderFlag
                hPlaceHolder = findobj(obj.hFigure, 'Type', 'uiimage', 'Tag', 'FiscalizaPlaceHolder');
                if ~isempty(hPlaceHolder)
                    set(hPlaceHolder, 'Parent', obj.hFigure, 'Visible', 0)
                end
            end

            if ~isempty(obj.hGrid.Children)
                delete(setdiff(obj.hGrid.Children, findobj(obj.hFigure, 'Type', 'uiimage', 'Tag', 'FiscalizaPlaceHolder')))
            end
            set(obj.hGrid, 'RowHeight', {'1x'}, 'ColumnWidth', {'1x'}, 'RowSpacing', 5, 'Scrollable', 'on', 'BackgroundColor', [1,1,1])

            obj.hGridRow = 0;
        end


        %-----------------------------------------------------------------%
        function set.BackgroundColor(obj, value)
            obj.BackgroundColor = value;
            backGroundUpdate(obj, value)
        end
    end


    methods (Access = protected)
        %-----------------------------------------------------------------%
        function renderComponents(obj, groupName)
            switch groupName
                case 'TITLE'
                    preBuiltGroup_TITLE(obj);
                case 'GENERAL'
                    preBuiltGroup_GENERAL(obj);
                case 'HOURS'
                    preBuiltGroup_HOURS(obj);
                case 'REPORT'
                    preBuiltGroup_REPORT(obj);
                case 'OTHERS_EDITABLE_FIELDS'
                    OthersEditableFields(obj);
            end
        end


        %-----------------------------------------------------------------%
        function preBuiltGroup_TITLE(obj)
            titleFields = {'id', 'status', 'subject', 'author', 'atualizacao'};
            titleValues = FieldInfo(obj, titleFields, 'cellstr');
            titleText   = sprintf(['<h2 style="display: inline-flex; font-size: 16px;">Inspeção nº %.0f <font style="display: inline-block; font-size: 10px; ' ...
                                   'text-transform: uppercase; color: #0065ff;">%s</font></h2><p style="font-size: 12px;">%s<p style="font-size: 10px; '     ...
                                   'color: gray; text-align: justify; padding: 0px 2px 0px 0px;">Criada por %s. %s.</p></p>'], titleValues{:});

            % Componentes:
            obj.hGridRow = obj.hGridRow + 1;
            obj.hGrid.RowHeight(obj.hGridRow) = {72};

            Label(obj, obj.hGrid, titleText, {'left', 'top'}, 1, 'black', 'html', strjoin(titleFields,','), obj.hGridRow, 1)
        end


        %-----------------------------------------------------------------%
        function preBuiltGroup_GENERAL(obj)
            containerSettings = struct('Height',      {{17, 198}},       ...
                                       'Label',       'Aspectos gerais', ...
                                       'Interpreter', 'none',            ...
                                       'Image',       'Link_18.png',     ...
                                       'ImageTag',    'no_fiscaliza_issue,no_sei_processo_fiscalizacao');

            typeFields = {'tema', 'subtema'};
            typeValues = FieldInfo(obj, typeFields, 'cellstr');
            typeText   = sprintf('%s\n%s', typeValues{:});
            
            % Componentes:
            hContainer = Container(obj, containerSettings);
            hGridGroup = GridLayout(obj, hContainer, {22, 22, 17, 22, 17, '1x'}, {'1x', '1x'}, [10,10,10,5]);            

            Label(obj, hGridGroup, typeText,          {'right', 'top'},    10, [.5,.5,.5], 'none', strjoin(typeFields,','), [1 2], [1 2])
            Label(obj, hGridGroup, 'Tipo:',           {'left',  'bottom'}, 11, [0,0,0],    'none', '',                      1,      1)
            Label(obj, hGridGroup, 'Data de início:', {'left',  'bottom'}, 11, [0,0,0],    'none', '',                      3,      1)
            Label(obj, hGridGroup, 'Data limite:',    {'left',  'bottom'}, 11, [0,0,0],    'none', '',                      3,      2)
            Label(obj, hGridGroup, 'Descrição:',      {'left',  'bottom'}, 11, [0,0,0],    'none', '',                      5,     [1 2])
        
            DropDown(obj,   hGridGroup, 'tipo_de_inspecao', 2, [1 2])
            DatePicker(obj, hGridGroup, 'start_date',       4, 1)
            DatePicker(obj, hGridGroup, 'due_date',         4, 2)
            TextArea(obj,   hGridGroup, 'description',      6, [1 2])
        end
        
        
        %-----------------------------------------------------------------%
        function preBuiltGroup_HOURS(obj)
            containerSettings = struct('Height',      {{28, 42}},                                                                                                                         ...
                                       'Label',       {{'Estimativas de horas:'; '<font style="font-size: 10px; color: #808080;">Preparação | Deslocamento | Execução | Conclusão</font>'}}, ...
                                       'Interpreter', 'html');

            % Componentes:
            hContainer = Container(obj, containerSettings);
            hGridGroup = GridLayout(obj, hContainer, {22}, {'1x', '1x', '1x', '1x'}, [10,10,10,10]);

            EditField(obj, hGridGroup, 'horas_de_preparacao',   [0, inf], 1, 1)
            EditField(obj, hGridGroup, 'horas_de_deslocamento', [0, inf], 1, 2)
            EditField(obj, hGridGroup, 'horas_de_execucao',     [0, inf], 1, 3)
            EditField(obj, hGridGroup, 'horas_de_conclusao',    [0, inf], 1, 4)
        end


        %-----------------------------------------------------------------%
        function preBuiltGroup_REPORT(obj)
            containerSettings = struct('Height',      {{17, 110}}, ...
                                       'Label',       'Documento', ...
                                       'Interpreter', 'none');

            % Componentes:
            hContainer = Container(obj, containerSettings);
            hGridGroup = GridLayout(obj, hContainer, {17,22,17,22}, {110,'1x',20}, [10,10,10,5]);

            Label(obj, hGridGroup, 'Nº SEI:',    {'left', 'bottom'}, 11, [0,0,0], 'none', '', 1, 1)
            Label(obj, hGridGroup, 'Arquivo:',   {'left', 'bottom'}, 11, [0,0,0], 'none', '', 3, 1)

            EditField(obj, hGridGroup, 'no_sei_relatorio_de_atividades', [], 2, 1)
            set(findobj(hGridGroup, 'Tag', 'no_sei_relatorio_de_atividades'), 'Editable', 0)
            
            EditField(obj, hGridGroup, 'html_path', [], 4, [1,2])
            set(findobj(hGridGroup, 'Type', 'uieditfield', 'Tag', 'html_path'), 'Value', obj.reportFilePath)

            Image(obj, hGridGroup, 'html_path', 4, 3, 'OpenFile_18.png', {'center', 'center'}, 'GetFileImage')
        end


        %-----------------------------------------------------------------%
        function OthersEditableFields(obj)            
            % Editable fields (fields2Render property)
            editableFields = obj.fields2Render;
            editableFieldsNames = setStackOrder(obj, editableFields);

            % Renderizable fields:
            renderizedComp      = findobj(obj.hGrid, '-not', {'Type', 'uigridlayout', '-or', 'Type', 'uipanel', '-or', 'Type', 'uiimage'});
            renderizedComp(cellfun(@(x) isempty(x), {renderizedComp.Tag})) = [];
            renderizedFields    = strsplit(strjoin({renderizedComp.Tag}, ','), ',');            
        
            for ii = 1:numel(editableFieldsNames)
                fieldName  = editableFieldsNames{ii};
                if ismember(fieldName, [renderizedFields'; obj.fields2Ignore(:,1)])
                    continue
                end
        
                try
                    fieldClass = class(editableFields.(fieldName));        
                    switch fieldClass
                        case {'py.fiscaliza.datatypes.AtomicField', 'py.fiscaliza.datatypes.SimpleField', 'py.fiscaliza.datatypes.EncodedString'}
                            AtomicOrSimpleFields(obj, editableFields, fieldName);
        
                        case 'py.fiscaliza.datatypes.FieldWithOptions'
                            FieldWithOptions(obj, editableFields, fieldName);

                        otherwise
                            error('Unexpected field class "%s"', fieldClass)
                    end
        
                catch ME
                    fprintf('%s - %s\n', fieldName, ME.message)
                end
            end
        end


        %-----------------------------------------------------------------%
        function addJSListenerEffect(obj)
            hComponents = FindComponents(obj);

            for ii = 1:numel(hComponents)
                hComponent = hComponents(ii);

                if isempty(hComponent.Tag) || ~ismember(hComponent.Tag, obj.fieldsTriggerJSEffect)
                    continue
                end

                switch hComponent.Type
                    case 'uicheckboxtree'
                        hComponent.CheckedNodesChangedFcn = @(src, evt)obj.Listener(src, evt, 'JSEffect');
                    otherwise % {'uicheckbox', 'uidatepicker', 'uidropdown', 'uieditfield', 'uitextarea'}
                        hComponent.ValueChangedFcn = @(src, evt)obj.Listener(src, evt, 'JSEffect');
                end
            end
        end
    end


    %---------------------------------------------------------------------%
    % COMPONENTES BÁSICOS
    %---------------------------------------------------------------------%
    methods (Access = private)
        %-----------------------------------------------------------------%
        function hGridLayout = GridLayout(obj, hParent, RowHeight, ColumnWidth, Padding)
            hGridLayout = uigridlayout(hParent, 'RowHeight',       RowHeight,           ...
                                                'ColumnWidth',     ColumnWidth,         ...
                                                'BackgroundColor', obj.BackgroundColor, ...
                                                'Padding',         Padding,             ...
                                                'RowSpacing',      5,                   ...
                                                'ColumnSpacing',   5);
        end


        %-----------------------------------------------------------------%
        function Label(obj, hGrid, Text, TextAlign, TextFont, TextColor, Interpreter, Tag, Row, Column)
            hLabel = uilabel(hGrid, 'Text',                Text,         ...
                                    'HorizontalAlignment', TextAlign{1}, ...
                                    'VerticalAlignment',   TextAlign{2}, ...
                                    'WordWrap',            'on',         ...
                                    'FontSize',            TextFont,     ...
                                    'FontColor',           TextColor,    ...
                                    'Interpreter',         Interpreter,  ...
                                    'Tag',                 Tag);
            hLabel.Layout.Row = Row;
            hLabel.Layout.Column = Column;
        end


        %-----------------------------------------------------------------%
        function DropDown(obj, hGrid, fieldName, Row, Column)
            [fieldValue, fieldOptions] = FieldInfo(obj, fieldName, 'normal');
            if isnumeric(fieldValue)
                fieldValue = num2str(fieldValue);
            end

            hDropDown = uidropdown(hGrid, 'FontSize',        11,           ...
                                          'BackgroundColor', [1 1 1],      ...
                                          'Items',           fieldOptions, ...
                                          'Value',           fieldValue,   ...
                                          'Tag',             fieldName);
            hDropDown.Layout.Row = Row;
            hDropDown.Layout.Column = Column;
        end


        %-----------------------------------------------------------------%
        function CheckBox(obj, hGrid, fieldName, Row, Column)
            editableFields = obj.fields2Render;

            fieldValue  = FieldInfo(obj, fieldName, 'normal');
            if isempty(fieldValue) || isequal(fieldValue, '0')
                fieldValue = false;
            elseif isequal(fieldValue, '1')
                fieldValue = true;
            end

            hCheckBox = uicheckbox(hGrid, 'FontSize', 11,         ...
                                          'Value',    fieldValue, ...
                                          'Text',     char(getPythonAttribute(obj, editableFields.(fieldName), 'name')), ...
                                          'Tag',      fieldName);
            hCheckBox.Layout.Row = Row;
            hCheckBox.Layout.Column = Column;
        end


        %-----------------------------------------------------------------%
        function DatePicker(obj, hGrid, fieldName, Row, Column)
            fieldValue  = FieldInfo(obj, fieldName, 'normal');

            hDatePicker = uidatepicker(hGrid, 'DisplayFormat', 'dd/MM/yyyy',                                      ...
                                              'FontSize',      11,                                                ...
                                              'Value',         datetime(fieldValue, 'InputFormat', 'yyyy-MM-dd'), ...
                                              'Tag',           fieldName);
            hDatePicker.Layout.Row = Row;
            hDatePicker.Layout.Column = Column;
        end


        %-----------------------------------------------------------------%
        function Image(obj, hGrid, fieldName, Row, Column, ImageFile, ImageAlign, ImageCallback)
            MFilePath = fileparts(mfilename('fullpath'));
            hImage    = uiimage(hGrid, 'HorizontalAlignment', ImageAlign{1},                                                 ...
                                       'VerticalAlignment',   ImageAlign{2},                                                 ...
                                       'ImageSource',         fullfile(MFilePath, 'resources', 'fiscalizaGUI', ImageFile),   ...
                                       'ImageClickedFcn',     @(src, evt)obj.Listener(src, evt, ImageCallback),              ...
                                       'Tag',                 fieldName);
            hImage.Layout.Row = Row;
            hImage.Layout.Column = Column;
        end


        %-----------------------------------------------------------------%
        function TextArea(obj, hGrid, fieldName, Row, Column)
            fieldValue = FieldInfo(obj, fieldName, 'normal');

            hTextArea  = uitextarea(hGrid, 'FontSize', 11,         ...
                                           'Value',    fieldValue, ...
                                           'Tag',      fieldName);
            hTextArea.Layout.Row = Row;
            hTextArea.Layout.Column = Column;
        end


        %-----------------------------------------------------------------%
        function EditField(obj, hGrid, fieldName, fieldLimits, Row, Column)
            fieldValue = FieldInfo(obj, fieldName, 'normal');
            fieldValue = checkIfNumericField(obj, fieldName, fieldValue);

            % Criada exceção para alguns campos, como "no_sei_processo_fiscalizacao", 
            % para o qual a lib retorna como uma string uma estrutura.
            % "{'numero': '53554.000003/2024-29', 'link_acesso': 'https://seihm.anatel.gov.br/sei/controlador.php?acao=procedimento_trabalhar&id_procedimento=1981673'}"
            if isstruct(fieldValue)
                fieldsList = fieldnames(fieldValue);
                fieldValue = fieldValue.(fieldsList{1});
            end

            if isnumeric(fieldValue)
                if isempty(fieldValue)
                    fieldValue = 0;
                end

                if isinteger(fieldValue)
                    fieldValue = double(fieldValue);
                    fieldRound  = 'on';
                    fieldFormat = '%.0f';
                else
                    fieldRound  = 'off';
                    fieldFormat = '%.3f';
                end

                hEditFields = uieditfield(hGrid, 'numeric', 'Limits',                fieldLimits, ...
                                                            'RoundFractionalValues', fieldRound,  ...
                                                            'ValueDisplayFormat',    fieldFormat, ...
                                                            'FontSize',              11,          ...
                                                            'Value',                 fieldValue,  ...
                                                            'Tag',                   fieldName);
            else
                hEditFields = uieditfield(hGrid, 'text',    'FontSize',              11,         ...
                                                            'Value',                 fieldValue, ...
                                                            'Tag',                   fieldName);
            end
            hEditFields.Layout.Row = Row;
            hEditFields.Layout.Column = Column;
        end


        %-----------------------------------------------------------------%
        function Tree(obj, hGrid, fieldName, fieldValue, fieldOptions, Row)
            hTree = uitree(hGrid, 'checkbox', 'FontSize', 11, 'Tag', fieldName);
            hTree.Layout.Row = Row;

            if isempty(fieldOptions)
                for ii = 1:numel(fieldValue)
                    childNode = uitreenode(hTree, 'Text', fieldValue{ii});
                    hTree.CheckedNodes = [hTree.CheckedNodes; childNode];
                end

            else
                for ii = 1:numel(fieldOptions)
                    childNode = uitreenode(hTree, 'Text', fieldOptions{ii});
                    if ismember(fieldOptions{ii}, fieldValue)
                        hTree.CheckedNodes = [hTree.CheckedNodes; childNode];
                    end
                end
            end
        end
    end


    %---------------------------------------------------------------------%
    % MISCELÂNEAS
    %---------------------------------------------------------------------%
    methods (Access = private)
        %-----------------------------------------------------------------%
        function backGroundUpdate(obj, value)
            hGridLayout = findobj(obj.hGrid, 'Type', 'uigridlayout');
            set(hGridLayout, 'BackgroundColor', value)
        end


        %-----------------------------------------------------------------%
        function jsBackDoorInitialization(obj)
            hHTML = findobj(obj.hFigure, 'Type', 'uihtml', 'Tag', 'jsBackDoor');
            if ~isempty(hHTML)
                obj.jsBackDoor = hHTML;
            else
                obj.jsBackDoor = uihtml(obj.hFigure, 'HTMLSource', ccTools.fcn.jsBackDoorHTMLSource, 'Visible', 'off', 'Tag', 'jsBackDoor');
            end
        end


        %-----------------------------------------------------------------%
        function progressDialogInitialization(obj)
            hProgressDialog = ccTools.Object.findobj(obj.hFigure);
            if ~isempty(hProgressDialog)
                obj.progressDialog = hProgressDialog;
            else
                obj.progressDialog = ccTools.ProgressDialogV2(obj.jsBackDoor);
            end
        end


        %-----------------------------------------------------------------%
        function hContainer = Container(obj, containerSettings)
            obj.hGridRow = obj.hGridRow + 2;
            obj.hGrid.RowHeight(obj.hGridRow-1:obj.hGridRow) = containerSettings.Height;
        
            % Container label + optional image
            if isfield(containerSettings, 'Image')
                hGridGroup = GridLayout(obj, obj.hGrid, {'1x'}, {'1x', 16}, [0,0,0,0]);
                hGridGroup.Layout.Row = obj.hGridRow-1;
        
                Label(obj, hGridGroup, containerSettings.Label, {'left', 'bottom'}, 11, [0,0,0], containerSettings.Interpreter, '', 1, 1)
                Image(obj, hGridGroup, containerSettings.ImageTag, 1, 2, containerSettings.Image, {'center', 'bottom'}, 'ContainerImage')
                
            else
                Label(obj, obj.hGrid, containerSettings.Label, {'left', 'bottom'}, 11, [0,0,0], containerSettings.Interpreter, '', obj.hGridRow-1, 1)
            end    
        
            % Container
            hContainer = uipanel(obj.hGrid);
            hContainer.Layout.Row = obj.hGridRow;
        end
        
        
        %-----------------------------------------------------------------%
        function AtomicOrSimpleFields(obj, editableFields, fieldName)
            % Label
            obj.hGridRow = obj.hGridRow + 1;
            obj.hGrid.RowHeight{obj.hGridRow} = 17;
            Label(obj, obj.hGrid, char(getPythonAttribute(obj, editableFields.(fieldName), 'name')), {'left', 'bottom'}, 11, [0,0,0], 'none', '', obj.hGridRow, 1)

            % EditField
            obj.hGridRow = obj.hGridRow + 1;
            obj.hGrid.RowHeight{obj.hGridRow} = 22;

            EditField(obj, obj.hGrid, fieldName, [-inf inf], obj.hGridRow, 1)
        end
        
        
        %-----------------------------------------------------------------%
        function FieldWithOptions(obj, editableFields, fieldName)
            [fieldValue, fieldOptions] = FieldInfo(obj, fieldName, 'normal');
            fieldOptionsElements = numel(fieldOptions);

            obj.hGridRow = obj.hGridRow + 1;
            obj.hGrid.RowHeight{obj.hGridRow} = 17;
            Label(obj, obj.hGrid, char(getPythonAttribute(obj, editableFields.(fieldName), 'name')), {'left', 'bottom'}, 11, [0,0,0], 'none', '', obj.hGridRow, 1)
        
            if getPythonAttribute(obj, editableFields.(fieldName), 'multiple')
                if any(cellfun(@(x) isnumeric(x), fieldValue))
                    fieldValue = cellfun(@(x) num2str(x), fieldValue, 'UniformOutput', false);
                end
        
                if fieldOptionsElements && fieldOptionsElements <= 200
                    obj.hGridRow = obj.hGridRow + 1;
                    obj.hGrid.RowHeight{obj.hGridRow} = 112;            
                else
                    fieldOptions = {};

                    obj.hGridRow = obj.hGridRow + 2;
                    obj.hGrid.RowHeight(obj.hGridRow-1:obj.hGridRow) = {22, 112};
        
                    hGridGroup = GridLayout(obj, obj.hGrid, {'1x'}, {'1x', 16}, [0,0,0,0]);
                    hGridGroup.Layout.Row = obj.hGridRow-1;
            
                    uieditfield(hGridGroup, 'text', 'FontSize', 11);
                    Image(obj,  hGridGroup, fieldName, 1, 2, 'Sum_18.png', {'center', 'bottom'}, 'AddTreeNode')
                end

                Tree(obj, obj.hGrid, fieldName, fieldValue, fieldOptions, obj.hGridRow)
            
            else
                obj.hGridRow = obj.hGridRow + 1;
                obj.hGrid.RowHeight{obj.hGridRow} = 22;

                DropDown(obj, obj.hGrid, fieldName, obj.hGridRow, 1)
            end
        end


        %-----------------------------------------------------------------%
        function [fieldValue, fieldOptions] = FieldInfo(obj, fieldName, searchType)
            editableFields = obj.fields2Render;
            fieldOptions   = {};

            switch searchType
                case 'normal'
                    if isfield(editableFields, fieldName)
                        fieldValue = DataTypeMapping(obj, 'py2mat', getPythonAttribute(obj, editableFields.(fieldName), 'value'));
                        if isfield(struct(editableFields.(fieldName)), 'options')
                            fieldOptions = sort(DataTypeMapping(obj, 'py2mat', getPythonAttribute(obj, editableFields.(fieldName), 'options')));
                        end

                    elseif isfield(obj.issueInfo, fieldName)
                        fieldValue = obj.issueInfo.(fieldName);
        
                    else
                        fieldValue = '';                        
                    end

                case 'cellstr'
                    fieldValue = {};
                    for ii = 1:numel(fieldName)
                        fieldValue{ii} = obj.issueInfo.(fieldName{ii});
                        if iscellstr(fieldValue{ii})
                            fieldValue{ii} = char(fieldValue{ii});
                        end
                    end
            end
        end


        %-----------------------------------------------------------------%
        function fieldValue = checkIfNumericField(obj, fieldName, fieldValue)
            if ismember(fieldName, obj.fields2Integer)
                if ~isnumeric(fieldValue)
                    fieldValue = int32(str2double(fieldValue));
                end
            end
        end


        %-----------------------------------------------------------------%
        function hComponents = FindComponents(obj)
            hComponents = findobj(obj.hGrid, 'Type', 'uicheckbox',         '-or', ...
                                             'Type', 'uicheckboxtree',     '-or', ...
                                             'Type', 'uidatepicker',       '-or', ...
                                             'Type', 'uidropdown',         '-or', ...
                                             'Type', 'uieditfield',        '-or', ...
                                             'Type', 'uinumericeditfield', '-or', ...
                                             'Type', 'uitextarea');
        end


        function [fieldValue, trimFlag] = getComponentFieldValue(obj, hComponent)
            trimFlag = false;
            switch hComponent.Type
                case 'uicheckbox'
                    if hComponent.Value
                        fieldValue = '1';
                    else
                        fieldValue = '0';
                    end

                case 'uicheckboxtree'
                    if ~isempty(hComponent.CheckedNodes)
                        fieldValue = {hComponent.CheckedNodes.Text};
                    else
                        fieldValue = {};
                    end

                case 'uidatepicker'
                    fieldValue = datestr(hComponent.Value, 'yyyy-mm-dd');

                case {'uidropdown', 'uinumericeditfield'}
                    fieldValue = hComponent.Value;

                case 'uieditfield'
                    fieldValue = strtrim(hComponent.Value);
                    trimFlag   = true;

                case 'uitextarea'
                    fieldValue = strtrim(strjoin(hComponent.Value, '\n'));
                    trimFlag   = true;

                otherwise
                    error('Unexpexted value.')
            end
        end


        %-----------------------------------------------------------------%
        function setComponentFieldValue(obj, hComponent, newFieldValue)
            hComponent.BackgroundColor = [0.84, 0.91, 0.97];

            switch hComponent.Type
                case {'uicheckbox', 'uidatepicker', 'uidropdown', 'uinumericeditfield', 'uieditfield', 'uitextarea'}
                    fieldValueClass = class(hComponent.Value);
                    switch fieldValueClass
                        case 'char'
                            if isnumeric(newFieldValue)
                                newFieldValue = num2str(newFieldValue);
                            end
                        case 'double'
                            if ~isnumeric(newFieldValue)
                                newFieldValue = str2double(newFieldValue);
                            end
                    end
                    hComponent.Value = newFieldValue;

                case 'uicheckboxtree'
                    for ii = 1:numel(newFieldValue)
                        idx = [];
                        if ~isempty(hComponent.Children)
                            idx = find(strcmp({hComponent.Children.Text}, newFieldValue{ii}), 1);
                        end
    
                        if ~isempty(idx)
                            hComponent.CheckedNodes = [hComponent.CheckedNodes; hComponent.Children(idx)];
                        else
                            childNode = uitreenode(hComponent, 'Text', newFieldValue{ii});
                            hComponent.CheckedNodes = [hComponent.CheckedNodes; childNode];
                        end
                    end

                otherwise
                    error('Unexpexted value.')
            end
        end
        
        
        %-----------------------------------------------------------------%
        function Listener(obj, src, evt, eventName)
            obj.progressDialog.Visible = 'visible';

            try
                switch eventName
                    case 'ContainerImage'
                        fieldTag = src.Tag;
    
                        switch fieldTag
                            case 'no_fiscaliza_issue,no_sei_processo_fiscalizacao'
                                fieldValues = struct('FISCALIZA', FieldInfo(obj, {'no_fiscaliza_issue'},           'cellstr'), ...
                                                     'SEI',       FieldInfo(obj, {'no_sei_processo_fiscalizacao'}, 'cellstr'));
                                fieldText   = sprintf(['Outras informações acerca da <b>Inspeção nº %s</b> constam no próprio FISCALIZA, acessível <a href="%s">aqui</a>.<br><br>' ...
                                                       'Já informações acerca do <b>Processo nº %s</b> constam no SEI, acessível <a href="%s">aqui</a>.'], fieldValues.FISCALIZA.numero, fieldValues.FISCALIZA.link_acesso, fieldValues.SEI.numero, fieldValues.SEI.link_acesso);
                                UIAlert(obj, fieldText, 'warning')
    
                            otherwise
                                % Place holder para eventos futuros...
                        end

                    case 'GetFileImage'
                        [fileName, filePath] = uigetfile({'*.zip',  'ZIP (*.zip)'; '*.html', 'HTML (*.html)'}, '');
                        figure(obj.hFigure)
                        
                        if fileName
                            hEditField = findobj(src.Parent, 'Type', 'uieditfield', 'Tag', src.Tag);
                            hEditField.Value = fullfile(filePath, fileName);

                            obj.reportFilePath = fullfile(filePath, fileName);
                        else
                            obj.reportFilePath = '';
                        end
    
                    case 'AddTreeNode'
                        fieldName  = src.Tag;
    
                        hEditField = findobj(src.Parent,  'Type', 'uieditfield');
                        hTree      = findobj(obj.hFigure, 'Type', 'uicheckboxtree', 'Tag', fieldName);
                        
                        fieldValue = strtrim(hEditField.Value);
                        if isempty(fieldValue)
                            error('Insira um valor para o campo "%s".', fieldName)
                        end

                        [~, fieldOptions] = FieldInfo(obj, fieldName, 'normal');
                        if numel(fieldOptions)
                            idx = find(strcmpi(strtrim(fieldOptions), fieldValue), 1);
                            if ~isempty(idx)
                                fieldValue = fieldOptions{idx};
                            else
                                error('Valor inserido não pertence à lista de possíveis valores do campo "%s".', fieldName)
                            end                            

                        else
                            switch fieldName
                                case 'entidade_da_inspecao'
                                    checkCNPJOrCPF(fieldValue, 'NumberValidation');
                                    fieldValue = regexprep(fieldValue, '\D', '');

                                case 'acao_de_risco_a_vida'
                                    if isempty(regexpi(fieldValue, '^ACAO_.*_[0-9]{4}_[0-9]{4}$', 'once'))
                                        error('Deve ser inserida a identificação textual da Ação. Por exemplo: ACAO_GR08_2024_0013.')
                                    end
                                    fieldValue = upper(fieldValue);
                                
                                otherwise
                                    % error('Não prevista a forma de consulta para inclusão de valor do campo "%s".', fieldName)
                            end
                        end

                        if ~isempty(hTree.CheckedNodes)
                            includedValues = {hTree.CheckedNodes.Text};
                        else
                            includedValues = {};
                        end

                        if ~ismember(fieldValue, includedValues)
                            childNode = uitreenode(hTree, 'Text', fieldValue);
                            hTree.CheckedNodes = [hTree.CheckedNodes; childNode];
                        else
                            error('O valor <b>%s</b> já havia sido inserido na lista do campo "%s".', fieldValue, fieldName)
                        end
                        hEditField.Value   = '';
    
                    case 'JSEffect'
                        guiData = readDataFromComponents(obj);
                        updateFields(obj, guiData);
                        Data2GUI(obj)
                end

            catch ME
                UIAlert(obj, ME.message, 'error')
            end

            obj.progressDialog.Visible = 'hidden';
        end


        %-----------------------------------------------------------------%
        function dialogMessage = HTMLSyntax(obj, rawMessage)
            dialogMessage = sprintf('<p style="font-size: 12px; text-align:justify;">%s</p>', rawMessage);
        end


        %-----------------------------------------------------------------%
        function UIAlert(obj, dialogMessage, dialogIcon)
            uialert(obj.hFigure, HTMLSyntax(obj, dialogMessage), '', 'Icon', dialogIcon, 'Interpreter', 'html')
        end


        %-----------------------------------------------------------------%
        function editableFieldsNames = setStackOrder(obj, editableFields)
            editableFieldsNames  = fieldnames(editableFields);
            referenceStackOrder  = refStackOrder(obj);

            stackOrderCellIndex  = cellfun(@(x) find(strcmp(x, referenceStackOrder), 1), editableFieldsNames, 'UniformOutput', false);
            stackOrderEmptyIndex = cellfun(@(x) isempty(x), stackOrderCellIndex);

            % Se a lib entregar um campo não mapeado em "refStackOrder", esse 
            % campo será renderizado ao final.
            if any(stackOrderEmptyIndex)
                idx  = find(stackOrderEmptyIndex);
                nMax = max(cell2mat(stackOrderCellIndex(~stackOrderEmptyIndex)));
                
                stackOrderCellIndex(idx) = num2cell(nMax+1:nMax+numel(idx))';
            end
            stackOrderNumericIndex = cell2mat(stackOrderCellIndex);

            [~, stackOrderNumericIndex] = sort(stackOrderNumericIndex);
            editableFieldsNames = editableFieldsNames(stackOrderNumericIndex);
        end


        %-----------------------------------------------------------------%
        function stackOrder = refStackOrder(obj)
            stackOrder = {'status' 'tipo_de_inspecao' 'start_date' 'due_date' 'description'                                  ... % CAMPOS REDMINE (exceto "tipo_de_inspecao")
                          'horas_de_preparacao' 'horas_de_deslocamento' 'horas_de_execucao' 'horas_de_conclusao'             ... % HORAS
                          'no_sei_processo_fiscalizacao'                                                                     ... % PFIS
                          'coordenacao_responsavel' 'fiscal_responsavel' 'fiscais' 'agrupamento' 'area_do_pacp'              ... % UNIDADE EXECUTANTE
                          'entidade_com_cadastro_stel' 'entidade_da_inspecao' 'nome_da_entidade' 'cnpjcpf_da_entidade'       ... % FISCALIZADA (1/3)
                          'entidade_outorgada' 'numero_da_estacao' 'identificacao_da_nao_outorgada'                          ... % FISCALIZADA (2/3)
                          'servicos_da_inspecao' 'esta_em_operacao'                                                          ... % FISCALIZADA (3/3)
                          'ufmunicipio' 'endereco_da_inspecao' 'coordenadas_geograficas' 'latitude_coordenadas'              ... % LOCAL DA FISCALIZAÇÃO (1/2)
                          'longitude_coordenadas' 'coordenadas_estacao' 'latitude_da_estacao' 'longitude_da_estacao'         ... % LOCAL DA FISCALIZAÇÃO (2/2)
                          'houve_interferencia' 'identificada_a_origem' 'sanada_ou_mitigada' 'foi_constatada_interferencia'  ... % INTERFERÊNCIA (1/4)
                          'interferencia_sanada' 'justificativa_nao_resolucao' 'local_interf_confere_indicado'               ... % INTERFERÊNCIA (2/4)
                          'tipo_de_fonte_interferente' 'fonte_e_modelo' 'frequencia_mhz' 'potencia_de_operacao_w'            ... % INTERFERÊNCIA (3/4)
                          'distancia_ao_interferido' 'homologada' 'ha_outras_fontes_interfer'                                ... % INTERFERÊNCIA (4/4)
                          'frequencias' 'unidade_de_frequencia' 'frequencia_inicial' 'unidade_da_frequencia_inicial'         ... % ASPECTOS TÉCNICOS (1/5) - FREQUÊNCIA (1/2)
                          'frequencia_final' 'unidade_da_frequencia_final'                                                   ... % ASPECTOS TÉCNICOS (2/5) - FREQUÊNCIA (2/2)
                          'potencia_medida' 'unidade_de_potencia'                                                            ... % ASPECTOS TÉCNICOS (3/5) - POTÊNCIA
                          'tipo_de_medicao' 'campo_eletrico__pico_vm' 'campo_eletrico_rms_vm' 'altura_do_sistema_irradiante' ... % ASPECTOS TÉCNICOS (4/5) - CAMPO ELÉTRICO E ALTURA
                          'uso_de_produto_homologado' 'no_de_homologacao'                                                    ... % ASPECTOS TÉCNICOS (5/5) - HOMOLOGAÇÃO
                          'qtd_de_emissoes' 'qtd_identificadas' 'qtd_licenciadas'                                            ... % QTD. EMISSÕES
                          'procedimentos' 'houve_obice' 'situacao_constatada' 'irregularidade' 'tipificacao_da_infracao'     ... % PROCEDIMENTOS
                          'motivo_de_lai' 'qnt_produt_lacradosapreend' 'no_do_lacre'                                         ... % PLAI (1/3)
                          'gerar_plai' 'tipo_do_processo_plai' 'coord_fi_plai'                                               ... % PLAI (2/3)
                          'lai_vinculadas' 'no_sei_do_plaiguarda' 'no_sei_do_aviso_lai'                                      ... % PLAI (3/3)
                          'situacao_de_risco_a_vida' 'acao_de_risco_a_vida_criada' 'acao_de_risco_a_vida'                    ... % RISCO À VIDA
                          'gerar_relatorio' 'no_sei_relatorio_de_atividades' 'no_sei_relatorio_monitoramento'                ... % RELATÓRIO (1/2)
                          'relatorio_de_atividades' 'html'                                                                   ... % RELATÓRIO (2/2) (campos internos à lib)
                          'documento_instaurador_do_pado' 'pai_instaurado_pela_anatel' 'numero_do_pai'                       ... % PROCESSOS SANCIONATÓRIOS (1/2)
                          'no_sei_do_oficio_ao_mctic' 'no_sav' 'no_pcdp'                                                     ... % PROCESSOS SANCIONATÓRIOS (2/2)
                          'precisa_reservar_instrumentos' 'reserva_de_instrumentos' 'utilizou_algum_instrumento'             ... % INSTRUMENTOS (1/2)
                          'copiar_instrumento_da_reserva' 'instrumentos_utilizados'                                          ... % INSTRUMENTOS (2/2)
                          'utilizou_apoio_policial' 'utilizou_tecnicas_amostrais' 'observacao_tecnica_amostral' 'observacoes'};
        end


        %-----------------------------------------------------------------%
        function guiData = readDataFromComponents(obj)
            % Identifica elementos que armazenam informações que foram efetivamente
            % editadas. Esses elementos, diga-se, possuem o seu atributo "Tag" 
            % preenchido.
            guiData        = struct;
            hComponents    = FindComponents(obj);
            editableFields = obj.fields2Render;

            for ii = 1:numel(hComponents)
                if isempty(hComponents(ii).Tag)
                    continue
                end

                fieldName  = hComponents(ii).Tag;
                fieldValue = getComponentFieldValue(obj, hComponents(ii));
                
                guiData.(fieldName) = fieldValue;

                if isfield(editableFields, fieldName)
                    if isfield(obj.issueInfo, fieldName)
                        previousValue = obj.issueInfo.(fieldName);
                    else
                        previousValue = '';
                    end
                    previousValue = checkIfNumericField(obj, fieldName, previousValue);
                    
                    if isstruct(previousValue)
                        fieldsList = fieldnames(previousValue);
                        previousValue = previousValue.(fieldsList{1});
                    end
    
                    % Esse é um passo opcional e puramente estético, eliminando
                    % possíveis caracteres vazios inseridos pelo usuário.
                    if ischar(previousValue)
                        previousValue = strtrim(previousValue);
                    end

                    % Garantir que a ordem de uma cellstr não interfira na análise 
                    % para determinar se houve edição do campo.
                    if iscellstr(previousValue)
                        previousValue = sort(previousValue);
                    end

                    if iscellstr(fieldValue)
                        fieldValue = sort(fieldValue);
                    end
    
                    % Essa comparação aqui é perigosa porque [], '' e {} são diferentes 
                    % entre si. Ao validar que ao menos um dos valores - o antigo ou o 
                    % novo - deva ser diferente de vazio, garante-se que o valor do campo
                    % sob análise foi, de fato, alterado.
                    if (isempty(previousValue) && isempty(fieldValue)) || isequal(previousValue, fieldValue)
                        guiData = rmfield(guiData, fieldName);
                    end

                elseif isempty(fieldValue)
                    guiData = rmfield(guiData, fieldName);
                end
            end
        end
    end


    methods (Static = true)
        %------------------------------------------------------------------%
        function ID = serviceMapping(ID)
            arguments
                ID (1,1) int16
            end

            global id2nameTable
            
            if isempty(id2nameTable)
                MFilePath    = fileparts(mfilename('fullpath'));
                fileName     = fullfile(MFilePath, 'resources', 'fiscalizaGUI', 'serviceMapping.xlsx');
                id2nameTable = readtable(fileName, 'VariableNamingRule', 'preserve');
                id2nameTable.ID = int16(id2nameTable.ID);
            end

            [~, idxFind] = ismember(ID, id2nameTable.ID);
            if idxFind
                ID = id2nameTable.("Serviço"){idxFind};
            else
                ID = num2str(ID);
            end
        end
    end
end