classdef Elevation < handle
    
    properties
        %-----------------------------------------------------------------%
        cacheFolder
        cacheMapping = table('Size',          [0, 7],                                                           ...
                             'VariableTypes', {'cell', 'double', 'double', 'double', 'double', 'cell', 'cell'}, ...
                             'VariableNames', {'Server', 'Lat1', 'Long1', 'Lat2', 'Long2', 'File', 'Timestamp'});
    end


    properties (Access = private, Constant)
        %-----------------------------------------------------------------%
        cacheFile = 'cacheMapping.xlsx'
        URL = "https://api.open-elevation.com/api/v1/lookup?locations="
        floatTol = 1e-5
    end


    methods
        %-----------------------------------------------------------------%
        function [obj, msgWarning] = Elevation()
            obj.cacheFolder  = fullfile(ccTools.fcn.OperationSystem('programData'), 'ANATEL', 'Elevation');
            
            try                
                obj.cacheMapping = readtable(fullfile(obj.cacheFolder, obj.cacheFile));
                msgWarning = '';
            catch ME
                msgWarning = ME.message;
            end
        end

        %-----------------------------------------------------------------%
        function [wayPoints3D, msgWarning] = Get(obj, txInfo, rxInfo, nPoints, ForceSearch, Server)
            arguments
                obj
                txInfo      struct % struct('Latitude', {}, 'Longitude', {})
                rxInfo      struct % struct('Latitude', {}, 'Longitude', {})
                nPoints     uint16  {mustBeGreaterThanOrEqual(nPoints, 64), mustBeLessThanOrEqual(nPoints, 1024)} = 256
                ForceSearch logical = false
                Server      char {mustBeMember(Server, {'Open-Elevation', 'MathWorks WMS Server'})} = 'Open-Elevation'                
            end

            wayPoints2D = WayPoints2D(obj, txInfo, rxInfo, nPoints);
            if ForceSearch
                [wayPoints3D, msgWarning] = WebRequest(obj, Server, wayPoints2D);
            
            else
                wayPoints3D = checkCache(obj, wayPoints2D);
                msgWarning = '';                
                if isempty(wayPoints3D)
                    [wayPoints3D, msgWarning] = WebRequest(obj, Server, wayPoints2D);
                end
            end
        end
    end


    methods (Access = private)
        %-----------------------------------------------------------------%
        function [wayPoints3D, msgWarning] = WebRequest(obj, Server, wayPoints2D)
            wayPoints3D = [];
            
            try
                switch Server
                    case 'Open-Elevation'
                        % https://api.open-elevation.com/api/v1/lookup?locations=41.161758,-8.583933|-12.5,-38.5
                        APIRequest  = obj.URL + strjoin(string(wayPoints2D(:,1)) + "," + string(wayPoints2D(:,2)), '|');
                        APIAnswer   = webread(APIRequest, weboptions('Timeout', 10));
                
                        wayPoints3D = cell2mat(cellfun(@(x) [x.latitude, x.longitude x.elevation], APIAnswer.results, 'UniformOutput', false));
                        msgWarning  = add2Cache(obj, Server, wayPoints2D, wayPoints3D);
                
                    case 'MathWorks WMS Server'
                        WMSLayerObject = wmsfind('mathworks', 'SearchField', 'serverurl');
                        WMSLayerObject = refine(WMSLayerObject, 'elevation');
                
                        [Lat1,  Lat2]  = bounds(wayPoints2D(:,1));
                        [Long1, Long2] = bounds(wayPoints2D(:,2));
                
                        [zMatrix, zMatrixReference] = wmsread(WMSLayerObject, 'Latlim', [Lat1, Lat2], 'Lonlim', [Long1, Long2], 'ImageFormat', 'image/bil');
                        zMatrix = double(zMatrix);
                        wayPoints3D = WayPoints3D(obj, wayPoints2D, zMatrix, zMatrixReference);
                        msgWarning  = add2Cache(obj, Server, wayPoints2D, zMatrix, zMatrixReference);
                end

            catch ME
                msgWarning = ME.message;
            end
        end

        %-----------------------------------------------------------------%
        function msgWarning = add2Cache(obj, Server, wayPoints2D, varargin)
            switch Server
                case 'Open-Elevation'
                    wayPoints3D = varargin{1};
                    [Lat1, Long1, Lat2, Long2] = Bounds(obj, wayPoints2D);

                case 'MathWorks WMS Server'
                    zMatrix = varargin{1};
                    zMatrixReference = varargin{2};

                    Lat1  = zMatrixReference.LatitudeLimits(1);
                    Lat2  = zMatrixReference.LatitudeLimits(2);
                    Long1 = zMatrixReference.LongitudeLimits(1);
                    Long2 = zMatrixReference.LongitudeLimits(2);
            end

            fileFolder = fullfile(obj.cacheFolder, Server, datestr(now, 'yyyy.mm'));
            if ~isfolder(fileFolder)
                mkdir(fileFolder)
            end

            fileName = fullfile(fileFolder, [char(matlab.lang.internal.uuid()) '.mat']);            
            obj.cacheMapping(end+1, :) = {Server, Lat1, Long1, Lat2, Long2, fileName, datestr(now)};

            try
                switch Server
                    case 'Open-Elevation'
                        save(fileName, 'wayPoints3D', '-v7.3', '-nocompression')
    
                    case 'MathWorks WMS Server'
                        save(fileName, 'zMatrix', 'zMatrixReference', '-v7.3', '-nocompression')
                end
                writetable(obj.cacheMapping(end, :), fullfile(obj.cacheFolder, obj.cacheFile), 'WriteMode', 'append', 'AutoFitWidth', false);
                msgWarning = '';
            catch ME
                msgWarning = ME.message;
            end
        end

        %-----------------------------------------------------------------%
        function [Lat1, Long1, Lat2, Long2] = Bounds(obj, wayPoints2D)
            Lat1  = wayPoints2D(1,1);
            Long1 = wayPoints2D(1,2);
            Lat2  = wayPoints2D(end,1);
            Long2 = wayPoints2D(end,2);
        end

        %-----------------------------------------------------------------%
        function wayPoints3D = checkCache(obj, wayPoints2D)
            [Lat1, Long1, Lat2, Long2] = Bounds(obj, wayPoints2D);

            % A procura inicial é restrita às informações obtidas em 'Open-Elevation'.
            % Não identificando a informação requerida, procura-se no rol de
            % informações obtidas em 'MathWorks WMS Server'.
            cacheValidation1 = strcmp(obj.cacheMapping.Server, 'Open-Elevation');
            cacheValidation2 = abs(obj.cacheMapping.Lat1  - Lat1)  <= obj.floatTol & ...
                               abs(obj.cacheMapping.Lat2  - Lat2)  <= obj.floatTol & ...
                               abs(obj.cacheMapping.Long1 - Long1) <= obj.floatTol & ...
                               abs(obj.cacheMapping.Long2 - Long2) <= obj.floatTol;            
            idxCache = find(cacheValidation1 & cacheValidation2, 1);

            if isempty(idxCache)
                cacheValidation3 = obj.cacheMapping.Lat1  <= Lat1  & ...
                                   obj.cacheMapping.Lat2  >= Lat2  & ...
                                   obj.cacheMapping.Long1 <= Long1 & ...
                                   obj.cacheMapping.Long2 >= Long2;
                idxCache = find(~cacheValidation1 & cacheValidation3, 1);
            end

            wayPoints3D = [];
            if ~isempty(idxCache)
                fileName = obj.cacheMapping.File{idxCache};

                switch obj.cacheMapping.Server{idxCache}
                    case 'Open-Elevation'
                        load(fileName, 'wayPoints3D')
                        
                        nWayPoints   = height(wayPoints2D);
                        nCachePoints = height(wayPoints3D);
                        
                        if nWayPoints ~= nCachePoints
                            z  = 1:nCachePoints;
                            zq = linspace(1, nCachePoints, nWayPoints);
                            wayPoints3D = [wayPoints2D, interp1(z, wayPoints3D(:,3), zq)'];
                        end
    
                    case 'MathWorks WMS Server'
                        load(fileName, 'zMatrix', 'zMatrixReference')
                        wayPoints3D = WayPoints3D(obj, wayPoints2D, zMatrix, zMatrixReference);
                end
            end
        end

        %-----------------------------------------------------------------%
        function wayPoints2D = WayPoints2D(obj, txInfo, rxInfo, nPoints)
            wayPoints2D = gcwaypts(txInfo.Latitude, txInfo.Longitude, rxInfo.Latitude, rxInfo.Longitude, nPoints-1);
        end

        %-----------------------------------------------------------------%
        function wayPoints3D = WayPoints3D(obj, wayPoints2D, zMatrix, zMatrixReference)
            wayPoints3D = [wayPoints2D, geointerp(zMatrix, zMatrixReference, wayPoints2D(:,1), wayPoints2D(:,2), 'nearest')];
        end
    end
end