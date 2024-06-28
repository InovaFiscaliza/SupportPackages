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
        % este que encapsula a funcionalidade principal de resgate de informações, 
        % validação e formatação de informações e atualização de inspeção.
        Issue

        % Atributos da issue para uso no MATLAB, já com os tipos de dados
        % do MATLAB.
        IssueInfo
    end

    methods
        %-----------------------------------------------------------------%
        function obj = fiscalizaLib(userName, userPass, testFlag)
            pyMod = py.importlib.import_module('main');
            py.importlib.reload(pyMod);

            obj.Module    = pyMod;
            obj.Fiscaliza = pyMod.Fiscaliza(pyargs('username', userName, 'password', userPass, 'teste', logical(testFlag)));
        end


        %-----------------------------------------------------------------%
        function detalhar_issue(obj, issueNumber)
            obj.Issue = obj.Fiscaliza.get_issue(num2str(issueNumber));

            issueType = char(obj.Issue.type);
            if ~strcmp(issueType, 'atividade_de_inspecao')
                error('O relato da lib fiscaliza é restrita às <i>issues</i> do tipo "atividade_de_inspecao". A <i>issue</i> nº %d, contudo, é uma "%s".', issueNumber, issueType)
            end
            
            obj.IssueInfo = py2matRedmine(obj, issueNumber, py.getattr(obj.Issue, 'attrs'), 1);
        end


        %-----------------------------------------------------------------%
        function relatar_inspecao(obj)
            workersList = {app.WorkersTree.CheckedNodes(1).Text};
            for ii = 2:numel(app.WorkersTree.CheckedNodes)
                workersList = [workersList, app.WorkersTree.CheckedNodes(ii).Text];
            end
            workersList = py.list(workersList);
            serviceList = py.list(app.FinalReport.Services');
            
            Cities = {};
            for ii = 1:numel(app.City.Value)
                Cities{ii} = sprintf('%s/%s', app.City.Value{ii}(end-1:end), app.City.Value{ii}(1:end-3));
            end
            Cities = py.list(Cities);
            
            tableJournal = py.list({jsonencode(app.FinalReport.tableJournal)});
            
            rawData = struct('Classe_da_Inspecao',            'Técnica',                       ...
                             'Tipo_de_Inspecao',              'Uso do Espectro - Monitoração', ...
                             'description',                   strjoin(app.issueDescription.Value), ...
                             'Fiscal_Responsavel',            app.Responsable.Value,           ...
                             'Fiscais',                       workersList,                     ...
                             'Html',                          app.ReportFile.Value,            ...
                             'Gerar_Relatorio',               int8(app.CheckBox.Value),        ...
                             'Frequencia_Inicial',            app.Limit1.Value,                ...
                             'Unidade_da_Frequencia_Inicial', 'MHz',                           ...
                             'Frequencia_Final',              app.Limit2.Value,                ...
                             'Unidade_da_Frequencia_Final',   'MHz',                           ...
                             'start_date',                    datestr(app.DatePicker1.Value, 'yyyy-mm-dd'), ...
                             'due_date',                      datestr(app.DatePicker2.Value, 'yyyy-mm-dd'), ...
                             'UF_Municipio',                  Cities,                           ...
                             'Servicos_da_Inspecao',          serviceList,                      ...
                             'Qtd_Emissoes',                  int32(app.EmissionsCount1.Value), ...
                             'Qtd_Licenciadas',               int32(app.EmissionsCount2.Value), ...
                             'Qtd_Identificadas',             int32(app.EmissionsCount3.Value), ...
                             'Horas_de_Preparacao',           int32(app.Hours1.Value),          ...
                             'Horas_de_Deslocamento',         int32(app.Hours2.Value),          ...
                             'Horas_de_Execucao',             int32(app.Hours3.Value),          ...
                             'Horas_de_Conclusao',            int32(app.Hours4.Value),          ...
                             'Latitude',                      round(app.Latitude.Value,  6),    ...
                             'Longitude',                     round(app.Longitude.Value, 6),    ...
                             'Uso_de_PF',                     'Não se aplica PF - uso apenas de formulários', ...
                             'Acao_de_risco_a_vida_criada',   'Não',   ...
                             'Impossibilidade_acesso_online', '0',     ...
                             'Reservar_Instrumentos',         '0',     ...
                             'Utilizou_algum_instrumento',    int8(0), ...
                             'notes',                         tableJournal, ...
                             'uploads',                       py.list({py.dict(pyargs('path',         replace(app.ReportFile.Value, 'html', 'json'), ...
                                                                                      'filename',     'Info.json',                                   ...
                                                                                      'description',  'Informações gerais acerca da fiscalização (sensor, período de observação, faixas monitoradas, emissões identificadas etc).', ...
                                                                                      'content_type', '.json'))}));
            
            try
                finalStatus   = app.issueDesiredStatus.Value;
                replaceReport = false;
                if app.CheckBox.Value && ~isempty(app.Hyperlink2.Text)
                    replaceReport = true;
                end

                importLib(obj, 'update')
                pyModule = obj.Module.update;
                pyModule.relatar_inspecao(pyargs('dados',    py.dict(rawData),               ...
                                                 'inspecao', num2str(app.IssueNumber.Value), ...
                                                 'login',    app.Login,          ...
                                                 'senha',    app.Password,       ...
                                                 'teste',    app.Teste,          ...
                                                 'parar_em', finalStatus,        ...
                                                 'substituir_relatorio', replaceReport));
                
            catch ME
                layoutFcn.modalWindow(app.UIFigure, 'ccTools.MessageBox', ME.message);
            end
        end
    end
        
        
    methods (Access=private) 
        %-----------------------------------------------------------------%
        function issueStruct = py2matRedmine(obj, issueNumber, issueDict, recurrenceLevel)
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

                switch FieldClass
                    case 'py.int'
                        FieldValue = double(FieldValue);
                    case 'py.str'
                        FieldValue = isJSONFormat(obj, char(FieldValue));
                    case 'py.list'
                        FieldValue = cellfun(@(x) char(x), cell(FieldValue), 'UniformOutput', false);
                    case 'py.dict'
                        FieldValue = py2matRedmine(obj, -1, FieldValue, recurrenceLevel+1);
                    case 'py.NoneType'
                        FieldValue = '';
                end

                if recurrenceLevel == 1
                    if strcmp(FieldName, 'status') && ismember(FieldValue, ["Cancelada", "Relatada", "Conferida"])
                        error('A inspeção nº %d não é passível de relato por já estar no estado "%s".', issueNumber, FieldValue)
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