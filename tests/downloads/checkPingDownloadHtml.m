function uiFigure = checkPingDownloadHtml
% CHECKPINGDOWNLOADHTML Open the isolated ping download-avatar UI harness.

mFilePath = fileparts(mfilename('fullpath'));
projectFolder = fileparts(fileparts(mFilePath));
downloadHtmlPath = fullfile(projectFolder, 'src', 'General', '+ui', 'html', 'pingDownloadAvatar.html');

currentDownloadCount = 3;
currentProgress = 0;
currentRate = 1e6;
statusResetTimer = [];

uiFigure = uifigure('Name', 'Teste do pingDownloadAvatar.html', ...
                    'Position', [100, 100, 560, 340]);
uiFigure.CloseRequestFcn = @closeFigure;
mainLayout = uigridlayout(uiFigure, [5, 2]);
mainLayout.Padding = [12, 12, 12, 12];
mainLayout.RowSpacing = 12;
mainLayout.ColumnSpacing = 12;
mainLayout.RowHeight = {32, 64, 64, 64, 28};
mainLayout.ColumnWidth = {'1x', 112};

titleLabel = uilabel(mainLayout, 'Text', 'Ping download avatar', ...
                     'FontWeight', 'bold');
titleLabel.Layout.Row = 1;
titleLabel.Layout.Column = 1;

downloadHTML = uihtml(mainLayout);
downloadHTML.HTMLEventReceivedFcn = @downloadEventReceived;
downloadHTML.HTMLSource = downloadHtmlPath;
downloadHTML.Layout.Row = 1;
downloadHTML.Layout.Column = 2;

countSlider = uislider(mainLayout, ...
                       'Limits', [0, 23], ...
                       'MajorTicks', [0, 1, 12, 23], ...
                       'MajorTickLabels', {'0', '1', '12', '23'}, ...
                       'Value', currentDownloadCount, ...
                       'ValueChangedFcn', @countChanged);
countSlider.Layout.Row = 2;
countSlider.Layout.Column = 1;
countLabel = uilabel(mainLayout, 'HorizontalAlignment', 'right');
countLabel.Layout.Row = 2;
countLabel.Layout.Column = 2;

progressSlider = uislider(mainLayout, ...
                          'Limits', [0, 100], ...
                          'MajorTicks', [0, 25, 50, 75, 100], ...
                          'MajorTickLabels', {'0%', '25%', '50%', '75%', '100%'}, ...
                          'Value', currentProgress, ...
                          'ValueChangedFcn', @progressChanged);
progressSlider.Layout.Row = 3;
progressSlider.Layout.Column = 1;
progressLabel = uilabel(mainLayout, 'HorizontalAlignment', 'right');
progressLabel.Layout.Row = 3;
progressLabel.Layout.Column = 2;

rateSlider = uislider(mainLayout, ...
                      'Limits', [0, 25e6], ...
                      'MajorTicks', [0, 1e6, 10e6, 20e6, 21e6, 25e6], ...
                      'MajorTickLabels', {'0', '1M', '10M', '20M', '21M', '25M'}, ...
                      'Value', currentRate, ...
                      'ValueChangedFcn', @rateChanged);
rateSlider.Layout.Row = 4;
rateSlider.Layout.Column = 1;
rateLabel = uilabel(mainLayout, 'HorizontalAlignment', 'right');
rateLabel.Layout.Row = 4;
rateLabel.Layout.Column = 2;

statusLabel = uilabel(mainLayout, 'Text', 'Aguardando o HTML.', ...
                      'HorizontalAlignment', 'center');
statusLabel.Layout.Row = 5;
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

    function sendDownloads()
        downloadTemplate = struct('id', 0, ...
                                  'rate', currentRate, ...
                                  'progress', currentProgress);
        downloads = repmat(downloadTemplate, 1, currentDownloadCount);
        for downloadIndex = 1:currentDownloadCount
            downloads(downloadIndex).id = downloadIndex;
        end
        if ~isempty(downloadHTML) && isvalid(downloadHTML)
            downloadHTML.Data = downloads;
        end
        countLabel.Text = sprintf('Downloads: %d', currentDownloadCount);
        progressLabel.Text = sprintf('Progresso: %.1f%%', currentProgress);
        rateLabel.Text = sprintf('Rate: %.3g', currentRate);
    end

    function downloadEventReceived(~, event)
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

        if eventName == "downloadAvatarReady"
            statusLabel.Text = 'HTML pronto.';
        elseif eventName == "downloadAvatarClick"
            statusLabel.Text = 'Clique recebido pelo MATLAB.';
            restartStatusResetTimer()
        elseif eventName == "pingDownloadAvatarError"
            message = 'Dados de download inválidos.';
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