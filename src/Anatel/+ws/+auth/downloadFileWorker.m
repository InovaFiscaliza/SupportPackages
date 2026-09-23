function result = downloadFileWorker(requestContext, request, chunkSize, maxRetries, progressQueue, jobId)
% DOWNLOADFILEWORKER Compatibility wrapper for the shared UI worker.
result = ui.downloadFileWorker(requestContext, request, chunkSize, ...
                               maxRetries, progressQueue, jobId);
end
