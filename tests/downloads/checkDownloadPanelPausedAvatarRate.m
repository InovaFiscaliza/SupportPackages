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

avatarData = panel.AvatarHTML.Data;
for attempt = 1:20
    drawnow
    if isstruct(avatarData) && numel(avatarData) == 1 && ...
            isfield(avatarData, 'id') && avatarData.id == taskID
        break
    end
    pause(0.05)
    avatarData = panel.AvatarHTML.Data;
end
assert(isstruct(avatarData) && numel(avatarData) == 1)
assert(avatarData.id == taskID)
assert(avatarData.rate == 0)

report = struct('TaskID', taskID, ...
                'LifecycleState', pausedSnapshot.LifecycleState, ...
                'AvatarRate', avatarData.rate);

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