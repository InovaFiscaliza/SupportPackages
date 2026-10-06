function uiFigure = checkPingTransferHtml
% CHECKPINGTRANSFERHTML Open the isolated ping transfer-avatar UI harness.

mFilePath = fileparts(mfilename('fullpath'));
projectFolder = fileparts(fileparts(mFilePath));
downloadHtmlPath = fullfile(projectFolder, 'src', 'General', '+ui', 'html', 'pingTransferAvatar.html');

currentDownloadCount = 3;
currentProgress = 0;
currentRate = 1e6;
currentDirectionMode = 'Ambas';
statusResetTimer = [];

uiFigure = uifigure('Name', 'Teste do pingTransferAvatar.html', ...
                    'Position', [100, 100, 560, 380]);
uiFigure.CloseRequestFcn = @closeFigure;
mainLayout = uigridlayout(uiFigure, [6, 2]);
mainLayout.Padding = [12, 12, 12, 12];
mainLayout.RowSpacing = 12;
mainLayout.ColumnSpacing = 12;
mainLayout.RowHeight = {32, 32, 64, 64, 64, 28};
mainLayout.ColumnWidth = {'1x', 112};

titleLabel = uilabel(mainLayout, 'Text', 'Ping do avatar de transferências', ...
                     'FontWeight', 'bold');
titleLabel.Layout.Row = 1;
titleLabel.Layout.Column = 1;

downloadHTML = uihtml(mainLayout);
downloadHTML.HTMLEventReceivedFcn = @downloadEventReceived;
downloadHTML.HTMLSource = downloadHtmlPath;
downloadHTML.Layout.Row = 1;
downloadHTML.Layout.Column = 2;

directionDropdown = uidropdown(mainLayout, ...
                               'Items', {'Somente downloads', 'Somente uploads', 'Ambas'}, ...
                               'Value', currentDirectionMode, ...
                               'ValueChangedFcn', @directionChanged);
directionDropdown.Layout.Row = 2;
directionDropdown.Layout.Column = 1;
directionLabel = uilabel(mainLayout, 'Text', 'Direção', ...
                         'HorizontalAlignment', 'right');
directionLabel.Layout.Row = 2;
directionLabel.Layout.Column = 2;

countSlider = uislider(mainLayout, ...
                       'Limits', [0, 23], ...
                       'MajorTicks', [0, 1, 12, 23], ...
                       'MajorTickLabels', {'0', '1', '12', '23'}, ...
                       'Value', currentDownloadCount, ...
                       'ValueChangedFcn', @countChanged);
countSlider.Layout.Row = 3;
countSlider.Layout.Column = 1;
countLabel = uilabel(mainLayout, 'HorizontalAlignment', 'right');
countLabel.Layout.Row = 3;
countLabel.Layout.Column = 2;

progressSlider = uislider(mainLayout, ...
                          'Limits', [0, 100], ...
                          'MajorTicks', [0, 25, 50, 75, 100], ...
                          'MajorTickLabels', {'0%', '25%', '50%', '75%', '100%'}, ...
                          'Value', currentProgress, ...
                          'ValueChangedFcn', @progressChanged);
progressSlider.Layout.Row = 4;
progressSlider.Layout.Column = 1;
progressLabel = uilabel(mainLayout, 'HorizontalAlignment', 'right');
progressLabel.Layout.Row = 4;
progressLabel.Layout.Column = 2;

rateSlider = uislider(mainLayout, ...
                      'Limits', [0, 25e6], ...
                      'MajorTicks', [0, 1e6, 10e6, 20e6, 21e6, 25e6], ...
                      'MajorTickLabels', {'0', '1M', '10M', '20M', '21M', '25M'}, ...
                      'Value', currentRate, ...
                      'ValueChangedFcn', @rateChanged);
rateSlider.Layout.Row = 5;
rateSlider.Layout.Column = 1;
rateLabel = uilabel(mainLayout, 'HorizontalAlignment', 'right');
rateLabel.Layout.Row = 5;
rateLabel.Layout.Column = 2;

statusLabel = uilabel(mainLayout, 'Text', 'Aguardando o HTML.', ...
                      'HorizontalAlignment', 'center');
statusLabel.Layout.Row = 6;
statusLabel.Layout.Column = [1, 2];

sendDownloads()

    function countChanged(source, ~)
        currentDownloadCount = round(source.Value);
        source.Value = currentDownloadCount;
        sendDownloads()
    end

    function progressChanged(source, ~)
        currentProgress = source.Value;
        sendDownloads()
    end

    function rateChanged(source, ~)
        currentRate = source.Value;
        sendDownloads()
    end

    function directionChanged(source, ~)
        currentDirectionMode = source.Value;
        sendDownloads()
    end

    function sendDownloads()
        downloadTemplate = struct('id', 0, ...
                                  'rate', currentRate, ...
                                  'progress', currentProgress, ...
                                  'direction', 'download');
        downloads = repmat(downloadTemplate, 1, currentDownloadCount);
        for downloadIndex = 1:currentDownloadCount
            downloads(downloadIndex).id = downloadIndex;
            if strcmp(currentDirectionMode, 'Somente uploads') || ...
                    (strcmp(currentDirectionMode, 'Ambas') && mod(downloadIndex, 2) == 0)
                downloads(downloadIndex).direction = 'upload';
            end
        end
        if ~isempty(downloadHTML) && isvalid(downloadHTML)
            downloadHTML.Data = downloads;
        end
        countLabel.Text = sprintf('Transferências: %d', currentDownloadCount);
        progressLabel.Text = sprintf('Progresso: %.1f%%', currentProgress);
        rateLabel.Text = sprintf('Taxa: %.3g', currentRate);
    end

    function downloadEventReceived(~, event)
        eventName = string(event.HTMLEventName);
        payload = event.HTMLEventData;
        if ischar(payload) || (isstring(payload) && isscalar(payload))
            try
                payload = jsondecode(char(payload));
            catch
                payload = struct();
            end
        end

        if eventName == "transferAvatarReady"
            statusLabel.Text = 'HTML pronto.';
        elseif eventName == "transferAvatarClick"
            statusLabel.Text = 'Clique recebido pelo MATLAB.';
            restartStatusResetTimer()
        elseif eventName == "pingTransferAvatarError"
            message = 'Dados de transferência inválidos.';
            if isstruct(payload) && isfield(payload, 'message')
                message = char(payload.message);
            end
            statusLabel.Text = message;
        end
    end

    function restartStatusResetTimer()
        stopStatusResetTimer()
        statusResetTimer = timer('ExecutionMode', 'singleShot', ...
                                 'StartDelay', 1, ...
                                 'TimerFcn', @restoreReadyStatus);
        start(statusResetTimer)
    end

    function restoreReadyStatus(~, ~)
        if ~isempty(statusLabel) && isvalid(statusLabel)
            statusLabel.Text = 'HTML pronto.';
        end
        stopStatusResetTimer()
    end

    function stopStatusResetTimer()
        if ~isempty(statusResetTimer) && isvalid(statusResetTimer)
            stop(statusResetTimer)
            delete(statusResetTimer)
        end
        statusResetTimer = [];
    end

    function closeFigure(source, ~)
        stopStatusResetTimer()
        if ~isempty(source) && isvalid(source)
            delete(source)
        end
    end
end