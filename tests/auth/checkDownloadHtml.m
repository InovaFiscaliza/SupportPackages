function uiFigure = checkDownloadHtml
% checkDownloadHtml Testa o componente downloadAvatar.html sem downloads reais.
%
% O slider usa percentuais de 0 a 100 e o componente recebe níveis de 0 a 10.
% O nível zero representa a fila ociosa; clicar no controle simula a abertura
% da janela de downloads. O botão de estado liga/desliga a animação de atividade
% sem alterar o percentual exibido.

mFilePath = fileparts(mfilename('fullpath'));
projectFolder = fileparts(fileparts(mFilePath));
downloadHtmlPath = fullfile(projectFolder, 'src', 'Anatel', '+ws', '+auth', 'downloadAvatar.html');

currentProgress = 0;
currentLevel = 0;
isDownloadRunning = false;
currentBallCount = 1;
currentSpeedRadiansPerSecond = 5.2;
blinkTimer = [];

uiFigure = uifigure('Name', 'Teste do downloadAvatar.html', ...
                    'Position', [100, 100, 520, 300]);
uiFigure.CloseRequestFcn = @closeFigure;

mainLayout = uigridlayout(uiFigure, [5, 2]);
mainLayout.Padding = [12, 12, 12, 12];
mainLayout.RowSpacing = 16;
mainLayout.ColumnSpacing = 12;
mainLayout.RowHeight = {60, 28, 60, 60, 28};
mainLayout.ColumnWidth = {'1x', 22};

progressSlider = uislider(mainLayout, ...
                          'Limits', [0, 100], ...
                          'MajorTicks', 0:10:100, ...
                          'MajorTickLabels', arrayfun(@(value) sprintf('%d%%', value), ...
                                                     0:10:100, 'UniformOutput', false), ...
                          'MinorTicks', [], ...
                          'Value', currentProgress, ...
                          'ValueChangedFcn', @progressChanged);
progressSlider.Layout.Row = 1;
progressSlider.Layout.Column = 1;

downloadHTML = uihtml(mainLayout);
downloadHTML.HTMLEventReceivedFcn = @downloadEventReceived;
downloadHTML.HTMLSource = downloadHtmlPath;
downloadHTML.Layout.Row = 1;
downloadHTML.Layout.Column = 2;

runningButton = uibutton(mainLayout, 'state', ...
                         'Text', 'iniciar download', ...
                         'Value', isDownloadRunning, ...
                         'ValueChangedFcn', @runningChanged);
runningButton.Layout.Row = 2;
runningButton.Layout.Column = 1;

ballCountSlider = uislider(mainLayout, ...
                           'Limits', [1, 10], ...
                           'MajorTicks', 1:10, ...
                           'MajorTickLabels', arrayfun(@num2str, 1:10, 'UniformOutput', false), ...
                           'MinorTicks', [], ...
                           'Value', currentBallCount, ...
                           'ValueChangedFcn', @ballCountChanged);
ballCountSlider.Layout.Row = 3;
ballCountSlider.Layout.Column = 1;

speedSlider = uislider(mainLayout, ...
                       'Limits', [0, 20], ...
                       'MajorTicks', [0, 5, 10, 15, 20], ...
                       'MajorTickLabels', {'0', '5', '10', '15', '20'}, ...
                       'MinorTicks', [], ...
                       'Value', currentSpeedRadiansPerSecond, ...
                       'ValueChangedFcn', @speedChanged);
speedSlider.Layout.Row = 4;
speedSlider.Layout.Column = 1;

clickIndicator = uilabel(mainLayout, ...
                         'Text', 'Download Click', ...
                         'HorizontalAlignment', 'center');
clickIndicator.Layout.Row = 5;
clickIndicator.Layout.Column = 1;
indicatorBackgroundColor = clickIndicator.BackgroundColor;

sendProgress()

    function progressChanged(source, ~)
        currentProgress = round(source.Value);
        source.Value = currentProgress;
        sendProgress()
    end

    function runningChanged(source, ~)
        isDownloadRunning = source.Value;
        if isDownloadRunning
            source.Text = 'parar download';
        else
            source.Text = 'iniciar download';
        end
        sendProgress()
    end

    function ballCountChanged(source, ~)
        currentBallCount = round(source.Value);
        source.Value = currentBallCount;
        sendProgress()
    end

    function speedChanged(source, ~)
        currentSpeedRadiansPerSecond = source.Value;
        sendProgress()
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

        if eventName == "downloadAvatarClick"
            handleDownloadClick()
            return
        end
        if ~isstruct(payload) || ~isfield(payload, 'type')
            return
        end

        switch string(payload.type)
            case "ready"
                sendProgress()
            case "click"
                handleDownloadClick()
        end
    end

    function handleDownloadClick()
        blinkIndicator()
    end

    function blinkIndicator()
        if ~isempty(blinkTimer) && isvalid(blinkTimer)
            stop(blinkTimer)
            delete(blinkTimer)
        end

        clickIndicator.BackgroundColor = [0, 1, 0];
        drawnow limitrate
        blinkTimer = timer('ExecutionMode', 'singleShot', ...
                           'StartDelay', 1, ...
                           'TimerFcn', @restoreIndicator);
        start(blinkTimer)
    end

    function restoreIndicator(~, ~)
        if ~isempty(clickIndicator) && isvalid(clickIndicator)
            clickIndicator.BackgroundColor = indicatorBackgroundColor;
        end
        if ~isempty(blinkTimer) && isvalid(blinkTimer)
            delete(blinkTimer)
            blinkTimer = [];
        end
    end

    function sendProgress()
        currentLevel = progressToLevel(currentProgress);
        if ~isempty(downloadHTML) && isvalid(downloadHTML)
            downloadHTML.Data = struct('level', currentLevel, ...
                                       'inProgress', isDownloadRunning, ...
                                       'ballCount', currentBallCount, ...
                                       'speedRadiansPerSecond', currentSpeedRadiansPerSecond);
        end
    end

    function level = progressToLevel(progress)
        if progress <= 0
            level = 0;
        elseif progress >= 90
            level = 10;
        else
            level = ceil(progress / 10);
        end
    end

    function closeFigure(source, ~)
        if ~isempty(blinkTimer) && isvalid(blinkTimer)
            stop(blinkTimer)
            delete(blinkTimer)
            blinkTimer = [];
        end
        if ~isempty(source) && isvalid(source)
            delete(source)
        end
    end
end