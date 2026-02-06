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

            if strcmp(env, 'DS')
                operation = [operation '-DS'];
            end

            try
                header = {'Authorization', ['Basic ' ws.WebServiceBase.base64encode([obj.login ':' obj.password])], ...
                          'Content-Type', 'application/json'};
            
                switch operation
                    %-----------------------------------------------------%
                    % ## eFiscaliza HM/TS/PD ##
                    %-----------------------------------------------------%
                    case 'queryIssue'
                        if ~strcmp(issue.type, 'ATIVIDADE DE INSPEÇÃO')
                            error('ws:eFiscaliza:UnexpectedIssueType', 'Unexpected issue type "%s"', issue.type)
                        end

                        endPoint = sprintf('%s/atividadesInspecao?IdAtividadeInspecao=%s', obj.url.(env), string(issue.id));
                        response = ws.WebServiceBase.request(endPoint, 'GET', header);
        
                        if ~isfield(response.Body.Data, 'AtividadeInspecaoList')
                            error('ws:eFiscaliza:RequestFailed', response.show)
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
                            error('ws:eFiscaliza:UnexpectedIssueType', 'Unexpected issue type "%s"', issue.type)
                        end

                        unit     = varargin{1};
                        docSpec  = varargin{2};
                        fileName = varargin{3};

                        fileId = fopen(fileName);
                        byteArray = fread(fileId, [1, inf], 'uint8=>uint8');
                        fclose(fileId);
                        fileContent = matlab.net.base64encode(byteArray);

                        switch issue.type
                            case 'AÇÃO DE INSPEÇÃO'
                                issueTypeFieldName = 'ID_INSPEC_ACAO';
                            case 'ATIVIDADE DE INSPEÇÃO'
                                issueTypeFieldName = 'ID_INSPEC_ATIVIDADE';
                        end

                        body = struct( ...
                            issueTypeFieldName, issue.id,              ...
                            'UNIDADE_GERADORA', unit,                  ...
                            'TIPO',             docSpec.originId,      ...
                            'TIPOLOGIA',        docSpec.typeId,        ...
                            'DESCRICAO',        docSpec.description,   ...
                            'OBSERVACAO',       docSpec.note,          ...
                            'NIVEL_ACESSO',     docSpec.accessLevelId, ...
                            'HIPOTESE_LEGAL',   docSpec.legalBasisId,  ...
                            'CONTEUDO',         fileContent            ...
                        );

                        if strcmp(operation, 'uploadExternalDocument')
                            [~, name, ext] = fileparts(fileName);

                            body.DATA         = datestr(now, 'dd/mm/yyyy');
                            body.NOME_ARQUIVO = [name, ext];
                        end

                        endPoint = [obj.url.(env) '/incluirDocumentoSei'];
                        response = ws.WebServiceBase.request(endPoint, 'POST', header, body);
        
                        if ~isfield(response.Body.Data, 'StrRetornoInclusaoDocumento')
                            error('ws:eFiscaliza:RequestFailed', response.show)
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

                    %-----------------------------------------------------%
                    % ## eFiscaliza DS ##
                    %-----------------------------------------------------%
                    case 'queryIssue-DS'
                        if ~strcmp(issue.type, 'ATIVIDADE DE INSPEÇÃO')
                            error('ws:eFiscaliza:UnexpectedIssueType', 'Unexpected issue type "%s"', issue.type)
                        end

                        endPoint = sprintf('%s/atividades/%s', obj.url.(env), string(issue.id));
                        response = ws.WebServiceBase.request(endPoint, 'GET', header);
        
                        if any(~isfield(response.Body.Data, {'usuario', 'atividadeInspecao'}))
                            error('ws:eFiscaliza:RequestFailed', response.show)
                        end
        
                        msg = struct( ...
                            'issueId', issue.id, ...
                            'issueTree', struct( ...
                                'solicitacao', response.Body.Data.atividadeInspecao.("coInspecSolicitacao").value, ...
                                'acao', response.Body.Data.atividadeInspecao.("coInspecAcao").value, ...
                                'atividade',   response.Body.Data.atividadeInspecao.("coInspecAtividade").value ...
                            ), ...
                            'unit', response.Body.Data.atividadeInspecao.("sgUnidadeExecutante").value, ...
                            'description', response.Body.Data.atividadeInspecao.("deInspecAtividade").value, ...
                            'period', sprintf( ...
                                '%s a %s', ...
                                response.Body.Data.atividadeInspecao.("dtInicioDesejado").value, ...
                                response.Body.Data.atividadeInspecao.("dtFimDesejado").value ...
                            ), ...
                            'fiscais', {{response.Body.Data.atividadeInspecao.("noFiscalResponsavel").value}}, ... % PENDENTE LISTA DE FISCAIS
                            'sei', response.Body.Data.atividadeInspecao.("nuSeiProcesso").value, ...
                            'usuario', response.Body.Data.usuario ...
                        );

                    case {'uploadDocument-DS', 'uploadExternalDocument-DS'}
                        if ~ismember(issue.type, {'ATIVIDADE DE INSPEÇÃO'})
                            error('ws:eFiscaliza:UnexpectedIssueType', 'Unexpected issue type "%s"', issue.type)
                        end

                        unit     = varargin{1};
                        docSpec  = varargin{2};
                        fileName = varargin{3};

                        fileId = fopen(fileName);
                        byteArray = fread(fileId, [1, inf], 'uint8=>uint8');
                        fclose(fileId);
                        fileContent = matlab.net.base64encode(byteArray);

                        body = struct( ...
                            'conteudo', fileContent, ...
                            'tipo', docSpec.originId, ...
                            'tipologia', docSpec.typeId, ...
                            'descricao', docSpec.description, ...
                            'observacao', docSpec.note, ...
                            'nivelAcesso', docSpec.accessLevelId, ...
                            'hipoteseLegal', docSpec.legalBasisId, ...
                            'unidadeGeradora', unit ...
                        );

                        if isfield(docSpec, 'interessados')
                            body.interessados = docSpec.interessados;
                        end

                        if isfield(docSpec, 'nomeArvore')
                            body.nomeArvore = docSpec.nomeArvore;
                        end

                        if strcmp(operation, 'uploadExternalDocument-DS')
                            [~, name, ext] = fileparts(fileName);

                            body.data = datestr(now, 'dd/mm/yyyy');
                            body.nomeArquivo = [name, ext];
                        end

                        endPoint = sprintf('%s/atividades/%d/documento-SEI', obj.url.(env), issue.id);
                        response = ws.WebServiceBase.request(endPoint, 'POST', header, body);
        
                        if ~isstruct(response.Body.Data) || ~isfield(response.Body.Data, 'successo') || ~response.Body.Data.successo
                            error('ws:eFiscaliza:RequestFailed', response.show)
                        end
        
                        sei  = response.Body.Data.documentoFormatado;
                        link = response.Body.Data.linkAcesso;
                        msg  = sprintf( ...
                            '<b>%s: %s</b>\nDocumento cadastrado no SEI sob o nº <a href="%s" target="_blank">%s</a>', ...
                            response.StatusCode, ...
                            response.StatusLine, ...
                            link, ...
                            sei ...
                        );
    
                    otherwise
                        error('ws:eFiscaliza:UnexpectedOperation', 'Unexpected operation "%s"', operation)
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