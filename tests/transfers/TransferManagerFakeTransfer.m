classdef TransferManagerFakeTransfer < handle

    properties
        Request
        Direction (1,:) char = 'download'
        IsResumable (1,1) logical = true
        IsRunning (1,1) logical = false
        IsPaused (1,1) logical = false
        ProgressFcn = []
        CompletedFcn = []
        ErrorFcn = []
        AutoComplete (1,1) logical = true
    end

    methods
        function obj = TransferManagerFakeTransfer(request)
            obj.Request = request;
            obj.Direction = request.Direction;
            obj.IsResumable = strcmp(request.Direction, 'download');
            if isappdata(0, 'TransferManagerFakeTransferAutoComplete')
                obj.AutoComplete = getappdata(0, 'TransferManagerFakeTransferAutoComplete');
            end
        end

        function start(obj)
            if obj.IsRunning
                return
            end
            obj.IsRunning = true;
            if strcmp(obj.Direction, 'upload')
                sourceSize = 0;
                sourceInfo = dir(obj.Request.LocalPath);
                if isfile(obj.Request.LocalPath) && isscalar(sourceInfo) && ...
                        ~sourceInfo.isdir
                    sourceSize = double(sourceInfo.bytes);
                end
                if ~isempty(obj.ProgressFcn)
                    obj.ProgressFcn(sourceSize, sourceSize)
                end
                obj.IsRunning = false;
                if ~isempty(obj.CompletedFcn)
                    obj.CompletedFcn(struct('LocalPath', obj.Request.LocalPath, ...
                                            'TransferredBytes', sourceSize, ...
                                            'TotalBytes', sourceSize));
                end
                return
            end
            if ~isempty(obj.ProgressFcn)
                obj.ProgressFcn(10, 20)
            end
            if ~obj.AutoComplete
                fileID = fopen(obj.Request.PartialPath, 'wb');
                if fileID ~= -1
                    fclose(fileID);
                end
                return
            end
            localFolder = fileparts(obj.Request.LocalPath);
            if ~isfolder(localFolder)
                mkdir(localFolder)
            end
            fileID = fopen(obj.Request.LocalPath, 'wb');
            if fileID == -1
                error('tests:TransferManagerFakeTransfer:targetUnavailable', ...
                      'Could not create the target file.')
            end
            cleanup = onCleanup(@() fclose(fileID));
            fwrite(fileID, zeros(1, 20, 'uint8'), 'uint8');
            obj.IsRunning = false;
            if ~isempty(obj.CompletedFcn)
                obj.CompletedFcn(struct('LocalPath', obj.Request.LocalPath, ...
                                        'TransferredBytes', 20, ...
                                        'TotalBytes', 20));
            end
        end

        function pause(obj)
            obj.IsPaused = true;
            obj.IsRunning = false;
        end

        function resume(obj)
            obj.IsPaused = false;
            obj.start()
        end

        function stop(obj)
            obj.IsRunning = false;
            obj.IsPaused = false;
        end
    end
end
