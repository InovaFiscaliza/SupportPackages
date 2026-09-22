function result = downloadFileWorker(requestContext, request, chunkSize, maxRetries, progressQueue, jobId)
%DOWNLOADFILEWORKER Performs ranged download work on a background worker.

    partialPath = request.PartialPath;
    chunkPath = request.ChunkPath;
    finalPath = fullfile(request.TargetFolder, request.FileName);
    bytesReceived = fileSize(partialPath);
    totalBytes = [];
    retryCount = 0;

    result = struct('Success', false, ...
                    'BytesReceived', bytesReceived, ...
                    'TotalBytes', totalBytes, ...
                    'FinalPath', finalPath, ...
                    'Error', []);

    try
        ensureFolder(request.TempFolder)
        if strcmp(request.PartialAction, 'restart')
            deleteIfExists(partialPath)
            deleteIfExists(chunkPath)
            bytesReceived = 0;
            result.BytesReceived = 0;
            request.PartialAction = 'none';
        end

        while true
            if isfile(chunkPath)
                delete(chunkPath)
            end

            firstByte = bytesReceived;
            lastByte = firstByte + chunkSize - 1;
            response = requestRange(requestContext.CookieHeader, request.URL, firstByte, lastByte);
            statusCode = double(response.StatusCode);

            if statusCode == 401 || statusCode == 403 || (statusCode >= 300 && statusCode < 400)
                error('ws:auth:F5Session:sessionExpired', ...
                      'The authenticated session expired during the download.')
            end
            if statusCode < 200 || statusCode >= 300
                error('ws:auth:F5Session:httpError', 'Request returned HTTP %d (%s).', ...
                      statusCode, char(response.StatusCode))
            end

            data = response.Body.Data;
            if isempty(data)
                data = uint8.empty(0, 1);
            elseif ~isa(data, 'uint8')
                error('ws:auth:F5Session:unexpectedPayload', ...
                      'Unexpected payload (%s) in raw reading.', class(data))
            end

            fileID = fopen(chunkPath, 'wb');
            if fileID == -1
                error('ws:auth:F5Session:fileOpenFailed', 'Could not write to "%s".', chunkPath)
            end
            fwrite(fileID, data, 'uint8');
            fclose(fileID)

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
        if isfile(chunkPath)
            delete(chunkPath)
        end

        if retryCount < maxRetries && ~strcmp(exception.identifier, 'ws:auth:F5Session:fileOpenFailed')
            retryCount = retryCount + 1;
            pause(2 * retryCount)
            result = downloadFileWorker(requestContext, request, chunkSize, ...
                                        maxRetries - retryCount, progressQueue, jobId);
            return
        end

        restoreBackup(request.BackupPath, finalPath)
        result.Error = exception;
        result.BytesReceived = fileSize(partialPath);
        result.TotalBytes = totalBytes;
    end
end


function response = requestRange(cookieHeader, url, firstByte, lastByte)
    header = [matlab.net.http.HeaderField('Cookie', cookieHeader), ...
              matlab.net.http.HeaderField('Range', sprintf('bytes=%d-%d', firstByte, lastByte))];
    request = matlab.net.http.RequestMessage('GET', header);
    options = matlab.net.http.HTTPOptions('MaxRedirects', 0, ...
                                          'ConnectTimeout', 30, ...
                                          'ConvertResponse', false);

    response = request.send(url, options);
end


function totalBytes = totalFromResponse(response, statusCode)
    totalBytes = [];
    field = response.getFields('Content-Range');
    if ~isempty(field)
        token = regexp(char(field.Value), '/\s*(\d+)', 'tokens', 'once');
        if ~isempty(token)
            totalBytes = str2double(token{1});
            return
        end
    end

    if statusCode == 200
        field = response.getFields('Content-Length');
        if ~isempty(field)
            totalBytes = str2double(field.Value);
        end
    end
end


function appendFile(sourcePath, targetPath)
    sourceID = fopen(sourcePath, 'rb');
    if sourceID == -1
        error('ws:auth:F5Session:fileOpenFailed', 'Could not read "%s".', sourcePath)
    end
    sourceCleanup = onCleanup(@() fclose(sourceID)); %#ok<NASGU>

    targetID = fopen(targetPath, 'ab');
    if targetID == -1
        error('ws:auth:F5Session:fileOpenFailed', 'Could not write to "%s".', targetPath)
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
        if strcmp(request.CollisionAction, 'overwrite')
            delete(finalPath)
        else
            error('ws:auth:F5Session:targetExists', ...
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
    error('ws:auth:F5Session:fileTransferFailed', ...
          'Could not move or copy "%s" to "%s": %s %s', ...
          sourcePath, destinationPath, message, copyMessage)
end
delete(sourcePath)
end


function ensureFolder(folderPath)
if ~isfolder(folderPath)
    [created, message] = mkdir(folderPath);
    if ~created && ~isfolder(folderPath)
        error('ws:auth:F5Session:folderUnavailable', '%s', message)
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
