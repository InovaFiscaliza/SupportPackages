classdef TransferPanelFakeTransfer < handle

    % TRANSFERPANELFAKETRANSFER Deterministic transfer test double.
    %
    % This class implements the downloader protocol required by
    % ui.TransferPanel. It uses a timer to emit progress. Downloads write
    % simulated partial data and publish a fake target; uploads report
    % progress without modifying the source file. It invokes the configured
    % completion or error callback and never performs network I/O.

    properties
        Request
        Direction (1,:) char = 'download'
        IsResumable (1,1) logical = true
        TransferredBytes (1,1) double = 0
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
        ResolvedProtocol (1,:) char = ''
        Timer = []
    end

    methods
        function obj = TransferPanelFakeTransfer(request)
            % TRANSFERPANELFAKETRANSFER Create a fake task from a request.
            %
            % REQUEST is the normalized struct supplied by
            % ui.TransferPanel.TransferFactory.
            obj.Request = request;
            obj.Direction = request.Direction;
            if strcmp(request.Direction, 'upload')
                obj.ResolvedProtocol = request.ResolvedProtocol;
                if isempty(obj.ResolvedProtocol)
                    obj.ResolvedProtocol = request.Protocol;
                    if strcmp(obj.ResolvedProtocol, 'auto')
                        if strcmp(request.Method, 'PUT')
                            obj.ResolvedProtocol = 'raw';
                        else
                            obj.ResolvedProtocol = 'multipart';
                        end
                    end
                end
                obj.IsResumable = strcmp(obj.ResolvedProtocol, 'tus');
            else
                obj.IsResumable = true;
            end
            [obj.TotalBytes, obj.BytesPerSecond] = sampleProfile(request.FileName);
            if strcmp(request.Direction, 'upload')
                fileInfo = dir(request.LocalPath);
                obj.TotalBytes = double(fileInfo.bytes);
            elseif isfile(request.PartialPath)
                fileInfo = dir(request.PartialPath);
                obj.TransferredBytes = min(obj.TotalBytes, fileInfo.bytes);
                obj.WrittenBytes = obj.TransferredBytes;
            end
        end

        function sourceInfo = prepare(obj)
            % PREPARE Publish deterministic transfer metadata to the manager.
            sourceInfo = struct('IsResumable', obj.IsResumable);
            if strcmp(obj.Direction, 'upload')
                sourceInfo.ResolvedProtocol = obj.ResolvedProtocol;
                sourceInfo.UploadURL = obj.Request.UploadURL;
                sourceInfo.UploadOffset = obj.Request.UploadOffset;
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
            % PAUSE Stop resumable progress temporarily while retaining task state.
            if ~obj.IsRunning || ~obj.IsResumable
                return
            end
            obj.IsRunning = false;
            obj.IsPaused = true;
            stop(obj.Timer)
        end

        function resume(obj)
            % RESUME A previously paused simulated transfer.
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

            obj.TransferredBytes = min(obj.TotalBytes, ...
                                       obj.TransferredBytes + obj.BytesPerSecond * 0.1);
            obj.writePartialFile()
            if ~isempty(obj.ProgressFcn)
                obj.ProgressFcn(obj.TransferredBytes, obj.TotalBytes)
            end

            if obj.TransferredBytes >= obj.TotalBytes
                obj.finish()
            end
        end

        function writePartialFile(obj)
            % WRITEPARTIALFILE Write representative partial and chunk files.
            if strcmp(obj.Direction, 'upload')
                return
            end
            if ~isfolder(obj.Request.TempFolder)
                mkdir(obj.Request.TempFolder)
            end
            bytesToWrite = floor(obj.TransferredBytes) - obj.WrittenBytes;
            if bytesToWrite <= 0
                return
            end

            partialPath = obj.Request.PartialPath;
            fileID = fopen(partialPath, 'ab');
            if fileID == -1
                error('ui:TransferPanelFakeTransfer:partialOpenFailed', ...
                      'Could not create the partial file "%s".', partialPath)
            end
            cleanup = onCleanup(@() fclose(fileID));
            fwrite(fileID, zeros(1, bytesToWrite, 'uint8'), 'uint8');
            obj.WrittenBytes = obj.WrittenBytes + bytesToWrite;

            chunkPath = obj.Request.ChunkPath;
            chunkID = fopen(chunkPath, 'wb');
            if chunkID == -1
                error('ui:TransferPanelFakeTransfer:chunkOpenFailed', ...
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

            if isfield(obj.Request, 'SimulateFailure') && obj.Request.SimulateFailure
                obj.fail('ui:TransferPanelFakeTransfer:simulatedFailure', ...
                         'Falha simulada para o harness do painel.')
                return
            end

            if strcmp(obj.Direction, 'upload')
                if ~isempty(obj.CompletedFcn)
                    obj.CompletedFcn(struct('LocalPath', obj.Request.LocalPath, ...
                                            'TransferredBytes', obj.TransferredBytes, ...
                                            'TotalBytes', obj.TotalBytes));
                end
                return
            end

            if isfile(obj.Request.LocalPath)
                if strcmp(obj.Request.CollisionAction, 'overwrite')
                    delete(obj.Request.LocalPath)
                else
                    obj.fail('ui:TransferPanelFakeTransfer:targetExists', ...
                             'O arquivo de destino apareceu durante o download.')
                    return
                end
            end

            localFolder = fileparts(obj.Request.LocalPath);
            if ~isfolder(localFolder)
                mkdir(localFolder)
            end
            partialPath = obj.Request.PartialPath;
            fileID = fopen(obj.Request.LocalPath, 'wb');
            if fileID == -1
                obj.fail('ui:TransferPanelFakeTransfer:targetUnavailable', ...
                         'Não foi possível criar o arquivo de destino simulado.')
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
                obj.CompletedFcn(struct('LocalPath', obj.Request.LocalPath, ...
                                        'TransferredBytes', obj.TransferredBytes, ...
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
    'sample4_bin', [40 * 1024^2, 1024 * 1024], ...
    'sample_failed_bin', [256 * 1024, 1024 * 1024], ...
    'sample_cancel_bin', [2 * 1024^2, 1024 * 1024], ...
    'sample_existing_bin', [256 * 1024, 1024 * 1024], ...
    'sample_partial_bin', [256 * 1024, 1024 * 1024]);

fieldName = matlab.lang.makeValidName(strrep(fileName, '.', '_'));
if isfield(profiles, fieldName)
    profile = profiles.(fieldName);
else
    profile = [10 * 1024^2, 250 * 1024];
end
totalBytes = profile(1);
bytesPerSecond = profile(2);
end
