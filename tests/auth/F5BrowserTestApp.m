classdef F5BrowserTestApp < matlab.apps.AppBase

    % F5BrowserTestApp
    % Mini-navegador de teste para ws.auth.F5Session: autentica uma única vez
    % e delega os downloads ao componente geral ui.TransferPanel.

    properties (Access = private)
        Session
        SessionListener
        UIFigure matlab.ui.Figure
        URLDropDown matlab.ui.control.DropDown
        ExecutionModeImage matlab.ui.control.Image
        DebugImage matlab.ui.control.Image
        DownloadModeImage matlab.ui.control.Image
        TransferPanel
        ProfileAvatarHTML matlab.ui.control.HTML
        HTMLView matlab.ui.control.HTML
        ProfilePanel
        DebugMode (1,1) logical = false
        DownloadExecutionMode (1, :) char = 'desktopStandaloneApp'
        SilentDownloadMode (1,1) logical = false
        AuthResourceFolder (1, :) char = ''
        DefaultServerDownloadPath (1, :) char = ''
        ProfileAvatarHTMLPath (1, :) char = ''
        ProfileAvatarState struct = struct('action', 'render', ...
                            'connected', false, ...
                            'initial', '?', ...
                            'photoPngBase64', '')
        ProfileAvatarHTMLReady (1,1) logical = false
    end

    properties (Constant, Access = private)
        AuthenticationURL = 'https://fiscalizacao.anatel.gov.br/rffusion/api/users/login'
        DefaultURLs = {'https://fiscalizacao.anatel.gov.br/rffusion/api/users/me', ...
                       'https://fiscalizacao.anatel.gov.br/rffusion/api/map/stations', ...
                       'https://fiscalizacao.anatel.gov.br/rffusion/api/host/10321/zabbix_metrics', ...
                       'https://fiscalizacao.anatel.gov.br/downloads/2026/PE/2611101/36/p-a2d86905--rfeye002126_260919_T063900.bin', ...
                       'https://fiscalizacao.anatel.gov.br/downloads/2024/RO/1100205/176/p-1f25532e--rfeye002210_240819_T175952.bin', ...
                       'https://fiscalizacao.anatel.gov.br/downloads/2026/SP/3549805/79/p-6b9f7d03--rfeye002266_260901_T073300.bin', ...
                       'https://httpbin.org/bytes/1024', ...
                       'http://httpbin.org/bytes/1024'}
    end


    methods
        function app = F5BrowserTestApp()
            appFolder = fileparts(mfilename('fullpath'));
            addpath(fullfile(fileparts(fileparts(appFolder)), 'src', 'Anatel'))
            addpath(fullfile(fileparts(fileparts(appFolder)), 'src', 'General'))

            createComponents(app)
            registerApp(app, app.UIFigure)

            if nargout == 0
                clear app
            end
        end

        function delete(app)
            if ~isempty(app.SessionListener) && isvalid(app.SessionListener)
                delete(app.SessionListener)
            end
            if ~isempty(app.ProfilePanel) && isvalid(app.ProfilePanel)
                delete(app.ProfilePanel)
            end
            if ~isempty(app.TransferPanel) && isvalid(app.TransferPanel)
                delete(app.TransferPanel)
            end
            if ~isempty(app.Session) && isvalid(app.Session)
                delete(app.Session)
            end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure)
            end
        end
    end


    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Name', 'F5Session :: Navegador de teste', ...
                                     'Position', [100, 100, 1000, 700]);
            app.UIFigure.CloseRequestFcn = @(~, ~) delete(app);
            app.AuthResourceFolder = fileparts(mfilename('fullpath'));
            app.DefaultServerDownloadPath = app.AuthResourceFolder;
            projectFolder = fileparts(fileparts(app.AuthResourceFolder));
            app.ProfileAvatarHTMLPath = fullfile(projectFolder, 'src', 'Anatel', '+ws', '+auth', 'profileAvatar.html');

            gridLayout = uigridlayout(app.UIFigure, [2, 6]);
            gridLayout.RowHeight = {24, '1x'};
            gridLayout.ColumnWidth = {22, 22, 22, '1x', 24, 22};

            app.ExecutionModeImage = uiimage(gridLayout, ...
                                             'ImageClickedFcn', @(~, ~) app.toggleDownloadExecutionMode());
            app.ExecutionModeImage.Layout.Row = 1;
            app.ExecutionModeImage.Layout.Column = 1;
            app.refreshDownloadExecutionModeImage()

            app.DebugImage = uiimage(gridLayout, ...
                                     'ImageSource', fullfile(app.AuthResourceFolder, 'debug-start.svg'), ...
                                     'ImageClickedFcn', @(~, ~) app.toggleDebugMode());
            app.DebugImage.Layout.Row = 1;
            app.DebugImage.Layout.Column = 2;

            app.DownloadModeImage = uiimage(gridLayout, ...
                                            'ImageClickedFcn', @(~, ~) app.toggleSilentDownloadMode());
            app.DownloadModeImage.Layout.Row = 1;
            app.DownloadModeImage.Layout.Column = 3;
            app.refreshSilentDownloadModeImage()

            app.URLDropDown = uidropdown(gridLayout, ...
                                         'Editable', 'on', ...
                                         'Items', app.DefaultURLs, ...
                                         'Value', '<digite uma URL ou selecione>');
            app.URLDropDown.ValueChangedFcn = @(~, ~) app.navigate();
            app.URLDropDown.Layout.Row = 1;
            app.URLDropDown.Layout.Column = 4;

            app.TransferPanel = ui.TransferPanel(gridLayout, ...
                'TransferFactory', @(request) app.createDownloader(request), ...
                'executionMode', app.DownloadExecutionMode, ...
                'CollisionPolicy', app.downloadCollisionPolicy(), ...
                'tempPath', fullfile(tempdir, 'F5BrowserTestApp-downloads'), ...
                'targetPath', app.DefaultServerDownloadPath);
            app.TransferPanel.AvatarHTML.Layout.Row = 1;
            app.TransferPanel.AvatarHTML.Layout.Column = 5;
            app.TransferPanel.CompletedFcn = @(taskID, info, taskInfo) ...
                app.onDownloadCompleted(taskID, info, taskInfo);
            app.TransferPanel.ErrorFcn = @(taskID, exception, taskInfo) ...
                app.onDownloadFailed(taskID, exception, taskInfo);

            app.ProfileAvatarHTML = uihtml(gridLayout);
            app.ProfileAvatarHTML.HTMLEventReceivedFcn = @(~, event) app.onProfileAvatarEvent(event);
            app.ProfileAvatarHTML.HTMLSource = app.ProfileAvatarHTMLPath;
            app.ProfileAvatarHTML.Layout.Row = 1;
            app.ProfileAvatarHTML.Layout.Column = 6;

            app.HTMLView = uihtml(gridLayout, 'HTMLSource', '<html><body></body></html>');
            app.HTMLView.Layout.Row = 2;
            app.HTMLView.Layout.Column = [1, 6];

            app.ProfilePanel = ui.ProfilePanel(app.UIFigure, ...
                'Anchor', app.ProfileAvatarHTML, ...
                'SignOutFcn', @() app.signOut());

            app.setSession(ws.auth.F5Session(app.AuthenticationURL))
        end

        function navigate(app)
            url = strtrim(app.URLDropDown.Value);
            if isempty(url)
                return
            end
            app.addToHistory(url)

            try
                if app.isDownloadURL(url)
                    if app.SilentDownloadMode
                        displayMode = 'silent';
                    else
                        displayMode = 'normal';
                    end
                    app.TransferPanel.addDownload(url, 'DisplayMode', displayMode)
                    app.refreshStatus()
                    return
                end

                app.ensureSession(url)

                progressDialog = uiprogressdlg(app.UIFigure, ...
                                                'Indeterminate', 'on', ...
                                                'Message', sprintf('Lendo %s', url));
                progressCleanup = onCleanup(@() close(progressDialog)); %#ok<NASGU>
                app.render(read(app.Session, url))
            catch ME
                app.HTMLView.HTMLSource = '<html><body></body></html>';
                uialert(app.UIFigure, ME.message, 'Falha na requisição')
            end

            app.refreshStatus()
        end

        function connect(app)
            try
                app.ensureSession(app.AuthenticationURL)
                [~, response] = readRaw(app.Session, app.AuthenticationURL);
                app.renderRawResponse(response)
            catch ME
                uialert(app.UIFigure, ME.message, 'Falha na autenticação')
            end
            app.refreshStatus()
        end

        function profileImageClicked(app)
            if ~isempty(app.Session) && isvalid(app.Session) && app.Session.IsAuthenticated
                [~, profile] = app.Session.getAuthenticationInfo();
                app.ProfilePanel.toggle(profile)
            else
                app.connect()
            end
        end

        function toggleDebugMode(app)
            app.DebugMode = ~app.DebugMode;
            app.refreshDebugImage()
        end

        function toggleDownloadExecutionMode(app)
            if strcmp(app.DownloadExecutionMode, 'webApp')
                app.DownloadExecutionMode = 'desktopStandaloneApp';
            else
                app.DownloadExecutionMode = 'webApp';
            end
            app.TransferPanel.executionMode = app.DownloadExecutionMode;
            app.TransferPanel.setCollisionPolicy(app.downloadCollisionPolicy());
            app.refreshDownloadExecutionModeImage()
        end

        function toggleSilentDownloadMode(app)
            app.SilentDownloadMode = ~app.SilentDownloadMode;
            app.refreshSilentDownloadModeImage()
        end

        function policy = downloadCollisionPolicy(~)
            policy = 'askInRow';
        end

        function onProfileAvatarEvent(app, event)
            eventName = eventProperty(event, {'HTMLEventName', 'EventName'});
            payload = eventProperty(event, {'HTMLEventData', 'Data'});
            if ischar(payload) || (isstring(payload) && isscalar(payload))
                try
                    payload = jsondecode(char(payload));
                catch
                    payload = struct();
                end
            end

            if strcmp(eventName, 'profileAvatarClick')
                app.profileImageClicked()
                return
            end
            if ~isstruct(payload) || ~isfield(payload, 'type')
                return
            end

            switch string(payload.type)
                case "ready"
                    app.ProfileAvatarHTMLReady = true;
                    app.ProfileAvatarHTML.Data = app.ProfileAvatarState;
                case "click"
                    app.profileImageClicked()
            end
        end

        function downloader = createDownloader(app, request)
            if isempty(app.Session) || ~isvalid(app.Session)
                app.setSession(ws.auth.F5Session(app.AuthenticationURL))
            end
            downloader = ws.auth.FileTransfer(app.Session, request);
        end

        function setSession(app, session)
            if ~isempty(app.SessionListener) && isvalid(app.SessionListener)
                delete(app.SessionListener)
            end
            app.SessionListener = [];
            app.Session = session;
            if ~isempty(session)
                app.SessionListener = addlistener(session, 'AuthenticationChanged', ...
                    @(~, ~) app.onSessionAuthenticationChanged());
            end
        end

        function onSessionAuthenticationChanged(app)
            if isvalid(app) && ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                app.refreshStatus()
            end
        end

        function onDownloadCompleted(app, ~, info, taskInfo)
            logPath = app.downloadLogPath(taskInfo);
            F5BrowserTestApp.writeDownloadLog(logPath, sprintf(...
                'END\nTransferred bytes: %d\nLocal path: %s\n', ...
                info.TransferredBytes, info.LocalPath));
        end

        function onDownloadFailed(app, ~, exception, taskInfo)
            logPath = app.downloadLogPath(taskInfo);
            F5BrowserTestApp.writeDownloadLog(logPath, sprintf(...
                'ERROR\n%s\nEND\n', ...
                getReport(exception, 'extended', 'hyperlinks', 'off')));
            uialert(app.UIFigure, ...
                    F5BrowserTestApp.downloadErrorReport(exception, taskInfo.LocalPath, logPath), ...
                    'Falha no download')
        end

        function logPath = downloadLogPath(app, taskInfo)
            logPath = '';
            if app.DebugMode && ~isempty(taskInfo) && isfield(taskInfo, 'TaskID')
                logPath = fullfile(app.AuthResourceFolder, [taskInfo.TaskID, '_download.log']);
            end
        end

        function signOut(app)
            app.ProfilePanel.hide()
            if ~isempty(app.Session) && isvalid(app.Session)
                logout(app.Session)
                app.setSession([])
            end
            app.HTMLView.HTMLSource = '<html><body></body></html>';
            app.refreshStatus()
        end

        function addToHistory(app, url)
            if ~ismember(url, app.URLDropDown.Items)
                app.URLDropDown.Items = [app.URLDropDown.Items, {url}];
            end
            app.URLDropDown.Value = url;
        end

        function ensureSession(app, url)
            if ~isempty(app.Session) && isvalid(app.Session) && app.Session.IsAuthenticated
                if strcmpi(matlab.net.URI(url).Host, matlab.net.URI(app.Session.LoginURL).Host)
                    return
                end
                delete(app.Session)
            end

            app.setSession(ws.auth.F5Session(app.AuthenticationURL))
            app.refreshStatus()
            progressDialog = uiprogressdlg(app.UIFigure, ...
                                           'Indeterminate', 'on', ...
                                           'Message', 'Conclua a autenticação na janela do navegador (login + aprovação no Authenticator).');
            progressCleanup = onCleanup(@() close(progressDialog)); %#ok<NASGU>

            debugFile = '';
            if app.DebugMode
                debugFile = fullfile(app.AuthResourceFolder, ...
                                     [datestr(now, 'yymmdd_HHMMSS') '_browser-state.log']);
                fprintf('F5Session browser state log: %s\n', debugFile)
            end
            app.Session.login(300, debugFile)
        end

        function refreshStatus(app)
            isConnected = ~isempty(app.Session) && isvalid(app.Session) && app.Session.IsAuthenticated;
            if isConnected
                [~, profile] = app.Session.getAuthenticationInfo();
                app.updateProfileAvatar(true, profile)
                app.ProfilePanel.update(profile)
            else
                app.ProfilePanel.hide()
                app.updateProfileAvatar(false, struct())
            end
        end

        function refreshDebugImage(app)
            if app.DebugMode
                app.DebugImage.ImageSource = fullfile(app.AuthResourceFolder, 'debug-stop.svg');
            else
                app.DebugImage.ImageSource = fullfile(app.AuthResourceFolder, 'debug-start.svg');
            end
        end

        function refreshDownloadExecutionModeImage(app)
            if strcmp(app.DownloadExecutionMode, 'webApp')
                app.ExecutionModeImage.ImageSource = fullfile(app.AuthResourceFolder, 'globe.svg');
                app.ExecutionModeImage.Tooltip = 'Web App Server mode';
            else
                app.ExecutionModeImage.ImageSource = fullfile(app.AuthResourceFolder, 'vm.svg');
                app.ExecutionModeImage.Tooltip = 'Desktop mode';
            end
        end

        function refreshSilentDownloadModeImage(app)
            if app.SilentDownloadMode
                app.DownloadModeImage.ImageSource = fullfile(app.AuthResourceFolder, 'bell.svg');
                app.DownloadModeImage.Tooltip = 'Reativar notificacoes de download';
            else
                app.DownloadModeImage.ImageSource = fullfile(app.AuthResourceFolder, 'bell-slash.svg');
                app.DownloadModeImage.Tooltip = 'Ativar downloads silenciosos';
            end
        end

        function updateProfileAvatar(app, isConnected, profile)
            state = struct('action', 'render', ...
                           'connected', logical(isConnected), ...
                           'initial', '?', ...
                           'photoPngBase64', '');
            if isConnected
                state.initial = app.profileInitial(profile);
                try
                    state.photoPngBase64 = app.loadProfilePictureBase64();
                catch
                    state.photoPngBase64 = '';
                end
            end
            app.ProfileAvatarState = state;
            if app.ProfileAvatarHTMLReady && ~isempty(app.ProfileAvatarHTML) && isvalid(app.ProfileAvatarHTML)
                app.ProfileAvatarHTML.Data = state;
            end
        end

        function base64 = loadProfilePictureBase64(app)
            picturePath = fullfile(app.AuthResourceFolder, 'Profile-Picture.png');
            base64 = '';
            if ~isfile(picturePath)
                return
            end
            fileID = fopen(picturePath, 'rb');
            if fileID == -1
                return
            end
            fileCleanup = onCleanup(@() fclose(fileID)); %#ok<NASGU>
            imageBytes = fread(fileID, [1, inf], '*uint8');
            base64 = char(matlab.net.base64encode(imageBytes));
        end

        function initial = profileInitial(app, profile)
            name = app.profileField(profile, {'NA_USER_NAME', 'name', 'displayName', 'username', 'userName'});
            if isempty(name)
                name = app.profileField(profile, {'NA_USER_EMAIL', 'email'});
            end
            if isempty(name)
                initial = '?';
            else
                initial = upper(strtrim(name(1)));
            end
        end

        function value = profileField(app, profile, candidates)
            value = '';
            if ~isstruct(profile) || isempty(profile)
                return
            end
            fields = fieldnames(profile);
            for candidateIndex = 1:numel(candidates)
                fieldIndex = find(strcmpi(fields, candidates{candidateIndex}), 1);
                if isempty(fieldIndex)
                    continue
                end
                value = app.profileValueText(profile.(fields{fieldIndex}));
                if ~isempty(strtrim(value))
                    return
                end
            end
        end

        function text = profileValueText(~, value)
            if ischar(value)
                text = value;
            elseif isstring(value) && isscalar(value)
                text = char(value);
            elseif (isnumeric(value) || islogical(value)) && isscalar(value)
                text = char(string(value));
            elseif isstruct(value) || iscell(value) || isnumeric(value) || islogical(value)
                text = char(jsonencode(value));
            else
                text = char(string(value));
            end
        end

        function renderRawResponse(app, response)
            responseText = char(response.show);
            app.HTMLView.HTMLSource = sprintf('<html><body><pre>%s</pre></body></html>', ...
                                              app.escapeHTML(responseText));
        end

        function render(app, data)
            if ischar(data) || isStringScalar(data)
                content = char(data);
                if ~contains(content, '<html', 'IgnoreCase', true) && ~contains(content, '<body', 'IgnoreCase', true)
                    content = sprintf('<pre>%s</pre>', app.escapeHTML(content));
                end
            elseif isstruct(data) || iscell(data) || isnumeric(data) || islogical(data)
                content = sprintf('<pre>%s</pre>', app.escapeHTML(jsonencode(data, 'PrettyPrint', true)));
            else
                content = sprintf('<pre>Conteudo nao renderizavel (%s).</pre>', class(data));
            end
            baseURL = strtrim(app.URLDropDown.Value);
            app.HTMLView.HTMLSource = sprintf('<html><head><base href="%s"></head><body>%s</body></html>', ...
                                              app.escapeHTML(baseURL), app.sanitizeHTML(content));
        end
    end


    methods (Static, Access = private)
        function tf = isDownloadURL(url)
            tf = false;
            try
                uri = matlab.net.URI(url);
                f5Host = char(matlab.net.URI(F5BrowserTestApp.AuthenticationURL).Host);
                if ~strcmpi(char(uri.Host), f5Host)
                    % F5Session is intentionally limited to its exact host.
                    % External URLs are handled by the generic download panel.
                    tf = true;
                    return
                end
                pathSegments = uri.Path;
                lastSegmentIsFile = ~isempty(pathSegments) && contains(pathSegments(end), '.');
                tf = lastSegmentIsFile;
            catch
            end
        end

        function report = downloadErrorReport(exception, filePath, logPath)
            logText = '';
            if ~isempty(logPath)
                logText = sprintf('\n\nLog: %s', logPath);
            end
            report = sprintf('Falha ao baixar o arquivo para "%s".\n\nIdentificador: %s\nMensagem: %s%s\n\nStack:\n%s', ...
                             filePath, exception.identifier, exception.message, logText, ...
                             getReport(exception, 'extended', 'hyperlinks', 'off'));
        end

        function writeDownloadLog(filePath, text)
            if isempty(filePath)
                return
            end
            fileID = fopen(filePath, 'a');
            if fileID == -1
                return
            end
            fileCleanup = onCleanup(@() fclose(fileID)); %#ok<NASGU>
            fprintf(fileID, '[%s] %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS.FFF'), text);
        end

        function text = escapeHTML(text)
            text = char(text);
            text = strrep(text, '&', '&amp;');
            text = strrep(text, '<', '&lt;');
            text = strrep(text, '>', '&gt;');
        end

        function content = sanitizeHTML(content)
            content = regexprep(content, '<script\b.*?</script\s*>', '', 'ignorecase');
            content = regexprep(content, '<script\b[^>]*>', '', 'ignorecase');
            content = regexprep(content, '\s+on[a-z]+\s*=\s*"[^"]*"', '', 'ignorecase');
            content = regexprep(content, '\s+on[a-z]+\s*=\s*''[^'']*''', '', 'ignorecase');
            content = regexprep(content, 'javascript:', '', 'ignorecase');
        end
    end
end


function value = eventProperty(event, propertyNames)
value = '';
for propertyIndex = 1:numel(propertyNames)
    if isprop(event, propertyNames{propertyIndex})
        propertyValue = event.(propertyNames{propertyIndex});
        if ischar(propertyValue) || (isstring(propertyValue) && isscalar(propertyValue))
            value = char(propertyValue);
        else
            value = propertyValue;
        end
        return
    end
end
end
