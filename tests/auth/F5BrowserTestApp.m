classdef F5BrowserTestApp < matlab.apps.AppBase

    % F5BrowserTestApp
    % Mini-navegador de teste para ws.auth.F5Session: autentica uma única vez
    % (SAML + MFA na janela embarcada) e reaproveita os cookies em memória
    % para navegar por outras URLs do mesmo host via cliente HTTP do MATLAB.

    properties (Access = private)
        Session
        FigureBackgroundColor  % Store the figure background color

        UIFigure    matlab.ui.Figure
        URLDropDown matlab.ui.control.DropDown
        DebugImage matlab.ui.control.Image
        DownloadAvatarHTML matlab.ui.control.HTML
        ProfileAvatarHTML matlab.ui.control.HTML
        HTMLView    matlab.ui.control.HTML
        ProfileMenu matlab.ui.container.Panel
        DownloadContent matlab.ui.container.Panel
        ProfileNameLabel matlab.ui.control.Label
        ProfileDetailsLabel matlab.ui.control.Label
        SignOutButton matlab.ui.control.Button
        DebugMode (1,1) logical = false
        AuthResourceFolder (1, :) char = ''
        DefaultServerDownloadPath (1, :) char = ''
        DownloadAvatarHTMLPath (1, :) char = ''
        ProfileAvatarHTMLPath (1, :) char = ''
        DownloadAvatarState struct = struct('level', 0, ...
                    'inProgress', false, ...
                    'ballCount', 0, ...
                    'speedRadiansPerSecond', 0)
        DownloadAvatarHTMLReady (1,1) logical = false
        ProfileAvatarState struct = struct('action', 'render', ...
                            'connected', false, ...
                            'initial', '?', ...
                            'photoPngBase64', '')
        ProfileAvatarHTMLReady (1,1) logical = false
        DownloadDialog
        DownloadStack
        DownloadTasks = {}
        NextDownloadID (1,1) double = 0
    end

    properties (Constant, Access = private)
        AuthenticationURL = 'https://fiscalizacao.anatel.gov.br/rffusion/api/users/login'
        DefaultURLs = {'https://fiscalizacao.anatel.gov.br/rffusion/api/users/me', ...
                       'https://fiscalizacao.anatel.gov.br/rffusion/server/zabbix_metrics', ...
                       'https://fiscalizacao.anatel.gov.br/rffusion/server/runtime-health', ...
                       'https://fiscalizacao.anatel.gov.br/rffusion/api/map/stations', ...
                       'https://fiscalizacao.anatel.gov.br/rffusion/api/map/stations?start_date=2026-09-01&end_date=2026-09-07', ...
                       'https://fiscalizacao.anatel.gov.br/downloads/2024/RO/1100205/176/p-1f25532e--rfeye002210_240819_T175952.bin', ...
                       'https://fiscalizacao.anatel.gov.br/downloads/2026/SP/3549805/79/p-6b9f7d03--rfeye002266_260901_T073300.bin'}
    end


    methods
        %-----------------------------------------------------------------%
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

        %-----------------------------------------------------------------%
        function delete(app)
            for taskID = 1:numel(app.DownloadTasks)
                task = app.DownloadTasks{taskID};
                if isempty(task)
                    continue
                end
                if ~isempty(task.Downloader) && isvalid(task.Downloader)
                    delete(task.Downloader)
                end
                app.closeDownloadDialog(taskID)
            end
            app.DownloadTasks = {};
            app.closeDownloadContainer()
            delete(app.Session)

            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure)
            end
        end
    end


    methods (Access = private)
        %-----------------------------------------------------------------%
        function createComponents(app)
            app.UIFigure = uifigure('Name', 'F5Session :: Navegador de teste', 'Position', [100, 100, 1000, 700]);
            app.UIFigure.CloseRequestFcn = @(~, ~) delete(app);
            app.AuthResourceFolder = fileparts(mfilename('fullpath'));
            app.DefaultServerDownloadPath = app.AuthResourceFolder;
            projectFolder = fileparts(fileparts(app.AuthResourceFolder));
            app.DownloadAvatarHTMLPath = fullfile(projectFolder, 'src', 'Anatel', '+ws', '+auth', 'downloadAvatar.html');
            app.ProfileAvatarHTMLPath = fullfile(projectFolder, 'src', 'Anatel', '+ws', '+auth', 'profileAvatar.html');

            % Store the figure's background color for use in panels
            app.FigureBackgroundColor = app.UIFigure.Color;

            gridLayout = uigridlayout(app.UIFigure, [2, 4]);
            gridLayout.RowHeight   = {22, '1x'};
            gridLayout.ColumnWidth = {'1x', 22, 22, 22};

            app.URLDropDown = uidropdown(gridLayout, 'Editable', 'on', 'Items', app.DefaultURLs, 'Value', '<digite uma URL ou selecione>');
            app.URLDropDown.ValueChangedFcn = @(~, ~) navigate(app);
            app.URLDropDown.Layout.Row    = 1;
            app.URLDropDown.Layout.Column = 1;

            app.DebugImage = uiimage(gridLayout, ...
                                     'ImageSource', fullfile(app.AuthResourceFolder, 'debug-alt.svg'), ...
                                     'ImageClickedFcn', @(~, ~) app.toggleDebugMode());
            app.DebugImage.Layout.Row    = 1;
            app.DebugImage.Layout.Column = 2;

            app.DownloadAvatarHTML = uihtml(gridLayout);
            app.DownloadAvatarHTML.HTMLEventReceivedFcn = @(~, event) app.onDownloadAvatarEvent(event);
            app.DownloadAvatarHTML.HTMLSource = app.DownloadAvatarHTMLPath;
            app.DownloadAvatarHTML.Layout.Row    = 1;
            app.DownloadAvatarHTML.Layout.Column = 3;

            app.ProfileAvatarHTML = uihtml(gridLayout);
            app.ProfileAvatarHTML.HTMLEventReceivedFcn = @(~, event) app.onProfileAvatarEvent(event);
            app.ProfileAvatarHTML.HTMLSource = app.ProfileAvatarHTMLPath;
            app.ProfileAvatarHTML.Layout.Row    = 1;
            app.ProfileAvatarHTML.Layout.Column = 4;

            app.HTMLView = uihtml(gridLayout, 'HTMLSource', '<html><body></body></html>');
            app.HTMLView.Layout.Row    = 2;
            app.HTMLView.Layout.Column = [1, 4];

            app.UIFigure.WindowButtonDownFcn = @(~, event) app.onMainFigureButtonDown(event);

            app.ProfileMenu = uipanel(app.UIFigure, 'Visible', 'off', 'Title', 'Perfil');
            menuLayout = uigridlayout(app.ProfileMenu, [3, 1]);
            menuLayout.Padding = [12, 8, 12, 8];
            menuLayout.RowHeight = {30, '1x', 34};

            app.ProfileNameLabel = uilabel(menuLayout, 'Text', '', 'FontWeight', 'bold');
            app.ProfileNameLabel.Layout.Row = 1;
            app.ProfileNameLabel.Layout.Column = 1;

            app.ProfileDetailsLabel = uilabel(menuLayout, 'Text', '', 'VerticalAlignment', 'top', 'WordWrap', 'on');
            app.ProfileDetailsLabel.Layout.Row = 2;
            app.ProfileDetailsLabel.Layout.Column = 1;

            app.SignOutButton = uibutton(menuLayout, ...
                                         'Text', 'desconectar', ...
                                         'ButtonPushedFcn', @(~, ~) app.signOut());
            app.SignOutButton.Layout.Row = 3;
            app.SignOutButton.Layout.Column = 1;
        end

        %-----------------------------------------------------------------%
        function navigate(app)
            url = strtrim(app.URLDropDown.Value);
            if isempty(url)
                return
            end
            addToHistory(app, url)

            try
                ensureSession(app, url)

                if app.isDownloadURL(url)
                    defaultFilePath = fullfile(app.DefaultServerDownloadPath, app.fileNameFromURL(url));
                    downloadFile(app, url, defaultFilePath)
                    refreshStatus(app)
                    return
                end

                progressDialog = uiprogressdlg(app.UIFigure, 'Indeterminate', 'on', 'Message', sprintf('Lendo %s', url));
                progressCleanup = onCleanup(@() close(progressDialog));

                render(app, read(app.Session, url))

            catch ME
                app.HTMLView.HTMLSource = '<html><body></body></html>';
                uialert(app.UIFigure, ME.message, 'Falha na requisição')
            end

            refreshStatus(app)
        end

        %-----------------------------------------------------------------%
        function connect(app)
            try
                ensureSession(app, app.AuthenticationURL)
                [~, response] = readRaw(app.Session, app.AuthenticationURL);
                renderRawResponse(app, response)
            catch ME
                uialert(app.UIFigure, ME.message, 'Falha na autenticação')
            end

            refreshStatus(app)
        end

        %-----------------------------------------------------------------%
        function profileImageClicked(app)
            if ~isempty(app.Session) && isvalid(app.Session) && app.Session.IsAuthenticated
                app.toggleProfileMenu()
                return
            end

            app.connect()
        end

        %-----------------------------------------------------------------%
        function toggleDebugMode(app)
            app.DebugMode = ~app.DebugMode;
            app.refreshDebugImage()
        end

        %-----------------------------------------------------------------%
        function onProfileAvatarEvent(app, event)
            eventName = "";
            if isprop(event, 'HTMLEventName')
                eventName = string(event.HTMLEventName);
            elseif isprop(event, 'EventName')
                eventName = string(event.EventName);
            end

            payload = [];
            if isprop(event, 'HTMLEventData')
                payload = event.HTMLEventData;
            elseif isprop(event, 'Data')
                payload = event.Data;
            end
            if ischar(payload) || (isstring(payload) && isscalar(payload))
                try
                    payload = jsondecode(char(payload));
                catch
                    payload = struct();
                end
            end
            if eventName == "profileAvatarClick"
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

        %-----------------------------------------------------------------%
        function onDownloadAvatarEvent(app, event)
            eventName = "";
            if isprop(event, 'HTMLEventName')
                eventName = string(event.HTMLEventName);
            elseif isprop(event, 'EventName')
                eventName = string(event.EventName);
            end

            payload = [];
            if isprop(event, 'HTMLEventData')
                payload = event.HTMLEventData;
            elseif isprop(event, 'Data')
                payload = event.Data;
            end
            if ischar(payload) || (isstring(payload) && isscalar(payload))
                try
                    payload = jsondecode(char(payload));
                catch
                    payload = struct();
                end
            end

            if eventName == "downloadAvatarClick"
                app.showDownloadContainer()
                return
            end
            if ~isstruct(payload) || ~isfield(payload, 'type')
                return
            end

            switch string(payload.type)
                case "ready"
                    app.DownloadAvatarHTMLReady = true;
                    app.DownloadAvatarHTML.Data = app.DownloadAvatarState;

                case "click"
                    app.showDownloadContainer()
            end
        end

        %-----------------------------------------------------------------%
        function showDownloadContainer(app)
            if isempty(app.DownloadDialog) || ~isvalid(app.DownloadDialog)
                return
            end

            app.DownloadDialog.Visible = 'on';
            drawnow
            app.refreshDownloadContainer()
            uistack(app.DownloadDialog, 'top')
        end

        %-----------------------------------------------------------------%
        function hideDownloadContainer(app)
            if ~isempty(app.DownloadDialog) && isvalid(app.DownloadDialog)
                app.DownloadDialog.Visible = 'off';
            end
        end

        %-----------------------------------------------------------------%
        function onMainFigureButtonDown(app, ~)
            if isempty(app.DownloadDialog) || ~isvalid(app.DownloadDialog) || ...
                    ~strcmp(app.DownloadDialog.Visible, 'on')
                return
            end

            point = app.UIFigure.CurrentPoint;
            panelPosition = app.DownloadDialog.Position;
            insidePanel = point(1) >= panelPosition(1) && ...
                          point(1) <= panelPosition(1) + panelPosition(3) && ...
                          point(2) >= panelPosition(2) && ...
                          point(2) <= panelPosition(2) + panelPosition(4);
            if ~insidePanel
                app.hideDownloadContainer()
            end
        end

        %-----------------------------------------------------------------%
        function toggleProfileMenu(app)
            if strcmp(app.ProfileMenu.Visible, 'on')
                app.ProfileMenu.Visible = 'off';
                return
            end

            [~, profile] = app.Session.getAuthenticationInfo();
            app.ProfileNameLabel.Text = app.profileName(profile);
            app.ProfileDetailsLabel.Text = app.profileDetails(profile);

            drawnow
            imagePosition = getpixelposition(app.ProfileAvatarHTML, true);
            menuWidth = 300;
            menuHeight = 240;
            figureSize = app.UIFigure.Position(3:4);
            menuX = min(max(8, imagePosition(1) + imagePosition(3) - menuWidth), ...
                        max(8, figureSize(1) - menuWidth - 8));
            menuY = imagePosition(2) - menuHeight - 4;
            if menuY < 8
                menuY = imagePosition(2) + imagePosition(4) + 4;
            end

            app.ProfileMenu.Position = [menuX, menuY, menuWidth, menuHeight];
            app.ProfileMenu.Visible = 'on';
            uistack(app.ProfileMenu, 'top')
        end

        %-----------------------------------------------------------------%
        function signOut(app)
            app.ProfileMenu.Visible = 'off';
            if ~isempty(app.Session) && isvalid(app.Session)
                logout(app.Session)
                app.Session = [];
            end
            app.HTMLView.HTMLSource = '<html><body></body></html>';
            refreshStatus(app)
        end

        %-----------------------------------------------------------------%
        function downloadFile(app, url, filePath)
            % URLs cujo último segmento tem extensão são baixadas para disco,
            % em vez de renderizadas.

            if nargin < 3 || isempty(filePath)
                [fileName, folderName] = uiputfile('*.*', 'Salvar arquivo');
                figure(app.UIFigure)

                if isequal(fileName, 0)
                    return
                end
                filePath = fullfile(folderName, fileName);
            end

            filePath = resolveExistingFile(app, filePath);
            if isempty(filePath)
                return
            end
            if app.isDownloadPathActive(filePath)
                uialert(app.UIFigure, ...
                        sprintf('O arquivo "%s" já está sendo baixado.', filePath), ...
                        'Download')
                return
            end
            [~, baseName, extension] = fileparts(filePath);

            app.NextDownloadID = app.NextDownloadID + 1;
            taskID = app.NextDownloadID;
            task = app.createDownloadDialog(taskID, [baseName, extension]);
            task.FilePath = filePath;

            task.LogPath = [filePath, '.log'];
            app.DownloadTasks{taskID} = task;
            F5BrowserTestApp.writeDownloadLog(task.LogPath, sprintf('START\nURL: %s\nDestination: %s\nSession: %s\n', ...
                                                                     url, filePath, app.sessionDebugText()));

            % O download roda em backgroundPool: esta função retorna
            % imediatamente e a aplicação segue utilizável.
            task.Downloader = ws.auth.FileDownload(app.Session, url, filePath);
            task.Downloader.ProgressFcn  = @(receivedBytes, totalBytes) app.onDownloadProgress(taskID, receivedBytes, totalBytes);
            task.Downloader.CompletedFcn = @(info) app.onDownloadCompleted(taskID, info);
            task.Downloader.ErrorFcn     = @(ME) app.onDownloadFailed(taskID, ME);
            app.DownloadTasks{taskID} = task;
            app.showDownloadContainer()
            app.updateDownloadAvatar()
            start(task.Downloader)
        end

        %-----------------------------------------------------------------%
        function onDownloadCompleted(app, taskID, info)
            task = app.getDownloadTask(taskID);
            if isempty(task)
                return
            end
            F5BrowserTestApp.writeDownloadLog(task.LogPath, sprintf('Bytes received: %d\nEND\n', info.BytesReceived));
            app.closeDownloadDialog(taskID)
            app.DownloadTasks{taskID} = [];
            app.updateDownloadAvatar()
        end

        %-----------------------------------------------------------------%
        function onDownloadFailed(app, taskID, exception)
            task = app.getDownloadTask(taskID);
            if isempty(task)
                return
            end
            F5BrowserTestApp.writeDownloadLog(task.LogPath, sprintf('ERROR\n%s\nEND\n', ...
                                                                     getReport(exception, 'extended', 'hyperlinks', 'off')));
            app.closeDownloadDialog(taskID)
            app.DownloadTasks{taskID} = [];
            app.updateDownloadAvatar()

            % O arquivo parcial é preservado para permitir a retomada.
            uialert(app.UIFigure, ...
                    F5BrowserTestApp.downloadErrorReport(exception, task.FilePath, task.LogPath), ...
                    'Falha no download')
        end

        %-----------------------------------------------------------------%
        function filePath = resolveExistingFile(app, filePath)
            % Um arquivo já existente pode ser um download interrompido: o
            % usuário decide entre retomar, recomeçar ou salvar em outro nome.

            while isfile(filePath)
                fileInfo = dir(filePath);
                choice = uiconfirm(app.UIFigure, ...
                                   sprintf(['O arquivo "%s" já existe (%s gravados).\n\n', ...
                                            'Continuar retoma o download a partir do que já está em disco.'], ...
                                           filePath, F5BrowserTestApp.formatBytes(fileInfo.bytes)), ...
                                   'Arquivo existente', ...
                                   'Options', {'Continuar', 'Reiniciar', 'Outro nome', 'Cancelar'}, ...
                                   'DefaultOption', 1, 'CancelOption', 4);

                switch choice
                    case 'Continuar'
                        return

                    case 'Reiniciar'
                        delete(filePath)
                        return

                    case 'Outro nome'
                        [fileName, folderName] = uiputfile('*.*', 'Salvar arquivo', filePath);
                        figure(app.UIFigure)
                        if isequal(fileName, 0)
                            filePath = '';
                            return
                        end
                        filePath = fullfile(folderName, fileName);

                    otherwise
                        filePath = '';
                        return
                end
            end
        end

        %-----------------------------------------------------------------%
        function task = createDownloadDialog(app, taskID, fileName)
            task = struct('Downloader', [], ...
                          'Dialog', [], ...
                          'Separator', [], ...
                          'StatusLabel', [], ...
                          'BytesLabel', [], ...
                          'ProgressTrack', [], ...
                          'ProgressFill', [], ...
                          'ProgressMarkers', [], ...
                          'ProgressFraction', 0, ...
                          'ReceivedBytes', 0, ...
                          'TotalBytes', [], ...
                          'TransferRate', NaN, ...
                          'PauseButton', [], ...
                          'StopButton', [], ...
                          'FileName', fileName, ...
                          'FilePath', '', ...
                          'LogPath', '', ...
                          'IsPaused', false, ...
                          'IsStopped', false, ...
                          'StartTimer', tic, ...
                          'ProgressSamples', zeros(0, 2));

            app.ensureDownloadContainer()
            task.Dialog = uipanel(app.DownloadStack, ...
                                  'BorderType', 'none', ...
                                  'BackgroundColor', app.FigureBackgroundColor);
            task.Separator = uipanel(app.DownloadStack, ...
                                     'BorderType', 'none', ...
                                     'BackgroundColor', [0.55, 0.55, 0.55], ...
                                     'Visible', 'off');
            gridLayout = uigridlayout(task.Dialog, [4, 3]);
            gridLayout.Padding = [16, 12, 16, 8];
            gridLayout.RowSpacing = 4;
            gridLayout.RowHeight = {24, 20, 46, 30};
            gridLayout.ColumnWidth = {'1x', 90, 90};

            task.StatusLabel = uilabel(gridLayout, ...
                                       'Text', fileName, ...
                                       'HorizontalAlignment', 'left', ...
                                       'VerticalAlignment', 'bottom', ...
                                       'WordWrap', 'on');
            task.StatusLabel.Layout.Row = 1;
            task.StatusLabel.Layout.Column = [1, 3];

            % Barra simples: uma faixa azul preenchendo a trilha, com linhas
            % verticais nos pontos de 0%, 25%, 50%, 75% e 100%.
            task.ProgressTrack = uipanel(gridLayout, ...
                                         'BorderType', 'none', ...
                                         'BackgroundColor', app.FigureBackgroundColor);
            task.ProgressTrack.Layout.Row = 2;
            task.ProgressTrack.Layout.Column = [1, 3];

            task.ProgressFill = uipanel(task.ProgressTrack, ...
                                        'BorderType', 'none', ...
                                        'BackgroundColor', [0, 0.447, 0.741], ...
                                        'Units', 'pixels', ...
                                        'Position', [0, 0, 0, 1]);
            task.ProgressMarkers = gobjects(1, 5);
            for markerIndex = 1:numel(task.ProgressMarkers)
                task.ProgressMarkers(markerIndex) = uipanel(task.ProgressTrack, ...
                                                             'BorderType', 'none', ...
                                                             'BackgroundColor', [0.45, 0.45, 0.45], ...
                                                             'Units', 'pixels', ...
                                                             'Position', [0, 0, 1, 1]);
            end

            task.BytesLabel = uilabel(gridLayout, 'Text', '', 'WordWrap', 'on');
            task.BytesLabel.Layout.Row = 3;
            task.BytesLabel.Layout.Column = [1, 3];

            task.PauseButton = uibutton(gridLayout, 'Text', 'Pausar', ...
                                        'ButtonPushedFcn', @(~, ~) app.toggleDownloadPause(taskID));
            task.PauseButton.Layout.Row = 4;
            task.PauseButton.Layout.Column = 2;

            task.StopButton = uibutton(gridLayout, 'Text', 'Parar', ...
                                       'ButtonPushedFcn', @(src, ~) app.stopDownload(taskID, src));
            task.StopButton.Layout.Row = 4;
            task.StopButton.Layout.Column = 3;
            drawnow
            app.updateProgressScale(task, task.ProgressTrack.InnerPosition)
        end

        %-----------------------------------------------------------------%
        function onDownloadProgress(app, taskID, receivedBytes, totalBytes)
            % Sem Content-Length não há total conhecido: a barra fica vazia e
            % apenas o volume recebido é informado.

            task = app.getDownloadTask(taskID);
            if isempty(task) || task.IsStopped || ~isvalid(app)
                return
            end
            task.ReceivedBytes = double(receivedBytes);
            task.TotalBytes = totalBytes;
            if isempty(task.ProgressTrack) || ~isvalid(task.ProgressTrack)
                app.DownloadTasks{taskID} = task;
                app.updateDownloadAvatar()
                return
            end

            elapsedSeconds = toc(task.StartTimer);
            task.ProgressSamples(end+1, :) = [elapsedSeconds, double(receivedBytes)];
            cutoffTime = elapsedSeconds - 10;
            samplesBeforeCutoff = find(task.ProgressSamples(:, 1) <= cutoffTime, 1, 'last');
            if ~isempty(samplesBeforeCutoff)
                task.ProgressSamples = task.ProgressSamples(samplesBeforeCutoff:end, :);
            end

            % fake default transfer rate to simulate a minimum speed before enough samples are collected
            transferRate = 100000;
            if elapsedSeconds >= 10 && size(task.ProgressSamples, 1) >= 2
                sampleDuration = task.ProgressSamples(end, 1) - task.ProgressSamples(1, 1);
                if sampleDuration >= 10
                    transferRate = (task.ProgressSamples(end, 2) - task.ProgressSamples(1, 2)) / sampleDuration;
                end
            end

            if isempty(totalBytes) || totalBytes <= 0
                fraction = 0;
            else
                fraction = min(receivedBytes/totalBytes, 1);
            end
            task.BytesLabel.Text = app.downloadProgressText(receivedBytes, totalBytes, elapsedSeconds, transferRate);
            task.ProgressFraction = fraction;
            task.TransferRate = transferRate;

            trackSize = task.ProgressTrack.InnerPosition;
            app.updateProgressScale(task, trackSize);

            app.DownloadTasks{taskID} = task;
            app.updateDownloadAvatar()
            drawnow limitrate
        end

        %-----------------------------------------------------------------%
        function updateDownloadAvatar(app)
            activeCount = 0;
            receivedBytes = 0;
            totalBytes = 0;
            transferRate = 0;

            for taskID = 1:numel(app.DownloadTasks)
                task = app.DownloadTasks{taskID};
                if isempty(task) || task.IsStopped
                    continue
                end

                activeCount = activeCount + 1;
                if isfield(task, 'ReceivedBytes') && isscalar(task.ReceivedBytes) && isfinite(task.ReceivedBytes)
                    receivedBytes = receivedBytes + max(0, double(task.ReceivedBytes));
                end
                if isfield(task, 'TotalBytes') && ~isempty(task.TotalBytes) && ...
                        isscalar(task.TotalBytes) && isfinite(task.TotalBytes) && task.TotalBytes > 0
                    totalBytes = totalBytes + double(task.TotalBytes);
                end
                if isfield(task, 'TransferRate') && isscalar(task.TransferRate) && ...
                        isfinite(task.TransferRate) && task.TransferRate > 0
                    transferRate = transferRate + double(task.TransferRate);
                end
            end

            percentage = 0;
            if totalBytes > 0
                percentage = min(100, receivedBytes/totalBytes*100);
            end
            level = app.downloadAvatarLevel(percentage);
            speedRadiansPerSecond = transferRate/1024^2*2*pi;
            state = struct('level', level, ...
                           'inProgress', activeCount > 0, ...
                           'ballCount', activeCount, ...
                           'speedRadiansPerSecond', speedRadiansPerSecond);

            if isequal(state, app.DownloadAvatarState)
                return
            end
            app.DownloadAvatarState = state;
            if app.DownloadAvatarHTMLReady && ~isempty(app.DownloadAvatarHTML) && isvalid(app.DownloadAvatarHTML)
                app.DownloadAvatarHTML.Data = state;
            end
        end

        %-----------------------------------------------------------------%
        function level = downloadAvatarLevel(~, percentage)
            if percentage <= 0
                level = 0;
            elseif percentage >= 90
                level = 10;
            else
                level = ceil(percentage/10);
            end
        end

        %-----------------------------------------------------------------%
        function text = downloadProgressText(~, receivedBytes, totalBytes, elapsedSeconds, transferRate)
            receivedText = F5BrowserTestApp.formatBytes(receivedBytes);
            totalText = '-';
            totalSizeText = '-';
            if ~isempty(totalBytes) && totalBytes > 0
                totalText = F5BrowserTestApp.formatBytes(totalBytes);
                totalSizeText = F5BrowserTestApp.formatTotalBytes(totalBytes);
            end

            if elapsedSeconds < 10
                elapsedText = '- s';
                remainingText = '- s';
            else
                elapsedText = F5BrowserTestApp.formatDuration(elapsedSeconds);
                remainingText = '- s';
                if ~isempty(totalBytes) && totalBytes > 0 && isfinite(transferRate) && transferRate > 0
                    remainingBytes = max(0, double(totalBytes) - double(receivedBytes));
                    remainingText = F5BrowserTestApp.formatDuration(remainingBytes/transferRate);
                end
            end

            text = sprintf('%s / %s (%s) | Decorrido: %s | Restante: %s', ...
                           receivedText, totalText, totalSizeText, elapsedText, remainingText);
        end

        %-----------------------------------------------------------------%
        function updateProgressScale(~, task, trackSize)
            if isempty(task.ProgressTrack) || ~isvalid(task.ProgressTrack)
                return
            end

            trackWidth = max(0, trackSize(3));
            trackHeight = max(1, trackSize(4));
            task.ProgressFill.Position = [0, 0, task.ProgressFraction*trackWidth, trackHeight];

            markerWidth = 1;
            markerXPositions = round((0:4)/4 * max(0, trackWidth - markerWidth));
            for markerIndex = 1:numel(task.ProgressMarkers)
                marker = task.ProgressMarkers(markerIndex);
                if ~isempty(marker) && isvalid(marker)
                    marker.Position = [markerXPositions(markerIndex), 0, markerWidth, trackHeight];
                end
            end
        end

        %-----------------------------------------------------------------%
        function resizeDownloadProgressBars(app)
            if isempty(app.DownloadDialog) || ~isvalid(app.DownloadDialog)
                return
            end

            for taskID = 1:numel(app.DownloadTasks)
                task = app.DownloadTasks{taskID};
                if isempty(task) || isempty(task.Dialog) || ~isvalid(task.Dialog)
                    continue
                end
                if ~isempty(task.ProgressTrack) && isvalid(task.ProgressTrack)
                    app.updateProgressScale(task, task.ProgressTrack.InnerPosition)
                end
            end
        end

        %-----------------------------------------------------------------%
        function onDownloadWindowResized(app)
            if isempty(app.DownloadDialog) || ~isvalid(app.DownloadDialog)
                return
            end

            % Let the standard grid finish resizing before refreshing the
            % nested progress grids.
            drawnow
            app.resizeDownloadProgressBars()
            drawnow limitrate
        end

        %-----------------------------------------------------------------%
        function toggleDownloadPause(app, taskID)
            task = app.getDownloadTask(taskID);
            if isempty(task) || task.IsStopped
                return
            end

            task.IsPaused = ~task.IsPaused;
            if task.IsPaused
                pause(task.Downloader)
                task.PauseButton.Text = 'Continuar';
            else
                resume(task.Downloader)
                task.PauseButton.Text = 'Pausar';
            end
            task.TransferRate = NaN;
            app.DownloadTasks{taskID} = task;
            app.updateDownloadAvatar()
        end

        %-----------------------------------------------------------------%
        function stopDownload(app, taskID, ~)
            task = app.getDownloadTask(taskID);
            if isempty(task)
                return
            end

            task.IsStopped = true;
            task.IsPaused = false;
            if ~isempty(task.Downloader) && isvalid(task.Downloader)
                stop(task.Downloader)
            end
            app.DownloadTasks{taskID} = task;
            app.closeDownloadDialog(taskID)
            app.updateDownloadAvatar()
        end

        %-----------------------------------------------------------------%
        function closeDownloadDialog(app, taskID)
            task = app.getDownloadTask(taskID);
            if isempty(task)
                return
            end
            if ~isempty(task.Dialog) && isvalid(task.Dialog)
                delete(task.Dialog)
            end
            if ~isempty(task.Separator) && isvalid(task.Separator)
                delete(task.Separator)
            end
            task.Dialog = [];
            task.Separator = [];
            task.StatusLabel = [];
            task.BytesLabel = [];
            task.ProgressTrack = [];
            task.ProgressFill = [];
            task.ProgressMarkers = [];
            task.PauseButton = [];
            task.StopButton = [];
            app.DownloadTasks{taskID} = task;
            app.refreshDownloadContainer()
        end

        %-----------------------------------------------------------------%
        function ensureDownloadContainer(app)
            if ~isempty(app.DownloadDialog) && isvalid(app.DownloadDialog)
                return
            end

            app.DownloadDialog = uipanel(app.UIFigure, ...
                                         'Title', 'Downloads', ...
                                         'Visible', 'off', ...
                                         'Scrollable', 'off', ...
                                         'Units', 'pixels', ...
                                         'BorderType', 'line', ...
                                         'BackgroundColor', app.FigureBackgroundColor);
            app.DownloadContent = uipanel(app.DownloadDialog, ...
                                          'BorderType', 'none', ...
                                          'Units', 'pixels', ...
                                          'BackgroundColor', app.FigureBackgroundColor);
            app.DownloadStack = uigridlayout(app.DownloadContent, [1, 1]);
            app.DownloadStack.Padding = [0, 0, 0, 0];
            app.DownloadStack.RowSpacing = 0;
            app.DownloadStack.ColumnWidth = {'1x'};
            app.DownloadStack.RowHeight = {152};
            app.positionDownloadContainer(1)
            app.resizeDownloadProgressBars()
        end

        %-----------------------------------------------------------------%
        function closeDownloadContainer(app)
            if ~isempty(app.DownloadDialog) && isvalid(app.DownloadDialog)
                delete(app.DownloadDialog)
            end
            app.DownloadDialog = [];
            app.DownloadContent = matlab.ui.container.Panel.empty;
            app.DownloadStack = [];
        end

        %-----------------------------------------------------------------%
        function refreshDownloadContainer(app)
            if isempty(app.DownloadDialog) || ~isvalid(app.DownloadDialog)
                app.DownloadDialog = [];
                app.DownloadContent = matlab.ui.container.Panel.empty;
                app.DownloadStack = [];
                return
            end

            activeIDs = [];
            for taskID = 1:numel(app.DownloadTasks)
                task = app.DownloadTasks{taskID};
                if ~isempty(task) && ~isempty(task.Dialog) && isvalid(task.Dialog)
                    activeIDs(end+1) = taskID; %#ok<AGROW>
                end
            end

            if isempty(activeIDs)
                delete(app.DownloadDialog)
                app.DownloadDialog = [];
                app.DownloadContent = matlab.ui.container.Panel.empty;
                app.DownloadStack = [];
                return
            end

            contentHeight = 16 + 153*numel(activeIDs);
            rowHeights = repmat({1}, 1, 2*numel(activeIDs));
            rowHeights(1:2:end) = repmat({152}, 1, numel(activeIDs));
            app.DownloadStack.RowHeight = rowHeights;
            app.positionDownloadContainer(contentHeight)
            drawnow
            for row = 1:numel(activeIDs)
                task = app.DownloadTasks{activeIDs(row)};
                task.Dialog.Layout.Row = 2*row - 1;
                task.Dialog.Layout.Column = 1;
                task.Separator.Layout.Row = 2*row;
                task.Separator.Layout.Column = 1;
                if row < numel(activeIDs)
                    task.Separator.Visible = 'on';
                else
                    task.Separator.Visible = 'off';
                end
            end
            drawnow
            app.resizeDownloadProgressBars()
            drawnow limitrate
        end

        %-----------------------------------------------------------------%
        function positionDownloadContainer(app, contentHeight)
            if isempty(app.DownloadDialog) || ~isvalid(app.DownloadDialog)
                return
            end

            drawnow limitrate
            avatarPosition = getpixelposition(app.DownloadAvatarHTML, true);
            figurePosition = app.UIFigure.Position;
            figureWidth = figurePosition(3);
            panelWidth = min(560, max(220, figureWidth - 16));
            panelChromeHeight = 24;
            availablePanelHeight = max(64, avatarPosition(2) - 8);
            panelHeight = min(max(64, contentHeight + panelChromeHeight), availablePanelHeight);
            panelX = min(max(8, avatarPosition(1)), max(8, figureWidth - panelWidth - 8));
            panelY = max(8, avatarPosition(2) - panelHeight - 4);

            app.DownloadDialog.Position = [panelX, panelY, panelWidth, panelHeight];
            app.DownloadDialog.Scrollable = 'off';
            drawnow limitrate
            innerPosition = app.DownloadDialog.InnerPosition;
            needsVerticalScroll = contentHeight > innerPosition(4);
            if needsVerticalScroll
                app.DownloadDialog.Scrollable = 'on';
                drawnow limitrate
            end
            innerPosition = app.DownloadDialog.InnerPosition;
            horizontalSafetyMargin = 16;
            contentWidth = max(1, floor(innerPosition(3)) - horizontalSafetyMargin);
            app.DownloadContent.Position = [0, 0, contentWidth, contentHeight];
            drawnow limitrate

            % Re-measure after the first layout pass. A vertical scrollbar can
            % reduce the viewport by a pixel after the child is positioned.
            innerPosition = app.DownloadDialog.InnerPosition;
            stableContentWidth = max(1, floor(innerPosition(3)) - horizontalSafetyMargin);
            if stableContentWidth ~= contentWidth
                app.DownloadContent.Position = [0, 0, stableContentWidth, contentHeight];
                drawnow limitrate
            end
        end

        %-----------------------------------------------------------------%
        function stopAllDownloads(app, source)
            for taskID = 1:numel(app.DownloadTasks)
                task = app.DownloadTasks{taskID};
                if isempty(task)
                    continue
                end
                task.IsStopped = true;
                task.IsPaused = false;
                if ~isempty(task.Downloader) && isvalid(task.Downloader)
                    stop(task.Downloader)
                end
                app.DownloadTasks{taskID} = task;
                app.closeDownloadDialog(taskID)
            end
            app.updateDownloadAvatar()
            if ~isempty(source) && isvalid(source)
                delete(source)
            end
            app.DownloadDialog = [];
            app.DownloadStack = [];
        end

        %-----------------------------------------------------------------%
        function task = getDownloadTask(app, taskID)
            task = [];
            if ~isvalid(app) || taskID > numel(app.DownloadTasks)
                return
            end
            task = app.DownloadTasks{taskID};
        end

        %-----------------------------------------------------------------%
        function tf = isDownloadPathActive(app, filePath)
            tf = false;
            for taskID = 1:numel(app.DownloadTasks)
                task = app.DownloadTasks{taskID};
                if isempty(task) || isempty(task.Downloader)
                    continue
                end
                if isvalid(task.Downloader) && task.Downloader.IsRunning && ...
                        strcmpi(task.FilePath, filePath)
                    tf = true;
                    return
                end
            end
        end

        %-----------------------------------------------------------------%
        function addToHistory(app, url)
            if ~ismember(url, app.URLDropDown.Items)
                app.URLDropDown.Items = [app.URLDropDown.Items, {url}];
            end
            app.URLDropDown.Value = url;
        end

        %-----------------------------------------------------------------%
        function ensureSession(app, url)
            % Uma nova sessão só é necessária se ainda não há login válido ou
            % se a URL aponta para outro host (fora do escopo do cookie F5).

            if ~isempty(app.Session) && isvalid(app.Session) && app.Session.IsAuthenticated
                if strcmpi(matlab.net.URI(url).Host, matlab.net.URI(app.Session.LoginURL).Host)
                    return
                end
                delete(app.Session)
            end

            app.Session = ws.auth.F5Session(app.AuthenticationURL);
            refreshStatus(app)

            progressDialog = uiprogressdlg(app.UIFigure, 'Indeterminate', 'on', ...
                                           'Message', 'Conclua a autenticação na janela do navegador (login + aprovação no Authenticator).');
            progressCleanup = onCleanup(@() close(progressDialog));

            debugFile = '';
            if app.DebugMode
                debugFile = fullfile(app.AuthResourceFolder, ...
                                     [datestr(now, 'yymmdd_HHMMSS') '_browser-state.log']);
                fprintf('F5Session browser state log: %s\n', debugFile)
            end
            app.Session.login(300, debugFile)
        end

        %-----------------------------------------------------------------%
        function refreshStatus(app)
            isConnected = ~isempty(app.Session) && isvalid(app.Session) && app.Session.IsAuthenticated;

            if isConnected
                [~, profile] = app.Session.getAuthenticationInfo();
                app.updateProfileAvatar(true, profile)
                return
            end

            app.ProfileMenu.Visible = 'off';
            app.updateProfileAvatar(false, struct())
        end

        %-----------------------------------------------------------------%
        function refreshDebugImage(app)
            if app.DebugMode
                app.DebugImage.ImageSource = fullfile(app.AuthResourceFolder, 'debug-alt-active.svg');
            else
                app.DebugImage.ImageSource = fullfile(app.AuthResourceFolder, 'debug-alt.svg');
            end
        end

        %-----------------------------------------------------------------%
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

        %-----------------------------------------------------------------%
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
            fileCleanup = onCleanup(@() fclose(fileID));
            imageBytes = fread(fileID, [1, inf], '*uint8');
            base64 = char(matlab.net.base64encode(imageBytes));
        end

        %-----------------------------------------------------------------%
        function initial = profileInitial(app, profile)
            name = app.profileField(profile, {'NA_USER_NAME', 'name', 'displayName', 'username', 'userName'});
            if isempty(name)
                name = app.profileField(profile, {'NA_USER_EMAIL', 'email'});
            end

            if isempty(name)
                initial = '?';
            else
                name = strtrim(name);
                initial = upper(name(1));
            end
        end

        %-----------------------------------------------------------------%
        function name = profileName(app, profile)
            name = app.profileField(profile, {'NA_USER_NAME', 'name', 'displayName', 'username', 'userName'});
            if isempty(name)
                name = app.profileField(profile, {'NA_USER_EMAIL', 'email'});
            end
            if isempty(name)
                name = 'Usuario autenticado';
            end
        end

        %-----------------------------------------------------------------%
        function text = profileDetails(app, profile)
            if ~isstruct(profile) || isempty(profile)
                text = 'Dados do perfil indisponiveis.';
                return
            end

            fields = fieldnames(profile);
            lines = cell(size(fields));
            for fieldIndex = 1:numel(fields)
                fieldName = fields{fieldIndex};
                lines{fieldIndex} = sprintf('%s: %s', fieldName, app.profileValueText(profile.(fieldName)));
            end
            text = strjoin(lines, newline);
        end

        %-----------------------------------------------------------------%
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

        %-----------------------------------------------------------------%
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

        %-----------------------------------------------------------------%
        function renderRawResponse(app, response)
            responseText = char(response.show);

            app.HTMLView.HTMLSource = sprintf('<html><body><pre>%s</pre></body></html>', ...
                                              app.escapeHTML(responseText));
        end

        %-----------------------------------------------------------------%
        function render(app, data)
            if ischar(data) || isStringScalar(data)
                content = char(data);
                if ~contains(content, '<html', 'IgnoreCase', true) && ~contains(content, '<body', 'IgnoreCase', true)
                    content = sprintf('<pre>%s</pre>', app.escapeHTML(content));
                end

            elseif isstruct(data) || iscell(data) || isnumeric(data) || islogical(data)
                content = sprintf('<pre>%s</pre>', app.escapeHTML(jsonencode(data, 'PrettyPrint', true)));

            else
                content = sprintf('<pre>Conteúdo não renderizável (%s).</pre>', class(data));
            end

            baseURL = strtrim(app.URLDropDown.Value);
            app.HTMLView.HTMLSource = sprintf('<html><head><base href="%s"></head><body>%s</body></html>', ...
                                              app.escapeHTML(baseURL), app.sanitizeHTML(content));
        end

        %-----------------------------------------------------------------%
        function text = sessionDebugText(app)
            info = app.Session.debugInfo();
            text = sprintf('Authenticated: %d, Cookie count: %d, Cookie names: %s', ...
                           info.IsAuthenticated, info.CookieCount, strjoin(info.CookieNames, ', '));
        end
    end


    methods (Static, Access = private)
        %-----------------------------------------------------------------%
        function tf = isDownloadURL(url)
            tf = false;
            try
                pathSegments = matlab.net.URI(url).Path;
                tf = ~isempty(pathSegments) && contains(pathSegments(end), '.');
            catch
            end
        end

        %-----------------------------------------------------------------%
        function fileName = fileNameFromURL(url)
            fileName = 'download';
            try
                pathSegments = matlab.net.URI(url).Path;
                if ~isempty(pathSegments) && strlength(pathSegments(end))
                    fileName = char(pathSegments(end));
                end
            catch
            end

            % O nome vem da URL: descarta separadores e caracteres inválidos.
            fileName = regexprep(fileName, '[\\/:*?"<>|]', '_');
        end

        %-----------------------------------------------------------------%
        function report = downloadErrorReport(exception, filePath, logPath)
            report = sprintf('Falha ao baixar o arquivo para "%s".\n\nIdentificador: %s\nMensagem: %s\n\nLog: %s\n\nStack:\n%s', ...
                             filePath, exception.identifier, exception.message, logPath, ...
                             getReport(exception, 'extended', 'hyperlinks', 'off'));

            if ispc
                try
                    memoryInfo = memory;
                    report = sprintf('%s\nMemória disponível: %.1f MB', ...
                                     report, memoryInfo.MemAvailableAllArrays/2^20);
                catch
                end
            end
        end

        %-----------------------------------------------------------------%
        function writeDownloadLog(filePath, text)
            fileID = fopen(filePath, 'a');
            if fileID == -1
                return
            end
            fileCleanup = onCleanup(@() fclose(fileID));

            fprintf(fileID, '[%s] %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS.FFF'), text);
        end

        %-----------------------------------------------------------------%
        function text = formatBytes(value)
            if nargin == 0 || isempty(value) || ~isscalar(value) || ~isfinite(value)
                text = 'unknown';
                return
            end

            value = double(value);
            signText = '';
            if value < 0
                signText = '-';
                value = abs(value);
            end
            digits = sprintf('%.0f', value);
            firstGroupLength = mod(numel(digits), 3);
            if firstGroupLength == 0
                firstGroupLength = 3;
            end

            groupCount = 1 + floor((numel(digits) - firstGroupLength)/3);
            groups = cell(1, groupCount);
            groups{1} = digits(1:firstGroupLength);
            for groupIndex = 2:groupCount
                startIndex = firstGroupLength + (groupIndex - 2)*3 + 1;
                groups{groupIndex} = digits(startIndex:startIndex + 2);
            end
            text = [signText, strjoin(groups, ' ')];
        end

        %-----------------------------------------------------------------%
        function text = formatTotalBytes(value)
            value = double(value);
            unitScales = [1024^3, 1024^2, 1024];
            unitNames = {'GBytes', 'MBytes', 'kBytes'};
            unitIndex = find(value >= unitScales, 1, 'first');
            if isempty(unitIndex)
                unitIndex = numel(unitScales);
            end

            unitValue = max(1, round(value/unitScales(unitIndex)));
            text = sprintf('%.0f %s', unitValue, unitNames{unitIndex});
        end

        %-----------------------------------------------------------------%
        function text = formatDuration(seconds)
            if isempty(seconds) || ~isscalar(seconds) || ~isfinite(seconds)
                text = '- s';
                return
            end

            seconds = max(0, round(double(seconds)));
            if seconds < 60
                text = sprintf('%.0f s', seconds);
                return
            end

            minutes = floor(seconds/60);
            remainingSeconds = mod(seconds, 60);
            if minutes < 60
                if remainingSeconds == 0
                    text = sprintf('%.0f min', minutes);
                else
                    text = sprintf('%.0f min %.0f s', minutes, remainingSeconds);
                end
                return
            end

            hours = floor(minutes/60);
            remainingMinutes = mod(minutes, 60);
            if remainingMinutes == 0
                text = sprintf('%.0f h', hours);
            else
                text = sprintf('%.0f h %.0f min', hours, remainingMinutes);
            end
        end

        %-----------------------------------------------------------------%
        function text = escapeHTML(text)
            text = char(text);
            text = strrep(text, '&', '&amp;');
            text = strrep(text, '<', '&lt;');
            text = strrep(text, '>', '&gt;');
        end

        %-----------------------------------------------------------------%
        function content = sanitizeHTML(content)
            % O conteúdo vem do backend autenticado, mas o uihtml compartilha o
            % contexto CEF do MATLAB - scripts de terceiros ficam de fora.

            content = regexprep(content, '<script\b.*?</script\s*>', '', 'ignorecase');
            content = regexprep(content, '<script\b[^>]*>', '', 'ignorecase');
            content = regexprep(content, '\s+on[a-z]+\s*=\s*"[^"]*"', '', 'ignorecase');
            content = regexprep(content, '\s+on[a-z]+\s*=\s*''[^'']*''', '', 'ignorecase');
            content = regexprep(content, 'javascript:', '', 'ignorecase');
        end
    end

end
