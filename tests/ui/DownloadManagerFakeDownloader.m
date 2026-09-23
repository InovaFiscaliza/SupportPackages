classdef DownloadManagerFakeDownloader < handle

    properties
        Request
        IsRunning (1,1) logical = false
        IsPaused (1,1) logical = false
        ProgressFcn = []
        CompletedFcn = []
        ErrorFcn = []
        AutoComplete (1,1) logical = true
    end

    methods
        function obj = DownloadManagerFakeDownloader(request)
            obj.Request = request;
            if isappdata(0, 'DownloadManagerFakeDownloaderAutoComplete')
                obj.AutoComplete = getappdata(0, 'DownloadManagerFakeDownloaderAutoComplete');
            end
        end

        function start(obj)
            if obj.IsRunning
                return
            end
            obj.IsRunning = true;
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
            if ~isfolder(obj.Request.TargetFolder)
                mkdir(obj.Request.TargetFolder)
            end
            fileID = fopen(obj.Request.FinalPath, 'wb');
            if fileID == -1
                error('tests:DownloadManagerFakeDownloader:targetUnavailable', ...
                      'Could not create the target file.')
            end
            cleanup = onCleanup(@() fclose(fileID));
            fwrite(fileID, zeros(1, 20, 'uint8'), 'uint8');
            obj.IsRunning = false;
            if ~isempty(obj.CompletedFcn)
                obj.CompletedFcn(struct('FinalPath', obj.Request.FinalPath, ...
                                        'BytesReceived', 20, ...
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
