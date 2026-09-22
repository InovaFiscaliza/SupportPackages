function uiFigure = checkDownloadHtml
% CHECKDOWNLOADHTML Open the isolated download-avatar UI harness.
%
% This harness tests only the reusable downloadAvatar.html uihtml asset. It
% does not start downloads, authenticate, access the network, or instantiate
% ui.DownloadPanel. Sliders and a state button send representative visual
% state to the HTML component, while the callback indicator confirms that the
% avatar click event returns to MATLAB.
%
% The returned figure remains open until the user closes it.

mFilePath = fileparts(mfilename('fullpath'));
projectFolder = fileparts(fileparts(mFilePath));
downloadHtmlPath = fullfile(projectFolder, 'src', 'General', '+ui', 'html', 'downloadAvatar.html');

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
        % PROGRESSCHANGED Update the simulated visual progress level.
        currentProgress = round(source.Value);
        source.Value = currentProgress;
        sendProgress()
    end

    function runningChanged(source, ~)
        % RUNNINGCHANGED Toggle the simulated active-download animation.
        isDownloadRunning = source.Value;
        if isDownloadRunning
            source.Text = 'parar download';
        else
            source.Text = 'iniciar download';
        end
        sendProgress()
    end

    function ballCountChanged(source, ~)
        % BALLCOUNTCHANGED Update the number of simulated orbiting balls.
        currentBallCount = round(source.Value);
        source.Value = currentBallCount;
        sendProgress()
    end

    function speedChanged(source, ~)
        % SPEEDCHANGED Update the simulated orbit speed.
        currentSpeedRadiansPerSecond = source.Value;
        sendProgress()
    end

    function downloadEventReceived(~, event)
        % DOWNLOADEVENTRECEIVED Handle ready and click events from the asset.
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
        % HANDLEDOWNLOADCLICK Confirm that the avatar click reached MATLAB.
        blinkIndicator()
    end

    function blinkIndicator()
        % BLINKINDICATOR Highlight the click confirmation label briefly.
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
        % RESTOREINDICATOR Restore the click indicator background color.
        if ~isempty(clickIndicator) && isvalid(clickIndicator)
            clickIndicator.BackgroundColor = indicatorBackgroundColor;
        end
        if ~isempty(blinkTimer) && isvalid(blinkTimer)
            delete(blinkTimer)
            blinkTimer = [];
        end
    end

    function sendProgress()
        % SENDPROGRESS Send the current visual state to downloadAvatar.html.
        currentLevel = progressToLevel(currentProgress);
        if ~isempty(downloadHTML) && isvalid(downloadHTML)
            downloadHTML.Data = struct('level', currentLevel, ...
                                       'inProgress', isDownloadRunning, ...
                                       'ballCount', currentBallCount, ...
                                       'speedRadiansPerSecond', currentSpeedRadiansPerSecond);
        end
    end

    function level = progressToLevel(progress)
        % PROGRESSTOLEVEL Convert percentage progress to an avatar level.
        if progress <= 0
            level = 0;
        elseif progress >= 90
            level = 10;
        else
            level = ceil(progress / 10);
        end
    end

    function closeFigure(source, ~)
        % CLOSEFIGURE Stop the click timer and close the harness figure.
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
