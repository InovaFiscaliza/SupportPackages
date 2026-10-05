function report = checkTransferPanelDestination
% CHECKTRANSFERPANELDESTINATION Validate mode-specific destination resolution.

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
webPanel = ui.TransferPanel(layout, ...
    'TransferFactory', @createDownloader, ...
    'DestinationResolver', @resolveDesktopDestination, ...
    'executionMode', 'webApp', ...
    'tempPath', tempPath, ...
    'targetPath', webTargetPath);
policyRejected = false;
try
    webPanel.CollisionPolicy = 'uniqueName';
catch
    policyRejected = true;
end
assert(policyRejected)
policyRejected = false;
try
    webPanel.CollisionPolicy = 'overwrite';
catch
    policyRejected = true;
end
assert(policyRejected)
webTaskID = webPanel.addDownload('https://example.test/download/web.bin');
webSnapshot = webPanel.Manager.getSnapshot(webTaskID);
assert(~resolverCalled)
assert(~factoryCalled)
assert(strcmp(webSnapshot.LifecycleState, 'awaitingConflictDecision'))
assert(strcmp(webSnapshot.LocalPath, fullfile(webTargetPath, 'web.bin')))
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
desktopPanel = ui.TransferPanel(layout, ...
    'TransferFactory', @createDownloader, ...
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
assert(strcmp(fileparts(desktopSnapshot.LocalPath), desktopTargetPath))
assert(strcmp(desktopSnapshot.FileName, 'selected.bin'))
delete(desktopPanel)

createFile(fullfile(desktopTargetPath, 'overwrite.bin'))
resolverFileName = 'overwrite.bin';
resolverFileName = 'overwrite.bin';
factoryCalled = false;
keepPanel = ui.TransferPanel(layout, ...
    'TransferFactory', @createDownloader, ...
    'DestinationResolver', @resolveDesktopDestination, ...
    'executionMode', 'desktopStandaloneApp', ...
    'tempPath', tempPath, ...
    'targetPath', webTargetPath);
keepTaskID = keepPanel.addDownload('https://example.test/download/overwrite.bin');
keepSnapshot = keepPanel.Manager.getSnapshot(keepTaskID);
assert(strcmp(keepSnapshot.LifecycleState, 'awaitingConflictDecision'))
assert(~factoryCalled)
keepPanel.Manager.resolveConflict(keepTaskID, 'keep')
assert(~factoryCalled)
assert(isfile(fullfile(desktopTargetPath, 'overwrite.bin')))
assert(dir(fullfile(desktopTargetPath, 'overwrite.bin')).bytes == 1)
keptHistory = keepPanel.Manager.getHistory();
keptEntry = keptHistory(strcmp({keptHistory.LocalPath}, ...
                               fullfile(desktopTargetPath, 'overwrite.bin')));
assert(numel(keptEntry) == 1)
assert(strcmp(keptEntry.LifecycleState, 'completed'))
assert(keptEntry.isAvailable)
assert(keptEntry.TransferredBytes == 1)
assert(isempty(keepPanel.Manager.getSnapshot(keepTaskID)))
downloadContainers = findall(uiFigure, 'Type', 'uipanel', 'BorderType', 'line');
assert(numel(downloadContainers) == 1)
assert(strcmp(downloadContainers.Visible, 'on'))
delete(keepPanel)

resolverFileName = 'renamed';
factoryCalled = false;
renamedPanel = ui.TransferPanel(layout, ...
    'TransferFactory', @createDownloader, ...
    'DestinationResolver', @resolveDesktopDestination, ...
    'executionMode', 'desktopStandaloneApp', ...
    'tempPath', tempPath, ...
    'targetPath', webTargetPath);
renamedTaskID = renamedPanel.addDownload('https://example.test/download/original.bin');
assert(factoryCalled)
assert(strcmp(factoryRequest.FileName, 'renamed.bin'))
assert(strcmp(factoryRequest.LocalPath, fullfile(desktopTargetPath, 'renamed.bin')))
assert(isfile(fullfile(desktopTargetPath, 'renamed.bin')))
assert(~isfile(fullfile(desktopTargetPath, 'renamed')))
assert(isempty(renamedPanel.Manager.getSnapshot(renamedTaskID)))
delete(renamedPanel)

report = struct('WebTaskID', webTaskID, ...
                'PartialTaskID', partialTaskID, ...
                'DesktopTaskID', desktopTaskID, ...
                'KeepTaskID', keepTaskID, ...
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
        downloader = TransferManagerFakeTransfer(request);
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