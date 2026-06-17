classdef Location < handle
    
    properties
        %-----------------------------------------------------------------%
        CacheFolder
        CacheIndex = table( ...
            'Size', [0, 6], ...
            'VariableTypes', {'cell', 'double', 'double', 'cell', 'cell', 'cell'}, ...
            'VariableNames', {'Server', 'Latitude', 'Longitude', 'City', 'Response', 'Timestamp'} ...
        )
    end


    properties (Access = private)
        %-----------------------------------------------------------------%
        Endpoints = struct( ...
            'bigdatacloud', struct('url', "https://api.bigdatacloud.net/data/reverse-geocode-client", 'apiKey', "") ...
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
        function [obj, warningMsg] = Location()
            obj.CacheFolder = fullfile(appEngine.util.OperationSystem('programData'), 'ANATEL', 'Location');

            if ~isfolder(obj.CacheFolder)
                mkdir(obj.CacheFolder)
            end
            
            try                
                obj.CacheIndex = readtable(fullfile(obj.CacheFolder, obj.CACHE_INDEX_FILE));
                warningMsg = '';
            catch ME
                warningMsg = ME.message;
            end
        end

        %-----------------------------------------------------------------%
        function [city, warningMsg] = Get(obj, point, forceSearch, server)
            arguments
                obj
                point struct % struct('Latitude', {}, 'Longitude', {})
                forceSearch logical = false
                server char {mustBeMember(server, {'bigdatacloud'})} = 'bigdatacloud'
            end

            lat = point.Latitude;
            lng = point.Longitude;

            if forceSearch
                [city, warningMsg] = FetchLocation(obj, server, lat, lng);
            
            else
                city = LookupCache(obj, lat, lng);
                warningMsg = '';                
                if isempty(city)
                    [city, warningMsg] = FetchLocation(obj, server, lat, lng);
                end
            end
        end

        %-----------------------------------------------------------------%
        function isCached = IsCached(obj, lat, lng)
            isCached = any( ...
                abs(obj.CacheIndex.Latitude  - lat) <= obj.COORD_TOLERANCE  & ...
                abs(obj.CacheIndex.Longitude - lng) <= obj.COORD_TOLERANCE ...
            );
        end
    end


    methods (Access = private)
        %-----------------------------------------------------------------%
        function [city, warningMsg] = FetchLocation(obj, server, lat, lng)
            arguments
                obj
                server char {mustBeMember(server, {'bigdatacloud'})}
                lat
                lng
            end

            IBGE = gpsLib.checkIfIBGEIsGlobal();
            city = '';

            try
                switch server
                    case 'bigdatacloud'
                        cityInfo = webread(BuildRequestUrl(obj, server, lat, lng));

                        cityOptions = {};
                        if isstruct(cityInfo) 
                            if all(isfield(cityInfo, {'city', 'principalSubdivisionCode'})) && ~isempty(cityInfo.city) && ~isempty(cityInfo.principalSubdivisionCode)
                                cityOptions{end+1} = sprintf('%s/%s', cityInfo.city, cityInfo.principalSubdivisionCode(end-1:end));
                            end

                            if all(isfield(cityInfo, {'locality', 'principalSubdivisionCode'})) && ~isempty(cityInfo.locality) && ~isempty(cityInfo.principalSubdivisionCode)
                                cityOptions{end+1} = sprintf('%s/%s', cityInfo.locality, cityInfo.principalSubdivisionCode(end-1:end));
                            end
                        end

                        cityIdx = find(ismember(cityOptions, IBGE.City), 1);
                        if ~isempty(cityIdx)
                            city = cityOptions{cityIdx};
                        end

                        warningMsg = SaveToCache(obj, server, lat, lng, cityInfo, city);

                    otherwise
                        % ToDo
                        % Identificar e implementar outros serviços que entregam 
                        % informações da localidade a partir das suas coordenadas.
                end

            catch ME
                warningMsg = ME.identifier;
            end
        end

        %-----------------------------------------------------------------%
        function requestUrl = BuildRequestUrl(obj, endpointName, lat, lng)
            % Monta a URL de requisição para o endpoint e lote de pontos...
            endPoint = obj.Endpoints.(endpointName);

            switch endpointName
                case 'bigdatacloud'
                    requestUrl = endPoint.url + "?latitude=" + string(lat) + "&longitude=" + string(lng) + "&localityLanguage=pt";
                    if strlength(endPoint.apiKey) > 0
                        requestUrl = requestUrl + "&key=" + endPoint.apiKey;
                    end

                otherwise
                    % ...
            end
        end

        %-----------------------------------------------------------------%
        function warningMsg = SaveToCache(obj, server, lat, lng, cityInfo, city)
            obj.CacheIndex(end+1, :) = {server, lat, lng, city, jsonencode(cityInfo), datestr(now)};

            try
                writetable(obj.CacheIndex(end, :), fullfile(obj.CacheFolder, obj.CACHE_INDEX_FILE), 'WriteMode', 'append', 'AutoFitWidth', false);
                warningMsg = '';
            catch ME
                warningMsg = ME.message;
            end
        end

        %-----------------------------------------------------------------%
        function city = LookupCache(obj, lat, lng)
            cacheIdx = find( ...
                abs(obj.CacheIndex.Latitude  - lat) <= obj.COORD_TOLERANCE  & ...
                abs(obj.CacheIndex.Longitude - lng) <= obj.COORD_TOLERANCE, 1 ...
            );

            if isempty(cacheIdx)
                city = '';
            else
                city = obj.CacheIndex.City{cacheIdx};
            end
        end
    end
end