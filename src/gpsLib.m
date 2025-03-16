classdef (Abstract) gpsLib

    properties (Constant)
        apiURL       = 'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=<Latitude>&longitude=<Longitude>&localityLanguage=pt'
        apiCityToken = 'city'
        apiUnitToken = 'principalSubdivisionCode'
    end

    methods (Static = true)
        %-----------------------------------------------------------------%
        function path = path()
            path = fileparts(mfilename('fullpath'));
        end

        %-----------------------------------------------------------------%
        function [IBGE, msgError] = checkIfIBGEIsGlobal()
            global IBGE
            msgError = '';

            try
                if isempty(IBGE)
                    load(fullfile(gpsLib.path(), 'resources', 'IBGE.mat'), 'IBGE');
                end
            catch ME
                msgError = ME.message;
            end
        end

        %-----------------------------------------------------------------%
        function [cityName, Latitude, Longitude] = findCityCoordinates(cityName)
            IBGE = gpsLib.checkIfIBGEIsGlobal();
            
            idx = find(strcmpi(IBGE.City, cityName));
            if ~isempty(idx)
                cityName  = IBGE.City{idx};
                Latitude  = IBGE.Latitude(idx);
                Longitude = IBGE.Longitude(idx);
            else
                cityName      = '';
                Latitude  = [];
                Longitude = [];
            end
        end

        %-----------------------------------------------------------------%
        function [cityName, cityDistance, cityInfo] = findNearestCity(refPoint, method, varargin)
            arguments
                refPoint struct % struct('Latitude', {}, 'Longitude', {})
                method   {mustBeMember(method, {'API/IBGE', 'API', 'IBGE'})} = 'API/IBGE'
            end

            arguments (Repeating)
                varargin
            end
            
            IBGE = gpsLib.checkIfIBGEIsGlobal();
        
            switch method
                case 'API/IBGE'
                    [cityName, cityDistance, cityInfo] = gpsLib.findNearestCity(refPoint, 'API');
                
                    if isempty(cityName) || (cityDistance == -1) || isempty(cityInfo)
                        [cityName, cityDistance, cityInfo] = gpsLib.findNearestCity(refPoint, 'IBGE', cityInfo);
                    end
        
                case 'API'
                    [cityName, cityDistance, cityInfo] = gpsLib.getCityFromAPI(refPoint, IBGE);
        
                case 'IBGE'
                    cityInfo = varargin{1};
                    [cityName, cityDistance, cityInfo] = gpsLib.getCityFromIBGE(refPoint, IBGE, cityInfo);
            end
        end

        %-----------------------------------------------------------------%
        function [cityName, cityDistance, cityInfo] = getCityFromAPI(refPoint, IBGE)
            arguments
                refPoint struct % struct('Latitude', {}, 'Longitude', {})
                IBGE     table
            end

            cityName     = '';
            cityDistance = -1;
            cityInfo     = '';
        
            try
                cityInfo         = webread(replace(gpsLib.apiURL, {'<Latitude>', '<Longitude>'}, {num2str(refPoint.Latitude), num2str(refPoint.Longitude)}));
                cityInfo.source  = 'API';
        
                if ~isempty(cityInfo.(gpsLib.apiCityToken))
                    cityName     = sprintf('%s/%s', cityInfo.(gpsLib.apiCityToken), cityInfo.(gpsLib.apiUnitToken)(end-1:end));
                end
        
                idxCity = find(strcmp(IBGE.City, cityName), 1);
                if ~isempty(idxCity)
                    cityDistance = deg2km(distance(refPoint.Latitude, refPoint.Longitude, IBGE.Latitude(idxCity), IBGE.Longitude(idxCity)));
                end            
            catch
            end
        end        
        
        %-----------------------------------------------------------------%
        function [cityName, cityDistance, cityInfo] = getCityFromIBGE(refPoint, IBGE, cityInfo)
            arguments
                refPoint struct % struct('Latitude', {}, 'Longitude', {})
                IBGE     table
                cityInfo = ''
            end

            [cityDistance, ...
             idxMin]        = min(deg2km(distance(refPoint.Latitude, refPoint.Longitude, IBGE.Latitude, IBGE.Longitude)));
            cityName        = IBGE.City{idxMin};
            cityInfo.source = 'IBGE';
        end

        %-----------------------------------------------------------------%
        function gpsData = interpolation(gpsArray)
            arguments
                gpsArray (:,3) single % Status | Latitude | Longitude
            end

            gpsData   = struct('Status', 0, 'Matrix', []);
            gpsStatus = max(gpsArray(:,1));
            
            if gpsStatus > 0
                gpsData.Status = gpsStatus;
        
                idxStatusInvalid = find(gpsArray(:, 1) == 0);
                if ~isempty(idxStatusInvalid)
                    idxStatusValid = find(gpsArray(:, 1) > 0);
        
                    latArray  = interp1(idxStatusValid, gpsArray(idxStatusValid,2), idxStatusInvalid, 'linear', 'extrap');
                    longArray = interp1(idxStatusValid, gpsArray(idxStatusValid,3), idxStatusInvalid, 'linear', 'extrap');
                    gpsArray(idxStatusInvalid, 2:3) = [latArray, longArray];
                end
        
                gpsData.Matrix = gpsArray(:, 2:3);
            end
        end

        %-----------------------------------------------------------------%
        function gpsSummary = summary(gpsData)
            arguments
                gpsData struct %  struct('Status', {}, 'Latitude', {}, 'Longitude', {})
            end

            gpsSummary = struct('Status',          0, ...
                                'Count',           0, ...
                                'Latitude',       -1, ...
                                'Longitude',      -1, ...
                                'Latitude_std',   -1, ...
                                'Longitude_std',  -1, ...
                                'stdRange',       -1, ...
                                'Location',       '', ...
                                'LocationSource', '', ...
                                'Matrix',         [], ...
                                'Edited',         false);
        
            % Organizando informação de GPS proveniente de mais de um arquivo
            % (aplicável para os arquivos MAT gerados no appAnalise, por exemplo)
            % em uma única variável.
            gpsStatus = arrayfun(@(x) x.Status, gpsData);
            idxStatusValid = gpsStatus ~= 0;
            gpsMatrix = vertcat(gpsData(idxStatusValid).Matrix);
        
            % Sumarizando a informação... essa estrutura de GPS é diferente da
            % estrutura usada na v. 1.35 do appAnalise, inserindo os campos
            % "Latitude_std", "Longitude_std" e "stdRange".
            if any(gpsStatus) && ~isempty(gpsMatrix)
                gpsSummary.Status        = max(gpsStatus);
                gpsSummary.Count         = height(gpsMatrix);
                gpsSummary.Latitude      = mean(gpsMatrix(:,1));
                gpsSummary.Longitude     = mean(gpsMatrix(:,2));
                gpsSummary.Latitude_std  = std(gpsMatrix(:,1), 1);
                gpsSummary.Longitude_std = std(gpsMatrix(:,2), 1);
                gpsSummary.Matrix        = gpsMatrix;
        
                stdRange = ones(1,3);
                for kk = 1:3
                    lat_min  = gpsSummary.Latitude  - kk*gpsSummary.Latitude_std;
                    lat_max  = gpsSummary.Latitude  + kk*gpsSummary.Latitude_std;
                    long_min = gpsSummary.Longitude - kk*gpsSummary.Longitude_std;
                    long_max = gpsSummary.Longitude + kk*gpsSummary.Longitude_std;
            
                    stdRange(kk) = 100 * sum(gpsMatrix(:,1) >= lat_min  & gpsMatrix(:,1) <= lat_max ...
                                           & gpsMatrix(:,2) >= long_min & gpsMatrix(:,2) <= long_max) / height(gpsMatrix);
                end

                gpsSummary.stdRange       = stdRange;
                [cityName, ~, cityInfo]   = gpsLib.findNearestCity(gpsSummary, 'API/IBGE');
                gpsSummary.Location       = cityName;
                gpsSummary.LocationSource = cityInfo.source;
            end
        end
    end
end