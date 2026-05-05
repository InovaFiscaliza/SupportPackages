classdef (Abstract) Geolocation

    % ## RF.Geolocation ##
    %   ├── aoA
    %   │   │── extractSpectralData
    %   │   │── createGeographicBins
    %   │   └── filterTriangulationPoints
    %   ├── poA
    %   │   │── createGeographicBins
    %   │   └── estimateLocationViaPowerOfArrival
    %   ├── extractSpectralData
    %   ├── createGeographicBins
    %   ├── filterTriangulationPoints
    %   ├── estimateLocationViaPowerOfArrival
    %   ├── runTest
    %   ├── buildReferenceData
    %   ├── computeTriangulationResults
    %   └── drawResults

    methods (Static = true)
        %-----------------------------------------------------------------%
        function [estimatedLatitude, estimatedLongitude, uncertaintyRadius] = aoA(specData, frequencyCenterMHz, bandWidthkHz, localizationParams)
            arguments    
                specData = []
                frequencyCenterMHz = 10
                bandWidthkHz = 10
                localizationParams = struct( ...
                    'confidenceThreshold', 80, ... 
                    'powerStandardDeviationFactor', 0.2, ... % número de desvios padrões  
                    'binSizeMeters', 10, ...
                    'maximumAzimuthStandardDeviation', 4, ...
                    'minimumPointsPerBin', 1 ...
                )
            end
            
            [powerLevel, azimuthAngle, confidenceLevel] = RF.Geolocation.extractSpectralData(specData, frequencyCenterMHz, bandWidthkHz);

            % Centro do canal em análise 
            channelCenter = round(height(powerLevel)/2);

            % Georeferenciamento das varreduras e Data Binning...
            [specRawTable, specBinTable] = RF.Geolocation.createGeographicBins(specData, frequencyCenterMHz, bandWidthkHz, localizationParams);

            % Função que encontra os indices dos pontos utilizados na
            % triangulação
            selectedMeasurementIndices = RF.Geolocation.filterTriangulationPoints(specBinTable, localizationParams, powerLevel, confidenceLevel, azimuthAngle);

            % Suavizando dados de AZIMUTES e recuperando apenas pontos
            % escolhidos (selectedMeasurementIndices)
            % Número de pontos = fração dos pontos amostrados  ou 50 - Testar o
            % timeStamp
            carHeadVector = min(50,ceil(size(powerLevel,2)/100));
            azMeasCenter =smoothdata(azimuthAngle(channelCenter,1:end-carHeadVector),'rloes',10)';
            angMaxPwr = azMeasCenter(selectedMeasurementIndices);
            
            % % Cálculo do eixo do carro:
            vehicleHeadingAngle = azimuth(specRawTable.Latitude(1:end-carHeadVector),specRawTable.Longitude(1:end-carHeadVector), ...
                specRawTable.Latitude(carHeadVector + 1:end),specRawTable.Longitude(carHeadVector + 1:end));

            % CORRIGIR AZIMUTES RECUPERADOS (selectedMeasurementIndices) CONFORME EIXO DO CARRO:
            angMaxPwr = mod(vehicleHeadingAngle(selectedMeasurementIndices) + angMaxPwr, 360);
        
            % Transferindo referência de Norte para Leste e sentido horário para
            % anti-horário conforme utilizado na função triangulateLOS
            AoA = mod(90 - angMaxPwr, 360);

            
            %%% TRIANGULANDO.....%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

            %transformar coordenadas geograficas da tabela specRawTable em coordenadas cartesianas:
            origin = [specRawTable.Latitude(1), specRawTable.Longitude(1), 0];
            [xpos, ypos] = grn2eqa(specRawTable.Latitude(selectedMeasurementIndices),specRawTable.Longitude(selectedMeasurementIndices), origin);
            zpos = zeros(height(xpos),1);

            detectionSetDT = cell(1,height(selectedMeasurementIndices)); % Initialize an empty array for object detections

            for indx = 1 : height(selectedMeasurementIndices) %height(az)%
                mp = struct('Frame','Spherical', ...
                    'OriginPosition',[xpos(indx), ypos(indx), zpos(indx)], ...
                    'OriginVelocity',zeros(1,3), ...
                    'Orientation', eye(3), ...
                    'HasAzimuth', true, ...
                    'HasElevation', true, ...
                    'HasRange', false, ...
                    'HasVelocity', false, ...
                    'IsParentToChild', true);
                detectionDT = objectDetection(indx, [AoA(indx);0], 'MeasurementNoise',0.01*eye(2),...
                    'SensorIndex', indx, 'MeasurementParameters', mp);

                detectionSetDT{indx} = detectionDT; % Append the detection to the set
            end

            % Triangular o emissor:
            [estPos,~] = triangulateLOS(detectionSetDT');
            
            % reverter as coordenadas cartesianas do emissor para coordenadas
            % geograficas:
            [estimatedLatitude, estimatedLongitude] = eqa2grn(estPos(1), estPos(2), origin);

            %%%% CALCULANDO O RAIO DO ERRO
            tx = txsite(Name="Triangulado", ...
                Latitude=estimatedLatitude, ...
                Longitude=estimatedLongitude);
            rx = rxsite(Name="Medidas", ...
                Latitude=specRawTable.Latitude(selectedMeasurementIndices), ...
                Longitude=specRawTable.Longitude(selectedMeasurementIndices));
            distanceToSource = distance(tx,rx);
            
            radiusScaleFactor = 20;
            minimumRadiusMeters = 50;
            confidenceWeightRadians = ((100 - confidenceLevel(channelCenter,selectedMeasurementIndices)').*(AoA)/100)*pi/180;

            % E = raizQuadrada{[Sum[i=1 a n](dist_i*Sigma_i)^2]/n^2)
            % distanceToSource: Distância entre a fonte estimada e o ponto de medição (metros).
            % Sigma: Desvio padrão do azimute do ponto em radianos (grau de confiança: ).
            % n: Número de pontos de medição.
        
            uncertaintyRadius = max(radiusScaleFactor*sqrt(sum((distanceToSource.*confidenceWeightRadians).^2)/(height(selectedMeasurementIndices)).^2), minimumRadiusMeters);
        end


        %-----------------------------------------------------------------%
        function [estimatedLatitude, estimatedLongitude, uncertaintyRadius] = poA(specData, frequencyCenterMHz, bandWidthKHz, localizationParams)
            % ...
            arguments
                specData = []
                frequencyCenterMHz = 10
                bandWidthKHz = 10
                localizationParams = struct( ...
                    'confidenceThreshold', 80, ... 
                    'powerStandardDeviationFactor', 0.2, ... % número de desvios padrões  
                    'binSizeMeters', 10, ...
                    'maximumAzimuthStandardDeviation', 4, ...
                    'minimumPointsPerBin', 1 ...
                )
            end

            % Georeferenciamento das varreduras e Data Binning...
            specRawTable = RF.Geolocation.createGeographicBins(specData, frequencyCenterMHz, bandWidthKHz, localizationParams);

            % Função que encontra os indices dos pontos utilizados na
            % triangulação
            [estimatedLatitude, estimatedLongitude, uncertaintyRadius] = RF.Geolocation.estimateLocationViaPowerOfArrival(specRawTable);
        end  


        %-----------------------------------------------------------------%
        function [powerLevel, azimuthValue, confidenceLevel] = extractSpectralData(specData, frequencyCenterMHz, bandWidthKHz)
            % Calcula potência do canal por varredura, mas a função espera que seja
            % passado "chLimits", com os limites em "Hertz" do canal.
            channelFrequencyHertz = frequencyCenterMHz * 1e+6; % MHz >> Hertz
            chBandWidth_Hertz = bandWidthKHz * 1e+3; % kHz >> Hertz
            idx = 1;
            
            chInferiorLimit   = channelFrequencyHertz - chBandWidth_Hertz/2; 
            chSuperiorLimit   = channelFrequencyHertz + chBandWidth_Hertz/2; 
            
            chLimits = [chInferiorLimit, chSuperiorLimit];
            chLimits(1) = max(chLimits(1), specData(idx).MetaData.FreqStart);
            chLimits(2) = min(chLimits(2), specData(idx).MetaData.FreqStop);
            
            aCoef  = (specData(idx).MetaData.FreqStop - specData(idx).MetaData.FreqStart) ./ (specData(idx).MetaData.DataPoints - 1);
            bCoef  = specData(idx).MetaData.FreqStart - aCoef;   
            idx1 = round((chLimits(1) - bCoef)/aCoef);
            idx2 = round((chLimits(2) - bCoef)/aCoef);
            levelData = specData(idx).Data{2};

            azimuthValue = [];
            confidenceLevel = [];
            if numel(specData(idx).Data)>3
                yData = specData(idx).Data{4};
                zData =specData(idx).Data{5};
                azimuthValue = double(yData(idx1:idx2,:)); 
                confidenceLevel = double(zData(idx1:idx2,:)); 
            end
            powerLevel = double(levelData(idx1:idx2,:));
        end


        %---------------------------------------------------------------%
        function [specRawTable, specBinTable] = createGeographicBins(specData, frequencyCenterMHz, bandWidthKHz, localizationParams)
            % Georeferenciamento das varreduras e Data Binning...
            chEmission = struct( ...
                'Frequency', frequencyCenterMHz, ...
                'ChannelBW', bandWidthKHz);
            specRawTable = RF.DataBinning.RawTableCreation(specData, 1, chEmission);
            
            % Data binning para agrupar pontos do teste em quadrículas
            [specRawTable,      ...
             ~, ...
             specBinTable,      ...
             ~,       ...
             tool_FilterSummary.UserData] = RF.DataBinning.execute(specRawTable, localizationParams.binSizeMeters, 'max');
        end


        %-----------------------------------------------------------------%
        function selectedMeasurementIndices = filterTriangulationPoints(specBinTable, localizationParams, powerLevel, confidenceLevel, azimuthAngle)
            % Função que encontra os indices dos pontos utilizados na
            % triangulação do Aoa
            arguments 
                specBinTable = []
                localizationParams = []
                powerLevel = []
                confidenceLevel = []
                azimuthAngle = []
            end

            % Aplicando os filtros:
            binIndices = repelem((1:height(specBinTable))', specBinTable.Measures);
     
            % Centro do canal em análise 
            channelCenter = round(height(powerLevel)/2);
            
            % indices nos quais a confiança reportada é menor que o threshold
            % confFilter são retirados
            lowConfidenceMask = confidenceLevel(channelCenter,1:end) < localizationParams.confidenceThreshold;
            
            powerWithHighConfidence = powerLevel(channelCenter,:);
            powerWithHighConfidence(lowConfidenceMask) = 0;

            grouping = @(x){x};
            powerByBin = splitapply(grouping,powerWithHighConfidence',binIndices);

            % transformações e smooth dos Az somete para os conjutos sem nenhuma medida
            % com confiança abaixo do threshold (ex. 80%);
            % Filtrar pontos a serem triangulados por ordem de maior potência recebida,
            % usando Desvio Padrão (ou outras medidas) para determinar quantos pontos serão
            % utilizados automaticamente
            smoothFunc = @(x){smoothdata(x,'rloes',10)};
            center = azimuthAngle(channelCenter,1:end);
            azMeasCenter = splitapply(smoothFunc,center',binIndices);
            
            % substituir por um cellarray
            for index = 1:height(powerByBin)
                isValidPoint = logical(powerByBin{index});
                powerByBin{index} = powerByBin{index}(isValidPoint);
                azMeasCenter{index} = azMeasCenter{index}(isValidPoint);
            end
            
            % Calcular desvio padrão de azimute por bin (variabilidade angular)
            azimuthStandardDeviation = cellfun(@std,azMeasCenter);
            % Contar número de medições por bin
            binMeasurementCount = cellfun(@height,powerByBin,'UniformOutput',false);

            % Dividir pontos por região geográfica (20 grupos)
            % Segmentar dados em 20 regiões para análise local de potência máxima
            groupSize = floor(height(powerWithHighConfidence')/20);
            potGroups = reshape(powerWithHighConfidence(1:20*(groupSize)),groupSize,[]);

            % Identificar os 10% maiores grupos de potência em cada região
            nSelectedGroups = floor(height(potGroups)/10);
            [~, ind] = maxk(potGroups,nSelectedGroups);
            % Calcular média das potências máximas para normalização
            maxPotGroups = mean(maxk(potGroups,nSelectedGroups));
            % Selecionar os 10 grupos com maior potência média
            [~,linearIndices] = maxk(maxPotGroups,10);

            % Aplicar filtro de potência mínima baseado em desvio padrão
            % Limiar = máxima potência - (fator × desvio padrão)
            % Isto garante apenas pontos com potência significativa
            minLevel = max(maxPotGroups(1,linearIndices))- ...
                        localizationParams.powerStandardDeviationFactor*std(maxPotGroups(1,linearIndices));
            % Manter apenas índices acima do limiar
            index = linearIndices(maxPotGroups(1,linearIndices) > minLevel);
            % Converter índices de grupo 2D para índices lineares 1D
            selectedMeasurementIndices = (index-1)*floor(height(powerWithHighConfidence')/20)+ind(:,index);
            selectedMeasurementIndices = reshape(selectedMeasurementIndices,[],1);

            % Filtro final: validar qualidade de medição por bin
            % Manter pontos onde:
            % 1) Desvio de azimute < máximo permitido (robustez angular)
            % 2) Número de pontos no bin > mínimo (confiabilidade estatística)
            selectedMeasurementIndices = selectedMeasurementIndices( ...
                (azimuthStandardDeviation(binIndices(selectedMeasurementIndices)) < localizationParams.maximumAzimuthStandardDeviation) & ...
                (cell2mat(binMeasurementCount(binIndices(selectedMeasurementIndices))) > localizationParams.minimumPointsPerBin));
        end


        %----------------------------------------------------------------%
        function [estimatedLatitude, estimatedLongitude, uncertaintyRadius] = estimateLocationViaPowerOfArrival(specRawTable)
            % Retorna lat, long e raio calculados do emissor para a
            % triangulação via PoA

            distanceToleranceMeters = 450; % threshold em torno da curva que delimita pontos a serem triangulados
            rssiPercentileArray = 5:3:26; % percentual de pontos a serem utilizados no fit da curva dist X Pot
            latEmissor = zeros(height(rssiPercentileArray'),1);
            longEmissor = zeros(height(rssiPercentileArray'),1);
            
            minimumReceivedPowerThreshold = min(100, prctile(specRawTable.ChannelPower, 99));

            pathLossConstant = 600; % constante livre da curva dist X Pot
            
            for ind = 1 : height(rssiPercentileArray')
                % selecionando os 'ind' max valores de potência recebida
                [maxValues, maxValuesIdxs] = maxk(specRawTable.ChannelPower, ceil((rssiPercentileArray(ind)/100)*height(specRawTable.ChannelPower)));
                
                % Filtrando rssi mínimo recebido
                maxValuesIdxs = maxValuesIdxs(maxValues > minimumReceivedPowerThreshold);
               
                if height(maxValues) < 3
                    % testa se todos os pontos max são maiores que o limite pré-estabelecido (minimumReceivedPowerThreshold)
                    %  - reduzir o limite mínimo para maxValue (para contemplar emissores de
                    % menor potência);
                    minimumReceivedPowerThreshold = minimumReceivedPowerThreshold - 5;
                    %  - atualizar valores de linear Indices
                    %  - reduzir o "pathLossConstant" da curva (dist X power) para ajustar à nova realidade
                    pathLossConstant = pathLossConstant - 30;
                    continue

                else
                    % 1. Triangular ORIGEM PARA OS MaxValues calculados
                    pot = specRawTable.ChannelPower(maxValuesIdxs);
                    distAferida = 10.^7.2*exp(-0.115*pot)+pathLossConstant;
                    latMax = specRawTable.Latitude(maxValuesIdxs);
                    longMax = specRawTable.Longitude(maxValuesIdxs);

                    [xpos,ypos,~] = matlab.deg2utm(latMax, longMax);
                    txPosition = [xpos';ypos'];
                    rxPosition = matlab.blePositionEstimate(txPosition,"lateration", ... 
                    distAferida');

                    % 2. Calcular distância de todos valores medidos no DT
                    % (specRawTable.Latitude e specRawTable.Longitude), para a fonte
                    % calculada em 1
                    [lat_reverted, lon_reverted] = matlab.utm2deg(rxPosition(1), rxPosition(2), '24 L'); 
                    tx = txsite(Name="Medido", ...
                        Latitude=specRawTable.Latitude, ...
                        Longitude=specRawTable.Longitude);
                    rx = rxsite(Name="Triangulado", ...
                        Latitude=lat_reverted, ...
                        Longitude=lon_reverted);
                    distEmissorParcial = distance(tx,rx);

                    % 3. Filtrar pontos para todos valores de potência que se enquadre em "distAferida =  10.^7.2*exp(-0.115*x) + pathLossConstant" +/- Threshold     
                    distAferidaTotal =  10.^7.2*exp(-0.115*specRawTable.ChannelPower)+pathLossConstant;
                    selectedMeasurementIndices = (distAferidaTotal>(distEmissorParcial'-distanceToleranceMeters))&(distAferidaTotal<(distEmissorParcial'+distanceToleranceMeters));

                    % 4. Se menos de 3 pontos foram filtrados,
                    % volte paro o for loop para rejustar
                    % parâmetros da curva
                    if sum(selectedMeasurementIndices) < 3
                        continue
                    end
                end

                latMax = specRawTable.Latitude(selectedMeasurementIndices>0);
                longMax = specRawTable.Longitude(selectedMeasurementIndices>0);
            
                [xpos,ypos,~] = matlab.deg2utm(latMax, longMax);
                txPosition = [xpos';ypos'];

                pot2 = specRawTable.ChannelPower(selectedMeasurementIndices>0);
                distAferida =  10.^7.2*exp(-0.115*pot2)+pathLossConstant;

                localizationMethod = "lateration";

                % Triangulação

                rxPosition = matlab.blePositionEstimate(txPosition,localizationMethod, ... 
                    distAferida');
            
                [lat_reverted, lon_reverted] = matlab.utm2deg(rxPosition(1), rxPosition(2), '24 L'); 
                latEmissor(ind) = lat_reverted;
                longEmissor(ind) = lon_reverted;
            end
            
            latEmissor = latEmissor(~(latEmissor==0));
            medLat = median(latEmissor);
            stdLat = std(latEmissor);
            locLat = (latEmissor > (medLat + 1.0*stdLat))|(latEmissor < (medLat - 1.0*stdLat));
            longEmissor = longEmissor(~(longEmissor==0));
            medLong = median(longEmissor);
            stdLong = std(longEmissor);
            locLong = (longEmissor > (medLong + 1.0*stdLong))|(longEmissor < (medLong - 1.0*stdLong));   
            
            [~, IndOut] = rmoutliers(latEmissor, OutlierLocations=(locLong|locLat));
            
            % Conversão para desenho de círculo de erro
            estimatedLatitude = median(latEmissor(~IndOut));
            estimatedLongitude = median(longEmissor(~IndOut));
            stdLat = std(latEmissor(~IndOut));
            stdLong = std(longEmissor(~IndOut));
            uncertaintyRadius = (stdLat + stdLong) * 111000;
        end


        %-----------------------------------------------------------------%
        function triangulationResults = runTest(method, testName, knownEmitterCoordinates, flagSaveTable, varargin)
            arguments
                method {mustBeMember(method, {'aoa', 'poa', 'both'})}
                testName {mustBeMember(testName, {'ViaAppAnalise', 'ViaPrompt'})}
                knownEmitterCoordinates = []
                flagSaveTable = 1
            end

            arguments (Repeating)
                varargin
            end

            switch testName
                case 'ViaAppAnalise'
                    specData = varargin{1};

                case 'ViaPrompt'
                    fileName = varargin{1};
                    specData = read(model.SpecData.empty, fileName, 'SingleFile');
            end

            [referenceData, nEmitters] = RF.Geolocation.buildReferenceData(specData, knownEmitterCoordinates);

            if strcmp(method, 'both')
                aoaResults = RF.Geolocation.computeTriangulationResults(specData, 'aoa', referenceData, nEmitters, flagSaveTable);
                poaResults = RF.Geolocation.computeTriangulationResults(specData, 'poa', referenceData, nEmitters, flagSaveTable);
                triangulationResults = struct('aoa', aoaResults, 'poa', poaResults);
            else
                triangulationResults = RF.Geolocation.computeTriangulationResults( ...
                    specData, method, referenceData, nEmitters, flagSaveTable);
            end
        end


        %-----------------------------------------------------------------%
        function [referenceData, nEmitters] = buildReferenceData(specData, knownEmitterCoordinates)
            if isempty(knownEmitterCoordinates)
                specData.UserData(1).ReportInclude = false;
                basicStats(specData)
                computeOccupancyPerBin(specData)

                if isempty(specData.UserData.Emissions)
                    [newIndex, newFreq, newBW_MHz, Method] = util.Detection.findPeaksPlusOCC(specData);
                    idx = 1;
                    channelObj = class.ChannelLib('appAnalise');
                    update(specData(idx), 'UserData:Emissions', 'Add', newIndex, newFreq, newBW_MHz*1000, Method, [], channelObj)
                end

                emissionsTable = specData(1).UserData.Emissions;
                classifications = emissionsTable.Classification;

                validMask = arrayfun(@(classification) ...
                    classification.AutoSuggested.Station > -1, classifications);

                if any(validMask)
                    validSuggestions = [classifications(validMask).AutoSuggested];
                    detections = [ ...
                        [validSuggestions.Latitude]', ...
                        [validSuggestions.Longitude]', ...
                        round(emissionsTable.Frequency(validMask), 1)];
                else
                    detections = zeros(0, 3);
                end

                nEmitters = size(detections, 1);
                referenceData = table();
                referenceData.FrequencyCenterMHz = detections(:,3);
                referenceData.BandWidthKHz = 200 * ones(nEmitters,1);
                referenceData.RealLatitude = detections(:,1);
                referenceData.RealLongitude = detections(:,2);
                referenceData.StationId = strcat("Emitter_", string((1:nEmitters)'));

            else
                if istable(knownEmitterCoordinates)
                    referenceData = knownEmitterCoordinates;
                else
                    referenceData = struct2table(knownEmitterCoordinates);
                end

                if ~ismember('FrequencyCenterMHz', referenceData.Properties.VariableNames)
                    referenceData.FrequencyCenterMHz = referenceData.FreqCenter;
                end

                if ~ismember('BandWidthKHz', referenceData.Properties.VariableNames)
                    referenceData.BandWidthKHz = referenceData.BW;
                end

                if ~ismember('RealLatitude', referenceData.Properties.VariableNames)
                    referenceData.RealLatitude = referenceData.Latitude;
                end

                if ~ismember('RealLongitude', referenceData.Properties.VariableNames)
                    referenceData.RealLongitude = referenceData.Longitude;
                end

                if ~ismember('StationId', referenceData.Properties.VariableNames)
                    referenceData.StationId = strcat("Emitter_", string((1:height(referenceData))'));
                end

                nEmitters = height(referenceData);
            end
        end


        %-----------------------------------------------------------------%
        function triangulationResults = computeTriangulationResults(specData, method, referenceData, nEmitters, flagSaveTable)

            triangulatedLatitude = zeros(nEmitters, 1);
            triangulatedLongitude = zeros(nEmitters, 1);
            triangulatedRadius = zeros(nEmitters, 1);
            triangulationError = zeros(nEmitters, 1);

            for emitterIndex = 1:nEmitters
                frequencyCenterMHz = referenceData.FrequencyCenterMHz(emitterIndex);
                bandWidthKHz = referenceData.BandWidthKHz(emitterIndex);

                switch method
                    case 'aoa'
                        [triangulatedLatitude(emitterIndex), triangulatedLongitude(emitterIndex), triangulatedRadius(emitterIndex)] = ...
                            RF.Geolocation.aoA(specData, frequencyCenterMHz, bandWidthKHz);

                    case 'poa'
                        [triangulatedLatitude(emitterIndex), triangulatedLongitude(emitterIndex), triangulatedRadius(emitterIndex)] = ...
                            RF.Geolocation.poA(specData, frequencyCenterMHz, bandWidthKHz);
                end

                % Validar se a triangulação retornou coordenadas válidas
                if isnan(triangulatedLatitude(emitterIndex)) || isnan(triangulatedLongitude(emitterIndex)) || ...
                   triangulatedLatitude(emitterIndex) < -90 || triangulatedLatitude(emitterIndex) > 90 || ...
                   triangulatedLongitude(emitterIndex) < -180 || triangulatedLongitude(emitterIndex) > 180
                    warning('Geolocation:InvalidTriangulation', ...
                        'Triangulation for emitter %s (%.1f MHz) resulted in invalid coordinates [Lat: %.2f, Lon: %.2f]', ...
                        referenceData.StationId{emitterIndex}, frequencyCenterMHz, ...
                        triangulatedLatitude(emitterIndex), triangulatedLongitude(emitterIndex));
                    triangulationError(emitterIndex) = NaN;
                else

                    estimatedSite = txsite(Name="Estimado", ...
                        Latitude=triangulatedLatitude(emitterIndex), ...
                        Longitude=triangulatedLongitude(emitterIndex));
                    realSite = rxsite(Name="Real", ...
                        Latitude=referenceData.RealLatitude(emitterIndex), ...
                        Longitude=referenceData.RealLongitude(emitterIndex));

                    triangulationError(emitterIndex) = distance(estimatedSite, realSite);
                end
            end

            triangulationResults = table( ...
                repmat(string(method), nEmitters, 1), ...
                string(referenceData.StationId), ...
                referenceData.FrequencyCenterMHz, ...
                referenceData.BandWidthKHz, ...
                referenceData.RealLatitude, ...
                referenceData.RealLongitude, ...
                triangulatedLatitude, ...
                triangulatedLongitude, ...
                triangulatedRadius, ...
                triangulationError, ...
                'VariableNames', { ...
                'Method', ...
                'StationId', ...
                'FrequencyCenterMHz', ...
                'BandWidthKHz', ...
                'RealLatitude', ...
                'RealLongitude', ...
                'TriangulatedLatitude', ...
                'TriangulatedLongitude', ...
                'TriangulatedRadius', ...
                'ErrorMeters'});

            if flagSaveTable
                writetable(triangulationResults, string(method) + "Table.xlsx");
            end
        end


        %-----------------------------------------------------------------%
        function drawResults(axesHandle, varargin)
            if ~isempty(axesHandle)
                estimatedLatitude = varargin{1};
                estimatedLongitude = varargin{2};
                uncertaintyRadius = max(0.01, varargin{3});

                delete(findobj(axesHandle.Children, 'Tag', 'estimatedEmissorLocation'))

                % [circleLatitudes, circleLongitudes] = scircle1(estimatedLatitude, estimatedLongitude, uncertaintyRadius);
                % geoplot(axesHandle, circleLatitudes, circleLongitudes, 'Color', '#ffffff', 'LineWidth', 1, 'LineStyle', ':', 'Tag', 'estimatedEmissorLocation');

                images.roi.Circle(axesHandle, 'Center', [estimatedLatitude, estimatedLongitude], 'Radius', 0.1, 'LineWidth', 1, 'Deletable', 0, 'FaceSelectable', 0, 'Color', 'red', 'Tag', 'estimatedEmissorLocation');
                geoplot(axesHandle, estimatedLatitude, estimatedLongitude, '^', 'Color', '#ffffff', 'LineWidth', 2.5, 'MarkerSize', 12, 'MarkerFaceColor', '#ffffff', 'Tag', 'estimatedEmissorLocation');
                geolimits(axesHandle, 'auto')

            else
                triangulationResults = varargin{1};

                f = uifigure;
                axesHandle = geoaxes(f);
                hold (axesHandle,'on');

                nResults = height(triangulationResults);
    
                % Cores diferentes para cada emissão
                colors = hsv(nResults);
    
                for resultIdx = 1:nResults
                    realLat = triangulationResults.RealLatitude(resultIdx);
                    realLon = triangulationResults.RealLongitude(resultIdx);
                    triangLat = triangulationResults.TriangulatedLatitude(resultIdx);
                    triangLon = triangulationResults.TriangulatedLongitude(resultIdx);
                    errorMeters = triangulationResults.ErrorMeters(resultIdx);
                    triangulatedRadius = triangulationResults.TriangulatedRadius(resultIdx);
                    stationId = triangulationResults.StationId{(resultIdx)};
    
                    % 1. Plotar ponto real (cruz)
                    geoplot(axesHandle, realLat, realLon, '+', ...
                        'Color', colors(resultIdx,:), 'LineWidth', 2.5, 'MarkerSize', 10);
                    text(axesHandle,  realLat, realLon, sprintf('%s', stationId), ...
                        'FontSize', 9, 'Color', colors(resultIdx,:));
    
                    % 2. Plotar ponto triangulado (triangulo)
                    geoplot(axesHandle, triangLat, triangLon, '^', ...
                        'Color', colors(resultIdx,:), 'LineWidth', 2, 'MarkerSize', 12);
                    midLat = (realLat + triangLat) / 2;
                    midLon = (realLon + triangLon) / 2;
                    text(axesHandle, midLat, midLon, sprintf(' %.2f m',errorMeters), ...
                        'FontSize', 8, 'Color', colors(resultIdx,:));
    
                    % 3. Traçar linha entre ponto real e triangulado
                    geoplot(axesHandle, [realLat, triangLat], [realLon, triangLon], '-', ...
                        'Color', colors(resultIdx,:), 'LineWidth', 1.5, 'DisplayName', ...
                        sprintf('Error: %.2f m', errorMeters));
    
                    % 4. Desenhar círculo de incerteza (raio = erro estimado)
                    if triangulatedRadius > 0
                        [circleLatitudes, circleLongitudes] = scircle1(triangLat, triangLon, triangulatedRadius/111000);
                        geoplot(axesHandle, circleLatitudes, circleLongitudes, 'Color', colors(resultIdx,:), ...
                            'LineWidth', 1, 'LineStyle', ':', 'DisplayName', ...
                            sprintf('Estimated Radius: %.2f m', triangulatedRadius));
                    end
                end
            end
        end
    end

end