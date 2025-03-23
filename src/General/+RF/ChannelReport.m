classdef ChannelReport < handle
    
    properties
        %-----------------------------------------------------------------%
        cacheFolder
        cacheMapping = table('Size',          [0, 3],                   ...
                             'VariableTypes', {'cell', 'cell', 'cell'}, ...
                             'VariableNames', {'URL', 'File', 'Timestamp'});
    end


    properties (Access = private, Constant)
        %-----------------------------------------------------------------%
        cacheFile = 'cacheMapping.xlsx'
    end


    methods
        %-----------------------------------------------------------------%
        function [obj, msgWarning] = ChannelReport()
            obj.cacheFolder = fullfile(ccTools.fcn.OperationSystem('programData'), 'ANATEL', 'ChannelReport');
            
            try                
                obj.cacheMapping = readtable(fullfile(obj.cacheFolder, obj.cacheFile));
                msgWarning = '';
            catch ME
                msgWarning = ME.message;
            end
        end

        %-----------------------------------------------------------------%
        function [idxCache, msgError] = Get(obj, URL, operationType)
            arguments
                obj
                URL char
                operationType char {mustBeMember(operationType, {'OnlyCache', 'Cache+RealTime', 'RealTime'})}
            end

            idxCache = [];
            msgError = '';

            switch operationType
                case 'OnlyCache'
                    idxCache = CheckCache(obj, URL);

                case 'Cache+RealTime'
                    idxCache = CheckCache(obj, URL);
                    if isempty(idxCache)
                        [idxCache, msgError] = WebRequest(obj, URL);
                    end

                case 'RealTime'
                    [idxCache, msgError] = WebRequest(obj, URL);
            end
        end
    end


    methods (Access = private)
        %-----------------------------------------------------------------%
        function idxCache = CheckCache(obj, URL)
            idxCache = find(strcmp(obj.cacheMapping.URL, URL));
            
            if ~isempty(idxCache)
                % Escolhe o mais recente...
                idxCache = idxCache(end);

                if isfile(obj.cacheMapping.File{idxCache})
                    return
                end
            end
        end

        %-----------------------------------------------------------------%
        function [idxCache, msgError] = WebRequest(obj, URL)
            idxCache = [];
            msgError = '';

            try
                fileFolder = fullfile(obj.cacheFolder, datestr(now, 'yyyy.mm'));
                if ~isfolder(fileFolder)
                    mkdir(fileFolder)
                end
    
                fileName = fullfile(fileFolder, [char(matlab.lang.internal.uuid()) '.pdf']);
                websave(fileName, URL, weboptions(Timeout=30));

                idxCache = height(obj.cacheMapping)+1;
                obj.cacheMapping(idxCache, :) = {URL, fileName, datestr(now)};
                writetable(obj.cacheMapping(end,:), fullfile(obj.cacheFolder, obj.cacheFile), 'WriteMode', 'append', 'AutoFitWidth', false);
                
            catch ME   
                msgError = ME.message;
            end
        end
    end
end