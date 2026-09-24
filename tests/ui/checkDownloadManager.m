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
setappdata(0, 'checkDownloadManager_factoryCallCount', 0)
setappdata(0, 'checkDownloadManager_lastRequest', struct())
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
lastRequest = getappdata(0, 'checkDownloadManager_lastRequest');
assert(strcmp(lastRequest.CollisionAction, 'uniqueName'))
assert(isempty(manager.getSnapshot(conflictID)))
errored = getappdata(0, 'checkDownloadManager_failed');
assert(~errored)

overwritePath = fullfile(targetPath, 'overwrite.bin');
writeFile(overwritePath, uint8(1))
overwriteRequest = request;
overwriteRequest.FileName = 'overwrite.bin';
overwriteID = manager.addDownload(overwriteRequest);
overwriteSnapshot = manager.getSnapshot(overwriteID);
assert(strcmp(overwriteSnapshot.ConflictType, 'target'))
manager.resolveConflict(overwriteID, 'overwrite')
lastRequest = getappdata(0, 'checkDownloadManager_lastRequest');
assert(strcmp(lastRequest.CollisionAction, 'overwrite'))
assert(isfile(overwritePath))
assert(dir(overwritePath).bytes == 20)
assert(~isfile(lastRequest.BackupPath))
assert(isempty(manager.getSnapshot(overwriteID)))

cancelTargetPath = fullfile(targetPath, 'cancel-target.bin');
writeFile(cancelTargetPath, uint8(7))
cancelTargetRequest = request;
cancelTargetRequest.FileName = 'cancel-target.bin';
factoryCallCount = getappdata(0, 'checkDownloadManager_factoryCallCount');
cancelTargetID = manager.addDownload(cancelTargetRequest);
manager.resolveConflict(cancelTargetID, 'cancel')
assert(isempty(manager.getSnapshot(cancelTargetID)))
assert(isfile(cancelTargetPath))
assert(getappdata(0, 'checkDownloadManager_factoryCallCount') == factoryCallCount)

resumePartialPath = fullfile(tempPath, 'resume-seed.part');
writeFile(resumePartialPath, uint8([1, 2, 3]))
resumeRequest = request;
resumeRequest.FileName = 'resume.bin';
resumeRequest.PartialPath = resumePartialPath;
resumeID = manager.addDownload(resumeRequest);
resumeSnapshot = manager.getSnapshot(resumeID);
assert(strcmp(resumeSnapshot.ConflictType, 'partial'))
manager.resolveConflict(resumeID, 'resume')
lastRequest = getappdata(0, 'checkDownloadManager_lastRequest');
assert(strcmp(lastRequest.PartialAction, 'resume'))
assert(~isfile(resumePartialPath))
assert(isempty(manager.getSnapshot(resumeID)))

restartPartialPath = fullfile(tempPath, 'restart-seed.part');
writeFile(restartPartialPath, uint8([1, 2, 3]))
restartRequest = request;
restartRequest.FileName = 'restart.bin';
restartRequest.PartialPath = restartPartialPath;
restartID = manager.addDownload(restartRequest);
restartSnapshot = manager.getSnapshot(restartID);
assert(strcmp(restartSnapshot.ConflictType, 'partial'))
manager.resolveConflict(restartID, 'restart')
lastRequest = getappdata(0, 'checkDownloadManager_lastRequest');
assert(strcmp(lastRequest.PartialAction, 'restart'))
assert(~isfile(restartPartialPath))
assert(isempty(manager.getSnapshot(restartID)))

cancelPartialPath = fullfile(tempPath, 'cancel-seed.part');
writeFile(cancelPartialPath, uint8([1, 2, 3]))
cancelPartialRequest = request;
cancelPartialRequest.FileName = 'cancel-partial.bin';
cancelPartialRequest.PartialPath = cancelPartialPath;
factoryCallCount = getappdata(0, 'checkDownloadManager_factoryCallCount');
cancelPartialID = manager.addDownload(cancelPartialRequest);
manager.resolveConflict(cancelPartialID, 'cancel')
assert(isempty(manager.getSnapshot(cancelPartialID)))
assert(~isfile(cancelPartialPath))
assert(getappdata(0, 'checkDownloadManager_factoryCallCount') == factoryCallCount)

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
                'ErrorRaised', errored, ...
                'ConflictTransitions', 6);
delete(manager)
rmappdata(0, 'checkDownloadManager_completed')
rmappdata(0, 'checkDownloadManager_failed')
rmappdata(0, 'checkDownloadManager_factoryCallCount')
rmappdata(0, 'checkDownloadManager_lastRequest')
end

function downloader = createDownloader(request)
setappdata(0, 'checkDownloadManager_factoryCallCount', ...
           getappdata(0, 'checkDownloadManager_factoryCallCount') + 1);
setappdata(0, 'checkDownloadManager_lastRequest', request);
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

function writeFile(filePath, bytes)
fileID = fopen(filePath, 'wb');
assert(fileID ~= -1)
cleanup = onCleanup(@() fclose(fileID)); %#ok<NASGU>
fwrite(fileID, bytes, 'uint8');
end
