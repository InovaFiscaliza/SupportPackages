function uiFigure = checkDownloadPanel
% CHECKDOWNLOADPANEL Open the sample-link UI harness for ui.DownloadPanel.
%
% The harness presents four clickable sample links in the first column, the
% ping download avatar in the second column, an execution log in row five, and
% a trash icon for deleting the local temp and target folders. Each sample
% uses DownloadPanelFakeDownloader with a different size and transfer speed.
%
% The returned figure remains open until the user closes it.

mFilePath = fileparts(mfilename('fullpath'));
projectFolder = fileparts(fileparts(mFilePath));
addpath(fullfile(projectFolder, 'src', 'General'))
addpath(mFilePath)

% Create isolated runtime folders below tests/downloads when the harness starts.
tempPath = fullfile(mFilePath, 'temp');
targetPath = fullfile(mFilePath, 'target');
ensureFolder(tempPath)
ensureFolder(targetPath)

sampleNames = {'sample1.bin', 'sample2.bin', 'sample3.bin', 'sample4.bin'};
sampleLabels = sampleNames;
sampleLabels{4} = 'sample4.bin [silent]';
executionLog = {'Ready. Click a sample link to start a download.'};

uiFigure = uifigure('Name', 'Teste do ui.DownloadPanel', ...
                    'Position', [100, 100, 720, 420]);
uiFigure.CloseRequestFcn = @closeFigure;
mainLayout = uigridlayout(uiFigure, [5, 2]);
mainLayout.Padding = [16, 16, 16, 16];
mainLayout.RowSpacing = 8;
mainLayout.ColumnSpacing = 16;
mainLayout.RowHeight = {'1x', '1x', '1x', '1x', '2x'};
mainLayout.ColumnWidth = {'1x', 24};

for sampleIndex = 1:numel(sampleNames)
    linkHTML = uihtml(mainLayout, ...
                      'HTMLSource', sampleLinkHTML(sampleLabels{sampleIndex}, sampleIndex));
    linkHTML.HTMLEventReceivedFcn = @(~, ~) startSample(sampleIndex);
    linkHTML.Layout.Row = sampleIndex;
    linkHTML.Layout.Column = 1;
end

statusLabel = uilabel(mainLayout, ...
                      'Text', strjoin(executionLog, newline), ...
                      'VerticalAlignment', 'top', ...
                      'WordWrap', 'on', ...
                      'BackgroundColor', uiFigure.Color);
statusLabel.Layout.Row = 5;
statusLabel.Layout.Column = 1;

panel = ui.DownloadPanel(mainLayout, ...
                         'DownloaderFactory', @createDownloader, ...
                         'executionMode', 'webApp', ...
                         'tempPath', tempPath, ...
                         'targetPath', targetPath, ...
                         'CollisionPolicy', 'askInRow');
panel.AvatarHTML.Layout.Row = 1;
panel.AvatarHTML.Layout.Column = 2;
drawnow
avatarPixelPosition = getpixelposition(panel.AvatarHTML, true);
if any(avatarPixelPosition(3:4) < 24)
    error('checkDownloadPanel:avatarTooSmall', ...
          'The ping download avatar needs a MATLAB host of at least 24-by-24 pixels.')
end
if ~endsWith(char(panel.AvatarHTML.HTMLSource), 'pingDownloadAvatar.html')
    error('checkDownloadPanel:unexpectedAvatarSource', ...
          'ui.DownloadPanel must use pingDownloadAvatar.html.')
end

trashImage = uiimage(mainLayout, ...
                     'ImageSource', fullfile(projectFolder, 'src', 'General', 'icons', 'download-trash.svg'), ...
                     'ImageClickedFcn', @clearDownloadFolders);
trashImage.Layout.Row = 5;
trashImage.Layout.Column = 2;

panel.CompletedFcn = @completed;
panel.ErrorFcn = @failed;

    function downloader = createDownloader(request)
        % CREATEDOWNLOADER Build the deterministic sample downloader.
        downloader = DownloadPanelFakeDownloader(request);
    end

    function startSample(sampleIndex)
        % STARTSAMPLE Start the sample selected by its link.
        try
            ensureFolder(tempPath)
            ensureFolder(targetPath)
            sampleName = sampleNames{sampleIndex};
            sampleLabel = sampleLabels{sampleIndex};
            sampleURL = ['https://example.test/download/', sampleName];
            displayMode = 'normal';
            if sampleIndex == 4
                displayMode = 'silent';
            end
            panel.addDownload(sampleURL, 'DisplayMode', displayMode);
            appendLog(sprintf('Started %s.', sampleLabel));
        catch exception
            appendLog(sprintf('Failed to start %s: %s', sampleNames{sampleIndex}, exception.message));
        end
    end

    function completed(taskID, info, ~)
        % COMPLETED Record a completed simulated download.
        appendLog(sprintf('Download %d completed: %s.', taskID, info.FinalPath));
    end

    function failed(taskID, exception, ~)
        % FAILED Record a failed simulated download.
        appendLog(sprintf('Download %d failed: %s.', taskID, exception.message));
    end

    function appendLog(message)
        % APPENDLOG Add a line to the row-five execution output.
        executionLog{end+1} = message; %#ok<AGROW>
        if ~isempty(statusLabel) && isvalid(statusLabel)
            statusLabel.Text = strjoin(executionLog, newline);
        end
    end

    function clearDownloadFolders(~, ~)
        % CLEARDOWNLOADFOLDERS Cancel downloads and delete both runtime folders.
        try
            panel.cancelAll()
            if isfolder(tempPath)
                rmdir(tempPath, 's')
            end
            if isfolder(targetPath)
                rmdir(targetPath, 's')
            end
            appendLog('Deleted temp and target folders.')
        catch exception
            appendLog(sprintf('Failed to delete download folders: %s', exception.message));
        end
    end

    function closeFigure(source, ~)
        % CLOSEFIGURE Release the panel and close the test figure.
        if ~isempty(panel) && isvalid(panel)
            delete(panel)
        end
        if ~isempty(source) && isvalid(source)
            delete(source)
        end
    end
end


function ensureFolder(folderPath)
% ENSUREFOLDER Create a runtime folder when it does not exist.
if ~isfolder(folderPath)
    [created, message] = mkdir(folderPath);
    if ~created && ~isfolder(folderPath)
        error('checkDownloadPanel:folderUnavailable', '%s', message)
    end
end
end


function html = sampleLinkHTML(sampleName, sampleIndex)
% SAMPLELINKHTML Build an underlined blue clickable sample link.
html = sprintf(['<html><head><style>', ...
                'html,body{width:100%%;height:100%%;margin:0;background:transparent;', ...
                'display:flex;align-items:center;}', ...
                'a{font-family:Arial,sans-serif;font-size:14px;color:#0072bd;', ...
                'text-decoration:underline;cursor:pointer;}', ...
                '</style></head><body>', ...
                '<a id="sample-link-%d" href="#">%s</a>', ...
                '<script>', ...
                '(function(){', ...
                'var matlabHtmlComponent=null;', ...
                'var link=document.getElementById("sample-link-%d");', ...
                'function notifyClick(event){', ...
                'event.preventDefault();', ...
                'var data={sample:%d};', ...
                'if(matlabHtmlComponent&&typeof matlabHtmlComponent.sendEventToMATLAB=== "function"){', ...
                'matlabHtmlComponent.sendEventToMATLAB("sampleDownloadClick",data);', ...
                '}else if(typeof sendEventToMATLAB=== "function"){', ...
                'sendEventToMATLAB("sampleDownloadClick",data);', ...
                '}', ...
                '}', ...
                'link.addEventListener("click",notifyClick);', ...
                'window.sampleLinkSetup=function(htmlComponent){matlabHtmlComponent=htmlComponent;};', ...
                '})();', ...
                'function setup(htmlComponent){window.sampleLinkSetup(htmlComponent);}', ...
                '</script></body></html>'], ...
               sampleIndex, sampleName, sampleIndex, sampleIndex);
end
