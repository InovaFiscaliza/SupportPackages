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

            progressDialog = uiprogressdlg(app.UIFigure, 'Indeterminate', 'on', 'Message', sprintf('Baixando %s', fileName));
            progressCleanup = onCleanup(@() close(progressDialog));

            filePath = fullfile(folderName, fileName);
            logPath = [filePath, '.log'];
            F5BrowserTestApp.writeDownloadLog(logPath, sprintf('START\nURL: %s\nDestination: %s\nSession: %s\n', ...
                                                            url, filePath, app.sessionDebugText()));
            try
                info = app.Session.downloadToFile(url, filePath, true, ...
                                                  @(receivedBytes, totalBytes) F5BrowserTestApp.updateProgress(progressDialog, receivedBytes, totalBytes));
                F5BrowserTestApp.writeDownloadLog(logPath, sprintf('RESPONSE: HTTP %d %s\nContent-Length: %s\nBytes received: %d\nEND\n', ...
                                                                  info.StatusCode, info.StatusMessage, F5BrowserTestApp.formatBytes(info.ContentLength), info.BytesReceived));
            catch ME
                if isfile(filePath)
                    delete(filePath)
                end

                F5BrowserTestApp.writeDownloadLog(logPath, sprintf('ERROR\n%s\nEND\n', ...
                                                                   getReport(ME, 'extended', 'hyperlinks', 'off')));

                error('F5BrowserTestApp:downloadFailed', ...
                      '%s', F5BrowserTestApp.downloadErrorReport(ME, filePath, logPath))
            end

            render(app, sprintf('Arquivo salvo em:\n%s', filePath))
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
        function updateProgress(progressDialog, receivedBytes, totalBytes)
            % Sem Content-Length não há total conhecido: mantém a barra
            % indeterminada e informa apenas o recebido.

            if ~isvalid(progressDialog)
                return
            end

            if isempty(totalBytes) || totalBytes <= 0
                progressDialog.Message = sprintf('Baixando... %.1f MB', receivedBytes/2^20);
            else
                progressDialog.Indeterminate = 'off';
                progressDialog.Value   = min(receivedBytes/totalBytes, 1);
                progressDialog.Message = sprintf('%.1f de %.1f MB', receivedBytes/2^20, totalBytes/2^20);
            end

            drawnow limitrate
        end

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
