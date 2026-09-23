function result = downloadFileWorker(requestContext, request, chunkSize, maxRetries, progressQueue, jobId)
% DOWNLOADFILEWORKER Compatibility wrapper for the shared generic worker.
result = download.downloadFileWorker(requestContext, request, chunkSize, ...
                               maxRetries, progressQueue, jobId);
end
