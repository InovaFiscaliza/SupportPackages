function uiFigure = checkTransferPanel
% CHECKTRANSFERPANEL Open the sample-link UI harness for ui.TransferPanel.
%
% The harness presents four clickable sample links in the first column, the
% ping download avatar in the second column, an execution log in row five, and
% a trash icon for deleting the local temp and target folders. Each sample
% uses TransferPanelFakeTransfer with a different size and transfer speed.
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
existingLocalPath = fullfile(targetPath, 'sample-existing.bin');
if ~isfile(existingLocalPath)
    writeHarnessFile(existingLocalPath, uint8([1, 2, 3, 4]))
end

sampleNames = {'sample1.bin', 'sample2.bin', 'sample3.bin', 'sample4.bin', ...
               'sample-failed.bin', 'sample-existing.bin', ...
               'sample-partial.bin', 'sample-cancel.bin'};
sampleLabels = sampleNames;
sampleLabels{4} = 'sample4.bin [silent]';
sampleLabels{5} = 'sample-failed.bin [failure]';
sampleLabels{6} = 'sample-existing.bin [keep/restart]';
sampleLabels{7} = 'sample-partial.bin [continue/restart]';
sampleLabels{8} = 'sample-cancel.bin [cancel]';
executionLog = {'Ready. Click a sample link to start a download.'};
seedPanelHistory(tempPath, targetPath)

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

startupHistory = panel.Manager.getHistory();
interruptedURL = 'https://example.test/history-interrupted.bin';
interruptedLocalPath = fullfile(targetPath, 'history-interrupted.bin');
interruptedRows = find(strcmp({startupHistory.Direction}, 'download') & ...
              strcmp({startupHistory.URL}, interruptedURL) & ...
              strcmp({startupHistory.LocalPath}, interruptedLocalPath) & ...
                       strcmp({startupHistory.LifecycleState}, ...
                              'awaitingConflictDecision'));
assert(numel(interruptedRows) == 1)
assert(isfile(startupHistory(interruptedRows(end)).TemporaryPath))
assert(startupHistory(interruptedRows(end)).TransferredBytes == 5)
interruptedAttempts = find(strcmp({startupHistory.Direction}, 'download') & ...
                            strcmp({startupHistory.URL}, interruptedURL) & ...
                            strcmp({startupHistory.LocalPath}, interruptedLocalPath));
assert(numel(interruptedAttempts) >= 2)
partialConflictLabels = findall(uiFigure, 'Type', 'uilabel', ...
                                'Text', 'Partial download found for history-interrupted.bin');
assert(numel(partialConflictLabels) == 1)

trashImage = uiimage(mainLayout, ...
                     'ImageSource', fullfile(projectFolder, 'src', 'General', 'icons', 'transfer-trash.svg'), ...
                     'ImageClickedFcn', @clearDownloadFolders);
trashImage.Layout.Row = numel(sampleNames) + 1;
trashImage.Layout.Column = 2;

panel.CompletedFcn = @completed;
panel.ErrorFcn = @failed;

    function downloader = createDownloader(request)
        % CREATEDOWNLOADER Build the deterministic sample downloader.
        if strcmp(request.FileName, 'sample-failed.bin')
            request.SimulateFailure = true;
        end
        downloader = TransferPanelFakeTransfer(request);
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
            if sampleIndex == 7
                writeHarnessFile(fullfile(tempPath, ...
                                          'seed_sample-partial.bin.part'), uint8([1, 2, 3, 4]));
            end
            panel.addDownload(sampleURL, 'DisplayMode', displayMode);
            appendLog(sprintf('Started %s.', sampleLabel));
        catch exception
            appendLog(sprintf('Failed to start %s: %s', sampleNames{sampleIndex}, exception.message));
        end
    end

    function completed(taskID, info, ~)
        % COMPLETED Record a completed simulated download.
        appendLog(sprintf('Download %d completed: %s.', taskID, info.LocalPath));
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
        error('checkTransferPanel:folderUnavailable', '%s', message)
    end
end
end

function seedPanelHistory(tempPath, targetPath)
historyPath = fullfile(tempPath, 'transfer-history.json');
store = datatransfer.TransferHistoryStore(historyPath);
nowText = char(datetime('now', 'TimeZone', 'UTC', ...
                        'Format', "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
existingLocalPath = fullfile(targetPath, 'sample-existing.bin');
if ~isfile(existingLocalPath)
    writeHarnessFile(existingLocalPath, uint8([1, 2, 3, 4]))
end
if ~isempty(store.getEntries())
    entries = store.getEntries();
    interruptedPath = fullfile(targetPath, 'history-interrupted.bin');
    interruptedEntryIndices = find(strcmp({entries.Direction}, 'download') & ...
                                   strcmp({entries.URL}, ...
                                          'https://example.test/history-interrupted.bin') & ...
                                   strcmp({entries.LocalPath}, interruptedPath));
    if isempty(interruptedEntryIndices)
        interruptedEntry = historyEntry('harness-interrupted', ...
                                        'history-interrupted.bin', ...
                                        interruptedPath, tempPath, ...
                                        'interrupted', 5, false, {}, nowText);
        writeHarnessFile(interruptedEntry.TemporaryPath, uint8([1, 2, 3, 4, 5]))
        store.upsert(interruptedEntry)
    else
        interruptedEntry = entries(interruptedEntryIndices(end));
        if ~isfile(interruptedEntry.TemporaryPath)
            writeHarnessFile(interruptedEntry.TemporaryPath, uint8([1, 2, 3, 4, 5]))
        end
    end
    return
end

completedPath = fullfile(targetPath, 'history-completed.bin');
writeHarnessFile(completedPath, uint8(zeros(1, 128, 'uint8')))
entries = [historyEntry('harness-completed', 'history-completed.bin', ...
                        completedPath, tempPath, 'completed', 128, true, {}, nowText), ...
           historyEntry('harness-failed', 'history-failed.bin', ...
                        fullfile(targetPath, 'history-failed.bin'), tempPath, ...
                        'failed', 64, false, {'Simulated test failure'}, nowText), ...
           historyEntry('harness-unavailable', 'history-unavailable.bin', ...
                        fullfile(targetPath, 'history-unavailable.bin'), tempPath, ...
                        'completed', 0, false, {}, nowText)];
olderInterruptedEntry = historyEntry('harness-interrupted-old', ...
                                     'history-interrupted.bin', ...
                                     fullfile(targetPath, 'history-interrupted.bin'), ...
                                     tempPath, 'interrupted', 3, false, {}, nowText);
latestInterruptedEntry = historyEntry('harness-interrupted', ...
                                      'history-interrupted.bin', ...
                                      fullfile(targetPath, 'history-interrupted.bin'), ...
                                      tempPath, 'interrupted', 5, false, {}, nowText);
writeHarnessFile(olderInterruptedEntry.TemporaryPath, uint8([1, 2, 3]))
writeHarnessFile(latestInterruptedEntry.TemporaryPath, uint8([1, 2, 3, 4, 5]))
entries = [entries, olderInterruptedEntry, latestInterruptedEntry];
for entryIndex = 1:numel(entries)
    store.upsert(entries(entryIndex))
end
end

function entry = historyEntry(entryID, logicalFileID, localPath, tempPath, ...
                              lifecycleState, transferredBytes, isAvailable, ...
                              errorMessages, timestamp)
taskID = regexprep(entryID, '[^a-zA-Z0-9]', '');
taskID = taskID(max(1, numel(taskID) - 7):end);
localBytes = [];
localModifiedAt = '';
if isAvailable
    localBytes = transferredBytes;
    localModifiedAt = timestamp;
end
entry = struct('EntryID', entryID, ...
                'Direction', 'download', ...
                'LogicalFileID', logicalFileID, ...
                'TaskID', taskID, ...
                'URL', ['https://example.test/', logicalFileID], ...
                'LocalPath', localPath, ...
                'TemporaryPath', fullfile(tempPath, [taskID, '_', logicalFileID, '.part']), ...
                'ChunkPath', fullfile(tempPath, [taskID, '_', logicalFileID, '.part.chunk']), ...
                'BackupPath', '', ...
                'TempFolder', tempPath, ...
                'StartedAt', timestamp, ...
                'CompletedAt', timestamp, ...
                'UpdatedAt', timestamp, ...
                'LifecycleState', lifecycleState, ...
                'TransferredBytes', transferredBytes, ...
                'MeasuredSpeed', [], ...
                'RateSource', 'none', ...
                'ErrorMessages', {errorMessages}, ...
                'AttemptedTimestamps', {{timestamp}}, ...
                'isAvailable', isAvailable, ...
                'Protocol', '', ...
                'UploadURL', '', ...
                'UploadOffset', 0, ...
                'LocalBytes', localBytes, ...
                'LocalModifiedAt', localModifiedAt, ...
                'Response', []);
end

function writeHarnessFile(filePath, bytes)
folderPath = fileparts(filePath);
if ~isfolder(folderPath)
    mkdir(folderPath)
end
fileID = fopen(filePath, 'wb');
assert(fileID ~= -1)
cleanup = onCleanup(@() fclose(fileID)); %#ok<NASGU>
fwrite(fileID, bytes, 'uint8');
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
