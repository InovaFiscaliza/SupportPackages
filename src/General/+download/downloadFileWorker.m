function result = downloadFileWorker(requestContext, request, chunkSize, maxRetries, progressQueue, jobId)
% DOWNLOADFILEWORKER Perform resumable HTTP transfer independent of auth.

partialPath = request.PartialPath;
chunkPath = request.ChunkPath;
finalPath = fullfile(request.TargetFolder, request.FileName);
bytesReceived = fileSize(partialPath);
totalBytes = [];
retryCount = 0;
currentURL = request.URL;

result = struct('Success', false, ...
                'NeedsAuthentication', false, ...
                'BytesReceived', bytesReceived, ...
                'TotalBytes', totalBytes, ...
                'FinalPath', finalPath, ...
                'FinalURL', currentURL, ...
                'ResolvedFileName', request.FileName, ...
                'Error', []);

try
    ensureFolder(request.TempFolder)
    if isfield(request, 'PartialAction') && strcmp(request.PartialAction, 'restart')
        deleteIfExists(partialPath)
        deleteIfExists(chunkPath)
        bytesReceived = 0;
        result.BytesReceived = 0;
        request.PartialAction = 'none';
    end

    while true
        deleteIfExists(chunkPath)
        firstByte = bytesReceived;
        lastByte = firstByte + chunkSize - 1;
        responseResult = download.downloadHTTPResponse(currentURL, requestContext, ...
                                                  'GET', firstByte, lastByte);
        if responseResult.NeedsAuthentication
            result.NeedsAuthentication = true;
            result.FinalURL = responseResult.FinalURL;
            return
        end

        response = responseResult.Response;
        currentURL = responseResult.FinalURL;
        result.FinalURL = currentURL;
        statusCode = double(response.StatusCode);
        if statusCode < 200 || statusCode >= 300
            error('download:downloadFileWorker:httpError', ...
                  'Request returned HTTP %d.', statusCode)
        end

        responseFileName = contentDispositionFileName(response);
        if ~isempty(responseFileName)
            result.ResolvedFileName = responseFileName;
        end

        data = response.Body.Data;
        if isempty(data)
            data = uint8.empty(0, 1);
        elseif ~isa(data, 'uint8')
            error('download:downloadFileWorker:unexpectedPayload', ...
                  'Unexpected payload (%s) in raw reading.', class(data))
        end

        fileID = fopen(chunkPath, 'wb');
        if fileID == -1
            error('download:downloadFileWorker:fileOpenFailed', ...
                  'Could not write to "%s".', chunkPath)
        end
        cleanup = onCleanup(@() closeFileQuietly(fileID)); %#ok<NASGU>
        fwrite(fileID, data, 'uint8');
        fclose(fileID)
        clear cleanup

        chunkBytes = numel(data);
        totalBytes = totalFromResponse(response, statusCode);
        if statusCode == 206
            appendFile(chunkPath, partialPath)
            bytesReceived = firstByte + chunkBytes;
        else
            moveFileWithFallback(chunkPath, partialPath)
            bytesReceived = chunkBytes;
        end

        retryCount = 0;
        send(progressQueue, struct('Type', 'progress', ...
                                   'JobId', jobId, ...
                                   'BytesReceived', bytesReceived, ...
                                   'TotalBytes', totalBytes));

        reachedTotal = ~isempty(totalBytes) && bytesReceived >= totalBytes;
        if reachedTotal || chunkBytes < chunkSize || statusCode == 200
            publishFile(request, partialPath, finalPath)
            cleanupSuccessfulFiles(request, partialPath, chunkPath)
            result.Success = true;
            result.BytesReceived = bytesReceived;
            result.TotalBytes = totalBytes;
            return
        end
    end
catch exception
    deleteIfExists(chunkPath)
    if retryCount < maxRetries && ~strcmp(exception.identifier, 'download:downloadFileWorker:fileOpenFailed')
        retryCount = retryCount + 1;
        pause(2 * retryCount)
        result = download.downloadFileWorker(requestContext, request, chunkSize, ...
                                       maxRetries - retryCount, progressQueue, jobId);
        return
    end

    restoreBackup(request.BackupPath, finalPath)
    result.Error = exception;
    result.BytesReceived = fileSize(partialPath);
    result.TotalBytes = totalBytes;
end
end


function value = contentDispositionFileName(response)
fields = response.getFields('Content-Disposition');
if isempty(fields)
    value = '';
    return
end
value = download.downloadContentDispositionFileName(char(fields(1).Value));
end


function totalBytes = totalFromResponse(response, statusCode)
totalBytes = [];
field = response.getFields('Content-Range');
if ~isempty(field)
    token = regexp(char(field(1).Value), '/\s*(\d+)', 'tokens', 'once');
    if ~isempty(token)
        totalBytes = str2double(token{1});
        return
    end
end
if statusCode == 200
    field = response.getFields('Content-Length');
    if ~isempty(field)
        totalBytes = str2double(field(1).Value);
    end
end
end


function appendFile(sourcePath, targetPath)
sourceID = fopen(sourcePath, 'rb');
if sourceID == -1
    error('download:downloadFileWorker:fileOpenFailed', 'Could not read "%s".', sourcePath)
end
sourceCleanup = onCleanup(@() fclose(sourceID)); %#ok<NASGU>
targetID = fopen(targetPath, 'ab');
if targetID == -1
    error('download:downloadFileWorker:fileOpenFailed', 'Could not write "%s".', targetPath)
end
targetCleanup = onCleanup(@() fclose(targetID)); %#ok<NASGU>
while true
    chunk = fread(sourceID, 1024*1024, '*uint8');
    if isempty(chunk)
        break
    end
    fwrite(targetID, chunk, 'uint8');
end
end


function publishFile(request, partialPath, finalPath)
ensureFolder(request.TargetFolder)
if isfile(finalPath)
    if isfield(request, 'CollisionAction') && strcmp(request.CollisionAction, 'overwrite')
        delete(finalPath)
    else
        error('download:downloadFileWorker:targetExists', ...
              'The target file "%s" already exists.', finalPath)
    end
end
moveFileWithFallback(partialPath, finalPath)
end


function cleanupSuccessfulFiles(request, partialPath, chunkPath)
deleteIfExists(partialPath)
deleteIfExists(chunkPath)
deleteIfExists(request.BackupPath)
end


function restoreBackup(backupPath, finalPath)
if isempty(backupPath) || ~isfile(backupPath) || isfile(finalPath)
    return
end
moveFileWithFallback(backupPath, finalPath)
end


function moveFileWithFallback(sourcePath, destinationPath)
[moved, message] = movefile(sourcePath, destinationPath, 'f');
if moved
    return
end
[copied, copyMessage] = copyfile(sourcePath, destinationPath, 'f');
if ~copied
    error('download:downloadFileWorker:fileTransferFailed', ...
          'Could not move or copy "%s" to "%s": %s %s', ...
          sourcePath, destinationPath, message, copyMessage)
end
delete(sourcePath)
end


function ensureFolder(folderPath)
if ~isfolder(folderPath)
    [created, message] = mkdir(folderPath);
    if ~created && ~isfolder(folderPath)
        error('download:downloadFileWorker:folderUnavailable', '%s', message)
    end
end
end


function deleteIfExists(filePath)
if ~isempty(filePath) && isfile(filePath)
    delete(filePath)
end
end


function bytes = fileSize(filePath)
if isfile(filePath)
    fileInfo = dir(filePath);
    bytes = fileInfo.bytes;
else
    bytes = 0;
end
end


function closeFileQuietly(fileID)
try
    fclose(fileID);
catch
end
end
