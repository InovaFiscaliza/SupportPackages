classdef F5BrowserTestApp < matlab.apps.AppBase

    % F5BrowserTestApp
    % Mini-navegador de teste para ws.auth.F5Session: autentica uma única vez
    % (SAML + MFA na janela embarcada) e reaproveita os cookies em memória
    % para navegar por outras URLs do mesmo host via cliente HTTP do MATLAB.

    properties (Access = private)
        Session

        UIFigure    matlab.ui.Figure
        URLDropDown matlab.ui.control.DropDown
        StatusLabel matlab.ui.control.Label
        HTMLView    matlab.ui.control.HTML
        DownloadDialog
        DownloadStack
        DownloadTasks = {}
        NextDownloadID (1,1) double = 0
    end

    properties (Constant, Access = private)
        DefaultURLs = {'https://fiscalizacao.anatel.gov.br/rffusion/debug/headers', ...
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

            gridLayout = uigridlayout(app.UIFigure, [2, 2]);
            gridLayout.RowHeight   = {22, '1x'};
            gridLayout.ColumnWidth = {'1x', 260};

            app.URLDropDown = uidropdown(gridLayout, 'Editable', 'on', 'Items', app.DefaultURLs, 'Value', '<digite uma URL ou selecione>');
            app.URLDropDown.ValueChangedFcn = @(~, ~) navigate(app);
            app.URLDropDown.Layout.Row    = 1;
            app.URLDropDown.Layout.Column = 1;

            app.StatusLabel = uilabel(gridLayout, 'Text', 'Desconectado', 'HorizontalAlignment', 'right');
            app.StatusLabel.Layout.Row    = 1;
            app.StatusLabel.Layout.Column = 2;

            app.HTMLView = uihtml(gridLayout, 'HTMLSource', '<html><body></body></html>');
            app.HTMLView.Layout.Row    = 2;
            app.HTMLView.Layout.Column = [1, 2];
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
                    downloadFile(app, url)
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
        function downloadFile(app, url)
            % URLs cujo último segmento tem extensão são baixadas para disco,
            % em vez de renderizadas.

            [fileName, folderName] = uiputfile('*.*', 'Salvar arquivo', fullfile(app.downloadFolder(), app.fileNameFromURL(url)));
            figure(app.UIFigure)

            if isequal(fileName, 0)
                return
            end

            filePath = resolveExistingFile(app, fullfile(folderName, fileName));
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
            app.refreshDownloadContainer()
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
                          'StatusLabel', [], ...
                          'BytesLabel', [], ...
                          'ProgressTrack', [], ...
                          'ProgressFill', [], ...
                          'PauseButton', [], ...
                          'StopButton', [], ...
                          'FileName', fileName, ...
                          'FilePath', '', ...
                          'LogPath', '', ...
                          'IsPaused', false, ...
                          'IsStopped', false);

                    app.ensureDownloadContainer()
                    task.Dialog = uipanel(app.DownloadStack, ...
                              'BorderType', 'line', ...
                              'Title', fileName);
            gridLayout = uigridlayout(task.Dialog, [3, 3]);
            gridLayout.RowHeight = {22, 18, 30};
            gridLayout.ColumnWidth = {'1x', 90, 90};

            task.StatusLabel = uilabel(gridLayout, ...
                                              'Text', sprintf('Baixando %s', fileName), ...
                                              'WordWrap', 'on');
            task.StatusLabel.Layout.Row = 1;
            task.StatusLabel.Layout.Column = [1, 3];

            % Barra simples: uma faixa azul preenchendo a trilha, sem escala
            % nem marcações (uigauge desenha régua e ponteiro).
            task.ProgressTrack = uipanel(gridLayout, ...
                                                'BorderType', 'line', ...
                                                'BackgroundColor', [1, 1, 1]);
            task.ProgressTrack.Layout.Row = 2;
            task.ProgressTrack.Layout.Column = [1, 3];

            task.ProgressFill = uipanel(task.ProgressTrack, ...
                                               'BorderType', 'none', ...
                                               'BackgroundColor', [0, 0.447, 0.741], ...
                                               'Units', 'pixels', ...
                                               'Position', [0, 0, 0, 1]);

            task.BytesLabel = uilabel(gridLayout, 'Text', '');
            task.BytesLabel.Layout.Row = 3;
            task.BytesLabel.Layout.Column = 1;

            task.PauseButton = uibutton(gridLayout, 'Text', 'Pausar', ...
                                        'ButtonPushedFcn', @(~, ~) app.toggleDownloadPause(taskID));
            task.PauseButton.Layout.Row = 3;
            task.PauseButton.Layout.Column = 2;

            task.StopButton = uibutton(gridLayout, 'Text', 'Parar', ...
                                       'ButtonPushedFcn', @(src, ~) app.stopDownload(taskID, src));
            task.StopButton.Layout.Row = 3;
            task.StopButton.Layout.Column = 3;
            task.Dialog.Layout.Row = 1;
            task.Dialog.Layout.Column = 1;
            drawnow
        end

        %-----------------------------------------------------------------%
        function onDownloadProgress(app, taskID, receivedBytes, totalBytes)
            % Sem Content-Length não há total conhecido: a barra fica vazia e
            % apenas o volume recebido é informado.

            task = app.getDownloadTask(taskID);
            if isempty(task) || task.IsStopped || ~isvalid(app)
                return
            end
            if isempty(task.ProgressTrack) || ~isvalid(task.ProgressTrack)
                return
            end

            if isempty(totalBytes) || totalBytes <= 0
                fraction = 0;
                task.BytesLabel.Text = F5BrowserTestApp.formatBytes(receivedBytes);
            else
                fraction = min(receivedBytes/totalBytes, 1);
                task.BytesLabel.Text = sprintf('%s / %s', ...
                                               F5BrowserTestApp.formatBytes(receivedBytes), ...
                                               F5BrowserTestApp.formatBytes(totalBytes));
            end

            trackSize = task.ProgressTrack.InnerPosition;
            task.ProgressFill.Position = [0, 0, fraction*trackSize(3), trackSize(4)];

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
                task.StatusLabel.Text = sprintf('Pausado - %s', task.FileName);
            else
                resume(task.Downloader)
                task.PauseButton.Text = 'Pausar';
                task.StatusLabel.Text = sprintf('Baixando %s', task.FileName);
            end
            app.DownloadTasks{taskID} = task;
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
            task.Dialog = [];
            task.StatusLabel = [];
            task.BytesLabel = [];
            task.ProgressTrack = [];
            task.ProgressFill = [];
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

            app.DownloadDialog = uifigure('Name', 'Downloads', ...
                                          'Position', [430, 320, 560, 200], ...
                                          'Resize', 'on', ...
                                          'CloseRequestFcn', @(src, ~) app.stopAllDownloads(src));
            app.DownloadStack = uigridlayout(app.DownloadDialog, [1, 1]);
            app.DownloadStack.Padding = [8, 8, 8, 8];
            app.DownloadStack.RowSpacing = 8;
            app.DownloadStack.ColumnWidth = {'1x'};
            app.DownloadStack.RowHeight = {150};
        end

        %-----------------------------------------------------------------%
        function closeDownloadContainer(app)
            if ~isempty(app.DownloadDialog) && isvalid(app.DownloadDialog)
                delete(app.DownloadDialog)
            end
            app.DownloadDialog = [];
            app.DownloadStack = [];
        end

        %-----------------------------------------------------------------%
        function refreshDownloadContainer(app)
            if isempty(app.DownloadDialog) || ~isvalid(app.DownloadDialog)
                app.DownloadDialog = [];
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
                app.DownloadStack = [];
                return
            end

            app.DownloadStack.RowHeight = repmat({150}, 1, numel(activeIDs));
            for row = 1:numel(activeIDs)
                task = app.DownloadTasks{activeIDs(row)};
                task.Dialog.Layout.Row = row;
                task.Dialog.Layout.Column = 1;
            end

            position = app.DownloadDialog.Position;
            position(3) = 560;
            position(4) = min(760, max(200, 16 + 158*numel(activeIDs)));
            app.DownloadDialog.Position = position;
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

            app.Session = ws.auth.F5Session(url);
            refreshStatus(app)

            progressDialog = uiprogressdlg(app.UIFigure, 'Indeterminate', 'on', ...
                                           'Message', 'Conclua a autenticação na janela do navegador (login + aprovação no Authenticator).');
            progressCleanup = onCleanup(@() close(progressDialog));

            login(app.Session)
        end

        %-----------------------------------------------------------------%
        function refreshStatus(app)
            isConnected = ~isempty(app.Session) && isvalid(app.Session) && app.Session.IsAuthenticated;

            if isConnected
                app.StatusLabel.Text = 'Conectado';
            else
                app.StatusLabel.Text = 'Desconectado';
            end
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
        function folderName = downloadFolder()
            if ispc
                homeFolder = getenv('USERPROFILE');
            else
                homeFolder = getenv('HOME');
            end

            % folderName = fullfile(homeFolder, 'Downloads');
            folderName = 'c:\GitHub\SupportPackages\tests\auth';
            if ~isfolder(folderName)
                folderName = homeFolder;
            end
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
            if nargin == 0 || isempty(value)
                text = 'unknown';
            else
                text = sprintf('%.0f', value);
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
