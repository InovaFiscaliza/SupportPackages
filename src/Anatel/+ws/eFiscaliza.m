classdef eFiscaliza < ws.WebServiceBase

    properties
        %-----------------------------------------------------------------%
        mfaLogin (1, 1) logical = false
        login = ''
        password = ''
    end


    properties (Constant)
        %-----------------------------------------------------------------%
        BASE_URL = struct( ...
            'DS', 'https://appsnetds.anatel.gov.br/eFiscaliza_API/rest/servico', ...
            'HM', 'https://appsnethm/eFiscaliza_API/rest/servico', ...
            'TS', 'https://appsnetts.anatel.gov.br/eFiscaliza_API/rest/servico', ...
            'PD', 'https://appsnet/eFiscaliza_API/rest/servico' ...
        )

        CURRENT_USER_URL = 'https://fiscalizacao.anatel.gov.br/rffusion/api/users/me'
    end


    methods
        %-----------------------------------------------------------------%
        function obj = eFiscaliza(loginMode, login, password)
            arguments
                loginMode char {mustBeMember(loginMode, {'mfa', 'manual'})}
                login char
                password char
            end

            obj.mfaLogin = strcmp(loginMode, 'mfa');
            
            if contains(login, '@')
                login = extractBefore(login, '@');
            end
            obj.login = login;

            obj.password = ws.WebServiceBase.base64encode(password);
        end

        %-----------------------------------------------------------------%
        function delete(obj)
            % Login automático (sessão F5 Big-IP) não pode ser descartado 
            % manualmente
            if ~obj.mfaLogin
                return
            end

            obj.login = '';
            obj.password = '';
        end

        %-----------------------------------------------------------------%
        function [msg, seiReport] = run(obj, env, operation, issue, varargin)
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

            seiReport = '';

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
                        endPoint = sprintf('%s/atividades/%s/contexto', obj.BASE_URL.(env), string(issue.id));
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

                        endPoint = sprintf('%s/atividades/%d/documento-SEI', obj.BASE_URL.(env), issue.id);
                        response = ws.WebServiceBase.request(endPoint, 'POST', header, body);
        
                        if ~isstruct(response.Body.Data) || ~isfield(response.Body.Data, 'sei') || ~isstruct(response.Body.Data.sei) || any(~isfield(response.Body.Data.sei, {'documentoFormatado', 'linkAcesso'})) || isempty(response.Body.Data.sei.documentoFormatado)
                            error('ws:eFiscaliza:RequestFailed', '%s\n%s', response.show, jsonencode(response.Body.Data))
                        end
        
                        seiReport = response.Body.Data.sei.documentoFormatado;
                        link = response.Body.Data.sei.linkAcesso;
                        msg = sprintf([ ...
                            '<b>%s: %s</b>\nDocumento cadastrado no SEI sob ' ...
                            'o nº <a href="%s" target="_blank">%s</a>' ...
                        ], response.StatusCode, response.StatusLine, link, seiReport);

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
    end


    methods (Static = true)
        %-----------------------------------------------------------------%
        function varargout = getCredentials(loginMode, executionMode, jsBackDoor, eventName, context)
            varargout = {};

            switch loginMode
                case 'manual'
                    createDialog()

                otherwise % 'auto'
                    try
                        url = ws.eFiscaliza.CURRENT_USER_URL;

                        switch executionMode
                            case 'webApp'
                                sendEventToHTMLSource(jsBackDoor, 'getAuthenticatedUser', struct('eventName', eventName, 'url', url));

                            otherwise
                                session = ws.auth.F5Session(url);
                                login(session)
                                [~, response] = readRaw(session, url);
                                credentials = jsondecode(response.Body.Data);
                                varargout = {struct('mfaLogin', true, 'login', credentials.NA_USER_EMAIL, 'password', '123456')};
                        end

                    catch
                        createDialog()
                    end
            end

            function createDialog()
                dialogBox = [
                    struct('id', 'login',    'label', 'Usuário: ', 'type', 'text');
                    struct('id', 'password', 'label', 'Senha: ',   'type', 'password')
                ];
                sendEventToHTMLSource(jsBackDoor, 'customForm', struct('UUID', eventName, 'Fields', dialogBox, 'Context', context));
            end
        end

        %-----------------------------------------------------------------%
        function id = serviceMapping(id)
            arguments
                id (1,1) int16
            end

            global id2nameTable
            
            if isempty(id2nameTable)
                MFilePath    = fileparts(mfilename('fullpath'));
                fileName     = fullfile(MFilePath, 'eFiscaliza', 'serviceMapping.xlsx');
                id2nameTable = readtable(fileName, 'VariableNamingRule', 'preserve');
                id2nameTable.ID = int16(id2nameTable.ID);
            end

            [~, idxFind] = ismember(id, id2nameTable.ID);
            if idxFind
                id = id2nameTable.("Serviço"){idxFind};
            else
                id = num2str(id);
            end
        end
    end

end