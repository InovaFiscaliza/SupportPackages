function report = checkUploadHttp
% CHECKUPLOADHTTP Verify a live Tus upload and retrieval from the test server.

projectFolder = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(projectFolder, 'src', 'General'))

uploadURL = 'http://containerhost.hv:8080/upload/';
healthURL = 'http://localhost:8080/files/test.txt';
downloadRoot = 'http://localhost:8080/files/';
runtimeFolder = tempname;
mkdir(runtimeFolder)
tempFolder = fullfile(runtimeFolder, 'temp');
targetFolder = fullfile(runtimeFolder, 'target');
mkdir(tempFolder)
mkdir(targetFolder)
uploadInfo = struct([]);
uploadError = [];
uploadSnapshot = struct([]);
observedProgressBytes = 0;
intermediateProgressBytes = 0;
cleanup = onCleanup(@() removeFolder(runtimeFolder)); %#ok<NASGU>

requestContext = unauthenticatedContext();
healthResponse = datatransfer.sendHTTPRequest(healthURL, requestContext, 'GET');
healthStatusCode = double(healthResponse.Response.StatusCode);
assert(healthStatusCode == 200)
assert(~isempty(healthResponse.Response.Body.Data))
healthPath = fullfile(targetFolder, 'health-test.txt');
healthResult = downloadToPath(healthURL, healthPath, tempFolder, ...
                              'healthtest', 'health-test.txt', requestContext);
assert(healthResult.Success)
assert(healthResult.TransferredBytes > 0)

[~, uniqueToken] = fileparts(tempname(runtimeFolder));
fileName = ['phase10_', uniqueToken, '.bin'];
sourcePath = fullfile(runtimeFolder, fileName);
payload = uint8(mod(0:65535, 256)).';
writeBytes(sourcePath, payload)
remoteURL = [downloadRoot, fileName];

manager = datatransfer.TransferManager(...
    'TransferFactory', @createTransfer, ...
    'HistoryFile', fullfile(runtimeFolder, 'transfer-history.json'), ...
    'TempFolder', tempFolder);
managerCleanup = onCleanup(@() deleteManager(manager)); %#ok<NASGU>
manager.CompletedFcn = @recordCompletion;
manager.ErrorFcn = @recordError;
manager.SnapshotFcn = @recordSnapshot;

request = struct('Direction', 'upload', ...
                 'URL', uploadURL, ...
                 'TempFolder', tempFolder, ...
                 'LocalPath', sourcePath, ...
                 'FileName', fileName, ...
                 'Protocol', 'auto', ...
                 'Method', 'POST', ...
                 'DisplayMode', 'normal');
manager.addTransfer(request);

waitClock = tic;
while isempty(uploadInfo) && isempty(uploadError) && toc(waitClock) < 120
    pause(0.05)
    drawnow
end
assert(isempty(uploadError), 'Tus upload failed.')
assert(~isempty(uploadInfo), 'Tus upload did not finish within 120 seconds.')
progressClock = tic;
while intermediateProgressBytes == 0 && toc(progressClock) < 5
    pause(0.05)
    drawnow
end
assert(strcmp(uploadInfo.ResolvedProtocol, 'tus'))
assert(uploadInfo.Success)
assert(uploadInfo.UploadOffset == numel(payload))
assert(~isempty(uploadInfo.UploadURL))
assert(strcmp(uploadSnapshot.ResolvedProtocol, 'tus'))
assert(uploadSnapshot.IsResumable)
assert(observedProgressBytes == numel(payload))
assert(intermediateProgressBytes > 0)

downloadPath = fullfile(targetFolder, fileName);
downloadResult = downloadToPath(remoteURL, downloadPath, tempFolder, ...
                                'roundtrip', fileName, requestContext);
assert(downloadResult.Success)
downloadedPayload = readBytes(downloadPath);
assert(isequal(downloadedPayload, payload))

report = struct('HealthStatusCode', healthStatusCode, ...
                'HealthBytes', healthResult.TransferredBytes, ...
                'UploadURL', uploadURL, ...
                'RemoteURL', remoteURL, ...
                'FileName', fileName, ...
                'ResolvedProtocol', uploadInfo.ResolvedProtocol, ...
                'IsResumable', uploadSnapshot.IsResumable, ...
                'UploadStatusCode', uploadInfo.StatusCode, ...
                'UploadedBytes', uploadInfo.UploadOffset, ...
                'ProgressBytesObserved', observedProgressBytes, ...
                'IntermediateProgressBytes', intermediateProgressBytes, ...
                'DownloadedBytes', downloadResult.TransferredBytes, ...
                'PayloadMatches', true);

    function transfer = createTransfer(transferRequest)
        transfer = datatransfer.HTTPFileTransfer(transferRequest, [], 16 * 1024, 0);
    end

    function recordCompletion(~, info, snapshot)
        uploadInfo = info;
        uploadSnapshot = snapshot;
    end

    function recordError(~, exception, ~)
        uploadError = exception;
    end

    function recordSnapshot(snapshot)
        if isfield(snapshot, 'Direction') && strcmp(snapshot.Direction, 'upload') && ...
                isfield(snapshot, 'TransferredBytes')
            transferredBytes = double(snapshot.TransferredBytes);
            observedProgressBytes = max(observedProgressBytes, transferredBytes);
            if transferredBytes > 0 && transferredBytes < numel(payload)
                intermediateProgressBytes = max(intermediateProgressBytes, transferredBytes);
            end
        end
    end

end


function requestContext = unauthenticatedContext
requestContext = struct('CookieHeader', '', ...
                        'AllowedHost', '', ...
                        'AuthenticationEligible', false, ...
                        'Authenticated', false);
end


function result = downloadToPath(url, localPath, tempFolder, taskID, fileName, requestContext)
request = struct('Direction', 'download', ...
                 'URL', url, ...
                 'TaskID', taskID, ...
                 'TempFolder', tempFolder, ...
                 'LocalPath', localPath, ...
                 'FileName', fileName, ...
                 'PartialPath', fullfile(tempFolder, [taskID, '_', fileName, '.part']), ...
                 'ChunkPath', fullfile(tempFolder, [taskID, '_', fileName, '.part.chunk']), ...
                 'BackupPath', '', ...
                 'CollisionAction', 'none', ...
                 'PartialAction', 'none');
result = datatransfer.downloadFileWorker( ...
    requestContext, request, 1024^2, 0, parallel.pool.DataQueue, 1);
end


function writeBytes(filePath, bytes)
fileID = fopen(filePath, 'wb');
assert(fileID ~= -1, 'Could not create the upload source file.')
cleanup = onCleanup(@() fclose(fileID)); %#ok<NASGU>
fwrite(fileID, bytes, 'uint8');
end


function bytes = readBytes(filePath)
fileID = fopen(filePath, 'rb');
assert(fileID ~= -1, 'Could not read the downloaded file.')
cleanup = onCleanup(@() fclose(fileID)); %#ok<NASGU>
bytes = fread(fileID, inf, '*uint8');
end


function removeFolder(folderPath)
if isfolder(folderPath)
    rmdir(folderPath, 's')
end
end


function deleteManager(manager)
if isvalid(manager)
    delete(manager)
end
end