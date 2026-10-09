function uiFigure = checkTransferPanel
% CHECKTRANSFERPANEL Open the sample-link UI harness for ui.TransferPanel.
%
% The harness presents four download links and two upload links in the first
% column, the ping transfer avatar in the second column, an execution log, and
% a trash icon for deleting the local temp and target folders. Transfers use
% TransferPanelFakeTransfer and do not perform network I/O.
%
% The returned figure remains open until the user closes it.

mFilePath = fileparts(mfilename('fullpath'));
projectFolder = fileparts(fileparts(mFilePath));
addpath(fullfile(projectFolder, 'src', 'General'))
addpath(mFilePath)

% Initialize the harness runtime folders.
tempPath = fullfile(mFilePath, 'temp');
targetPath = fullfile(mFilePath, 'target');
ensureFolder(tempPath)
ensureFolder(targetPath)
uploadSourcePath = fullfile(targetPath, 'sample-upload-source.bin');
ensureUploadSource(uploadSourcePath)

sampleNames = {'sample1.bin', 'sample2.bin', 'sample3.bin', 'sample4.bin', ...
               'sample-upload.bin', 'sample-upload-silent.bin'};
sampleLabels = sampleNames;
sampleLabels{4} = 'sample4.bin [silent]';
sampleLabels{5} = 'sample-upload.bin [upload]';
sampleLabels{6} = 'sample-upload-silent.bin [silent upload]';
executionLog = {'Ready. Click a sample link to start a transfer.'};

uiFigure = uifigure('Name', 'Teste do ui.TransferPanel', ...
                    'Position', [100, 100, 720, 560]);
uiFigure.CloseRequestFcn = @closeFigure;
mainLayout = uigridlayout(uiFigure, [numel(sampleNames) + 1, 2]);
mainLayout.Padding = [16, 16, 16, 16];
mainLayout.RowSpacing = 8;
mainLayout.ColumnSpacing = 16;
mainLayout.RowHeight = [repmat({'1x'}, 1, numel(sampleNames)), {'2x'}];
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
statusLabel.Layout.Row = numel(sampleNames) + 1;
statusLabel.Layout.Column = 1;

panel = ui.TransferPanel(mainLayout, ...
                         'TransferFactory', @createDownloader, ...
                         'executionMode', 'webApp', ...
                         'tempPath', tempPath, ...
                         'targetPath', targetPath, ...
                         'CollisionPolicy', 'askInRow');
panel.AvatarHTML.Layout.Row = 1;
panel.AvatarHTML.Layout.Column = 2;
drawnow

trashImage = uiimage(mainLayout, ...
                     'ImageSource', fullfile(projectFolder, 'src', 'General', 'icons', 'transfer-trash.svg'), ...
                     'ImageClickedFcn', @clearDownloadFolders);
trashImage.Layout.Row = numel(sampleNames) + 1;
trashImage.Layout.Column = 2;

panel.CompletedFcn = @completed;
panel.ErrorFcn = @failed;

    function downloader = createDownloader(request)
        % CREATEDOWNLOADER Build the deterministic sample downloader.
        downloader = TransferPanelFakeTransfer(request);
    end

    function startSample(sampleIndex)
        % STARTSAMPLE Start the sample selected by its link.
        try
            ensureFolder(tempPath)
            ensureFolder(targetPath)
            sampleName = sampleNames{sampleIndex};
            sampleLabel = sampleLabels{sampleIndex};
            if sampleIndex >= 5
                ensureUploadSource(uploadSourcePath)
                sampleURL = ['https://example.test/upload/', sampleName];
                displayMode = 'normal';
                if sampleIndex == numel(sampleNames)
                    displayMode = 'silent';
                end
                panel.addUpload(sampleURL, ...
                                'LocalPath', uploadSourcePath, ...
                                'FileName', sampleName, ...
                                'Protocol', 'raw', ...
                                'Method', 'PUT', ...
                                'DisplayMode', displayMode);
                transferKind = 'upload';
            else
                sampleURL = ['https://example.test/download/', sampleName];
                displayMode = 'normal';
                if sampleIndex == 4
                    displayMode = 'silent';
                end
                panel.addDownload(sampleURL, 'DisplayMode', displayMode);
                transferKind = 'download';
            end
            appendLog(sprintf('Started %s %s.', transferKind, sampleLabel));
        catch exception
            appendLog(sprintf('Failed to start %s: %s', sampleNames{sampleIndex}, exception.message));
        end
    end

    function completed(taskID, info, snapshot)
        % COMPLETED Record a completed simulated transfer.
        appendLog(sprintf('%s %d completed: %s.', ...
                          transferLabel(snapshot.Direction), taskID, info.LocalPath));
    end

    function failed(taskID, exception, snapshot)
        % FAILED Record a failed simulated transfer.
        appendLog(sprintf('%s %d failed: %s.', ...
                          transferLabel(snapshot.Direction), taskID, exception.message));
    end

    function appendLog(message)
        % APPENDLOG Add a line to the execution output.
        executionLog{end+1} = message;
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
        error('checkTransferPanel:folderUnavailable', '%s', message)
    end
end
end

function ensureUploadSource(filePath)
% ENSUREUPLOADSOURCE Create the deterministic upload source file when needed.
sourceBytes = 2 * 1024^2;
fileInfo = dir(filePath);
if isfile(filePath) && isscalar(fileInfo) && ...
        ~fileInfo.isdir && fileInfo.bytes == sourceBytes
    return
end

fileID = fopen(filePath, 'wb');
if fileID == -1
    error('checkTransferPanel:uploadSourceUnavailable', ...
          'Could not create the upload source file.')
end
cleanup = onCleanup(@() fclose(fileID));
bytesWritten = fwrite(fileID, zeros(1, sourceBytes, 'uint8'), 'uint8');
if bytesWritten ~= sourceBytes
    error('checkTransferPanel:uploadSourceWriteFailed', ...
          'Could not write the complete upload source file.')
end
end

function label = transferLabel(direction)
% TRANSFERLABEL Return a readable transfer direction for the execution log.
if strcmp(direction, 'upload')
    label = 'Upload';
else
    label = 'Download';
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
                'matlabHtmlComponent.sendEventToMATLAB("sampleTransferClick",data);', ...
                '}else if(typeof sendEventToMATLAB=== "function"){', ...
                'sendEventToMATLAB("sampleTransferClick",data);', ...
                '}', ...
                '}', ...
                'link.addEventListener("click",notifyClick);', ...
                'window.sampleLinkSetup=function(htmlComponent){matlabHtmlComponent=htmlComponent;};', ...
                '})();', ...
                'function setup(htmlComponent){window.sampleLinkSetup(htmlComponent);}', ...
                '</script></body></html>'], ...
               sampleIndex, sampleName, sampleIndex, sampleIndex);
end
