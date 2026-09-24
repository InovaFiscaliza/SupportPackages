function report = checkDownloadPanelDestination
% CHECKDOWNLOADPANELDESTINATION Validate mode-specific destination resolution.

mFilePath = fileparts(mfilename('fullpath'));
projectFolder = fileparts(fileparts(mFilePath));
addpath(fullfile(projectFolder, 'src', 'General'))
addpath(mFilePath)

tempPath = tempname;
webTargetPath = tempname;
desktopTargetPath = tempname;
mkdir(tempPath)
mkdir(webTargetPath)
mkdir(desktopTargetPath)
uiFigure = uifigure('Visible', 'off');
cleanup = onCleanup(@() cleanUp(uiFigure, tempPath, webTargetPath, desktopTargetPath)); %#ok<NASGU>
layout = uigridlayout(uiFigure, [1, 1]);

resolverCalled = false;
resolverContext = struct();
resolverFileName = 'selected.bin';
factoryCalled = false;
factoryRequest = struct();
createFile(fullfile(webTargetPath, 'web.bin'))
webPanel = ui.DownloadPanel(layout, ...
    'DownloaderFactory', @createDownloader, ...
    'DestinationResolver', @resolveDesktopDestination, ...
    'executionMode', 'webApp', ...
    'tempPath', tempPath, ...
    'targetPath', webTargetPath);
webTaskID = webPanel.addDownload('https://example.test/download/web.bin');
webSnapshot = webPanel.Manager.getSnapshot(webTaskID);
assert(~resolverCalled)
assert(~factoryCalled)
assert(strcmp(webSnapshot.LifecycleState, 'awaitingConflictDecision'))
assert(strcmp(webSnapshot.FinalPath, fullfile(webTargetPath, 'web.bin')))
downloadContainers = findall(uiFigure, 'Type', 'uipanel', 'BorderType', 'line');
assert(numel(downloadContainers) == 1)
assert(strcmp(downloadContainers.Visible, 'on'))
webPanel.Manager.resolveConflict(webTaskID, 'cancel')
createFile(fullfile(tempPath, 'pending_partial.bin.part'))
partialTaskID = webPanel.addDownload('https://example.test/download/partial.bin');
partialSnapshot = webPanel.Manager.getSnapshot(partialTaskID);
assert(strcmp(partialSnapshot.LifecycleState, 'awaitingConflictDecision'))
assert(strcmp(partialSnapshot.ConflictType, 'partial'))
downloadContainers = findall(uiFigure, 'Type', 'uipanel', 'BorderType', 'line');
assert(numel(downloadContainers) == 1)
assert(strcmp(downloadContainers.Visible, 'on'))
delete(webPanel)

createFile(fullfile(desktopTargetPath, 'selected.bin'))
desktopPanel = ui.DownloadPanel(layout, ...
    'DownloaderFactory', @createDownloader, ...
    'DestinationResolver', @resolveDesktopDestination, ...
    'executionMode', 'desktopStandaloneApp', ...
    'tempPath', tempPath, ...
    'targetPath', webTargetPath);
desktopTaskID = desktopPanel.addDownload('https://example.test/download/suggested.bin');
desktopSnapshot = desktopPanel.Manager.getSnapshot(desktopTaskID);
assert(resolverCalled)
assert(~factoryCalled)
assert(strcmp(resolverContext.ExecutionMode, 'desktopStandaloneApp'))
assert(strcmp(resolverContext.SuggestedFileName, 'suggested.bin'))
assert(strcmp(resolverContext.InitialFolder, webTargetPath))
assert(strcmp(desktopSnapshot.LifecycleState, 'awaitingConflictDecision'))
assert(strcmp(desktopSnapshot.TargetFolder, desktopTargetPath))
assert(strcmp(desktopSnapshot.FileName, 'selected.bin'))
delete(desktopPanel)

createFile(fullfile(desktopTargetPath, 'overwrite.bin'))
resolverFileName = 'overwrite.bin';
factoryCalled = false;
overwritePanel = ui.DownloadPanel(layout, ...
    'DownloaderFactory', @createDownloader, ...
    'DestinationResolver', @resolveDesktopDestination, ...
    'executionMode', 'desktopStandaloneApp', ...
    'CollisionPolicy', 'overwrite', ...
    'tempPath', tempPath, ...
    'targetPath', webTargetPath);
overwriteTaskID = overwritePanel.addDownload('https://example.test/download/overwrite.bin');
assert(factoryCalled)
assert(strcmp(factoryRequest.CollisionAction, 'overwrite'))
assert(isfile(fullfile(desktopTargetPath, 'overwrite.bin')))
assert(dir(fullfile(desktopTargetPath, 'overwrite.bin')).bytes == 20)
assert(isempty(overwritePanel.Manager.getSnapshot(overwriteTaskID)))
downloadContainers = findall(uiFigure, 'Type', 'uipanel', 'BorderType', 'line');
assert(isempty(downloadContainers) || ...
    all(strcmp({downloadContainers.Visible}, 'off')))
delete(overwritePanel)

resolverFileName = 'renamed';
factoryCalled = false;
renamedPanel = ui.DownloadPanel(layout, ...
    'DownloaderFactory', @createDownloader, ...
    'DestinationResolver', @resolveDesktopDestination, ...
    'executionMode', 'desktopStandaloneApp', ...
    'tempPath', tempPath, ...
    'targetPath', webTargetPath);
renamedTaskID = renamedPanel.addDownload('https://example.test/download/original.bin');
assert(factoryCalled)
assert(strcmp(factoryRequest.FileName, 'renamed.bin'))
assert(strcmp(factoryRequest.FinalPath, fullfile(desktopTargetPath, 'renamed.bin')))
assert(isfile(fullfile(desktopTargetPath, 'renamed.bin')))
assert(~isfile(fullfile(desktopTargetPath, 'renamed')))
assert(isempty(renamedPanel.Manager.getSnapshot(renamedTaskID)))
delete(renamedPanel)

report = struct('WebTaskID', webTaskID, ...
                'PartialTaskID', partialTaskID, ...
                'DesktopTaskID', desktopTaskID, ...
                'OverwriteTaskID', overwriteTaskID, ...
                'RenamedTaskID', renamedTaskID, ...
                'DesktopResolverCalled', resolverCalled);

    function resolution = resolveDesktopDestination(context)
        resolverCalled = true;
        resolverContext = context;
        resolution = struct('Cancelled', false, ...
                            'TargetFolder', desktopTargetPath, ...
                            'FileName', resolverFileName);
    end

    function downloader = createDownloader(request)
        factoryCalled = true;
        factoryRequest = request;
        downloader = DownloadManagerFakeDownloader(request);
    end
end

function createFile(filePath)
fileID = fopen(filePath, 'wb');
assert(fileID ~= -1)
cleanup = onCleanup(@() fclose(fileID)); %#ok<NASGU>
fwrite(fileID, uint8(1));
end

function cleanUp(uiFigure, varargin)
if ~isempty(uiFigure) && isvalid(uiFigure)
    delete(uiFigure)
end
for folderIndex = 1:numel(varargin)
    if isfolder(varargin{folderIndex})
        rmdir(varargin{folderIndex}, 's')
    end
end
end