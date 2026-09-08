classdef F5Session < handle

    % ws.auth.F5Session
    % Authenticated session in applications published behind the F5 BIG-IP APM
    % reverse proxy (SAML 2.0 federation with Azure AD + MFA).
    %
    % Login is ALWAYS interactive: an embedded browser window
    % (matlab.internal.webwindow, MATLAB's own CEF runtime) is opened at the
    % protected URL, the user completes the SAML flow and approves the Microsoft
    % Authenticator push. Once login is completed, the F5 session cookies
    % (LastMRH_Session, F5_ST and others present) are read via document.cookie
    % and maintained EXCLUSIVELY IN MEMORY, for the lifetime of this object.
    % Nothing is written to disk or reused between executions.
    %
    % Example:
    %   session = ws.auth.F5Session('https://host/app');
    %   login(session)
    %   data = read(session, 'https://host/app/api/v1/lookup?locations=-24,-52');
    %   delete(session)

    properties (SetAccess = immutable)
        %LoginURL Protected URL used to trigger the SAML flow.
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

        % Time tolerated before displaying the window: a still valid session in CEF
        % makes the landing occur without any user interaction.
        SilentLoginGracePeriod = 2
    end


    methods
        %-----------------------------------------------------------------%
        function obj = F5Session(loginURL)
            arguments
                loginURL (1,:) char {mustBeNonempty}
            end

            if ~startsWith(loginURL, 'https://', 'IgnoreCase', true)
                error('ws:auth:F5Session:insecureURL', 'Login URL must use HTTPS.')
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
            % LOGIN Opens the authentication window and waits for the user to complete
            % the SAML + MFA flow. Blocks until session cookies are obtained.

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
                    error('ws:auth:F5Session:windowClosed', 'Authentication window closed before login completion.')
                end

                if toc(startTime) > timeout
                    error('ws:auth:F5Session:timeout', 'Time expired (%d s) waiting for login completion.', round(timeout))
                end

                state = probeBrowser(obj);
                if hasLanded(obj, state)
                    obj.CookieHeader = strtrim(state.cookie);
                    break
                end

                if obj.IsBrowserVisible
                    % Hides already on return to the protected host (POST of SAMLResponse
                    % to ACS), before the final page is even painted.
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
            % LOGOUT Discards the in-memory session and closes the embedded window.

            closeBrowser(obj)

            % Overwrites the buffer before releasing it.
            obj.CookieHeader(:) = ' ';
            obj.CookieHeader    = '';
        end

        %-----------------------------------------------------------------%
        function [data, response] = read(obj, url, autoReauthenticate)
            % READ Authenticated GET request, with payload converted by
            % content type (JSON becomes struct, text becomes char).

            arguments
                obj
                url                (1,:) char {mustBeNonempty}
                autoReauthenticate (1,1) logical = true
            end

            [data, response] = fetch(obj, url, true, autoReauthenticate, []);
        end

        %-----------------------------------------------------------------%
        function [data, response] = readBytes(obj, url, autoReauthenticate, progressFcn)
            % READBYTES Authenticated GET request without payload conversion,
            % returning uint8. Mandatory for binary content, which
            % would be corrupted if the server labeled it as text.
            %
            % progressFcn, if provided, is called as f(bytesReceived,
            % totalBytes). Total is empty if the server does not send
            % Content-Length.

            arguments
                obj
                url                (1,:) char {mustBeNonempty}
                autoReauthenticate (1,1) logical = true
                progressFcn                      = []
            end

            [data, response] = fetch(obj, url, false, autoReauthenticate, progressFcn);

            if ~isa(data, 'uint8')
                error('ws:auth:F5Session:unexpectedPayload', 'Unexpected payload (%s) in raw reading.', class(data))
            end
        end

        %-----------------------------------------------------------------%
        function info = downloadToFile(obj, url, filePath, autoReauthenticate, progressFcn, maxRetries, retryDelay)
            % DOWNLOADTOFILE Transfers the payload in blocks directly to disk.
            % Avoids keeping large files entirely in MATLAB's memory.
            %
            % In case of connection drop during transfer, the operation
            % is automatically restarted (up to maxRetries times, with increasing
            % wait of retryDelay seconds). The download resumes from
            % already written bytes via Range header, if the
            % server supports it; otherwise, restarts from zero.

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
                    error('ws:auth:F5Session:sessionExpired', 'F5 session expired or invalidated. Re-authenticate.')
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
                error('ws:auth:F5Session:httpError', 'Request returned HTTP %d (%s).', info.StatusCode, info.StatusMessage)
            end
        end

        %-----------------------------------------------------------------%
        function info = debugInfo(obj)
            % DEBUGINFO Session diagnostics. Exposes names and quantity of
            % cookies - never their values, which do not leave this class.

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
            % Restarts the transfer (resuming via Range when possible)
            % up to maxRetries times if the connection drops during download.
            % HTTP errors (4xx/5xx) do not generate exceptions here - streamToFile
            % returns them in info.StatusCode - and therefore are not re-executed.

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
            % Uses matlab.net.http (same API already used in sendRequest) instead of
            % java.net/java.io: FileConsumer writes the response body to
            % disk in blocks, without the risk of the old Java code, whose readings
            % in java.io.InputStream.read(byte[]) were silently discarded
            % (MATLAB arrays passed to Java methods are converted by value).

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

            % MaxRedirects=0 keeps the F5's 302 to the login page visible.
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
                error('ws:auth:F5Session:fileOpenFailed', 'Could not write to "%s".', filePath)
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

            % Server may ignore Range and return the entire content (200);
            % in this case the file ended up with the complete content duplicated after
            % the bytes already written, so it is discarded and the download restarts.
            if resumeOffset > 0 && statusCode == 200
                fileCleanup = []; %#ok<NASGU> closes the file before deleting it
                delete(filePath)
                info = streamToFile(obj, url, filePath, progressFcn, 0);
                return
            end

            info.BytesReceived = ftell(fileID) - resumeOffset;
        end

        %-----------------------------------------------------------------%
        function openBrowser(obj)
            if ~exist('matlab.internal.webwindow', 'class')
                error('ws:auth:F5Session:unsupportedRelease', 'matlab.internal.webwindow unavailable in this MATLAB version.')
            end

            obj.Browser = matlab.internal.webwindow(obj.LoginURL);
            obj.Browser.Title = 'Authentication';
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
            % The window is only displayed when the flow leaves the protected host
            % (redirect to Azure AD or to the APM's /my.policy) or
            % when silent landing takes longer than tolerated.

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
            % During SAML flow redirects the evaluation may
            % fail - in this case the next polling iteration tries again.

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
                error('ws:auth:F5Session:notAuthenticated', 'Session not authenticated. Execute login(session) first.')
            end
        end

        %-----------------------------------------------------------------%
        function [data, response] = fetch(obj, url, convertResponse, autoReauthenticate, progressFcn)
            % Redirects to the login page (session expired or
            % invalidated) are detected and, by default, trigger new
            % interactive authentication.

            assertAuthenticated(obj)

            response = sendRequest(obj, url, convertResponse, progressFcn);
            if ws.auth.F5Session.isSessionExpired(response)
                if ~autoReauthenticate
                    error('ws:auth:F5Session:sessionExpired', 'F5 session expired or invalidated. Re-authenticate.')
                end

                login(obj)
                response = sendRequest(obj, url, convertResponse, progressFcn);

                if ws.auth.F5Session.isSessionExpired(response)
                    error('ws:auth:F5Session:sessionExpired', 'F5 session expired or invalidated even after new authentication.')
                end
            end

            if response.StatusCode ~= matlab.net.http.StatusCode.OK
                error('ws:auth:F5Session:httpError', 'Request returned HTTP %d (%s).', double(response.StatusCode), char(response.StatusCode))
            end
            data = response.Body.Data;
        end

        %-----------------------------------------------------------------%
        function response = sendRequest(obj, url, convertResponse, progressFcn)
            header  = matlab.net.http.HeaderField('Cookie', obj.CookieHeader);
            request = matlab.net.http.RequestMessage('GET', header);

            % MaxRedirects=0 keeps the F5's 302 to the login page visible.
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
            % executeJS returns the result encoded in JSON - and here the
            % result itself is already a JSON string, hence the double decoding.

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
            % ISSESSIONEXPIRED Identifies invalid session response: 401/403,
            % APM redirect to login, or login HTML instead of
            % API payload.

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
                    % In raw reading the login HTML also arrives as bytes.
                    payload = char(response.Body.Data(1:min(end, 2048))');
                end
            end
            tf = contains(payload, {'my.policy', 'SAMLRequest', 'login.microsoftonline.com'}, 'IgnoreCase', true);
        end
    end

end
