classdef UploadProgressMonitor < matlab.net.http.ProgressMonitor
    % UPLOADPROGRESSMONITOR Report raw file request progress in payload bytes.

    properties
        Direction matlab.net.http.MessageType = matlab.net.http.MessageType.Request
    end

    properties (SetObservable)
        Value uint64 = uint64(0)
    end

    properties (Access = private)
        ProgressQueue
        JobId
        PayloadBytes (1, 1) double = 0
    end

    methods
        function obj = UploadProgressMonitor(progressQueue, jobId, payloadBytes)
            % UPLOADPROGRESSMONITOR Create exact file-payload progress reporting.
            obj.ProgressQueue = progressQueue;
            obj.JobId = jobId;
            obj.PayloadBytes = double(payloadBytes);
        end

        function done(~)
            % DONE The file provider reports payload progress directly.
        end

        function reportPayloadBytes(obj, transferredBytes)
            % REPORTPAYLOADBYTES Publish the cumulative source-file bytes read.
            arguments
                obj
                transferredBytes (1, 1) double {mustBeFinite, mustBeNonnegative}
            end
            if obj.Direction ~= matlab.net.http.MessageType.Request || ...
                    isempty(obj.ProgressQueue)
                return
            end

            transferredBytes = min(transferredBytes, obj.PayloadBytes);
            send(obj.ProgressQueue, struct('Type', 'progress', ...
                                           'JobId', obj.JobId, ...
                                           'TransferredBytes', transferredBytes, ...
                                           'TotalBytes', obj.PayloadBytes));
        end
    end
end