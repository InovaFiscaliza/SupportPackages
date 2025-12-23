classdef Elevation < handle
    
    properties
        %-----------------------------------------------------------------%
        cacheFolder
        cacheMapping = table('Size',          [0, 8],                                                                     ...
                             'VariableTypes', {'cell', 'double', 'double', 'double', 'double', 'double', 'cell', 'cell'}, ...
                             'VariableNames', {'Server', 'Lat1', 'Long1', 'Lat2', 'Long2', 'Resolution', 'File', 'Timestamp'});
    end


    properties (Access = private, Constant)
        %-----------------------------------------------------------------%
        cacheFile    = 'cacheMapping.xlsx'
        
        URL1         = "https://api.open-elevation.com/api/v1/lookup?locations="
        URL2         = "http://rhfisnspdex02.anatel.gov.br/api/v1/lookup?locations="
        URLMaxSize   = 2048

        floatDiffTol = 1e-5
    end


    methods
        %-----------------------------------------------------------------%
        function [obj, msgWarning] = Elevation()
            obj.cacheFolder  = fullfile(appEngine.util.OperationSystem('programData'), 'ANATEL', 'Elevation');
            
            try                
                obj.cacheMapping = readtable(fullfile(obj.cacheFolder, obj.cacheFile));
                msgWarning = '';
            catch ME
                msgWarning = ME.message;
            end
        end

        %-----------------------------------------------------------------%
        function [wayPoints3D, msgWarning] = Get(obj, txObj, rxObj, nPoints, ForceSearch, Server)
            arguments
                obj
                txObj       struct % struct('Latitude', {}, 'Longitude', {})
                rxObj       struct % struct('Latitude', {}, 'Longitude', {})
                nPoints     double {mustBeInteger mustBeGreaterThanOrEqual(nPoints, 64), mustBeLessThanOrEqual(nPoints, 1024)} = 256
                ForceSearch logical = false
                Server      char {mustBeMember(Server, {'Open-Elevation', 'MathWorks WMS Server'})} = 'Open-Elevation'                
            end

            wayPoints2D = WayPoints2D(obj, txObj, rxObj, nPoints);
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
            arguments
                obj
                Server      char {mustBeMember(Server, {'Open-Elevation', 'MathWorks WMS Server'})}
                wayPoints2D
            end

            wayPoints3D = [];
            
            try
                switch Server
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

                        % Exemplos:
                        % https://api.open-elevation.com/api/v1/lookup?locations=41.161758,-8.583933|-12.5,-38.5
                        % http://rhfisnspdex02.anatel.gov.br/api/v1/lookup?locations=41.161758,-8.583933|-12.5,-38.5

                        nPoints   = height(wayPoints2D);
                        
                        strPoints = cellstr(string(wayPoints2D));
                        strPoints = strcat(strPoints(:,1), ',', strPoints(:,2));
                        
                        numURLChars    = .85 * obj.URLMaxSize - max(numel(obj.URL1), numel(obj.URL2));
                        numPointsChars = cellfun(@(x) numel(x), strPoints);
                        
                        kk = 1;
                        APIResults = {};

                        while kk <= nPoints
                            accSumNumChars     = cumsum(numPointsChars(kk:end));                            
                            numCharsValidation = find(numURLChars > accSumNumChars);                            
                            idxLastPoint       = kk + numCharsValidation(end) - 1;
                            APIBaseRequest     = strjoin(strPoints(kk:idxLastPoint), '|');

                            try
                                APIAnswer      = webread(obj.URL1 + APIBaseRequest, weboptions('Timeout', 10));
                            catch secundaryME
                                try
                                    APIAnswer  = webread(obj.URL2 + APIBaseRequest, weboptions('Timeout', 10));
                                catch
                                    rethrow(secundaryME)
                                end
                            end

                            kk = kk + numCharsValidation(end);
                            APIResults = [APIResults; APIAnswer.results];
                        end
                        APIResults     = vertcat(APIResults{:});
                
                        wayPoints3D    = cell2mat(arrayfun(@(x) [[x.latitude], [x.longitude] [x.elevation]], APIResults, 'UniformOutput', false));
                        msgWarning     = add2Cache(obj, Server, wayPoints2D, wayPoints3D);
                
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
            % O campo "Resolution" garante que será coletado em cache a informação
            % que apresente melhor resolução (no caso, o menor valor), na hipótese 
            % de ser encontrado mais de um arquivo em cache com informação do perfil 
            % de terreno do enlace sob análise.

            switch Server
                case 'Open-Elevation'
                    wayPoints3D = varargin{1};
                    [Latitude1,  ...
                     Longitude1, ...
                     Latitude2,  ...
                     Longitude2] = Bounds(obj, wayPoints2D);
                    Distance     = deg2km(distance(Latitude1, Longitude1, Latitude2, Longitude2)) * 1000;
                    Resolution   = Distance/height(wayPoints3D);

                case 'MathWorks WMS Server'
                    zMatrix     = varargin{1};
                    zMatrixReference = varargin{2};

                    Latitude1   = zMatrixReference.LatitudeLimits(1);
                    Latitude2   = zMatrixReference.LatitudeLimits(2);
                    Longitude1  = zMatrixReference.LongitudeLimits(1);
                    Longitude2  = zMatrixReference.LongitudeLimits(2);
                    
                    xDistance   = deg2km(zMatrixReference.RasterExtentInLongitude) * 1000; % Em metros
                    yDistance   = deg2km(zMatrixReference.RasterExtentInLatitude)  * 1000;
        
                    xResolution = xDistance/width(zMatrix);
                    yResolution = yDistance/height(zMatrix);

                    % Escolhe-se como valor significativo a pior resolução...
                    Resolution  = max(xResolution, yResolution);
            end            

            fileFolder = fullfile(obj.cacheFolder, Server, datestr(now, 'yyyy.mm'));
            if ~isfolder(fileFolder)
                mkdir(fileFolder)
            end

            fileName = fullfile(fileFolder, [char(matlab.lang.internal.uuid()) '.mat']);            
            obj.cacheMapping(end+1, :) = {Server, Latitude1, Longitude1, Latitude2, Longitude2, Resolution, fileName, datestr(now)};

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
            cacheValidation2 = abs(obj.cacheMapping.Lat1  - Lat1)  <= obj.floatDiffTol & ...
                               abs(obj.cacheMapping.Lat2  - Lat2)  <= obj.floatDiffTol & ...
                               abs(obj.cacheMapping.Long1 - Long1) <= obj.floatDiffTol & ...
                               abs(obj.cacheMapping.Long2 - Long2) <= obj.floatDiffTol;            
            idxCache = find(cacheValidation1 & cacheValidation2);

            if isempty(idxCache)
                cacheValidation3 = Lat1  >= obj.cacheMapping.Lat1  & ...
                                   Lat1  <= obj.cacheMapping.Lat2  & ...
                                   Lat2  >= obj.cacheMapping.Lat1  & ...
                                   Lat2  <= obj.cacheMapping.Lat2  & ...
                                   Long1 >= obj.cacheMapping.Long1 & ...
                                   Long1 <= obj.cacheMapping.Long2 & ...
                                   Long2 >= obj.cacheMapping.Long1 & ...
                                   Long2 <= obj.cacheMapping.Long2;
                idxCache = find(~cacheValidation1 & cacheValidation3);
            end

            wayPoints3D = [];
            if ~isempty(idxCache)
                if ~isscalar(idxCache)
                    [~, idxMin] = min(obj.cacheMapping.Resolution(idxCache));
                    idxCache = idxCache(idxMin);
                end

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
        function wayPoints2D = WayPoints2D(obj, txObj, rxObj, nPoints)
            wayPoints2D = gcwaypts(txObj.Latitude, txObj.Longitude, rxObj.Latitude, rxObj.Longitude, nPoints-1);
        end

        %-----------------------------------------------------------------%
        function wayPoints3D = WayPoints3D(obj, wayPoints2D, zMatrix, zMatrixReference)
            wayPoints3D = [wayPoints2D, geointerp(zMatrix, zMatrixReference, wayPoints2D(:,1), wayPoints2D(:,2), 'nearest')];
        end
    end
end