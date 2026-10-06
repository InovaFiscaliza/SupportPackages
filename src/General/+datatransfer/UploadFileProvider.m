classdef UploadFileProvider < matlab.net.http.io.FileProvider
    % UPLOADFILEPROVIDER Read source-file bytes and report exact payload progress.

    properties (Access = private)
        PayloadBytes (1, 1) double
        PayloadBytesRead (1, 1) double = 0
        ProgressMonitor
    end

    methods
        function obj = UploadFileProvider(source, sourceBytes, progressMonitor)
            % UPLOADFILEPROVIDER Create a read-only provider for a path or open file ID.
            arguments
                source
                sourceBytes (1, 1) double {mustBeFinite, mustBeNonnegative, mustBeInteger}
                progressMonitor = []
            end
            if isstring(source)
                if ~isscalar(source) || ismissing(source) || strlength(source) == 0
                    error('datatransfer:UploadFileProvider:invalidSource', ...
                          'Source must be a nonempty file path or open file identifier.')
                end
                source = char(source);
            elseif ischar(source)
                if ~isrow(source) || isempty(source)
                    error('datatransfer:UploadFileProvider:invalidSource', ...
                          'Source must be a nonempty file path or open file identifier.')
                end
            elseif isnumeric(source) && isscalar(source) && isreal(source) && ...
                    isfinite(source) && source >= 0 && source == floor(source)
                source = double(source);
            else
                error('datatransfer:UploadFileProvider:invalidSource', ...
                      'Source must be a nonempty file path or open file identifier.')
            end
            if ~isempty(progressMonitor) && ...
                    (~isa(progressMonitor, 'datatransfer.UploadProgressMonitor') || ...
                     ~isscalar(progressMonitor))
                error('datatransfer:UploadFileProvider:invalidProgressMonitor', ...
                      'ProgressMonitor must be empty or a scalar UploadProgressMonitor.')
            end

            obj@matlab.net.http.io.FileProvider(source);
            obj.FileSize = sourceBytes;
            obj.PayloadBytes = sourceBytes;
            obj.ProgressMonitor = progressMonitor;
        end

        function [data, stop] = getData(obj, length)
            % GETDATA Read the next source-file buffer and report its exact byte count.
            [data, stop] = obj.getData@matlab.net.http.io.FileProvider(length);
            bytesReturned = numel(data);
            if bytesReturned == 0
                return
            end

            obj.PayloadBytesRead = min(obj.PayloadBytes, ...
                                       obj.PayloadBytesRead + double(bytesReturned));
            if ~isempty(obj.ProgressMonitor)
                obj.ProgressMonitor.reportPayloadBytes(obj.PayloadBytesRead);
            end
        end
    end
end