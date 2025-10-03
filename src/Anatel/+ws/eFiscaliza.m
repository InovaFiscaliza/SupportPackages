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
            obj.password = base64encode(obj, password);
        end

        %-----------------------------------------------------------------%
        function msg = run(obj, env, operation, issue, varargin)
            arguments
                obj
                env       char {mustBeMember(env, {'DS', 'HM', 'TS', 'PD'})}
                operation char {mustBeMember(operation, {'uploadDocument', 'uploadExternalDocument'})}
                issue     struct
            end

            arguments (Repeating)
                varargin
            end

            try
                header = {'Authorization', ['Basic ' base64encode(obj, [obj.login ':' obj.password])], ...
                          'Content-Type', 'application/json'};
    
                switch issue.type
                    case 'AÇÃO DE INSPEÇÃO'
                        issueTypeFieldName = 'ID_INSPEC_ACAO';
                    case 'ATIVIDADE DE INSPEÇÃO'
                        issueTypeFieldName = 'ID_INSPEC_ATIVIDADE';
                end
            
                switch operation
                    case {'uploadDocument', 'uploadExternalDocument'}
                        unit     = varargin{1};
                        docSpec  = varargin{2};
                        fileName = varargin{3};
                        body     = struct(issueTypeFieldName, issue.id,              ...
                                          'UNIDADE_GERADORA', unit,                  ...
                                          'TIPO',             docSpec.originId,      ...
                                          'TIPOLOGIA',        docSpec.typeId,        ...
                                          'DESCRICAO',        docSpec.description,   ...
                                          'OBSERVACAO',       docSpec.note,          ...
                                          'NIVEL_ACESSO',     docSpec.accessLevelId, ...
                                          'HIPOTESE_LEGAL',   docSpec.legalBasisId,  ...
                                          'CONTEUDO',         base64encode(obj, fileread(fileName)));

                        if strcmp(operation, 'uploadExternalDocument')
                            [~, name, ext] = fileparts(fileName);

                            body.DATA         = datestr(now, 'dd/mm/yyyy');
                            body.NOME_ARQUIVO = [name, ext];
                        end
    
                    otherwise
                        error('UnexpectedCall')
                end

                endPoint = [obj.url.(env) '/incluirDocumentoSei'];
                response = ws.WebServiceBase.request(endPoint, 'POST', header, body);

                if ~isfield(response.Body.Data, 'StrRetornoInclusaoDocumento')
                    error(response.show)
                end

                sei  = response.Body.Data.StrRetornoInclusaoDocumento.DocumentoFormatado;
                link = response.Body.Data.StrRetornoInclusaoDocumento.LinkAcesso;
                msg  = sprintf('<b>%s: %s</b>\nDocumento cadastrado no SEI sob o nº <a href="%s" target="_blank">%s</a>', response.StatusCode, response.StatusLine, link, sei);

            catch ME
                msg  = ME.message;
            end
        end
    end

end