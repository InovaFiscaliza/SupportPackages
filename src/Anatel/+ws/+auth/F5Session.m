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
    % Cookie values stay in memory during normal operation. If debugFile is
    % supplied to login, the browser state may be written for diagnostics.
    %
    % The constructor argument is the URL used to start interactive login.
    % It is retained in LoginURL and reused for every reauthentication.
    %
    % Example:
    %   session = ws.auth.F5Session('https://host/app/login');
    %   login(session)
    %   data = read(session, 'https://host/app/api/v1/lookup?locations=-24,-52');
    %   delete(session)

    properties (SetAccess = immutable)
        %-----------------------------------------------------------------%
        LoginURL (1, :) char
    end


    properties (Dependent, SetAccess = private)
        %-----------------------------------------------------------------%
        IsAuthenticated
    end


    properties (Transient, SetAccess = private)
        %-----------------------------------------------------------------%
        UserProfile (1,1) struct = struct()
    end


    properties (Access = private, Transient, NonCopyable)
        %-----------------------------------------------------------------%
        CookieHeader (1, :) char    = ''
        DebugStateFile (1, :) char  = ''
        Browser = []
        IsBrowserVisible (1, 1) logical = false
        InteractionDone (1, 1) logical = false
    end

    
    properties (Constant, Access = private)
        %-----------------------------------------------------------------%
        REQUIRED_COOKIES = ["LastMRH_Session", "F5_ST"]
        POLL_INTERVAL = 0.25
        SILENT_LOGIN_GRACE_PERIOD = 2
    end


    methods
        %-----------------------------------------------------------------%
        function obj = F5Session(loginURL)
            arguments
                loginURL (1,:) char {mustBeNonempty}
            end

            if ~startsWith(loginURL, 'https://', 'IgnoreCase', true)
                error('ws:auth:F5Session:insecureURL', 'Insecure URL')
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

        %-----------------------------------------------------------------%
        function [isAuthenticated, userProfile] = getAuthenticationInfo(obj)
            % GETAUTHENTICATIONINFO Returns authentication status and profile.

            isAuthenticated = obj.IsAuthenticated;
            if isAuthenticated
                userProfile = obj.UserProfile;
            else
                userProfile = struct();
            end
        end
    end


    methods
        %-----------------------------------------------------------------%
        function login(obj, timeout, debugFile)
            % LOGIN Opens the authentication window and waits for the user to complete
            % the SAML + MFA flow. Blocks until session cookies are obtained or
            % the user declines to continue after a timeout.

            arguments
                obj
                timeout (1,1) double {mustBePositive, mustBeFinite} = 300
                debugFile (1,:) char = ''
            end

            obj.DebugStateFile = debugFile;
            if ~isempty(obj.DebugStateFile)
                initializeDebugStateFile(obj)
            end

            logout(obj)

            openBrowser(obj)
            browserCleanup = onCleanup(@() closeBrowser(obj));

            startTime = tic;
            while true
                if ~isBrowserAlive(obj)
                    error('ws:auth:F5Session:windowClosed', 'Window closed')
                end

                if toc(startTime) > timeout
                    choice = questdlg('The login timed out. Continue waiting?', ...
                        'F5Session timeout', 'Yes', 'No', 'No');
                    if strcmp(choice, 'Yes')
                        startTime = tic;
                    else
                        break
                    end
                end

                state = probeBrowser(obj);

                if hasLanded(obj, state)
                    obj.CookieHeader = strtrim(state.cookie);
                    updateUserProfile(obj)
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

                pause(obj.POLL_INTERVAL)
                % drawnow limitrate
            end
        end

        %-----------------------------------------------------------------%
        function logout(obj)
            % LOGOUT Discards the in-memory session and closes the embedded window.

            closeBrowser(obj)

            % Overwrites the buffer before releasing it.
            obj.CookieHeader(:) = ' ';
            obj.CookieHeader    = '';
            obj.UserProfile     = struct();
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
                error('ws:auth:F5Session:unexpectedPayload', 'Unexpected payload')
            end
        end

        %-----------------------------------------------------------------%
        function [data, response] = readRaw(obj, url, autoReauthenticate)
            % READRAW Authenticated GET request without payload conversion.

            arguments
                obj
                url                (1,:) char {mustBeNonempty}
                autoReauthenticate (1,1) logical = true
            end

            [data, response] = fetch(obj, url, false, autoReauthenticate, []);
        end

        %-----------------------------------------------------------------%
        function context = getDownloadContext(obj)
            assertAuthenticated(obj)
            context = struct('CookieHeader', obj.CookieHeader);
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
        function openBrowser(obj)
            if ~exist('matlab.internal.webwindow', 'class')
                error('ws:auth:F5Session:unsupportedRelease', 'UnsupportedRrelease')
            end

            obj.Browser = matlab.internal.webwindow(obj.LoginURL);
            obj.Browser.Title = 'Authentication';
            try
                iconPath = fullfile(fileparts(mfilename('fullpath')), ...
                            '..', '..', '..', 'General', 'icons', ...
                            'Anatel_Logo_Color_256x256.png');
                obj.Browser.Icon = iconPath;
            catch
                warning('ws:auth:F5Session:iconError', 'Failed to set browser window icon')
            end
            if ~isempty(obj.DebugStateFile)
                obj.Browser.openDevTools();
            end

            obj.Browser.CustomWindowClosingCallback = @(src, ~) close(src);
            setResizable(obj.Browser, false)

            obj.Browser.Position(3:4) = [500, 675];
            appEngine.util.setWindowPosition(obj.Browser)
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
            if elapsedTime > obj.SILENT_LOGIN_GRACE_PERIOD
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
                writeDebugState(obj, 'raw', rawValue)
                state    = ws.auth.F5Session.decodeJSResult(rawValue);
                writeDebugState(obj, 'decoded', state)
            catch ME
                writeDebugState(obj, 'error', struct('Identifier', ME.identifier, ...
                                                     'Message', ME.message))
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
            if isempty(state) || ~isstruct(state) || ~isfield(state, 'cookie')
                writeDebugState(obj, 'landed', struct('Result', false, ...
                                                      'Reason', 'Missing cookie state'))
                return
            end

            cookieNames = string({ws.auth.F5Session.parseCookieHeader(state.cookie).Name});

            tf = all(ismember(obj.REQUIRED_COOKIES, cookieNames));
            writeDebugState(obj, 'landed', struct('Result', tf, ...
                                                  'CookieNames', {cellstr(cookieNames)}, ...
                                                  'RequiredCookies', {cellstr(obj.REQUIRED_COOKIES)}))
        end

        %-----------------------------------------------------------------%
        function initializeDebugStateFile(obj)
            if isempty(obj.DebugStateFile)
                return
            end

            try
                folder = fileparts(obj.DebugStateFile);
                if ~isempty(folder) && ~isfolder(folder)
                    mkdir(folder)
                end

                fileID = fopen(obj.DebugStateFile, 'w');
                if fileID == -1
                    return
                end
                fileCleanup = onCleanup(@() fclose(fileID));
                fprintf(fileID, 'F5Session browser state log\n');
            catch
            end
        end

        %-----------------------------------------------------------------%
        function writeDebugState(obj, label, value)
            if isempty(obj.DebugStateFile)
                return
            end

            try
                fileID = fopen(obj.DebugStateFile, 'a');
                if fileID == -1
                    return
                end
                fileCleanup = onCleanup(@() fclose(fileID));

                if ischar(value) || isStringScalar(value)
                    text = char(value);
                else
                    text = jsonencode(value);
                end

                timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss.SSS'));
                fprintf(fileID, '\n[%s] %s\n%s\n', timestamp, label, text);
            catch
            end
        end

        %-----------------------------------------------------------------%
        function updateUserProfile(obj)
            try
                response = sendRequest(obj, obj.LoginURL, true, []);
                statusCode = double(response.StatusCode);
                profileFields = response.getFields('X-User-Profile');

                if statusCode >= 200 && statusCode < 300 && ~isempty(profileFields)
                    obj.UserProfile = ws.auth.F5Session.getLoginProfile(response);
                end
            catch
            end
        end

        %-----------------------------------------------------------------%
        function assertAuthenticated(obj)
            if ~obj.IsAuthenticated
                error('ws:auth:F5Session:notAuthenticated', 'Not authenticated')
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
                    error('ws:auth:F5Session:sessionExpired', 'Session expired')
                end

                login(obj)
                response = sendRequest(obj, url, convertResponse, progressFcn);

                if ws.auth.F5Session.isSessionExpired(response)
                    error('ws:auth:F5Session:sessionExpired', 'Session expired after auth')
                end
            end

            statusCode = double(response.StatusCode);
            if statusCode < 200 || statusCode >= 300
                error('ws:auth:F5Session:httpError', 'Http error')
            end

            profileFields = response.getFields('X-User-Profile');
            if ~isempty(profileFields)
                obj.UserProfile = ws.auth.F5Session.getLoginProfile(response);
                data = obj.UserProfile;
                return
            end

            if isempty(response.Body)
                data = [];
            else
                data = response.Body.Data;
            end
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

        %-----------------------------------------------------------------%
        function profile = getLoginProfile(response)
            field = response.getFields('X-User-Profile');
            profile = jsondecode(char(field(1).Value));
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