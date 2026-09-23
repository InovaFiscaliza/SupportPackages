function report = checkDownloadManager
% CHECKDOWNLOADMANAGER Validate manager lifecycle and target conflicts without UI.

mFilePath = fileparts(mfilename('fullpath'));
projectFolder = fileparts(fileparts(mFilePath));
addpath(fullfile(projectFolder, 'src', 'General'))
addpath(mFilePath)

tempPath = tempname;
targetPath = tempname;
mkdir(tempPath)
mkdir(targetPath)
cleanup = onCleanup(@() removeFolders(tempPath, targetPath)); %#ok<NASGU>

setappdata(0, 'checkDownloadManager_completed', struct('TaskID', [], 'FinalPath', ''))
setappdata(0, 'checkDownloadManager_failed', false)
manager = download.DownloadManager(...
    'DownloaderFactory', @createDownloader, ...
    'CollisionPolicy', 'askInRow');
manager.CompletedFcn = @completedDownload;
manager.ErrorFcn = @failedDownload;

request = struct('URL', 'https://example.test/download/sample.bin', ...
                 'TempFolder', tempPath, ...
                 'TargetFolder', targetPath, ...
                 'FileName', 'sample.bin');
taskID = manager.addDownload(request);
completed = getappdata(0, 'checkDownloadManager_completed');
assert(completed.TaskID == taskID)
assert(strcmp(completed.FinalPath, fullfile(targetPath, 'sample.bin')))
assert(isempty(manager.getSnapshot(taskID)))

existingPath = fullfile(targetPath, 'conflict.bin');
fileID = fopen(existingPath, 'wb');
fwrite(fileID, uint8(1));
fclose(fileID);
conflictRequest = request;
conflictRequest.FileName = 'conflict.bin';
conflictID = manager.addDownload(conflictRequest);
snapshot = manager.getSnapshot(conflictID);
assert(strcmp(snapshot.LifecycleState, 'awaitingConflictDecision'))
assert(strcmp(snapshot.ConflictType, 'target'))
manager.resolveConflict(conflictID, 'uniqueName')
completed = getappdata(0, 'checkDownloadManager_completed');
assert(strcmp(completed.FinalPath, fullfile(targetPath, 'conflict (1).bin')))
assert(isempty(manager.getSnapshot(conflictID)))
errored = getappdata(0, 'checkDownloadManager_failed');
assert(~errored)

rejectManager = download.DownloadManager(...
    'DownloaderFactory', @createDownloader, ...
    'CollisionPolicy', 'reject');
rejectID = rejectManager.addDownload(conflictRequest);
assert(isempty(rejectManager.getSnapshot(rejectID)))
assert(isfile(existingPath))
delete(rejectManager)

setappdata(0, 'DownloadManagerFakeDownloaderAutoComplete', false)
setappdata(0, 'checkDownloadManager_reordered', false)
holdManager = download.DownloadManager('DownloaderFactory', @createDownloader);
holdManager.TaskReorderedFcn = @reorderedDownload;
holdRequest = request;
holdRequest.FileName = 'held.bin';
holdID = holdManager.addDownload(holdRequest);
heldSnapshot = holdManager.getSnapshot(holdID);
duplicateID = holdManager.addDownload(holdRequest);
assert(duplicateID == holdID)
assert(getappdata(0, 'checkDownloadManager_reordered'))
assert(strcmp(heldSnapshot.LifecycleState, 'active'))
holdManager.pause(holdID)
pausedSnapshot = holdManager.getSnapshot(holdID);
assert(strcmp(pausedSnapshot.LifecycleState, 'paused'))
assert(isfile(pausedSnapshot.PartialPath))
holdManager.cancel(holdID)
assert(isempty(holdManager.getSnapshot(holdID)))
assert(~isfile(pausedSnapshot.PartialPath))
delete(holdManager)
rmappdata(0, 'DownloadManagerFakeDownloaderAutoComplete')
rmappdata(0, 'checkDownloadManager_reordered')

report = struct('CompletedTaskID', completed.TaskID, ...
                'ConflictTarget', completed.FinalPath, ...
                'ErrorRaised', errored);
delete(manager)
rmappdata(0, 'checkDownloadManager_completed')
rmappdata(0, 'checkDownloadManager_failed')
end

function downloader = createDownloader(request)
downloader = DownloadManagerFakeDownloader(request);
end

function completedDownload(~, info, snapshot)
completedDownloadState = getappdata(0, 'checkDownloadManager_completed');
completedDownloadState.TaskID = snapshot.ID;
completedDownloadState.FinalPath = info.FinalPath;
setappdata(0, 'checkDownloadManager_completed', completedDownloadState);
end

function failedDownload(~, ~, ~)
setappdata(0, 'checkDownloadManager_failed', true);
end

function reorderedDownload(~)
setappdata(0, 'checkDownloadManager_reordered', true);
end

function removeFolders(varargin)
for folderIndex = 1:nargin
    folderPath = varargin{folderIndex};
    if isfolder(folderPath)
        rmdir(folderPath, 's')
    end
end
end
