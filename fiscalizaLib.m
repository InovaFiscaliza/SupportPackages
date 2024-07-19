classdef fiscalizaLib < handle

    % https://sistemas.anatel.gov.br/fiscaliza
    % https://sistemasnet/fiscaliza
    % https://sistemasnethm/fiscaliza

    % % FISCALIZAHM FORA (sem VPN)
    % 'Error using main>authenticate (line 67)
    %  Python Error: ConnectionError: Não foi possível conectar ao servidor do Fiscaliza'
    
    % % FISCALIZAHM FORA (com VPN)
    % 'Error using base>process_response (line 180)
    %  Python Error: ServerError: Redmine returned internal error, check Redmine logs for details'
    
    % % LOGIN OU SENHA INCORRETA
    % 'Python Error: AuthError: Invalid authentication details'
    
    % % ISSUE QUE NÃO EXISTE
    % 'Python Error: ResourceNotFoundError: Requested resource doesn't exist'
    
    properties
        %-----------------------------------------------------------------%
        Module

        % A classe Fiscaliza é somente para efetuar a conexão e autenticação 
        % com o servidor do Redmine.
        Fiscaliza

        % O método get_issue instancia e retorna um objeto do tipo Issue, 
        % o qual encapsula a funcionalidade principal de resgate de informações, 
        % validação e formatação de informações e atualização de inspeção.
        Issue

        % Atributos da issue para uso no MATLAB, já com os tipos de dados
        % do MATLAB.
        IssueInfo
    end


    methods
        %-----------------------------------------------------------------%
        function obj = fiscalizaLib(userName, userPass, testFlag)
            pyMod = py.importlib.import_module('fiscaliza.main');
            py.importlib.reload(pyMod);

            obj.Module    = pyMod;
            obj.Fiscaliza = pyMod.Fiscaliza(pyargs('username', userName, 'password', userPass, 'teste', logical(testFlag)));
        end


        %-----------------------------------------------------------------%
        function get_issue(obj, issueNumber)
            if isnumeric(issueNumber)
                issueNumber = num2str(issueNumber);
            end

            obj.Issue = obj.Fiscaliza.get_issue(issueNumber);

            issueType = char(obj.Issue.type);
            if ~strcmp(issueType, 'atividade_de_inspecao')
                error('O relato da lib fiscaliza é restrito às <i>issues</i> do tipo "Atividade de inspeção". A <i>issue</i> nº %d, contudo, é uma "%s".', issueNumber, formatIssueType(obj, issueType))
            end
            
            obj.IssueInfo = py2matDataType(obj, issueNumber, py.getattr(obj.Issue, 'attrs'), 1);
        end


        %-----------------------------------------------------------------%
        function update(obj, newData)
            obj.Issue.update(py.dict(newData))
        end


        %-----------------------------------------------------------------%
        function [status, compData] = GUI2Data(obj, hPanel, hGrid)
            status   = false;
            compData = struct;

            editableFieldsNames  = fields(hGrid.UserData);
            editableFieldsNumber = numel(editableFieldsNames);

            for ii = 1:editableFieldsNumber
                compBaseName  = editableFieldsNames{ii};
                compBaseClass = class(hGrid.UserData.(compBaseName));

                switch compBaseClass
                    case {'matlab.ui.control.EditField', 'matlab.ui.control.NumericEditField', 'matlab.ui.control.DropDown'}
                        compValue = hGrid.UserData.(compBaseName).Value;

                    case 'matlab.ui.container.CheckBoxTree'
                        if ~isempty(hGrid.UserData.(compBaseName).CheckedNodes)
                            compValue = {hGrid.UserData.(compBaseName).CheckedNodes.Text};
                        else
                            compValue = {};
                        end

                    otherwise
                        continue
                end
                
                compData.(compBaseName) = compValue;
                if isfield(obj.IssueInfo, compBaseName) && ~isequal(compValue, obj.IssueInfo.(compBaseName))
                    status = true;
                end
            end
        end


        %-----------------------------------------------------------------%
        function Data2GUI(obj, hPanel, hGrid)
            if ~isempty(hGrid.Children)
                delete(hGrid.Children)
                hGrid.RowHeight = {'1x'};
            end

            editableFields       = struct(py.getattr(obj.Issue, 'editable_fields'));
            editableFieldsNames  = fields(editableFields);

            % Inicialmente, os campos já renderizados em tela são preenchidos...
            compHandles = findobj(hPanel, '-not', {'Type', 'uigridlayout', '-or', 'Type', 'uipanel'});
            compFields  = {};

            for ii = 1:numel(compHandles)
                compHandle = compHandles(ii);

                if ~isempty(compHandle.UserData)
                    compFieldType  = compHandle.UserData.Type;                    
                    compFieldName  = compHandle.UserData.Fields;
                    if isfield(compHandle.UserData, 'Format')
                        compFormat = compHandle.UserData.Format;
                    end

                    switch compFieldType
                        case 'matlab.ui.control.Label'
                            compFieldsValues = {};
                            for jj = 1:numel(compFieldName)
                                compFieldsValues{jj} = ComponentFieldValue(obj, editableFields, compFieldName{jj});
                                if iscell(compFieldsValues{jj}) 
                                    compFieldsValues{jj} = char(compFieldsValues{jj});
                                end
                            end
                            compHandle.Text  = sprintf(compFormat, compFieldsValues{:});

                        case 'matlab.ui.control.DatePicker'
                            compFieldValue   = ComponentFieldValue(obj, editableFields, compFieldName{1});
                            compHandle.Value = datetime(compFieldValue, 'InputFormat', 'yyyy-MM-dd');

                        case 'matlab.ui.control.TextArea'
                            compFieldValue   = ComponentFieldValue(obj, editableFields, compFieldName{1});
                            compHandle.Value = compFieldValue;

                        case 'matlab.ui.control.DropDown'
                            compFieldValue   = ComponentFieldValue(obj, editableFields, compFieldName{1});
                            compFieldOptions = unique([{''}, DataTypeMapping(obj, editableFields.(compFieldName{1}).options, 1)]);

                            set(compHandle, 'Value', compFieldValue, 'Items', compFieldOptions)

                        otherwise
                            continue
                    end

                    compFields = [compFields, compFieldName];
                end
            end

            % Renderiza os outros campos editáveis...
            hGridRow = 0;
            for ii = 1:numel(editableFieldsNames)
                compBaseName   = editableFieldsNames{ii};
                compBaseClass  = class(editableFields.(compBaseName));

                if ismember(compBaseName, compFields)
                    continue
                end
                
                % Label component
                compLabelText  = char(editableFields.(compBaseName).name);

                % Value component
                try
                    compValue  = DataTypeMapping(obj, editableFields.(compBaseName).value, 1);

                    hGridRow = hGridRow + 1;
                    hGrid.RowHeight{hGridRow} = 17;
                    compLabelUI = uilabel(hGrid, 'VerticalAlignment', 'bottom', 'Text', compLabelText, 'FontSize', 11);
                    compLabelUI.Layout.Row = hGridRow;

                    % O campo "entidade_da_inspecao" está vindo como SimpleField, 
                    % mas deveria ser FieldWithOptions, em que as options são 
                    % todos os CNPJs das empresas outorgadas.

                    % A própria lista de município sobrecarrega...

                    % Como implementar?

                    switch compBaseClass
                        case {'py.fiscaliza.datatypes.AtomicField', 'py.fiscaliza.datatypes.SimpleField'}
                            if isnumeric(compValue)
                                compFieldType = 'numeric';
                            else
                                compFieldType = 'text';
                                if isequal(compValue, {''})
                                    compValue = '';
                                end
                            end
                            hGridRow = hGridRow + 1;
                            hGrid.RowHeight{hGridRow} = 22;
                            hGrid.UserData.(compBaseName) = uieditfield(hGrid, compFieldType, 'Value', compValue, 'FontSize', 11);
                            hGrid.UserData.(compBaseName).Layout.Row = hGridRow;

                        case 'py.fiscaliza.datatypes.FieldWithOptions'
                            compValueOptions = DataTypeMapping(obj, editableFields.(compBaseName).options, 1);
                            compValueOptionsElements = numel(compValueOptions);

                            if isnumeric(compValue)
                                compValue = num2str(compValue);
                            end

                            % se for escolha múltipla, usar
                            % uitreecheckbox... ou uilistbox...
                            if editableFields.(compBaseName).multiple
                                if ischar(compValue)
                                    compValue = {compValue};
                                end

                                if compValueOptionsElements && compValueOptionsElements <= 200
                                    hGridRow = hGridRow + 1;
                                    hGrid.RowHeight{hGridRow} = 112;
                                    hGrid.UserData.(compBaseName) = uitree(hGrid, 'checkbox', 'FontSize', 11);
                                    hGrid.UserData.(compBaseName).Layout.Row = hGridRow;

                                    for jj = 1:numel(compValueOptions)
                                        childNode = uitreenode(hGrid.UserData.(compBaseName), 'Text', compValueOptions{jj});
                                        if ismember(compValueOptions{jj}, compValue)
                                            hGrid.UserData.(compBaseName).CheckedNodes = [hGrid.UserData.(compBaseName).CheckedNodes, childNode];
                                        end
                                    end

                                else
                                    hGridRow = hGridRow + 1;
                                    hGrid.RowHeight{hGridRow} = 22;
                                    compEditFieldUI = uieditfield(hGrid, 'text', 'FontSize', 11);
                                    compEditFieldUI.Layout.Row = hGridRow;

                                    hGridRow = hGridRow + 1;
                                    hGrid.RowHeight{hGridRow} = 112;
                                    hGrid.UserData.(compBaseName) = uitree(hGrid, 'checkbox', 'FontSize', 11);
                                    hGrid.UserData.(compBaseName).Layout.Row = hGridRow;

                                    if isequal(compValue, {''})
                                        compValue = {};
                                    end

                                    for jj = 1:numel(compValue)
                                        childNode = uitreenode(hGrid.UserData.(compBaseName), 'Text', compValue{jj});
                                        hGrid.UserData.(compBaseName).CheckedNodes = [hGrid.UserData.(compBaseName).CheckedNodes, childNode];
                                    end
                                end

                            else
                                compValueOptions = unique([{''}, compValueOptions]);

                                hGridRow = hGridRow + 1;
                                hGrid.RowHeight{hGridRow} = 22;
                                hGrid.UserData.(compBaseName) = uidropdown(hGrid, 'Items', compValueOptions, 'Value', compValue, 'BackgroundColor', [1,1,1], 'FontSize', 11);
                                hGrid.UserData.(compBaseName).Layout.Row = hGridRow;
                            end                     
                    end                    

                catch ME
                    compBaseName
                    ME.message
                end
            end

        end
    end
        
        
    methods (Access=private)
        %-----------------------------------------------------------------%
        function issueType = formatIssueType(obj, issueType)
            d = dictionary(["solicitacao_de_inspecao", "acao_de_inspecao", "atividade_de_inspecao"], ...
                           ["Solicitação de inspeção", "Ação de inspeção", "Atividade de inspeção"]);

            if isKey(d, issueType)
                issueType = d(issueType);
            end
        end


        %-----------------------------------------------------------------%
        function issueStruct = py2matDataType(obj, issueNumber, issueDict, recurrenceLevel)
            issueStruct = struct(issueDict);
            if recurrenceLevel == 1
                if isempty(issueStruct)
                    error('A lib fiscaliza retornou um dicionário vazio para a inspeção nº %s.', issueNumber)
                end
            end

            FieldNames = fieldnames(issueStruct);
            for ii = 1:numel(FieldNames)
                FieldName  = FieldNames{ii};
                FieldValue = issueStruct.(FieldName);

                % Notei que o "py.float" é convertido automaticamente para
                % "double". Arriscaria dizer que isso pode acontecer com o
                % "py.str", sendo convertido automaticamente para "char" ou
                % "string". 

                % Foram mapeados apenas os tipos de dados retornados pela
                % lib fiscaliza. 
                
                % Há, contudo, tipos de dados ainda não mapeados aqui: 
                % "py.bytes", "py.array.array", "py.numpy.ndarray, "py.memoryview", 
                % "py.tuple", "py.pandas.DataFrame", "py.datetime.datetime", 
                % "py.datetime.timedelta" etc.

                if isa(FieldValue, 'py.NoneType')
                    issueStruct = rmfield(issueStruct, FieldName);
                    continue
                end
                FieldValue = DataTypeMapping(obj, FieldValue, recurrenceLevel);
                issueStruct.(FieldName) = FieldValue;

                if recurrenceLevel == 1
                    if strcmp(FieldName, 'status') && ~ismember(FieldValue, {'Rascunho', 'Aguardando Execução', 'Em andamento', 'Relatando'})
                        error('A inspeção nº %s não é passível de relato por estar no estado "%s".', issueNumber, FieldValue)
                    end
                end                
            end
        end


        %-----------------------------------------------------------------%
        function compFieldValue = ComponentFieldValue(obj, editableFields, compFieldName)
            if isfield(editableFields, compFieldName)
                compFieldValue = DataTypeMapping(obj, editableFields.(compFieldName).value, 1);
            else
                compFieldValue = DataTypeMapping(obj, obj.IssueInfo.(compFieldName), 1);
            end
        end



        %-----------------------------------------------------------------%
        function matValue = DataTypeMapping(obj, pyValue, recurrenceLevel)
            pyClass = class(pyValue);
            
                switch pyClass
                    case {'py.int', 'py.long', 'py.float'}
                        matValue = double(pyValue);
                    case 'py.bool'
                        matValue = logical(pyValue);
                    case 'py.str'
                        matValue = isJSONFormat(obj, char(pyValue));
                    case 'py.list'
                        matValue = sort(cellfun(@(x) char(x), cell(pyValue), 'UniformOutput', false));
                        if isempty(matValue)
                            matValue = {''};
                        end
                    case 'py.dict'
                        matValue = py2matDataType(obj, -1, pyValue, recurrenceLevel+1);
                    case 'py.NoneType'
                        error('Not expected datatype.')
                    otherwise
                        matValue = pyValue;
                end
        end


        %-----------------------------------------------------------------%
        function FieldValue = isJSONFormat(obj, FieldValue)
            try
                tempValue = jsondecode(replace(FieldValue, {'=>', ''''}, {':', '"'}));
                if isstruct(tempValue)
                    FieldValue = tempValue;
                end
            catch
            end
        end
    end
end