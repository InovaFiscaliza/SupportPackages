classdef fiscalizaLib < handle

    % MENSAGENS DE ERRO EVIDENCIADAS:
    % 'Python Error: AuthError: Invalid authentication details'
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
        function GUICreation(obj, hGrid)
            editableFields       = struct(py.getattr(obj.Issue, 'editable_fields'));
            editableFieldsNames  = fields(editableFields);
            editableFieldsNumber = numel(editableFieldsNames);

            set(hGrid, 'RowHeight',  repmat({22}, 1, 2*editableFieldsNumber), ...
                       'Scrollable', 'on',                                    ...
                       'UserData',   struct())

            for ii = 1:editableFieldsNumber
                compBaseName   = editableFieldsNames{ii};
                compBaseClass  = class(editableFields.(compBaseName));
                
                compLabelName  = [compBaseName '_Label'];
                compLabelText  = char( editableFields.(compBaseName).name);
                
                compValue      = editableFields.(compBaseName).value;
                compValueClass = class(compValue);

                % Label component
                hGrid.UserData.(compLabelName) = uilabel(hGrid, 'VerticalAlignment', 'bottom', 'Text', compLabelText);
                hGrid.UserData.(compLabelName).Layout.Row = 2*ii-1;

                % Value component
                try
                    switch compBaseClass
                        case 'py.fiscaliza.datatypes.FieldWithOptions'
                            % se for escolha múltipla, usar
                            % uitreecheckbox... oi uilistbox...

                            compValueOptions = cellfun(@(x) char(x), cell(editableFields.(compBaseName).options), 'UniformOutput', false);
                            switch compValueClass
                                case 'py.str'
                                    compValue = char(compValue);

                                case 'py.list'
                                    compValue = cellfun(@(x) char(x), cell(compValue), 'UniformOutput', false);

                                case {'py.int', 'py.long', 'py.float', 'double'}
                                    compValue = num2str(double(compValue));
                            end

                            if editableFields.(compBaseName).multiple
                                hGrid.RowHeight{2*ii} = 112;

                                if numel(compValueOptions) > 50
                                    hGrid.UserData.(compBaseName) = uilistbox(hGrid, "Multiselect", "on", "Items", compValueOptions, "Value", compValue, "FontSize", 11);

                                else
                                    hGrid.UserData.(compBaseName) = uitree(hGrid, 'checkbox', 'FontSize', 11);
                                    for jj = 1:numel(compValueOptions)
                                        childNode = uitreenode(hGrid.UserData.(compBaseName), 'Text', compValueOptions{jj});
                                        if ismember(compValueOptions{jj}, compValue)
                                            hGrid.UserData.(compBaseName).CheckedNodes = [hGrid.UserData.(compBaseName).CheckedNodes, childNode];
                                        end
                                    end
                                end

                            else
                                compValueOptions = [{''}, compValueOptions];                                
                                hGrid.UserData.(compBaseName) = uidropdown(hGrid, 'Items', compValueOptions, 'Value', compValue, 'BackgroundColor', [1,1,1], 'FontSize', 11);
                            end
    
                        otherwise                                               % 'py.fiscaliza.datatypes.AtomicField' | 'py.fiscaliza.datatypes.SimpleField'
                            switch compValueClass
                                case {'py.int', 'py.long', 'py.float', 'double'}
                                    hGrid.UserData.(compBaseName) = uieditfield(hGrid, 'numeric', 'Value', double(compValue), 'FontSize', 11);

                                case 'py.list'
                                    compValue = cellfun(@(x) char(x), cell(compValue), 'UniformOutput', false);
                                    if isempty(compValue)
                                        compValue = {''};
                                    end
                                    hGrid.UserData.(compBaseName) = uieditfield(hGrid, 'text', 'Value', compValue{1}, 'FontSize', 11);

                                otherwise                                   % 'py.str'
                                    hGrid.UserData.(compBaseName) = uieditfield(hGrid, 'text', 'Value', char(compValue), 'FontSize', 11);
                            end                        
                    end
                    hGrid.UserData.(compBaseName).Layout.Row = 2*ii;
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
                    error('A lib fiscaliza retornou um dicionário vazio para a inspeção nº %d.', issueNumber)
                end
            end

            FieldNames = fieldnames(issueStruct);
            for ii = 1:numel(FieldNames)
                FieldName  = FieldNames{ii};
                FieldValue = issueStruct.(FieldName);
                FieldClass = class(FieldValue);

                % Notei que o "py.float" é convertido automaticamente para
                % "double". Arriscaria dizer que isso pode acontecer com o
                % "py.str", sendo convertido automaticamente para "char" ou
                % "string". 

                % Foram mapeados apenas os tipos de dados retornados pela
                % lib fiscaliza. 
                
                % Há, contudo, tipos de dados ainda não mapeados aqui: 
                % "py.bytes", "py.array.array", "py.numpy.ndarray, "py.memoryview", 
                % "py.tuple", "py.pandas.DataFrame", "py.datetime.datetime" e 
                % "py.datetime.timedelta".

                switch FieldClass
                    case {'py.int', 'py.long', 'py.float'}
                        FieldValue = double(FieldValue);
                    case 'py.bool'
                        FieldValue = logical(FieldValue);
                    case 'py.str'
                        FieldValue = isJSONFormat(obj, char(FieldValue));
                    case 'py.list'
                        FieldValue = cellfun(@(x) char(x), cell(FieldValue), 'UniformOutput', false);
                    case 'py.dict'
                        FieldValue = py2matDataType(obj, -1, FieldValue, recurrenceLevel+1);
                    case 'py.NoneType'
                        issueStruct = rmfield(issueStruct, FieldName);
                        continue
                end

                if recurrenceLevel == 1
                    if strcmp(FieldName, 'status') && ~ismember(FieldValue, {'Rascunho', 'Aguardando Execução', 'Em andamento', 'Relatando'})
                        error('A inspeção nº %d não é passível de relato por estar no estado "%s".', issueNumber, FieldValue)
                    end
                end

                issueStruct.(FieldName) = FieldValue;
            end
        end


        %-----------------------------------------------------------------%
        function FieldValue = isJSONFormat(obj, FieldValue)
            try
                FieldValue = jsondecode(replace(FieldValue, {'=>', ''''}, {':', '"'}));
            catch
            end
        end
    end
end