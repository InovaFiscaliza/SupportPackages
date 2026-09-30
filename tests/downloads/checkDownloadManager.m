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
historyFile = fullfile(tempPath, 'download-history.json');
cleanup = onCleanup(@() removeFolders(tempPath, targetPath)); %#ok<NASGU>

setappdata(0, 'checkDownloadManager_completed', struct('TaskID', [], 'FinalPath', ''))
setappdata(0, 'checkDownloadManager_failed', false)
setappdata(0, 'checkDownloadManager_factoryCallCount', 0)
setappdata(0, 'checkDownloadManager_lastRequest', struct())
manager = download.DownloadManager(...
    'DownloaderFactory', @createDownloader, ...
    'HistoryFile', historyFile, ...
    'TempFolder', tempPath, ...
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
history = manager.getHistory();
assert(numel(history) == 1)
completedEntry = history(1);
assert(numel(completedEntry) == 1)
assert(strcmp(completedEntry.LifecycleState, 'completed'))
assert(completedEntry.isAvailable)
assert(numel(completedEntry.AttemptedTimestamps) == 1)
assert(startsWith(completedEntry.StartedAt, '20'))
assert(endsWith(completedEntry.StartedAt, 'Z'))
delete(manager)
manager = download.DownloadManager(...
    'DownloaderFactory', @createDownloader, ...
    'HistoryFile', historyFile, ...
    'TempFolder', tempPath, ...
    'CollisionPolicy', 'askInRow');
history = manager.getHistory();
assert(numel(history) == 1)
assert(strcmp(history(1).LogicalFileID, completedEntry.LogicalFileID))
assert(history(1).isAvailable)
delete(fullfile(targetPath, 'sample.bin'))
delete(manager)
manager = download.DownloadManager(...
    'DownloaderFactory', @createDownloader, ...
    'HistoryFile', historyFile, ...
    'TempFolder', tempPath, ...
    'CollisionPolicy', 'askInRow');
manager.CompletedFcn = @completedDownload;
manager.ErrorFcn = @failedDownload;
history = manager.getHistory();
assert(~history(1).isAvailable)
retryID = manager.addDownload(request);
history = manager.getHistory();
assert(numel(history) == 2)
assert(strcmp(history(2).LogicalFileID, completedEntry.LogicalFileID))
assert(~strcmp(history(2).EntryID, completedEntry.EntryID))
assert(numel(history(2).AttemptedTimestamps) == 2)
assert(isempty(manager.getSnapshot(retryID)))

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
manager.resolveConflict(conflictID, 'restart')
completed = getappdata(0, 'checkDownloadManager_completed');
assert(strcmp(completed.FinalPath, fullfile(targetPath, 'conflict.bin')))
lastRequest = getappdata(0, 'checkDownloadManager_lastRequest');
assert(strcmp(lastRequest.CollisionAction, 'overwrite'))
assert(isfile(fullfile(targetPath, 'conflict.bin')))
assert(dir(fullfile(targetPath, 'conflict.bin')).bytes == 20)
assert(isempty(manager.getSnapshot(conflictID)))
errored = getappdata(0, 'checkDownloadManager_failed');
assert(~errored)

keepTargetPath = fullfile(targetPath, 'keep-existing.bin');
writeFile(keepTargetPath, uint8([1, 2, 3, 4, 5, 6, 7]))
keepRequest = request;
keepRequest.FileName = 'keep-existing.bin';
factoryCallCount = getappdata(0, 'checkDownloadManager_factoryCallCount');
keepID = manager.addDownload(keepRequest);
keepSnapshot = manager.getSnapshot(keepID);
assert(strcmp(keepSnapshot.LifecycleState, 'awaitingConflictDecision'))
manager.resolveConflict(keepID, 'keep')
assert(getappdata(0, 'checkDownloadManager_factoryCallCount') == factoryCallCount)
history = manager.getHistory();
keepEntry = history(strcmp({history.TargetPath}, keepTargetPath));
assert(numel(keepEntry) == 1)
assert(strcmp(keepEntry.LifecycleState, 'completed'))
assert(keepEntry.isAvailable)
assert(keepEntry.DownloadedBytes == 7)
assert(numel(keepEntry.AttemptedTimestamps) == 1)
assert(manager.deleteHistoryEntry(keepEntry.EntryID))
assert(isfile(keepTargetPath))

history = manager.getHistory();
conflictEntry = history(strcmp({history.TargetPath}, fullfile(targetPath, 'conflict.bin')));
assert(numel(conflictEntry) == 1)
restartedID = manager.restartHistoryEntry(conflictEntry.EntryID);
assert(isempty(manager.getSnapshot(restartedID)))
history = manager.getHistory();
conflictEntries = history(strcmp({history.LogicalFileID}, conflictEntry.LogicalFileID));
assert(numel(conflictEntries) == 2)
assert(~strcmp(conflictEntries(1).EntryID, conflictEntries(2).EntryID))
assert(numel(conflictEntries(2).AttemptedTimestamps) == 2)

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
    'HistoryFile', fullfile(tempPath, 'reject-history.json'), ...
    'TempFolder', tempPath, ...
    'CollisionPolicy', 'reject');
rejectID = rejectManager.addDownload(conflictRequest);
assert(isempty(rejectManager.getSnapshot(rejectID)))
assert(isfile(existingPath))
delete(rejectManager)

setappdata(0, 'DownloadManagerFakeDownloaderAutoComplete', false)
setappdata(0, 'checkDownloadManager_reordered', false)
holdManager = download.DownloadManager('DownloaderFactory', @createDownloader, ...
                                       'HistoryFile', fullfile(tempPath, 'hold-history.json'), ...
                                       'TempFolder', tempPath);
holdManager.TaskReorderedFcn = @reorderedDownload;
holdRequest = request;
holdRequest.FileName = 'held.bin';
holdRequest.DisplayMode = 'silent';
holdID = holdManager.addDownload(holdRequest);
heldSnapshot = holdManager.getSnapshot(holdID);
duplicateRequest = holdRequest;
duplicateRequest.DisplayMode = 'normal';
duplicateRequest.TargetFolder = fullfile(targetPath, 'alternate');
duplicateID = holdManager.addDownload(duplicateRequest);
assert(duplicateID == holdID)
assert(getappdata(0, 'checkDownloadManager_reordered'))
assert(strcmp(heldSnapshot.LifecycleState, 'active'))
assert(isfield(heldSnapshot, 'HistoryEntry'))
assert(strcmp(heldSnapshot.HistoryEntry.LogicalFileID, ...
              heldSnapshot.LogicalFileID))
duplicateSnapshot = holdManager.getSnapshot(holdID);
assert(strcmp(duplicateSnapshot.DisplayMode, 'normal'))
assert(isequal(duplicateSnapshot.AttemptedTimestamps, ...
               heldSnapshot.AttemptedTimestamps))
holdManager.pause(holdID)
pausedSnapshot = holdManager.getSnapshot(holdID);
assert(strcmp(pausedSnapshot.LifecycleState, 'paused'))
assert(isfile(pausedSnapshot.PartialPath))
holdManager.resume(holdID)
history = holdManager.getHistory();
assert(strcmp(history(end).LifecycleState, 'active'))
assert(isequal(history(end).AttemptedTimestamps, ...
               heldSnapshot.AttemptedTimestamps))
holdManager.pause(holdID)
history = holdManager.getHistory();
assert(strcmp(history(end).LifecycleState, 'paused'))
assert(isequal(history(end).AttemptedTimestamps, ...
               heldSnapshot.AttemptedTimestamps))
holdManager.cancel(holdID)
history = holdManager.getHistory();
assert(isempty(history))
assert(isempty(holdManager.getSnapshot(holdID)))
assert(~isfile(pausedSnapshot.PartialPath))
delete(holdManager)
rmappdata(0, 'DownloadManagerFakeDownloaderAutoComplete')
rmappdata(0, 'checkDownloadManager_reordered')

recoveryTempPath = tempname;
recoveryTargetPath = tempname;
mkdir(recoveryTempPath)
mkdir(recoveryTargetPath)
recoveryCleanup = onCleanup(@() removeFolders(recoveryTempPath, ...
                                              recoveryTargetPath)); %#ok<NASGU>
setappdata(0, 'DownloadManagerFakeDownloaderAutoComplete', false)
recoveryHistoryFile = fullfile(recoveryTempPath, 'history.json');
recoveryManager = download.DownloadManager(...
    'DownloaderFactory', @createDownloader, ...
    'HistoryFile', recoveryHistoryFile, ...
    'TempFolder', recoveryTempPath);
recoveryRequest = struct('URL', 'https://example.test/recovery.bin', ...
                         'TempFolder', recoveryTempPath, ...
                         'TargetFolder', recoveryTargetPath, ...
                         'FileName', 'recovery.bin');
recoveryTaskID = recoveryManager.addDownload(recoveryRequest);
recoverySnapshot = recoveryManager.getSnapshot(recoveryTaskID);
writeFile(recoverySnapshot.PartialPath, uint8([1, 2, 3, 4, 5]))
delete(recoveryManager)
recoveryHistoryStore = download.DownloadHistoryStore(recoveryHistoryFile);
recoveryHistory = recoveryHistoryStore.getEntries();
duplicateInterruptedEntry = recoveryHistory(1);
duplicateInterruptedEntry.EntryID = 'interrupted-retry';
duplicateInterruptedEntry.TaskID = 'deadbeef';
duplicateInterruptedEntry.TemporaryPath = fullfile(recoveryTempPath, ...
                                                  'deadbeef_recovery.bin.part');
duplicateInterruptedEntry.ChunkPath = [duplicateInterruptedEntry.TemporaryPath, '.chunk'];
duplicateInterruptedEntry.DownloadedBytes = 8;
duplicateInterruptedEntry.UpdatedAt = char(datetime('now', 'TimeZone', 'UTC', ...
    'Format', "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
writeFile(duplicateInterruptedEntry.TemporaryPath, uint8(1:8))
recoveryHistoryStore.upsert(duplicateInterruptedEntry)
recoveredManager = download.DownloadManager(...
    'DownloaderFactory', @createDownloader, ...
    'HistoryFile', recoveryHistoryFile, ...
    'TempFolder', recoveryTempPath);
recoveredHistory = recoveredManager.getHistory();
assert(numel(recoveredHistory) == 2)
assert(all(strcmp({recoveredHistory.LifecycleState}, 'interrupted')))
assert(all(arrayfun(@(entry) isfile(entry.TemporaryPath), recoveredHistory)))
factoryCallCount = getappdata(0, 'checkDownloadManager_factoryCallCount');
restoredTaskIDs = recoveredManager.restoreInterruptedDownloads();
assert(numel(restoredTaskIDs) == 1)
restoredSnapshot = recoveredManager.getSnapshot(restoredTaskIDs(1));
assert(strcmp(restoredSnapshot.LifecycleState, 'awaitingConflictDecision'))
assert(strcmp(restoredSnapshot.ConflictType, 'partial'))
assert(restoredSnapshot.ReceivedBytes == 8)
assert(strcmp(restoredSnapshot.PartialPath, duplicateInterruptedEntry.TemporaryPath))
assert(getappdata(0, 'checkDownloadManager_factoryCallCount') == factoryCallCount)
restoredHistory = recoveredManager.getHistory();
assert(numel(restoredHistory) == 3)
assert(sum(strcmp({restoredHistory.LifecycleState}, 'awaitingConflictDecision')) == 1)
delete(recoveredManager)
rmappdata(0, 'DownloadManagerFakeDownloaderAutoComplete')

corruptTempPath = tempname;
mkdir(corruptTempPath)
corruptCleanup = onCleanup(@() removeFolders(corruptTempPath)); %#ok<NASGU>
corruptHistoryFile = fullfile(corruptTempPath, 'history.json');
fileID = fopen(corruptHistoryFile, 'w');
fwrite(fileID, '{invalid json', 'char');
fclose(fileID);
orphanPath = fullfile(corruptTempPath, 'deadbeef_orphan.bin.part');
writeFile(orphanPath, uint8([1, 2, 3]))
legacyOrphanPath = fullfile(corruptTempPath, 'legacy-orphan.part');
writeFile(legacyOrphanPath, uint8([4, 5]))
unrelatedPath = fullfile(corruptTempPath, 'keep.bin');
writeFile(unrelatedPath, uint8(9))
corruptManager = download.DownloadManager(...
    'DownloaderFactory', @createDownloader, ...
    'HistoryFile', corruptHistoryFile, ...
    'TempFolder', corruptTempPath);
assert(~isfile(orphanPath))
assert(~isfile(legacyOrphanPath))
assert(isfile(unrelatedPath))
assert(isempty(corruptManager.getHistory()))
assert(isfile(corruptHistoryFile))
emptyHistoryDocument = jsondecode(fileread(corruptHistoryFile));
assert(isempty(emptyHistoryDocument.Entries))
delete(corruptManager)

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
