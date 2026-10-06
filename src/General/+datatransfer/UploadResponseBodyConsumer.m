classdef UploadResponseBodyConsumer < matlab.net.http.io.ContentConsumer
    % UPLOADRESPONSEBODYCONSUMER Capture a bounded upload response body.

    properties (SetAccess = private)
        CapturedBody uint8 = uint8.empty(0, 1)
        ResponseTruncated (1, 1) logical = false
    end

    properties (Constant, Access = private)
        MaximumBytes = 64 * 1024
    end

    methods (Access = protected)
        function accepted = initialize(obj)
            obj.CapturedBody = uint8.empty(0, 1);
            obj.ResponseTruncated = false;
            accepted = true;
        end

        function start(~)
        end
    end

    methods
        function [consumedBytes, stop] = putData(obj, data)
            % PUTDATA Capture response bytes up to the configured limit.
            if isempty(data)
                consumedBytes = 0;
                stop = false;
                return
            end

            availableBytes = obj.MaximumBytes - numel(obj.CapturedBody);
            retainedBytes = min(availableBytes, numel(data));
            if retainedBytes > 0
                obj.CapturedBody(end+1:end+retainedBytes, 1) = ...
                    reshape(data(1:retainedBytes), [], 1);
            end
            if retainedBytes < numel(data)
                obj.ResponseTruncated = true;
            end

            consumedBytes = numel(data);
            stop = false;
        end
    end
end