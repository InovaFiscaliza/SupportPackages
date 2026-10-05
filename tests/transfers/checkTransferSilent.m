function report = checkTransferSilent
% CHECKTRANSFERSILENT Validate silent task lifecycle and presentation policy.

mFilePath = fileparts(mfilename('fullpath'));
projectFolder = fileparts(fileparts(mFilePath));
addpath(fullfile(projectFolder, 'src', 'General'))
addpath(mFilePath)

tempPath = tempname;
targetPath = tempname;
blockedTarget = fullfile(tempPath, 'blocked-target');
mkdir(tempPath)
mkdir(targetPath)
writeFile(blockedTarget, uint8(1));
cleanup = onCleanup(@() cleanUp(tempPath, targetPath)); %#ok<NASGU>

setappdata(0, 'checkTransferSilent_snapshotCount', 0)
setappdata(0, 'checkTransferSilent_completedCount', 0)
setappdata(0, 'checkTransferSilent_errorCount', 0)
manager = datatransfer.TransferManager(...
    'TransferFactory', @createManagerDownloader, ...
    'HistoryFile', fullfile(tempPath, 'manager-history.json'), ...
    'TempFolder', tempPath);
manager.SnapshotFcn = @recordSnapshot;
manager.CompletedFcn = @recordCompleted;
manager.ErrorFcn = @recordError;

silentRequest = requestFor('manager-silent.bin', targetPath, tempPath);
silentRequest.DisplayMode = 'silent';
silentTaskID = manager.addTransfer(silentRequest);
assert(getappdata(0, 'checkTransferSilent_snapshotCount') == 0)
assert(getappdata(0, 'checkTransferSilent_completedCount') == 1)
assert(isfile(fullfile(targetPath, 'manager-silent.bin')))
assert(isempty(manager.getSnapshot(silentTaskID)))

errorRequest = requestFor('manager-error.bin', blockedTarget, tempPath);
errorRequest.DisplayMode = 'silent';
errorTaskID = manager.addTransfer(errorRequest);
assert(getappdata(0, 'checkTransferSilent_snapshotCount') == 0)
assert(getappdata(0, 'checkTransferSilent_errorCount') == 1)
assert(isempty(manager.getSnapshot(errorTaskID)))
history = manager.getHistory();
assert(strcmp(history(end).LifecycleState, 'failed'))
assert(~isempty(history(end).ErrorMessages))

normalRequest = requestFor('manager-normal.bin', targetPath, tempPath);
normalTaskID = manager.addTransfer(normalRequest);
assert(getappdata(0, 'checkTransferSilent_snapshotCount') > 0)
assert(isempty(manager.getSnapshot(normalTaskID)))

includedManager = datatransfer.TransferManager(...
    'TransferFactory', @createManagerDownloader, ...
    'HistoryFile', fullfile(tempPath, 'included-history.json'), ...
    'TempFolder', tempPath, ...
    'IncludeSilentTasks', true);
includedManager.SnapshotFcn = @recordSnapshot;
setappdata(0, 'TransferManagerFakeTransferAutoComplete', false)
includedRequest = requestFor('manager-included.bin', targetPath, tempPath);
includedRequest.DisplayMode = 'silent';
includedTaskID = includedManager.addTransfer(includedRequest);
assert(getappdata(0, 'checkTransferSilent_snapshotCount') > 0)
includedManager.cancel(includedTaskID)
delete(includedManager)
rmappdata(0, 'TransferManagerFakeTransferAutoComplete')

uiFigure = uifigure('Visible', 'off');
layout = uigridlayout(uiFigure, [1, 1]);
panelCompletedCount = 0;
panelErrorCount = 0;
panel = ui.TransferPanel(layout, ...
    'TransferFactory', @createPanelDownloader, ...
    'executionMode', 'webApp', ...
    'tempPath', tempPath, ...
    'targetPath', targetPath);
panel.CompletedFcn = @panelCompleted;
panel.ErrorFcn = @panelError;

panelSilentTaskID = panel.addDownload('https://example.test/panel-silent.bin', ...
                                      'DisplayMode', 'silent');
assert(panelCompletedCount == 1)
assert(isempty(panel.Manager.getSnapshot(panelSilentTaskID)))
assert(isempty(findall(uiFigure, 'Type', 'uipanel', 'BorderType', 'line')))

panelErrorTaskID = panel.addDownload('https://example.test/panel-error.bin', ...
                                     'DisplayMode', 'silent');
assert(panelErrorCount == 1)
assert(isempty(panel.Manager.getSnapshot(panelErrorTaskID)))
assert(isempty(findall(uiFigure, 'Type', 'uipanel', 'BorderType', 'line')))

silentCompletedCount = getappdata(0, 'checkTransferSilent_completedCount');
silentErrorCount = getappdata(0, 'checkTransferSilent_errorCount');
delete(panel)
delete(uiFigure)
delete(manager)
rmappdata(0, 'checkTransferSilent_snapshotCount')
rmappdata(0, 'checkTransferSilent_completedCount')
rmappdata(0, 'checkTransferSilent_errorCount')

report = struct('SilentCompleted', silentCompletedCount, ...
                'SilentErrors', silentErrorCount, ...
                'PanelCompleted', panelCompletedCount, ...
                'PanelErrors', panelErrorCount);

    function downloader = createManagerDownloader(request)
        downloader = TransferManagerFakeTransfer(request);
    end

    function downloader = createPanelDownloader(request)
        if strcmp(request.FileName, 'panel-error.bin')
            request.LocalPath = fullfile(blockedTarget, request.FileName);
        end
        downloader = TransferManagerFakeTransfer(request);
    end

    function recordSnapshot(~)
        setappdata(0, 'checkTransferSilent_snapshotCount', ...
                   getappdata(0, 'checkTransferSilent_snapshotCount') + 1);
    end

    function recordCompleted(~, ~, ~)
        setappdata(0, 'checkTransferSilent_completedCount', ...
                   getappdata(0, 'checkTransferSilent_completedCount') + 1);
    end

    function recordError(~, ~, ~)
        setappdata(0, 'checkTransferSilent_errorCount', ...
                   getappdata(0, 'checkTransferSilent_errorCount') + 1);
    end

    function panelCompleted(~, ~, ~)
        panelCompletedCount = panelCompletedCount + 1;
    end

    function panelError(~, ~, ~)
        panelErrorCount = panelErrorCount + 1;
    end
end

function request = requestFor(fileName, targetFolder, tempFolder)
request = struct('Direction', 'download', ...
                 'URL', ['https://example.test/', fileName], ...
                 'TempFolder', tempFolder, ...
                 'LocalPath', fullfile(targetFolder, fileName), ...
                 'FileName', fileName);
end

function writeFile(filePath, bytes)
fileID = fopen(filePath, 'wb');
assert(fileID ~= -1)
cleanup = onCleanup(@() fclose(fileID)); %#ok<NASGU>
fwrite(fileID, bytes, 'uint8');
end

function cleanUp(varargin)
for folderIndex = 1:numel(varargin)
    if isfolder(varargin{folderIndex})
        rmdir(varargin{folderIndex}, 's')
    end
end
end