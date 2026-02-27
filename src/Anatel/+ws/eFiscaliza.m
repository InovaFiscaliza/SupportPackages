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
                if ~strcmp(issue.type, 'ATIVIDADE DE INSPEÇÃO')
                    error('ws:eFiscaliza:UnexpectedIssueType', 'Unexpected issue type "%s"', issue.type)
                end


                header = {'Authorization', ['Basic ' ws.WebServiceBase.base64encode([obj.login ':' obj.password])], ...
                          'Content-Type', 'application/json'};
            
                switch operation
                    %-----------------------------------------------------%
                    % ## eFiscaliza HM/TS/PD ##
                    % (inclui DS, caso idêntico ao PD)
                    %-----------------------------------------------------%
                    case {'queryIssue', 'queryIssue-DS'}
                        endPoint = sprintf('%s/atividades/%s/contexto', obj.url.(env), string(issue.id));
                        response = ws.WebServiceBase.request(endPoint, 'GET', header);
        
                        if ~isstruct(response.Body.Data) || any(~isfield(response.Body.Data, {'solicitacao', 'acao', 'atividade', 'usuario'}))
                            error('ws:eFiscaliza:RequestFailed', response.show)
                        end
        
                        msg = struct( ...
                            'issueId', issue.id, ...
                            'issueContext', struct( ...
                                'solicitacao', response.Body.Data.solicitacao, ...
                                'acao', response.Body.Data.acao, ...
                                'atividade', response.Body.Data.atividade ...
                            ), ...
                            'usuario', response.Body.Data.usuario ...
                        );

                    case {'uploadDocument', 'uploadExternalDocument', 'uploadDocument-DS', 'uploadExternalDocument-DS'}
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

                        if ismember(operation, {'uploadExternalDocument', 'uploadExternalDocument-DS'})
                            [~, name, ext] = fileparts(fileName);

                            body.data = datestr(now, 'dd/mm/yyyy');
                            body.nomeArquivo = [name, ext];
                        end

                        endPoint = sprintf('%s/atividades/%d/documento-SEI', obj.url.(env), issue.id);
                        response = ws.WebServiceBase.request(endPoint, 'POST', header, body);
        
                        if ~isstruct(response.Body.Data) || ~isfield(response.Body.Data, 'sei') || ~isstruct(response.Body.Data.sei) || any(~isfield(response.Body.Data.sei, {'documentoFormatado', 'linkAcesso'})) || isempty(response.Body.Data.sei.documentoFormatado)
                            error('ws:eFiscaliza:RequestFailed', '%s\n%s', response.show, jsonencode(response.Body.Data))
                        end
        
                        sei  = response.Body.Data.sei.documentoFormatado;
                        link = response.Body.Data.sei.linkAcesso;
                        msg  = sprintf( ...
                            '<b>%s: %s</b>\nDocumento cadastrado no SEI sob o nº <a href="%s" target="_blank">%s</a>', ...
                            response.StatusCode, ...
                            response.StatusLine, ...
                            link, ...
                            sei ...
                        );

                    %-----------------------------------------------------%
                    % ## eFiscaliza DS ##
                    % (realização de testes, quando a versão em DS difere 
                    % da versão em PD)
                    %-----------------------------------------------------%
                    % case 'queryIssue-DS'
                    %     % ...
                    
                    % case {'uploadDocument-DS', 'uploadExternalDocument-DS'}
                    %     % ...
    
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