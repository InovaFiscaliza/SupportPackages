classdef F5Session < handle

    % ws.auth.F5Session
    % Sessão autenticada em aplicações publicadas atrás do proxy reverso
    % F5 BIG-IP APM (federação SAML 2.0 com Azure AD + MFA).
    %
    % O login é SEMPRE interativo: uma janela de navegador embarcada
    % (matlab.internal.webwindow, runtime CEF do próprio MATLAB) é aberta na
    % URL protegida, o usuário completa o fluxo SAML e aprova o push do
    % Microsoft Authenticator. Concluído o login, os cookies de sessão do F5
    % (LastMRH_Session, F5_ST e demais presentes) são lidos via document.cookie
    % e mantidos EXCLUSIVAMENTE EM MEMÓRIA, pelo tempo de vida deste objeto.
    % Nada é gravado em disco nem reaproveitado entre execuções.
    %
    % Exemplo:
    %   session = ws.auth.F5Session('https://host/app');
    %   login(session)
    %   data = read(session, 'https://host/app/api/v1/lookup?locations=-24,-52');
    %   delete(session)

    properties (SetAccess = immutable)
        %LoginURL URL protegida usada para disparar o fluxo SAML.
        LoginURL (1,:) char
    end

    properties (Dependent, SetAccess = private)
        IsAuthenticated
    end

    properties (Access = private, Transient, NonCopyable)
        CookieHeader     (1,:) char    = ''
        Browser                        = []
        IsBrowserVisible (1,1) logical = false
        InteractionDone  (1,1) logical = false
    end

    properties (Constant, Access = private)
        RequiredCookies = ["LastMRH_Session", "F5_ST"]
        PollInterval    = 0.25

        % Tempo tolerado antes de exibir a janela: sessão ainda válida no CEF
        % faz o landing ocorrer sem qualquer interação do usuário.
        SilentLoginGracePeriod = 2
    end


    methods
        %-----------------------------------------------------------------%
        function obj = F5Session(loginURL)
            arguments
                loginURL (1,:) char {mustBeNonempty}
            end

            if ~startsWith(loginURL, 'https://', 'IgnoreCase', true)
                error('ws:auth:F5Session:insecureURL', 'A URL de login deve usar HTTPS.')
            end
            obj.LoginURL = loginURL;
        end

        %-----------------------------------------------------------------%
        function delete(obj)
            logout(obj)
        end

        %-----------------------------------------------------------------%
        function tf = get.IsAuthenticated(obj)
            tf = ~isempty(obj.CookieHeader);
        end
    end


    methods
        %-----------------------------------------------------------------%
        function login(obj, timeout)
            % LOGIN Abre a janela de autenticação e aguarda o usuário concluir
            % o fluxo SAML + MFA. Bloqueia até obter os cookies de sessão.

            arguments
                obj
                timeout (1,1) double {mustBePositive, mustBeFinite} = 300
            end

            logout(obj)

            openBrowser(obj)
            browserCleanup = onCleanup(@() closeBrowser(obj));

            startTime = tic;
            while true
                if ~isBrowserAlive(obj)
                    error('ws:auth:F5Session:windowClosed', 'Janela de autenticação fechada antes da conclusão do login.')
                end

                if toc(startTime) > timeout
                    error('ws:auth:F5Session:timeout', 'Tempo esgotado (%d s) aguardando a conclusão do login.', round(timeout))
                end

                state = probeBrowser(obj);
                if hasLanded(obj, state)
                    obj.CookieHeader = strtrim(state.cookie);
                    break
                end

                if obj.IsBrowserVisible
                    % Oculta já no retorno ao host protegido (POST do SAMLResponse
                    % ao ACS), antes que a página final chegue a ser pintada.
                    if isOnTargetHost(obj, state)
                        hideBrowser(obj)
                    end

                elseif ~obj.InteractionDone && needsUserInteraction(obj, state, toc(startTime))
                    showBrowser(obj)
                end

                pause(obj.PollInterval)
                drawnow limitrate
            end
        end

        %-----------------------------------------------------------------%
        function logout(obj)
            % LOGOUT Descarta a sessão em memória e fecha a janela embarcada.

            closeBrowser(obj)

            % Sobrescreve o buffer antes de liberá-lo.
            obj.CookieHeader(:) = ' ';
            obj.CookieHeader    = '';
        end

        %-----------------------------------------------------------------%
        function [data, response] = read(obj, url, autoReauthenticate)
            % READ Requisição GET autenticada, com o payload convertido pelo
            % tipo de conteúdo (JSON vira struct, texto vira char).

            arguments
                obj
                url                (1,:) char {mustBeNonempty}
                autoReauthenticate (1,1) logical = true
            end

            [data, response] = fetch(obj, url, true, autoReauthenticate, []);
        end

        %-----------------------------------------------------------------%
        function [data, response] = readBytes(obj, url, autoReauthenticate, progressFcn)
            % READBYTES Requisição GET autenticada sem conversão do payload,
            % devolvendo uint8. Uso obrigatório para conteúdo binário, que
            % seria corrompido caso o servidor o rotulasse como texto.
            %
            % progressFcn, se informado, é chamado como f(bytesRecebidos,
            % bytesTotais). O total fica vazio se o servidor não enviar
            % Content-Length.

            arguments
                obj
                url                (1,:) char {mustBeNonempty}
                autoReauthenticate (1,1) logical = true
                progressFcn                      = []
            end

            [data, response] = fetch(obj, url, false, autoReauthenticate, progressFcn);

            if ~isa(data, 'uint8')
                error('ws:auth:F5Session:unexpectedPayload', 'Payload inesperado (%s) em leitura crua.', class(data))
            end
        end

        %-----------------------------------------------------------------%
        function info = downloadToFile(obj, url, filePath, autoReauthenticate, progressFcn, maxRetries, retryDelay)
            % DOWNLOADTOFILE Transfere o payload em blocos diretamente para disco.
            % Evita manter arquivos grandes inteiros na memória do MATLAB.
            %
            % Em caso de queda de conexão durante a transferência, a operação
            % é reiniciada automaticamente (até maxRetries vezes, com espera
            % crescente de retryDelay segundos). O download é retomado a
            % partir dos bytes já gravados via cabeçalho Range, caso o
            % servidor suporte; caso contrário, reinicia do zero.

            arguments
                obj
                url                (1,:) char {mustBeNonempty}
                filePath           (1,:) char {mustBeNonempty}
                autoReauthenticate (1,1) logical = true
                progressFcn                      = []
                maxRetries         (1,1) double {mustBeInteger, mustBeNonnegative} = 3
                retryDelay         (1,1) double {mustBeNonnegative} = 2
            end

            assertAuthenticated(obj)
            info = streamToFileWithRetry(obj, url, filePath, progressFcn, maxRetries, retryDelay);

            if (info.StatusCode >= 300 && info.StatusCode < 400) || info.StatusCode == 401 || info.StatusCode == 403
                if ~autoReauthenticate
                    error('ws:auth:F5Session:sessionExpired', 'Sessão F5 expirada ou invalidada. Refaça a autenticação.')
                end

                if isfile(filePath)
                    delete(filePath)
                end
                login(obj)
                info = streamToFileWithRetry(obj, url, filePath, progressFcn, maxRetries, retryDelay);
            end

            if info.StatusCode < 200 || info.StatusCode >= 300
                if isfile(filePath)
                    delete(filePath)
                end
                error('ws:auth:F5Session:httpError', 'Requisição retornou HTTP %d (%s).', info.StatusCode, info.StatusMessage)
            end
        end

        %-----------------------------------------------------------------%
        function info = debugInfo(obj)
            % DEBUGINFO Diagnóstico da sessão. Expõe nomes e quantidade de
            % cookies - nunca seus valores, que não saem desta classe.

            cookies = ws.auth.F5Session.parseCookieHeader(obj.CookieHeader);
            info = struct('LoginURL',        obj.LoginURL,       ...
                          'IsAuthenticated', obj.IsAuthenticated, ...
                          'CookieCount',     numel(cookies),      ...
                          'CookieNames',     string({cookies.Name}));
        end
    end


    methods (Access = private)
        %-----------------------------------------------------------------%
        function info = streamToFileWithRetry(obj, url, filePath, progressFcn, maxRetries, retryDelay)
            % Reinicia a transferência (retomando via Range quando possível)
            % até maxRetries vezes se a conexão cair no meio do download.
            % Erros HTTP (4xx/5xx) não geram exceção aqui - streamToFile os
            % devolve em info.StatusCode - e portanto não são reexecutados.

            attempt = 0;
            while true
                resumeOffset = 0;
                if isfile(filePath)
                    fileInfo = dir(filePath);
                    resumeOffset = fileInfo.bytes;
                end

                try
                    info = streamToFile(obj, url, filePath, progressFcn, resumeOffset);
                    return
                catch downloadError
                    if strcmp(downloadError.identifier, 'ws:auth:F5Session:fileOpenFailed') || attempt >= maxRetries
                        rethrow(downloadError)
                    end
                    attempt = attempt + 1;
                    pause(retryDelay * attempt)
                end
            end
        end

        %-----------------------------------------------------------------%
        function info = streamToFile(obj, url, filePath, progressFcn, resumeOffset)
            % Usa matlab.net.http (mesma API já empregada em sendRequest) em vez
            % de java.net/java.io: FileConsumer grava o corpo da resposta em
            % disco em blocos, sem o risco do antigo código Java, cujas leituras
            % em java.io.InputStream.read(byte[]) eram descartadas silenciosamente
            % (arrays MATLAB passados a métodos Java são convertidos por valor).

            arguments
                obj
                url          (1,:) char
                filePath     (1,:) char
                progressFcn
                resumeOffset (1,1) double = 0
            end

            header = matlab.net.http.HeaderField('Cookie', obj.CookieHeader);
            if resumeOffset > 0
                header(end+1) = matlab.net.http.HeaderField('Range', sprintf('bytes=%d-', resumeOffset));
            end
            request = matlab.net.http.RequestMessage('GET', header);

            % MaxRedirects=0 mantém visível o 302 do F5 para a página de login.
            options = matlab.net.http.HTTPOptions('MaxRedirects', 0, 'ConnectTimeout', 30);
            if ~isempty(progressFcn)
                options.ProgressMonitorFcn = @() ws.auth.DownloadProgressMonitor(progressFcn);
                options.UseProgressMonitor = true;
            end

            if resumeOffset > 0
                fileID = fopen(filePath, 'ab');
            else
                fileID = fopen(filePath, 'wb');
            end
            if fileID == -1
                error('ws:auth:F5Session:fileOpenFailed', 'Não foi possível gravar em "%s".', filePath)
            end
            fileCleanup = onCleanup(@() fclose(fileID));

            consumer = matlab.net.http.io.FileConsumer(fileID);
            response = request.send(url, options, consumer);

            statusCode = double(response.StatusCode);
            contentLengthField = response.getFields('Content-Length');
            if isempty(contentLengthField)
                contentLength = [];
            else
                contentLength = str2double(contentLengthField.Value);
            end

            info = struct('StatusCode', statusCode, ...
                          'StatusMessage', char(response.StatusCode), ...
                          'ContentLength', contentLength);
            if statusCode < 200 || statusCode >= 300
                return
            end

            % Servidor pode ignorar o Range e devolver o conteúdo inteiro (200);
            % nesse caso o arquivo ficou com o conteúdo completo duplicado após
            % os bytes já gravados, então é descartado e o download reinicia.
            if resumeOffset > 0 && statusCode == 200
                fileCleanup = []; %#ok<NASGU> fecha o arquivo antes de apagá-lo
                delete(filePath)
                info = streamToFile(obj, url, filePath, progressFcn, 0);
                return
            end

            info.BytesReceived = ftell(fileID) - resumeOffset;
        end

        %-----------------------------------------------------------------%
        function openBrowser(obj)
            if ~exist('matlab.internal.webwindow', 'class')
                error('ws:auth:F5Session:unsupportedRelease', 'matlab.internal.webwindow indisponível nesta versão do MATLAB.')
            end

            obj.Browser = matlab.internal.webwindow(obj.LoginURL);
            obj.Browser.Title = 'Autenticação';
            obj.Browser.CustomWindowClosingCallback = @(src, ~) src.close();

            screenSize = get(groot, 'ScreenSize');
            windowSize = [min(1000, screenSize(3)-100), min(800, screenSize(4)-100)];
            obj.Browser.Position = [(screenSize(3)-windowSize(1))/2, (screenSize(4)-windowSize(2))/2, windowSize];
        end

        %-----------------------------------------------------------------%
        function showBrowser(obj)
            if obj.IsBrowserVisible || ~isBrowserAlive(obj)
                return
            end

            obj.Browser.show()
            obj.Browser.bringToFront()
            obj.IsBrowserVisible = true;
        end

        %-----------------------------------------------------------------%
        function hideBrowser(obj)
            if isBrowserAlive(obj)
                obj.Browser.hide()
            end
            obj.IsBrowserVisible = false;
            obj.InteractionDone  = true;
        end

        %-----------------------------------------------------------------%
        function tf = needsUserInteraction(obj, state, elapsedTime)
            % A janela só é exibida quando o fluxo sai do host protegido
            % (redirecionamento ao Azure AD ou ao /my.policy do APM) ou
            % quando o landing silencioso demora mais que o tolerado.

            tf = true;
            if elapsedTime > obj.SilentLoginGracePeriod
                return
            end

            tf = false;
            if isempty(state) || ~isstruct(state) || ~isfield(state, 'url')
                return
            end

            try
                tf = ~strcmpi(matlab.net.URI(state.url).Host, matlab.net.URI(obj.LoginURL).Host) || ...
                      contains(state.url, 'my.policy', 'IgnoreCase', true);
            catch
            end
        end

        %-----------------------------------------------------------------%
        function closeBrowser(obj)
            if isBrowserAlive(obj)
                obj.Browser.close()
            end
            obj.Browser = [];
            obj.IsBrowserVisible = false;
            obj.InteractionDone  = false;
        end

        %-----------------------------------------------------------------%
        function tf = isBrowserAlive(obj)
            tf = ~isempty(obj.Browser) && isvalid(obj.Browser) && obj.Browser.isWindowValid;
        end

        %-----------------------------------------------------------------%
        function state = probeBrowser(obj)
            % Durante os redirecionamentos do fluxo SAML a avaliação pode
            % falhar - nesse caso a próxima iteração do polling tenta de novo.

            state = [];
            try
                rawValue = obj.Browser.executeJS('JSON.stringify({url: window.location.href, cookie: document.cookie})');
                state    = ws.auth.F5Session.decodeJSResult(rawValue);
            catch
            end
        end

        %-----------------------------------------------------------------%
        function tf = isOnTargetHost(obj, state)
            tf = false;
            if isempty(state) || ~isstruct(state) || ~isfield(state, 'url')
                return
            end

            try
                tf = strcmpi(matlab.net.URI(state.url).Host, matlab.net.URI(obj.LoginURL).Host) && ...
                     ~contains(state.url, 'my.policy', 'IgnoreCase', true);
            catch
            end
        end

        %-----------------------------------------------------------------%
        function tf = hasLanded(obj, state)
            tf = false;
            if ~isOnTargetHost(obj, state) || ~isfield(state, 'cookie')
                return
            end

            cookieNames = string({ws.auth.F5Session.parseCookieHeader(state.cookie).Name});
            tf = all(ismember(obj.RequiredCookies, cookieNames));
        end

        %-----------------------------------------------------------------%
        function assertAuthenticated(obj)
            if ~obj.IsAuthenticated
                error('ws:auth:F5Session:notAuthenticated', 'Sessão não autenticada. Execute login(session) antes.')
            end
        end

        %-----------------------------------------------------------------%
        function [data, response] = fetch(obj, url, convertResponse, autoReauthenticate, progressFcn)
            % Redirecionamentos para a página de login (sessão expirada ou
            % invalidada) são detectados e, por padrão, disparam nova
            % autenticação interativa.

            assertAuthenticated(obj)

            response = sendRequest(obj, url, convertResponse, progressFcn);
            if ws.auth.F5Session.isSessionExpired(response)
                if ~autoReauthenticate
                    error('ws:auth:F5Session:sessionExpired', 'Sessão F5 expirada ou invalidada. Refaça a autenticação.')
                end

                login(obj)
                response = sendRequest(obj, url, convertResponse, progressFcn);

                if ws.auth.F5Session.isSessionExpired(response)
                    error('ws:auth:F5Session:sessionExpired', 'Sessão F5 expirada ou invalidada mesmo após nova autenticação.')
                end
            end

            if response.StatusCode ~= matlab.net.http.StatusCode.OK
                error('ws:auth:F5Session:httpError', 'Requisição retornou HTTP %d (%s).', double(response.StatusCode), char(response.StatusCode))
            end
            data = response.Body.Data;
        end

        %-----------------------------------------------------------------%
        function response = sendRequest(obj, url, convertResponse, progressFcn)
            header  = matlab.net.http.HeaderField('Cookie', obj.CookieHeader);
            request = matlab.net.http.RequestMessage('GET', header);

            % MaxRedirects=0 mantém visível o 302 do F5 para a página de login.
            options = matlab.net.http.HTTPOptions('MaxRedirects', 0, 'ConnectTimeout', 30, 'ConvertResponse', convertResponse);

            if ~isempty(progressFcn)
                options.ProgressMonitorFcn = @() ws.auth.DownloadProgressMonitor(progressFcn);
                options.UseProgressMonitor = true;
            end

            response = request.send(url, options);
        end
    end


    methods (Static, Access = private)
        %-----------------------------------------------------------------%
        function value = decodeJSResult(rawValue)
            % executeJS devolve o resultado codificado em JSON - e aqui o
            % próprio resultado já é uma string JSON, daí a dupla decodificação.

            value = rawValue;
            for ii = 1:2
                if ~(ischar(value) || isStringScalar(value))
                    break
                end
                value = jsondecode(char(value));
            end
        end

        %-----------------------------------------------------------------%
        function cookies = parseCookieHeader(cookieHeader)
            cookies = struct('Name', {}, 'Value', {});

            tokens = strtrim(strsplit(char(cookieHeader), ';'));
            tokens(cellfun(@isempty, tokens)) = [];

            for ii = 1:numel(tokens)
                idx = find(tokens{ii} == '=', 1);
                if isempty(idx)
                    continue
                end
                cookies(end+1) = struct('Name', tokens{ii}(1:idx-1), 'Value', tokens{ii}(idx+1:end)); %#ok<AGROW>
            end
        end
    end


    methods (Static)
        %-----------------------------------------------------------------%
        function tf = isSessionExpired(response)
            % ISSESSIONEXPIRED Identifica resposta de sessão inválida: 401/403,
            % redirecionamento do APM para o login, ou HTML de login no lugar
            % do payload da API.

            arguments
                response (1,1) matlab.net.http.ResponseMessage
            end

            statusCode = double(response.StatusCode);
            if ismember(statusCode, [401, 403]) || (statusCode >= 300 && statusCode < 400)
                tf = true;
                return
            end

            payload = '';
            if ~isempty(response.Body)
                if ischar(response.Body.Data) || isStringScalar(response.Body.Data)
                    payload = char(response.Body.Data);

                elseif isa(response.Body.Data, 'uint8')
                    % Em leitura crua o HTML de login também chega como bytes.
                    payload = char(response.Body.Data(1:min(end, 2048))');
                end
            end
            tf = contains(payload, {'my.policy', 'SAMLRequest', 'login.microsoftonline.com'}, 'IgnoreCase', true);
        end
    end

end
