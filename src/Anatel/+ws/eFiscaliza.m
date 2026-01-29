classdef eFiscaliza < ws.WebServiceBase

    properties (Access = private)
        %-----------------------------------------------------------------%
        login
        password
    end


    properties (Access = private, Constant)
        %-----------------------------------------------------------------%
        url = struct('DS', 'https://appsnetds/eFiscaliza_API/rest/servico',               ...
                     'HM', 'https://appsnethm/eFiscaliza_API/rest/servico',               ...
                     'TS', 'https://appsnetts.anatel.gov.br/eFiscaliza_API/rest/servico', ...
                     'PD', 'https://appsnet/eFiscaliza_API/rest/servico')
    end


    methods
        %-----------------------------------------------------------------%
        function obj = eFiscaliza(login, password)
            arguments
                login    char
                password char
            end

            obj.login    = login;
            obj.password = ws.WebServiceBase.base64encode(password);
        end

        %-----------------------------------------------------------------%
        function msg = run(obj, env, operation, issue, varargin)
            arguments
                obj
                env       char {mustBeMember(env, {'DS', 'HM', 'TS', 'PD'})}
                operation char {mustBeMember(operation, {'queryIssue', 'uploadDocument', 'uploadExternalDocument'})}
                issue     struct
            end

            arguments (Repeating)
                varargin
            end

            try
                header = {'Authorization', ['Basic ' ws.WebServiceBase.base64encode([obj.login ':' obj.password])], ...
                          'Content-Type', 'application/json'};
            
                switch operation
                    case 'queryIssue'
                        if ~strcmp(issue.type, 'ATIVIDADE DE INSPEÇÃO')
                            error('Unexpected issue type %s', issue.type)
                        end

                        endPoint = sprintf('%s/atividadesInspecao?IdAtividadeInspecao=%s', obj.url.(env), string(issue.id));
                        response = ws.WebServiceBase.request(endPoint, 'GET', header);
        
                        if ~isfield(response.Body.Data, 'AtividadeInspecaoList')
                            error(response.show)
                        end
        
                        msg = struct( ...
                            'issueId', issue.id, ...
                            'issueTree', struct( ...
                                'solicitacao', response.Body.Data.AtividadeInspecaoList.("CO_INSPEC_SOLICITACAO").value, ...
                                'acao', response.Body.Data.AtividadeInspecaoList.("CO_INSPEC_ACAO").value, ...
                                'atividade',   response.Body.Data.AtividadeInspecaoList.("CO_INSPEC_ATIVIDADE").value ...
                            ), ...
                            'unit', response.Body.Data.AtividadeInspecaoList.("SG_UNIDADE_EXECUTANTE").value, ...
                            'description', response.Body.Data.AtividadeInspecaoList.("DE_INSPEC_ATIVIDADE").value, ...
                            'period', sprintf( ...
                                '%s a %s', ...
                                response.Body.Data.AtividadeInspecaoList.("DT_INICIO_DESEJADO").value, ...
                                response.Body.Data.AtividadeInspecaoList.("DT_FIM_DESEJADO").value ...
                            ), ...
                            'fiscais', {response.Body.Data.AtividadeInspecaoList.("Fiscais").value}, ...
                            'sei', response.Body.Data.AtividadeInspecaoList.("NU_SEI_PROCESSO").value ...
                        );

                    case {'uploadDocument', 'uploadExternalDocument'}
                        if ~ismember(issue.type, {'AÇÃO DE INSPEÇÃO', 'ATIVIDADE DE INSPEÇÃO'})
                            error('Unexpected issue type %s', issue.type)
                        end

                        unit     = varargin{1};
                        docSpec  = varargin{2};
                        fileName = varargin{3};

                        switch issue.type
                            case 'AÇÃO DE INSPEÇÃO'
                                issueTypeFieldName = 'ID_INSPEC_ACAO';
                            case 'ATIVIDADE DE INSPEÇÃO'
                                issueTypeFieldName = 'ID_INSPEC_ATIVIDADE';
                        end

                        % Interessados
                        
                        % Sigla: Sigla do interessado
                        % Nome: Nome do interessado
                        % IdContato: Identificador interno do interessado
                        % Cpf: CPF do interessado
                        % Cnpj: CNPJ do interessado

                        body = struct( ...
                            issueTypeFieldName, issue.id,              ...
                            'UNIDADE_GERADORA', unit,                  ...
                            'TIPO',             docSpec.originId,      ...
                            'TIPOLOGIA',        docSpec.typeId,        ...
                            'DESCRICAO',        docSpec.description,   ...
                            'OBSERVACAO',       docSpec.note,          ...
                            'NIVEL_ACESSO',     docSpec.accessLevelId, ...
                            'HIPOTESE_LEGAL',   docSpec.legalBasisId,  ...
                            'CONTEUDO',         ws.WebServiceBase.base64encode(fileread(fileName)) ...
                        );

                        if strcmp(operation, 'uploadExternalDocument')
                            [~, name, ext] = fileparts(fileName);

                            body.DATA         = datestr(now, 'dd/mm/yyyy');
                            body.NOME_ARQUIVO = [name, ext];
                        end

                        endPoint = [obj.url.(env) '/incluirDocumentoSei'];
                        response = ws.WebServiceBase.request(endPoint, 'POST', header, body);
        
                        if ~isfield(response.Body.Data, 'StrRetornoInclusaoDocumento')
                            error(response.show)
                        end
        
                        sei  = response.Body.Data.StrRetornoInclusaoDocumento.DocumentoFormatado;
                        link = response.Body.Data.StrRetornoInclusaoDocumento.LinkAcesso;
                        msg  = sprintf( ...
                            '<b>%s: %s</b>\nDocumento cadastrado no SEI sob o nº <a href="%s" target="_blank">%s</a>', ...
                            response.StatusCode, ...
                            response.StatusLine, ...
                            link, ...
                            sei ...
                        );
    
                    otherwise
                        error('UnexpectedCall')
                end

            catch ME
                msg  = ME.message;
            end
        end

        %-----------------------------------------------------------------%
        function login = getLogin(obj)
            login = obj.login;
        end
    end


    methods (Static = true)
        %-----------------------------------------------------------------%
        function ID = serviceMapping(ID)
            arguments
                ID (1,1) int16
            end

            global id2nameTable
            
            if isempty(id2nameTable)
                MFilePath    = fileparts(mfilename('fullpath'));
                fileName     = fullfile(MFilePath, 'eFiscaliza', 'serviceMapping.xlsx');
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