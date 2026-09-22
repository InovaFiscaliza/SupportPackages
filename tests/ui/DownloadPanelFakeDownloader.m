classdef DownloadPanelFakeDownloader < handle

    % DOWNLOADPANELFAKEDOWNLOADER Deterministic downloader test double.
    %
    % This class implements the downloader protocol required by
    % ui.DownloadPanel. It uses a timer to emit progress, writes simulated
    % partial data, publishes a fake target file, and invokes the configured
    % completion or error callback. It never performs network I/O.

    properties
        Request
        BytesReceived (1,1) double = 0
        TotalBytes (1,1) double
        BytesPerSecond (1,1) double
        WrittenBytes (1,1) double = 0
        IsRunning (1,1) logical = false
        IsPaused (1,1) logical = false
        ProgressFcn = []
        CompletedFcn = []
        ErrorFcn = []
    end

    properties (Access = private)
        Timer = []
    end

    methods
        function obj = DownloadPanelFakeDownloader(request)
            % DOWNLOADPANELFAKEDOWNLOADER Create a fake task from a request.
            %
            % REQUEST is the normalized struct supplied by
            % ui.DownloadPanel.DownloaderFactory.
            obj.Request = request;
            [obj.TotalBytes, obj.BytesPerSecond] = sampleProfile(request.FileName);
            if isfile(request.PartialPath)
                fileInfo = dir(request.PartialPath);
                obj.BytesReceived = min(obj.TotalBytes, fileInfo.bytes);
                obj.WrittenBytes = obj.BytesReceived;
            end
        end

        function start(obj)
            % START Begin emitting simulated progress callbacks.
            if obj.IsRunning
                return
            end
            obj.IsPaused = false;
            obj.IsRunning = true;
            obj.writePartialFile()
            if isempty(obj.Timer) || ~isvalid(obj.Timer)
                obj.Timer = timer('ExecutionMode', 'fixedRate', ...
                                  'Period', 0.1, ...
                                  'BusyMode', 'drop', ...
                                  'TimerFcn', @(~, ~) obj.tick());
            end
            start(obj.Timer)
        end

        function pause(obj)
            % PAUSE Stop progress temporarily while retaining task state.
            if ~obj.IsRunning
                return
            end
            obj.IsRunning = false;
            obj.IsPaused = true;
            stop(obj.Timer)
        end

        function resume(obj)
            % RESUME A previously paused simulated download.
            if obj.IsPaused
                start(obj)
            end
        end

        function stop(obj)
            % STOP Cancel progress without invoking completion callbacks.
            obj.IsRunning = false;
            obj.IsPaused = false;
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer)
            end
        end

        function delete(obj)
            % DELETE Stop and release the timer owned by this fake task.
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer)
                delete(obj.Timer)
            end
            obj.Timer = [];
        end
    end

    methods (Access = private)
        function tick(obj)
            % TICK Advance the fake transfer and notify the panel.
            if ~obj.IsRunning
                return
            end

            obj.BytesReceived = min(obj.TotalBytes, ...
                                    obj.BytesReceived + obj.BytesPerSecond * 0.1);
            obj.writePartialFile()
            if ~isempty(obj.ProgressFcn)
                obj.ProgressFcn(obj.BytesReceived, obj.TotalBytes)
            end

            if obj.BytesReceived >= obj.TotalBytes
                obj.finish()
            end
        end

        function writePartialFile(obj)
            % WRITEPARTIALFILE Write representative partial and chunk files.
            if ~isfolder(obj.Request.TempFolder)
                mkdir(obj.Request.TempFolder)
            end
            bytesToWrite = floor(obj.BytesReceived) - obj.WrittenBytes;
            if bytesToWrite <= 0
                return
            end

            partialPath = obj.Request.PartialPath;
            fileID = fopen(partialPath, 'ab');
            if fileID == -1
                error('ui:DownloadPanelFakeDownloader:partialOpenFailed', ...
                      'Could not create the partial file "%s".', partialPath)
            end
            cleanup = onCleanup(@() fclose(fileID));
            fwrite(fileID, zeros(1, bytesToWrite, 'uint8'), 'uint8');
            obj.WrittenBytes = obj.WrittenBytes + bytesToWrite;

            chunkPath = obj.Request.ChunkPath;
            chunkID = fopen(chunkPath, 'wb');
            if chunkID == -1
                error('ui:DownloadPanelFakeDownloader:chunkOpenFailed', ...
                      'Could not create the chunk file "%s".', chunkPath)
            end
            chunkCleanup = onCleanup(@() fclose(chunkID));
            chunkBytes = max(1, min(1024, round(obj.BytesPerSecond * 0.1)));
            fwrite(chunkID, zeros(1, chunkBytes, 'uint8'), 'uint8');
        end

        function finish(obj)
            % FINISH Publish the fake target and report completion or failure.
            obj.IsRunning = false;
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer)
            end

            if isfile(obj.Request.FinalPath)
                if strcmp(obj.Request.CollisionAction, 'overwrite')
                    delete(obj.Request.FinalPath)
                else
                    obj.fail('ui:DownloadPanelFakeDownloader:targetExists', ...
                             'The target file appeared while the download was running.')
                    return
                end
            end

            if ~isfolder(obj.Request.TargetFolder)
                mkdir(obj.Request.TargetFolder)
            end
            partialPath = obj.Request.PartialPath;
            fileID = fopen(obj.Request.FinalPath, 'wb');
            if fileID == -1
                obj.fail('ui:DownloadPanelFakeDownloader:targetUnavailable', ...
                         'Could not create the fake target file.')
                return
            end
            cleanup = onCleanup(@() fclose(fileID));
            fwrite(fileID, zeros(1, obj.TotalBytes, 'uint8'), 'uint8');
            if isfile(partialPath)
                delete(partialPath)
            end
            if isfield(obj.Request, 'ChunkPath') && isfile(obj.Request.ChunkPath)
                delete(obj.Request.ChunkPath)
            end
            if isfield(obj.Request, 'BackupPath') && isfile(obj.Request.BackupPath)
                delete(obj.Request.BackupPath)
            end

            if ~isempty(obj.CompletedFcn)
                obj.CompletedFcn(struct('FinalPath', obj.Request.FinalPath, ...
                                        'BytesReceived', obj.BytesReceived, ...
                                        'TotalBytes', obj.TotalBytes));
            end
        end

        function fail(obj, identifier, message)
            % FAIL Send a deterministic exception through ErrorFcn.
            exception = MException(identifier, message);
            if ~isempty(obj.ErrorFcn)
                obj.ErrorFcn(exception)
            end
        end
    end
end


function [totalBytes, bytesPerSecond] = sampleProfile(fileName)
% SAMPLEPROFILE Return the deterministic size and speed for a sample file.
profiles = struct(...
    'sample1_bin', [10 * 1024^2, 250 * 1024], ...
    'sample2_bin', [20 * 1024^2, 500 * 1024], ...
    'sample3_bin', [30 * 1024^2, 750 * 1024], ...
    'sample4_bin', [40 * 1024^2, 1024 * 1024]);

fieldName = matlab.lang.makeValidName(strrep(fileName, '.', '_'));
if isfield(profiles, fieldName)
    profile = profiles.(fieldName);
else
    profile = [10 * 1024^2, 250 * 1024];
end
totalBytes = profile(1);
bytesPerSecond = profile(2);
end
