classdef F5BrowserTestApp < matlab.apps.AppBase

    % F5BrowserTestApp
    % Mini-navegador de teste para ws.auth.F5Session: autentica uma única vez
    % e delega os downloads ao componente geral ui.TransferPanel.

    properties (Access = private)
        Session
        SessionListener
        UIFigure matlab.ui.Figure
        BrowserGrid matlab.ui.container.GridLayout
        Toolbar matlab.ui.container.GridLayout
        URLDropDown matlab.ui.control.DropDown
        ExecutionModeButton matlab.ui.control.StateButton
        DebugButton matlab.ui.control.StateButton
        SilentModeButton matlab.ui.control.StateButton
        TransferButton matlab.ui.control.Button
        ProfileButton matlab.ui.control.Button
        ResponseHost matlab.ui.control.Label
        BridgeHTML matlab.ui.control.HTML
        TransferPanel
        ProfilePanel
        DebugMode (1,1) logical = false
        DownloadExecutionMode (1, :) char = 'desktopStandaloneApp'
        SilentDownloadMode (1,1) logical = false
        AuthResourceFolder (1, :) char = ''
        DefaultServerDownloadPath (1, :) char = ''
        ProfileAvatarState struct = struct('action', 'render', ...
                            'connected', false, ...
                            'initial', '?', ...
                            'photoPngBase64', '')
        TransferStatus struct = struct('activeUpload', false, ...
                    'activeDownload', false, ...
                    'hasAttention', false)
        BridgeReady (1,1) logical = false
        BridgeTags struct = struct()
        ResponseState struct = struct('content', '', 'baseURL', '')
        NavigationGeneration (1,1) double = 0
        AuthenticationGeneration (1,1) double = 0
        UploadOperations cell = {}
        FallbackTimers cell = {}
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
                       'http://httpbin.org/bytes/1024', ...
                       'https://httpbin.org/post', ...
                       'https://httpbin.org/put'}
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
            app.cancelUploadFallbacks()
            if app.BridgeReady && ~isempty(app.BridgeHTML) && isvalid(app.BridgeHTML)
                try
                    sendEventToHTMLSource(app.BridgeHTML, 'f5BrowserPresentation', ...
                        struct('operation', 'dispose', 'responseTag', app.BridgeTags.response));
                catch
                end
            end
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
            app.BrowserGrid = uigridlayout(app.UIFigure, [2, 1]);
            app.BrowserGrid.RowHeight = {54, '1x'};
            app.BrowserGrid.ColumnWidth = {'1x'};
            app.BrowserGrid.RowSpacing = 0;
            app.BrowserGrid.ColumnSpacing = 0;
            app.BrowserGrid.Padding = [0 0 0 0];

            app.Toolbar = uigridlayout(app.BrowserGrid, [5, 8]);
            app.Toolbar.ColumnWidth = {34, 34, 34, 5, '1x', 5, 34, 34};
            app.Toolbar.RowHeight = {5, 7, 20, 7, 5};
            app.Toolbar.ColumnSpacing = 5;
            app.Toolbar.RowSpacing = 0;
            app.Toolbar.Padding = [10 5 5 5];
            app.Toolbar.BackgroundColor = [0.2 0.2 0.2];
            app.Toolbar.Layout.Row = 1;
            app.Toolbar.Layout.Column = 1;

            app.ExecutionModeButton = uibutton(app.Toolbar, 'state', ...
                'ValueChangedFcn', @(~, ~) app.toggleDownloadExecutionMode());
            app.ExecutionModeButton.Layout.Row = [2 4];
            app.ExecutionModeButton.Layout.Column = 1;
            app.configureToolbarButton(app.ExecutionModeButton);
            app.refreshDownloadExecutionModeImage()

            app.DebugButton = uibutton(app.Toolbar, 'state', ...
                'ValueChangedFcn', @(~, ~) app.toggleDebugMode());
            app.DebugButton.Layout.Row = [2 4];
            app.DebugButton.Layout.Column = 2;
            app.configureToolbarButton(app.DebugButton);
            app.refreshDebugImage()

            app.SilentModeButton = uibutton(app.Toolbar, 'state', ...
                'ValueChangedFcn', @(~, ~) app.toggleSilentDownloadMode());
            app.SilentModeButton.Layout.Row = [2 4];
            app.SilentModeButton.Layout.Column = 3;
            app.configureToolbarButton(app.SilentModeButton);
            app.refreshSilentDownloadModeImage()

            separator1 = uiimage(app.Toolbar);
            separator1.ScaleMethod = 'none';
            separator1.Enable = 'off';
            separator1.Layout.Row = [2 4];
            separator1.Layout.Column = 4;
            separator1.ImageSource = fullfile(projectFolder, 'src', 'General', 'icons', 'vertical-separator.svg');

            app.URLDropDown = uidropdown(app.Toolbar, ...
                                         'Editable', 'on', ...
                                         'Items', app.DefaultURLs, ...
                                         'Value', '<digite uma URL ou selecione>');
            app.URLDropDown.ValueChangedFcn = @(~, ~) app.navigate();
            app.URLDropDown.Layout.Row = 3;
            app.URLDropDown.Layout.Column = 5;

            separator2 = uiimage(app.Toolbar);
            separator2.ScaleMethod = 'none';
            separator2.Enable = 'off';
            separator2.Layout.Row = [2 4];
            separator2.Layout.Column = 6;
            separator2.ImageSource = fullfile(projectFolder, 'src', 'General', 'icons', 'vertical-separator.svg');

            app.TransferButton = uibutton(app.Toolbar, ...
                'ButtonPushedFcn', @(~, ~) app.TransferPanel.toggle());
            app.TransferButton.Layout.Row = [2 4];
            app.TransferButton.Layout.Column = 7;
            app.configureToolbarButton(app.TransferButton);
            app.TransferButton.Icon = fullfile(projectFolder, 'src', 'General', ...
                '+ui', 'html', 'transferStatusAvatar.svg');
            app.TransferButton.Tooltip = 'Transferências';

            app.ProfileButton = uibutton(app.Toolbar, ...
                'ButtonPushedFcn', @(~, ~) app.profileImageClicked());
            app.ProfileButton.Layout.Row = [2 4];
            app.ProfileButton.Layout.Column = 8;
            app.configureToolbarButton(app.ProfileButton);
            app.ProfileButton.Icon = fullfile(projectFolder, 'src', 'General', ...
                '+ui', 'html', 'profileStatusAvatar.svg');
            app.ProfileButton.Tooltip = 'Conectar';

            app.ResponseHost = uilabel(app.BrowserGrid);
            app.ResponseHost.Text = '';
            app.ResponseHost.BackgroundColor = [1 1 1];
            app.ResponseHost.Layout.Row = 2;
            app.ResponseHost.Layout.Column = 1;

            app.BridgeHTML = uihtml(app.UIFigure, 'Visible', 'off');
            app.BridgeHTML.HTMLEventReceivedFcn = @(~, event) app.onBridgeEvent(event);
            app.BridgeHTML.HTMLSource = appEngine.util.jsBackDoorHTMLSource();

            app.TransferPanel = ui.TransferPanel(app.BrowserGrid, ...
                'TransferFactory', @(request) ws.auth.FileTransfer(app.Session, request), ...
                'executionMode', app.DownloadExecutionMode, ...
                'CollisionPolicy', app.downloadCollisionPolicy(), ...
                'tempPath', fullfile(app.AuthResourceFolder, 'temp'), ...
                'targetPath', app.DefaultServerDownloadPath, ...
                'Anchor', app.TransferButton, ...
                'StatusFcn', @(status) app.onTransferStatusChanged(status));
            app.TransferPanel.CompletedFcn = @(taskID, info, taskInfo) ...
                app.onDownloadCompleted(taskID, info, taskInfo);
            app.TransferPanel.ErrorFcn = @(taskID, exception, taskInfo) ...
                app.onDownloadFailed(taskID, exception, taskInfo);

            app.ProfilePanel = ui.ProfilePanel(app.UIFigure, ...
                'Anchor', app.ProfileButton, ...
                'SignOutFcn', @() app.signOut());

            app.setSession(ws.auth.F5Session(app.AuthenticationURL))
        end

        function navigate(app)
 
            url = strtrim(app.URLDropDown.Value);
            if isempty(url) || strcmp(url, '<digite uma URL ou selecione>')
                return
            end
            app.addToHistory(url)
            app.NavigationGeneration = app.NavigationGeneration + 1;
            navigationGeneration = app.NavigationGeneration;

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
                progressCleanup = onCleanup(@() closeProgressDialog(progressDialog));
                response = app.sendGetRequest(url);
                if double(response.StatusCode) == 405
                    closeProgressDialog(progressDialog)
                    clear progressCleanup
                    app.tryUploadAfterMethodNotAllowed(url, response, navigationGeneration)
                else
                    app.renderHTTPResponse(response, url)
                end
            catch ME
                app.clearResponse()
                uialert(app.UIFigure, ME.message, 'Falha na requisição')
            end

            app.refreshStatus()
        end

        function response = sendGetRequest(app, url)
            requestContext = app.Session.getRequestContext(url);
            result = datatransfer.sendHTTPRequest(url, requestContext, 'GET');
            if result.NeedsAuthentication && requestContext.AuthenticationEligible
                requestContext = app.Session.authenticateForRequest(url);
                result = datatransfer.sendHTTPRequest(url, requestContext, 'GET');
            end
            response = result.Response;
        end

        function tryUploadAfterMethodNotAllowed(app, url, getResponse, navigationGeneration)
            [fileName, fileFolder] = uigetfile('*.*', 'Selecione o arquivo para enviar');
            if isequal(fileName, 0)
                app.renderRawResponse(getResponse, url)
                return
            end
            figure(app.UIFigure)
            localPath = fullfile(fileFolder, fileName);
            logicalFileID = ['f5-browser-', char(java.util.UUID.randomUUID())];
            operation = struct('LogicalFileID', logicalFileID, ...
                               'URL', url, ...
                               'LocalPath', localPath, ...
                               'GETResponse', getResponse, ...
                               'PUTResponse', [], ...
                               'POSTResponse', [], ...
                               'Stage', 'PUT', ...
                               'TaskIDs', [], ...
                               'NavigationGeneration', navigationGeneration, ...
                               'AuthenticationGeneration', app.AuthenticationGeneration, ...
                               'FallbackTimer', []);
            app.UploadOperations{end+1} = operation;
            try
                taskID = app.TransferPanel.addUpload(url, ...
                    'LocalPath', localPath, ...
                    'Protocol', 'raw', ...
                    'Method', 'PUT', ...
                    'ContentType', 'application/octet-stream', ...
                    'LogicalFileID', logicalFileID);
                operationIndex = app.findUploadOperation(logicalFileID);
                if ~isempty(operationIndex) && ~isempty(taskID)
                    existingSnapshot = app.TransferPanel.Manager.getSnapshot(taskID);
                    if ~isempty(existingSnapshot) && ...
                            ~strcmp(existingSnapshot.LogicalFileID, logicalFileID)
                        app.removeUploadOperation(operationIndex)
                        if navigationGeneration == app.NavigationGeneration
                            app.renderResponseText( ...
                                'An upload of this file to this URL is already active.', url)
                        end
                    else
                        app.UploadOperations{operationIndex}.TaskIDs(end+1) = taskID;
                    end
                end
            catch exception
                app.finishUploadOperation(logicalFileID, [], [], ...
                    getReport(exception, 'extended', 'hyperlinks', 'off'))
            end
        end

        function renderMethodResponses(app, url, getResponse, putResponse, postResponse, requestError)
            text = sprintf('GET %s\n%s', url, char(getResponse.show));
            if ~isempty(putResponse)
                text = sprintf('%s\n\nPUT %s\n%s', ...
                               text, url, app.formatUploadAttempt(putResponse));
            end
            if ~isempty(postResponse)
                text = sprintf('%s\n\nPOST %s\n%s', ...
                               text, url, app.formatUploadAttempt(postResponse));
            end
            if ~isempty(requestError)
                text = sprintf('%s\n\n%s', text, requestError);
            end
            app.renderResponseText(text, url)
        end

        function renderResponseText(app, text, baseURL)
            if nargin < 3
                baseURL = strtrim(app.URLDropDown.Value);
            end
            app.updateResponse(sprintf('<pre>%s</pre>', app.escapeHTML(text)), ...
                               baseURL);
        end

        function operationIndex = findUploadOperation(app, logicalFileID)
            operationIndex = find(cellfun(@(operation) ...
                strcmp(operation.LogicalFileID, logicalFileID), app.UploadOperations), 1);
        end

        function enqueueFallbackPost(app, logicalFileID)
            if ~isvalid(app)
                return
            end
            operationIndex = app.findUploadOperation(logicalFileID);
            if isempty(operationIndex)
                return
            end
            operation = app.UploadOperations{operationIndex};
            if ~strcmp(operation.Stage, 'fallbackPending') || ...
                    operation.AuthenticationGeneration ~= app.AuthenticationGeneration
                app.removeUploadOperation(operationIndex)
                return
            end
            app.UploadOperations{operationIndex}.Stage = 'POST';
            app.UploadOperations{operationIndex}.FallbackTimer = [];
            putResponse = operation.PUTResponse;
            try
                taskID = app.TransferPanel.addUpload(operation.URL, ...
                    'LocalPath', operation.LocalPath, ...
                    'Protocol', 'raw', ...
                    'Method', 'POST', ...
                    'ContentType', 'application/octet-stream', ...
                    'LogicalFileID', operation.LogicalFileID);
                operationIndex = app.findUploadOperation(logicalFileID);
                if ~isempty(operationIndex) && ~isempty(taskID)
                    existingSnapshot = app.TransferPanel.Manager.getSnapshot(taskID);
                    if ~isempty(existingSnapshot) && ...
                            ~strcmp(existingSnapshot.LogicalFileID, logicalFileID)
                        app.finishUploadOperation(logicalFileID, putResponse, [], ...
                            'Another upload of this file to this URL is already active.');
                    else
                        app.UploadOperations{operationIndex}.TaskIDs(end+1) = taskID;
                    end
                end
            catch exception
                app.finishUploadOperation(logicalFileID, ...
                    putResponse, [], ...
                    getReport(exception, 'extended', 'hyperlinks', 'off'))
            end
        end

        function onFallbackTimer(app, fallbackTimer, logicalFileID)
            if isvalid(app)
                app.enqueueFallbackPost(logicalFileID)
            end
            if isvalid(fallbackTimer)
                delete(fallbackTimer)
            end
            if isvalid(app)
                timerMask = cellfun(@(candidate) ~isequal(candidate, fallbackTimer), ...
                                   app.FallbackTimers);
                app.FallbackTimers = app.FallbackTimers(timerMask);
            end
        end

        function handleUploadFailure(app, taskID, failure, snapshot)
            operationIndex = app.findUploadOperation(snapshot.LogicalFileID);
            if isempty(operationIndex)
                return
            end
            operation = app.UploadOperations{operationIndex};
            if strcmp(operation.Stage, 'PUT') && isstruct(failure) && ...
                    isfield(failure, 'StatusCode') && isequal(failure.StatusCode, 405) && ...
                    isfield(failure, 'OutcomeUncertain') && ~failure.OutcomeUncertain && ...
                    operation.AuthenticationGeneration == app.AuthenticationGeneration
                operation.PUTResponse = failure;
                operation.Stage = 'fallbackPending';
                operation.TaskIDs(end+1) = taskID;
                fallbackTimer = timer('ExecutionMode', 'singleShot', ...
                    'StartDelay', 0.1, ...
                    'TimerFcn', @(source, ~) app.onFallbackTimer(source, operation.LogicalFileID));
                operation.FallbackTimer = fallbackTimer;
                app.UploadOperations{operationIndex} = operation;
                app.FallbackTimers{end+1} = fallbackTimer;
                start(fallbackTimer)
                return
            end

            operation.TaskIDs(end+1) = taskID;
            if strcmp(operation.Stage, 'POST')
                operation.POSTResponse = failure;
                app.UploadOperations{operationIndex} = operation;
                app.finishUploadOperation(operation.LogicalFileID, ...
                    operation.PUTResponse, operation.POSTResponse, '');
            else
                operation.PUTResponse = failure;
                app.UploadOperations{operationIndex} = operation;
                app.finishUploadOperation(operation.LogicalFileID, ...
                    operation.PUTResponse, [], '');
            end
        end

        function handleUploadCompleted(app, taskID, info, snapshot)
            operationIndex = app.findUploadOperation(snapshot.LogicalFileID);
            if isempty(operationIndex)
                return
            end
            operation = app.UploadOperations{operationIndex};
            operation.TaskIDs(end+1) = taskID;
            stage = operation.Stage;
            app.UploadOperations{operationIndex} = operation;
            if operation.NavigationGeneration == app.NavigationGeneration && ...
                operation.AuthenticationGeneration == app.AuthenticationGeneration
                statusCode = fieldOr(info, 'StatusCode', []);
                body = fieldOr(info, 'ResponseBody', uint8.empty(0, 1));
                if isempty(body)
                    bodyText = 'Upload completed.';
                else
                    bodyText = decodeResponseBody(body);
                end
                if isempty(statusCode)
                    text = sprintf('%s %s\n%s', stage, operation.URL, bodyText);
                else
                    text = sprintf('%s %s\nHTTP %d\n%s', ...
                        stage, operation.URL, statusCode, bodyText);
                end
                if fieldOr(info, 'ResponseTruncated', false)
                    text = sprintf('%s\n[corpo da resposta truncado]', text);
                end
                app.renderResponseText(text, operation.URL)
            end
            app.removeUploadOperation(operationIndex)
        end

        function finishUploadOperation(app, logicalFileID, putResponse, postResponse, requestError)
            operationIndex = app.findUploadOperation(logicalFileID);
            if isempty(operationIndex)
                return
            end
            operation = app.UploadOperations{operationIndex};
            if operation.NavigationGeneration == app.NavigationGeneration && ...
                operation.AuthenticationGeneration == app.AuthenticationGeneration
                app.renderMethodResponses(operation.URL, operation.GETResponse, ...
                    putResponse, postResponse, requestError);
            end
            app.removeUploadOperation(operationIndex)
        end

        function removeUploadOperation(app, operationIndex)
            operation = app.UploadOperations{operationIndex};
            if ~isempty(operation.FallbackTimer) && isvalid(operation.FallbackTimer)
                stop(operation.FallbackTimer)
                delete(operation.FallbackTimer)
            end
            app.UploadOperations(operationIndex) = [];
        end

        function cancelUploadFallbacks(app)
            for timerIndex = 1:numel(app.FallbackTimers)
                fallbackTimer = app.FallbackTimers{timerIndex};
                if ~isempty(fallbackTimer) && isvalid(fallbackTimer)
                    stop(fallbackTimer)
                    delete(fallbackTimer)
                end
            end
            app.FallbackTimers = {};
            for operationIndex = numel(app.UploadOperations):-1:1
                operation = app.UploadOperations{operationIndex};
                if strcmp(operation.Stage, 'fallbackPending')
                    app.removeUploadOperation(operationIndex)
                else
                    operation.FallbackTimer = [];
                    app.UploadOperations{operationIndex} = operation;
                end
            end
        end

        function text = formatUploadAttempt(~, attempt)
            if isstruct(attempt)
                statusCode = fieldOr(attempt, 'StatusCode', []);
                message = fieldOr(attempt, 'message', '');
                body = fieldOr(attempt, 'ResponseBody', uint8.empty(0, 1));
                if isempty(body)
                    bodyText = '';
                else
                    bodyText = decodeResponseBody(body);
                end
                if isempty(statusCode)
                    text = sprintf('%s\n%s', message, bodyText);
                else
                    text = sprintf('HTTP %d\n%s\n%s', statusCode, message, bodyText);
                end
                if fieldOr(attempt, 'ResponseTruncated', false)
                    text = sprintf('%s\n[corpo da resposta truncado]', text);
                end
            else
                text = getReport(attempt, 'extended', 'hyperlinks', 'off');
            end
        end

        function renderHTTPResponse(app, response, baseURL)
            if nargin < 3
                baseURL = strtrim(app.URLDropDown.Value);
            end
            if isempty(response.Body) || isempty(response.Body.Data)
                app.renderRawResponse(response, baseURL)
                return
            end

            data = response.Body.Data;
            if isa(data, 'uint8')
                fields = response.getFields('Content-Type');
                if isempty(fields)
                    app.renderRawResponse(response, baseURL)
                    return
                end
                contentType = lower(char(fields(1).Value));
                isJSON = contains(contentType, 'json');
                isText = startsWith(contentType, 'text/') || ...
                         contains(contentType, 'xml') || ...
                         contains(contentType, 'javascript');
                if ~isJSON && ~isText
                    app.renderRawResponse(response, baseURL)
                    return
                end

                text = native2unicode(reshape(data, 1, []), 'UTF-8');
                if isJSON
                    try
                        data = jsondecode(text);
                    catch
                        data = text;
                    end
                else
                    data = text;
                end
            end
            app.render(data, baseURL)
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

        function onBridgeEvent(app, event)
            if strcmp(event.HTMLEventName, 'f5BrowserPresentationReady')
                app.BridgeReady = true;
                sendEventToHTMLSource(app.BridgeHTML, 'f5BrowserPresentation', ...
                    struct('operation', 'profile', ...
                           'dataTag', app.BridgeTags.profile, ...
                           'state', app.ProfileAvatarState));
                sendEventToHTMLSource(app.BridgeHTML, 'f5BrowserPresentation', ...
                    struct('operation', 'transfer', ...
                           'dataTag', app.BridgeTags.transfer, ...
                           'state', app.TransferStatus));
                sendEventToHTMLSource(app.BridgeHTML, 'f5BrowserPresentation', ...
                    struct('operation', 'response', ...
                           'dataTag', app.BridgeTags.response, ...
                           'content', app.ResponseState.content, ...
                           'baseURL', app.ResponseState.baseURL));
                return
            end
            if ~strcmp(event.HTMLEventName, 'renderer')
                return
            end
            app.BridgeReady = false;
            tags = ui.CustomizationBase.getElementsDataTag({ ...
                app.ProfileButton; app.TransferButton; app.ResponseHost});
            if numel(tags) ~= 3 || any(cellfun(@isempty, tags))
                return
            end
            app.BridgeTags = struct('profile', tags{1}, ...
                                    'transfer', tags{2}, ...
                                    'response', tags{3});
            projectFolder = fileparts(fileparts(app.AuthResourceFolder));
            sourceFolder = fullfile(projectFolder, 'src', 'General', '+ui', 'html');
            payload = struct('operation', 'initialize', ...
                'profileTag', tags{1}, ...
                'transferTag', tags{2}, ...
                'responseTag', tags{3}, ...
                'profileSVG', fileread(fullfile(sourceFolder, 'profileStatusAvatar.svg')), ...
                'transferSVG', fileread(fullfile(sourceFolder, 'transferStatusAvatar.svg')), ...
                'profileState', app.ProfileAvatarState, ...
                'transferState', app.TransferStatus, ...
                'response', app.ResponseState);
            sendEventToHTMLSource(app.BridgeHTML, 'f5BrowserPresentation', payload)
        end

        %-----------------------------------------------------------------%
        function onTransferStatusChanged(app, status)
            app.TransferStatus = status;
            statusText = {};
            if status.activeUpload
                statusText{end+1} = 'Envio em andamento';
            end
            if status.activeDownload
                statusText{end+1} = 'Download em andamento';
            end
            if status.hasAttention
                statusText{end+1} = 'Transferência pausada ou pendente';
            end
            if isempty(statusText)
                statusText = {'Sem transferências ativas'};
            end
            app.TransferButton.Tooltip = strjoin(statusText, '; ');
            if app.BridgeReady
                sendEventToHTMLSource(app.BridgeHTML, 'f5BrowserPresentation', ...
                    struct('operation', 'transfer', ...
                           'dataTag', app.BridgeTags.transfer, ...
                           'state', status));
            end
        end

        %-----------------------------------------------------------------%
        function configureToolbarButton(~, button)
            button.Text = '';
            button.IconAlignment = 'center';
            button.BackgroundColor = [0.2 0.2 0.2];
            button.FontSize = 11;
            button.Tooltip = '';
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
            if isfield(taskInfo, 'Direction') && strcmp(taskInfo.Direction, 'upload')
                app.handleUploadCompleted(taskInfo.ID, info, taskInfo)
                return
            end
            logPath = app.downloadLogPath(taskInfo);
            F5BrowserTestApp.writeDownloadLog(logPath, sprintf(...
                'END\nTransferred bytes: %d\nLocal path: %s\n', ...
                info.TransferredBytes, info.LocalPath));
        end

        function onDownloadFailed(app, taskID, exception, taskInfo)
            if isfield(taskInfo, 'Direction') && strcmp(taskInfo.Direction, 'upload')
                app.handleUploadFailure(taskID, exception, taskInfo)
                return
            end
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
            app.AuthenticationGeneration = app.AuthenticationGeneration + 1;
            app.cancelUploadFallbacks()
            app.ProfilePanel.hide()
            if ~isempty(app.Session) && isvalid(app.Session)
                logout(app.Session)
                app.setSession(ws.auth.F5Session(app.AuthenticationURL))
            end
            app.clearResponse()
            app.refreshStatus()
        end

        function addToHistory(app, url)
            if ~ismember(url, app.URLDropDown.Items)
                app.URLDropDown.Items = [app.URLDropDown.Items, {url}];
            end
            app.URLDropDown.Value = url;
        end

        function ensureSession(app, url)
            if ~strcmpi(matlab.net.URI(url).Host, matlab.net.URI(app.AuthenticationURL).Host)
                return
            end
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
                app.DebugButton.Icon = fullfile(app.AuthResourceFolder, 'debug-stop.svg');
                app.DebugButton.Tooltip = 'Desativar depuração';
            else
                app.DebugButton.Icon = fullfile(app.AuthResourceFolder, 'debug-start.svg');
                app.DebugButton.Tooltip = 'Ativar depuração';
            end
            app.DebugButton.Value = app.DebugMode;
        end

        function refreshDownloadExecutionModeImage(app)
            if strcmp(app.DownloadExecutionMode, 'webApp')
                app.ExecutionModeButton.Icon = fullfile(app.AuthResourceFolder, 'globe.svg');
                app.ExecutionModeButton.Tooltip = 'Web App Server mode';
                app.ExecutionModeButton.Value = true;
            else
                app.ExecutionModeButton.Icon = fullfile(app.AuthResourceFolder, 'vm.svg');
                app.ExecutionModeButton.Tooltip = 'Desktop mode';
                app.ExecutionModeButton.Value = false;
            end
        end

        function refreshSilentDownloadModeImage(app)
            if app.SilentDownloadMode
                app.SilentModeButton.Icon = fullfile(app.AuthResourceFolder, 'bell.svg');
                app.SilentModeButton.Tooltip = 'Reativar notificações de download';
            else
                app.SilentModeButton.Icon = fullfile(app.AuthResourceFolder, 'bell-slash.svg');
                app.SilentModeButton.Tooltip = 'Ativar downloads silenciosos';
            end
            app.SilentModeButton.Value = app.SilentDownloadMode;
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
            if state.connected
                app.ProfileButton.Tooltip = 'Perfil';
            else
                app.ProfileButton.Tooltip = 'Conectar';
            end
            if app.BridgeReady
                sendEventToHTMLSource(app.BridgeHTML, 'f5BrowserPresentation', ...
                    struct('operation', 'profile', ...
                           'dataTag', app.BridgeTags.profile, ...
                           'state', state));
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

        function renderRawResponse(app, response, baseURL)
            if nargin < 3
                baseURL = strtrim(app.URLDropDown.Value);
            end
            responseText = char(response.show);
            app.renderResponseText(responseText, baseURL)
        end

        function render(app, data, baseURL)
            if nargin < 3
                baseURL = strtrim(app.URLDropDown.Value);
            end
            if ischar(data) || isStringScalar(data)
                content = formatJSONText(char(data));
                if ~contains(content, '<html', 'IgnoreCase', true) && ~contains(content, '<body', 'IgnoreCase', true)
                    content = sprintf('<pre>%s</pre>', app.escapeHTML(content));
                end
            elseif isstruct(data) || iscell(data) || isnumeric(data) || islogical(data)
                content = sprintf('<pre>%s</pre>', app.escapeHTML(jsonencode(data, 'PrettyPrint', true)));
            else
                content = sprintf('<pre>Conteudo nao renderizavel (%s).</pre>', class(data));
            end
            app.updateResponse(content, baseURL)
        end

        %-----------------------------------------------------------------%
        function updateResponse(app, content, baseURL)
            app.ResponseState = struct('content', content, 'baseURL', baseURL);
            if app.BridgeReady
                sendEventToHTMLSource(app.BridgeHTML, 'f5BrowserPresentation', ...
                    struct('operation', 'response', ...
                           'dataTag', app.BridgeTags.response, ...
                           'content', content, ...
                           'baseURL', baseURL));
            end
        end

        %-----------------------------------------------------------------%
        function clearResponse(app)
            app.ResponseState = struct('content', '', 'baseURL', '');
            if app.BridgeReady
                sendEventToHTMLSource(app.BridgeHTML, 'f5BrowserPresentation', ...
                    struct('operation', 'clearResponse', ...
                           'dataTag', app.BridgeTags.response));
            end
        end
    end


    methods (Static, Access = private)
        function tf = isDownloadURL(url)
            tf = false;
            try
                uri = matlab.net.URI(url);
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

    end
end


function value = fieldOr(source, fieldName, defaultValue)
value = defaultValue;
if isstruct(source) && isfield(source, fieldName)
    value = source.(fieldName);
end
end

function text = decodeResponseBody(body)
try
    text = native2unicode(reshape(uint8(body), 1, []), 'UTF-8');
    text = formatJSONText(text);
catch
    text = sprintf('[binary response: %d bytes]', numel(body));
end
end

function text = formatJSONText(text)
try
    data = jsondecode(text);
    text = jsonencode(data, 'PrettyPrint', true);
catch
end
end

    function closeProgressDialog(dialog)
    if ~isempty(dialog) && isvalid(dialog)
        close(dialog)
    end
end
