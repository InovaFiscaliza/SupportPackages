function report = checkDownloadPanelPausedAvatarRate
% CHECKDOWNLOADPANELPAUSEDAVATARRATE Verify paused tasks reach the avatar at rate zero.

mFilePath = fileparts(mfilename('fullpath'));
projectFolder = fileparts(fileparts(mFilePath));
addpath(fullfile(projectFolder, 'src', 'General'))
addpath(mFilePath)

tempPath = tempname;
targetPath = tempname;
mkdir(tempPath)
mkdir(targetPath)
autoCompleteKey = 'DownloadManagerFakeDownloaderAutoComplete';
hadAutoCompleteValue = isappdata(0, autoCompleteKey);
if hadAutoCompleteValue
    originalAutoCompleteValue = getappdata(0, autoCompleteKey);
else
    originalAutoCompleteValue = [];
end
setappdata(0, autoCompleteKey, false)

uiFigure = uifigure('Visible', 'off');
layout = uigridlayout(uiFigure, [1, 1]);
panel = ui.DownloadPanel(layout, ...
    'DownloaderFactory', @createDownloader, ...
    'executionMode', 'webApp', ...
    'tempPath', tempPath, ...
    'targetPath', targetPath);
cleanup = onCleanup(@() cleanUpPausedAvatarTest(panel, uiFigure, ...
    tempPath, targetPath, autoCompleteKey, hadAutoCompleteValue, ...
    originalAutoCompleteValue)); %#ok<NASGU>
drawnow

taskID = panel.addDownload('https://example.test/download/paused.bin');
activeSnapshot = panel.Manager.getSnapshot(taskID);
assert(strcmp(activeSnapshot.LifecycleState, 'active'))
panel.Manager.pause(taskID)
pausedSnapshot = panel.Manager.getSnapshot(taskID);
assert(strcmp(pausedSnapshot.LifecycleState, 'paused'))
assert(isnan(pausedSnapshot.TransferRate))

partialPath = fullfile(tempPath, 'seed_interrupted.bin.part');
fileID = fopen(partialPath, 'wb');
assert(fileID ~= -1)
fwrite(fileID, uint8([1, 2, 3, 4, 5]))
fclose(fileID)
pendingTaskID = panel.addDownload( ...
    'https://example.test/download/interrupted.bin');
pendingSnapshot = panel.Manager.getSnapshot(pendingTaskID);
assert(strcmp(pendingSnapshot.LifecycleState, 'awaitingConflictDecision'))
assert(strcmp(pendingSnapshot.ConflictType, 'partial'))

promotedTaskID = panel.addDownload('https://example.test/download/promoted.bin', ...
                                   'DisplayMode', 'silent');
otherTaskID = panel.addDownload('https://example.test/download/other.bin');
promotedSnapshot = panel.Manager.getSnapshot(promotedTaskID);
duplicateTaskID = panel.addDownload('https://example.test/download/promoted.bin');
assert(duplicateTaskID == promotedTaskID)
duplicateSnapshot = panel.Manager.getSnapshot(promotedTaskID);
assert(strcmp(duplicateSnapshot.DisplayMode, 'normal'))
assert(isequal(duplicateSnapshot.AttemptedTimestamps, ...
               promotedSnapshot.AttemptedTimestamps))
drawnow
promotedLabels = findall(uiFigure, 'Type', 'uilabel', 'Text', 'promoted.bin');
assert(numel(promotedLabels) == 1)
promotedRow = promotedLabels(1).Parent.Parent;
assert(promotedRow.Layout.Row == 1)
downloadContainers = findall(uiFigure, 'Type', 'uipanel', 'BorderType', 'line');
assert(numel(downloadContainers) == 1)
assert(strcmp(downloadContainers.Visible, 'on'))

avatarData = panel.AvatarHTML.Data;
for attempt = 1:20
    drawnow
    if isstruct(avatarData) && numel(avatarData) == 4 && ...
            all(ismember([taskID, pendingTaskID, promotedTaskID, otherTaskID], ...
                         [avatarData.id]))
        break
    end
    pause(0.05)
    avatarData = panel.AvatarHTML.Data;
end
assert(isstruct(avatarData) && numel(avatarData) == 4)
pausedAvatar = avatarData([avatarData.id] == taskID);
pendingAvatar = avatarData([avatarData.id] == pendingTaskID);
assert(numel(pausedAvatar) == 1 && pausedAvatar.rate == 0)
assert(numel(pendingAvatar) == 1 && pendingAvatar.rate == 0)

report = struct('TaskID', taskID, ...
                'PendingTaskID', pendingTaskID, ...
                'PromotedTaskID', promotedTaskID, ...
                'DuplicateTaskID', duplicateTaskID, ...
                'LifecycleState', pausedSnapshot.LifecycleState, ...
                'PausedAvatarRate', pausedAvatar.rate, ...
                'PendingAvatarRate', pendingAvatar.rate);

    function downloader = createDownloader(request)
        downloader = DownloadManagerFakeDownloader(request);
    end
end

function cleanUpPausedAvatarTest(panel, uiFigure, tempPath, targetPath, ...
        autoCompleteKey, hadAutoCompleteValue, originalAutoCompleteValue)
if ~isempty(panel) && isvalid(panel)
    delete(panel)
end
if ~isempty(uiFigure) && isvalid(uiFigure)
    delete(uiFigure)
end
if hadAutoCompleteValue
    setappdata(0, autoCompleteKey, originalAutoCompleteValue)
elseif isappdata(0, autoCompleteKey)
    rmappdata(0, autoCompleteKey)
end
if isfolder(tempPath)
    rmdir(tempPath, 's')
end
if isfolder(targetPath)
    rmdir(targetPath, 's')
end
end