classdef Elevation < handle
    
    properties
        %-----------------------------------------------------------------%
        CacheFolder
        CacheIndex = table( ...
            'Size', [0, 8], ...
            'VariableTypes', {'cell', 'double', 'double', 'double', 'double', 'double', 'cell', 'cell'}, ...
            'VariableNames', {'Server', 'Lat1', 'Long1', 'Lat2', 'Long2', 'Resolution', 'File', 'Timestamp'} ...
        )
    end


    properties (Access = private)
        %-----------------------------------------------------------------%
        Endpoints = struct( ...
            'openElevation', struct('url', "https://api.open-elevation.com/api/v1/lookup",     'apiKey', ""), ...
            'openMeteo',     struct('url', "https://api.open-meteo.com/v1/elevation",          'apiKey', ""), ...
            'anatel',        struct('url', "http://rhfisnspdex02.anatel.gov.br/api/v1/lookup", 'apiKey', "")  ...
        )
    end


    properties (Access = private, Constant)
        %-----------------------------------------------------------------%
        CACHE_INDEX_FILE = 'cacheMapping.xlsx'
        URL_MAX_LENGTH   = 2048
        COORD_TOLERANCE  = 1e-5
    end


    methods
        %-----------------------------------------------------------------%
        function [obj, warningMsg] = Elevation()
            obj.CacheFolder = fullfile(appEngine.util.OperationSystem('programData'), 'ANATEL', 'Elevation');
            
            try                
                obj.CacheIndex = readtable(fullfile(obj.CacheFolder, obj.CACHE_INDEX_FILE));
                warningMsg = '';
            catch ME
                warningMsg = ME.message;
            end
        end

        %-----------------------------------------------------------------%
        function [path3D, warningMsg] = Get(obj, txObj, rxObj, nPoints, forceSearch, server)
            arguments
                obj
                txObj       struct % struct('Latitude', {}, 'Longitude', {})
                rxObj       struct % struct('Latitude', {}, 'Longitude', {})
                nPoints     double {mustBeInteger mustBeGreaterThanOrEqual(nPoints, 64), mustBeLessThanOrEqual(nPoints, 1024)} = 256
                forceSearch logical = false
                server      char {mustBeMember(server, {'Open-Elevation', 'MathWorks WMS Server'})} = 'Open-Elevation'                
            end

            path2D = ComputeWaypoints(obj, txObj, rxObj, nPoints);
            if forceSearch
                [path3D, warningMsg] = FetchElevation(obj, server, path2D);
            
            else
                path3D = LookupCache(obj, path2D);
                warningMsg = '';                
                if isempty(path3D)
                    [path3D, warningMsg] = FetchElevation(obj, server, path2D);
                end
            end
        end

        %-----------------------------------------------------------------%
        function isCached = IsCached(obj, txObj, rxObj, nPoints)
            path2D = ComputeWaypoints(obj, txObj, rxObj, nPoints);
            [lat1, lon1, lat2, lon2] = PathBounds(obj, path2D);

            isCached = any( ...
                strcmp(obj.CacheIndex.Server, 'Open-Elevation')          & ...
                abs(obj.CacheIndex.Lat1  - lat1) <= obj.COORD_TOLERANCE  & ...
                abs(obj.CacheIndex.Lat2  - lat2) <= obj.COORD_TOLERANCE  & ...
                abs(obj.CacheIndex.Long1 - lon1) <= obj.COORD_TOLERANCE  & ...
                abs(obj.CacheIndex.Long2 - lon2) <= obj.COORD_TOLERANCE    ...
            );
        end
    end


    methods (Access = private)
        %-----------------------------------------------------------------%
        function [path3D, warningMsg] = FetchElevation(obj, server, path2D)
            arguments
                obj
                server  char {mustBeMember(server, {'Open-Elevation', 'MathWorks WMS Server'})}
                path2D
            end

            path3D = [];

            try
                switch server
                    case 'Open-Elevation'
                        % Uma alternativa ao Open-Elevation é serviço implantado
                        % na ANATEL, o qual possui as seguintes limitações:
                        % - Elevação apenas do território nacional;
                        % - Usuário precisa estar na rede interna, ou logado
                        %   através da VPN.

                        % Outra limitação é o tamanho da URL, o qual é limitado
                        % em 2048 caracteres. Para diminuir ainda mais o risco,
                        % aplica-se um fator de 85% a esse limite, de forma
                        % que as requisições terão no máximo cerca de 1740
                        % caracteres.

                        % Em 01/05/2026, a API Open-Elevation apresentou latência 
                        % de 1 a 4 s por requisição, enquanto a Open-Meteo apresentou 
                        % aproximadamente 200 ms. Portanto, utiliza-se a Open-Meteo 
                        % como fonte primária dos dados de elevação, com Open-Elevation 
                        % e ANATEL como fallback, nessa ordem.

                        % Exemplos:
                        % https://api.open-elevation.com/api/v1/lookup?locations=41.161758,-8.583933|-12.5,-38.5
                        % http://rhfisnspdex02.anatel.gov.br/api/v1/lookup?locations=41.161758,-8.583933|-12.5,-38.5
                        % https://api.open-meteo.com/v1/elevation?latitude=52.52,48.85,40.71&longitude=13.41,2.35,-74.01
                        
                        nPoints = height(path2D);
                        maxBatchChars = fix(.85 * obj.URL_MAX_LENGTH - strlength(obj.Endpoints.openElevation.url));
                        pointCharCount = strlength(string(path2D(:,1))) + strlength(string(path2D(:,2))) + 2;

                        batchStart = 1;
                        allElevations = [];

                        while batchStart <= nPoints
                            cumCharCount = cumsum(pointCharCount(batchStart:end));
                            fittingIdx = find(maxBatchChars > cumCharCount);
                            lastIdx = batchStart + fittingIdx(end) - 1;

                            batchLat = path2D(batchStart:lastIdx, 1);
                            batchLon = path2D(batchStart:lastIdx, 2);

                            for endPoint = ["openMeteo", "openElevation", "anatel"]
                                elevations = [];

                                try
                                    apiResponse = webread(BuildRequestUrl(obj, endPoint, batchLat, batchLon), weboptions('Timeout', 5));
                                    switch endPoint
                                        case {"openElevation", "anatel"}
                                            elevations = cellfun(@(x) x.elevation, apiResponse.results);
                                        case "openMeteo"
                                            elevations = apiResponse.elevation;    
                                    end

                                    if isnumeric(elevations) && (numel(elevations) == lastIdx-batchStart+1)
                                        break
                                    end

                                catch
                                end
                            end

                            allElevations = [allElevations; elevations];
                            batchStart = lastIdx + 1;
                        end

                        path3D = [path2D, allElevations];
                        warningMsg = SaveToCache(obj, server, path2D, path3D);

                    case 'MathWorks WMS Server'
                        wmsLayer = wmsfind('mathworks', 'SearchField', 'serverurl');
                        wmsLayer = refine(wmsLayer, 'elevation');

                        [lat1, lat2] = bounds(path2D(:,1));
                        [lng1, lng2] = bounds(path2D(:,2));

                        [zMatrix, zMatrixReference] = wmsread(wmsLayer, 'Latlim', [lat1, lat2], 'Lonlim', [lng1, lng2], 'ImageFormat', 'image/bil');
                        zMatrix = double(zMatrix);
                        
                        path3D = InterpolateElevation(obj, path2D, zMatrix, zMatrixReference);
                        warningMsg = SaveToCache(obj, server, path2D, zMatrix, zMatrixReference);
                end

            catch ME
                warningMsg = ME.identifier;
            end
        end

        %-----------------------------------------------------------------%
        function requestUrl = BuildRequestUrl(obj, endpointName, latitudes, longitudes)
            % Monta a URL de requisição para o endpoint e lote de pontos...
            endPoint = obj.Endpoints.(endpointName);

            switch endpointName
                case {'openElevation', 'anatel'}
                    requestUrl = endPoint.url + "?locations=" + strjoin(string(latitudes) + "," + string(longitudes), '|');
                    if strlength(endPoint.apiKey) > 0
                        requestUrl = requestUrl + "&key=" + endPoint.apiKey;
                    end

                case 'openMeteo'
                    requestUrl = endPoint.url + "?latitude=" + strjoin(string(latitudes),  ',') + "&longitude=" + strjoin(string(longitudes), ',');
                    if strlength(endPoint.apiKey) > 0
                        requestUrl = requestUrl + "&apikey=" + endPoint.apiKey;
                    end
            end
        end

        %-----------------------------------------------------------------%
        function warningMsg = SaveToCache(obj, server, path2D, varargin)
            % O campo "Resolution" garante que será coletado em cache a informação
            % que apresente melhor resolução (no caso, o menor valor), na hipótese 
            % de ser encontrado mais de um arquivo em cache com informação do perfil 
            % de terreno do enlace sob análise.

            switch server
                case 'Open-Elevation'
                    wayPoints3D = varargin{1};
                    [lat1, lng1, lat2, lng2] = PathBounds(obj, path2D);
                    pathDistance = deg2km(distance(lat1, lng1, lat2, lng2)) * 1000;
                    resolution = pathDistance / height(wayPoints3D);

                case 'MathWorks WMS Server'
                    zMatrix = varargin{1};
                    zMatrixReference = varargin{2};

                    lat1 = zMatrixReference.LatitudeLimits(1);
                    lat2 = zMatrixReference.LatitudeLimits(2);
                    lng1 = zMatrixReference.LongitudeLimits(1);
                    lng2 = zMatrixReference.LongitudeLimits(2);
                    
                    xDist = deg2km(zMatrixReference.RasterExtentInLongitude) * 1000; % Em metros
                    yDist = deg2km(zMatrixReference.RasterExtentInLatitude)  * 1000;
        
                    xRes = xDist / width(zMatrix);
                    yRes = yDist / height(zMatrix);

                    % Escolhe-se como valor significativo a pior resolução...
                    resolution = max(xRes, yRes);
            end            

            fileFolder = fullfile(obj.CacheFolder, server, datestr(now, 'yyyy.mm'));
            if ~isfolder(fileFolder)
                mkdir(fileFolder)
            end

            fileName = fullfile(fileFolder, [char(matlab.lang.internal.uuid()) '.mat']);            
            obj.CacheIndex(end+1, :) = {server, lat1, lng1, lat2, lng2, resolution, fileName, datestr(now)};

            try
                switch server
                    case 'Open-Elevation'
                        save(fileName, 'wayPoints3D', '-v7.3', '-nocompression')
    
                    case 'MathWorks WMS Server'
                        save(fileName, 'zMatrix', 'zMatrixReference', '-v7.3', '-nocompression')
                end
                writetable(obj.CacheIndex(end, :), fullfile(obj.CacheFolder, obj.CACHE_INDEX_FILE), 'WriteMode', 'append', 'AutoFitWidth', false);
                warningMsg = '';
            catch ME
                warningMsg = ME.message;
            end
        end

        %-----------------------------------------------------------------%
        function [lat1, lon1, lat2, lon2] = PathBounds(~, path2D)
            lat1 = path2D(1,   1);
            lon1 = path2D(1,   2);
            lat2 = path2D(end, 1);
            lon2 = path2D(end, 2);
        end

        %-----------------------------------------------------------------%
        function wayPoints3D = LookupCache(obj, path2D)
            [lat1, lng1, lat2, lng2] = PathBounds(obj, path2D);

            % A procura inicial é restrita às informações obtidas em 'Open-Elevation'.
            % Não identificando a informação requerida, procura-se no rol de
            % informações obtidas em 'MathWorks WMS Server'.
            isOpenElev    = strcmp(obj.CacheIndex.Server, 'Open-Elevation');
            matchesBounds = abs(obj.CacheIndex.Lat1  - lat1) <= obj.COORD_TOLERANCE & ...
                            abs(obj.CacheIndex.Lat2  - lat2) <= obj.COORD_TOLERANCE & ...
                            abs(obj.CacheIndex.Long1 - lng1) <= obj.COORD_TOLERANCE & ...
                            abs(obj.CacheIndex.Long2 - lng2) <= obj.COORD_TOLERANCE;
            cacheIdx = find(isOpenElev & matchesBounds);

            if isempty(cacheIdx)
                containsBounds = lat1 >= obj.CacheIndex.Lat1  & ...
                                 lat1 <= obj.CacheIndex.Lat2  & ...
                                 lat2 >= obj.CacheIndex.Lat1  & ...
                                 lat2 <= obj.CacheIndex.Lat2  & ...
                                 lng1 >= obj.CacheIndex.Long1 & ...
                                 lng1 <= obj.CacheIndex.Long2 & ...
                                 lng2 >= obj.CacheIndex.Long1 & ...
                                 lng2 <= obj.CacheIndex.Long2;
                cacheIdx = find(~isOpenElev & containsBounds);
            end

            wayPoints3D = [];
            if ~isempty(cacheIdx)
                if ~isscalar(cacheIdx)
                    [~, bestIdx] = min(obj.CacheIndex.Resolution(cacheIdx));
                    cacheIdx = cacheIdx(bestIdx);
                end

                fileName = obj.CacheIndex.File{cacheIdx};
                
                try
                    switch obj.CacheIndex.Server{cacheIdx}
                        case 'Open-Elevation'
                            load(fileName, 'wayPoints3D')
                            
                            nRequested = height(path2D);
                            nCached = height(wayPoints3D);
                            
                            if nRequested ~= nCached
                                z = 1:nCached;
                                zq = linspace(1, nCached, nRequested);
                                wayPoints3D = [path2D, interp1(z, wayPoints3D(:,3), zq)'];
                            end
        
                        case 'MathWorks WMS Server'
                            load(fileName, 'zMatrix', 'zMatrixReference')
                            wayPoints3D = InterpolateElevation(obj, path2D, zMatrix, zMatrixReference);
                    end
                catch
                end
            end
        end

        %-----------------------------------------------------------------%
        function path2D = ComputeWaypoints(~, txObj, rxObj, nPoints)
            path2D = gcwaypts(txObj.Latitude, txObj.Longitude, rxObj.Latitude, rxObj.Longitude, nPoints-1);
        end

        %-----------------------------------------------------------------%
        function path3D = InterpolateElevation(~, path2D, zMatrix, zMatrixReference)
            path3D = [path2D, geointerp(zMatrix, zMatrixReference, path2D(:,1), path2D(:,2), 'nearest')];
        end
    end
end