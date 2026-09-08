function result = downloadFileWorker(requestContext, url, filePath, chunkSize, maxRetries, progressQueue, jobId)
%DOWNLOADFILEWORKER Performs ranged download work on a background worker.

    bytesReceived = fileSize(filePath);
    totalBytes = [];
    retryCount = 0;
    tempPath = [filePath, '.chunk'];

    result = struct('Success', false, ...
                    'BytesReceived', bytesReceived, ...
                    'TotalBytes', totalBytes, ...
                    'Error', []);

    try
        while true
            if isfile(tempPath)
                delete(tempPath)
            end

            firstByte = bytesReceived;
            lastByte = firstByte + chunkSize - 1;
            response = requestRange(requestContext.CookieHeader, url, firstByte, lastByte);
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

            fileID = fopen(tempPath, 'wb');
            if fileID == -1
                error('ws:auth:F5Session:fileOpenFailed', 'Could not write to "%s".', tempPath)
            end
            fwrite(fileID, data, 'uint8');
            fclose(fileID)

            chunkBytes = numel(data);
            totalBytes = totalFromResponse(response, statusCode);

            if statusCode == 206
                appendFile(tempPath, filePath)
                bytesReceived = firstByte + chunkBytes;
            else
                movefile(tempPath, filePath, 'f')
                bytesReceived = chunkBytes;
            end

            retryCount = 0;
            send(progressQueue, struct('Type', 'progress', ...
                                       'JobId', jobId, ...
                                       'BytesReceived', bytesReceived, ...
                                       'TotalBytes', totalBytes));

            reachedTotal = ~isempty(totalBytes) && bytesReceived >= totalBytes;
            if reachedTotal || chunkBytes < chunkSize || statusCode == 200
                result.Success = true;
                result.BytesReceived = bytesReceived;
                result.TotalBytes = totalBytes;
                return
            end
        end
    catch exception
        if isfile(tempPath)
            delete(tempPath)
        end

        if retryCount < maxRetries && ~strcmp(exception.identifier, 'ws:auth:F5Session:fileOpenFailed')
            retryCount = retryCount + 1;
            pause(2 * retryCount)
            result = downloadFileWorker(requestContext, url, filePath, chunkSize, ...
                                        maxRetries - retryCount, progressQueue, jobId);
            return
        end

        result.Error = exception;
        result.BytesReceived = fileSize(filePath);
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


function bytes = fileSize(filePath)
    if isfile(filePath)
        fileInfo = dir(filePath);
        bytes = fileInfo.bytes;
    else
        bytes = 0;
    end
end
