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
    %   │   ├── buildReferenceData
    %   │   └── computeTriangulationResults
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

            % Linha correspondente à frequência central do canal (powerLevel tem
            % uma linha por bin de frequência e uma coluna por varredura).
            chFreqCenterIdx = round(height(powerLevel)/2);

            % Georreferencia as varreduras e agrupa os pontos em quadrículas (data binning).
            [specRawTable, specBinTable] = RF.Geolocation.createGeographicBins(specData, frequencyCenterMHz, bandWidthkHz, localizationParams);

            % Seleciona os índices das medidas usadas na triangulação
            % (filtragem por potência, confiança e dispersão de azimute).
            selectedMeasurementIndices = RF.Geolocation.filterTriangulationPoints(specBinTable, localizationParams, powerLevel, confidenceLevel, azimuthAngle);

            % Passo (em nº de amostras) usado adiante para estimar a proa do
            % veículo: 1% das varreduras, limitado a 50.
            carHeadVector = min(50, ceil(width(powerLevel)/100));

            % Suaviza a série de azimutes da frequência central (regressão local
            % robusta) e retém apenas os pontos escolhidos para a triangulação.
            azMeasCenter = smoothdata(azimuthAngle(chFreqCenterIdx, :), 'rloes', 10)';
            angMaxPwr = azMeasCenter(selectedMeasurementIndices);
            
            % Cálculo da proa (eixo longitudinal) do veículo:
            % O heading é estimado como o azimute entre a posição da amostra i
            % e a posição carHeadVector amostras à frente. Isso gera apenas
            % (N - carHeadVector) valores; as últimas carHeadVector posições — 
            % que não possuem ponto "à frente" — recebem o último heading válido.
            vehicleHeadingAngle = zeros(height(specRawTable), 1);
            vehicleHeadingAngle(1:end-carHeadVector) = azimuth( ...
                specRawTable.Latitude(1:end-carHeadVector), ...
                specRawTable.Longitude(1:end-carHeadVector), ...
                specRawTable.Latitude(carHeadVector+1:end), ...
                specRawTable.Longitude(carHeadVector+1:end) ...
            );
            vehicleHeadingAngle(end-carHeadVector+1:end) = vehicleHeadingAngle(end-carHeadVector);

            % Converte o azimute medido (relativo ao eixo do veículo) em azimute
            % absoluto referenciado ao Norte, somando a proa do carro em cada
            % ponto selecionado. Isso é válido se e somente se o azimuthAngle é 
            % medido RELATIVO ao eixo longitudinal do veículo (proa = 0°).
            angMaxPwr = mod(vehicleHeadingAngle(selectedMeasurementIndices) + angMaxPwr, 360);
        
            % Converte de rumo (horário a partir do Norte) para ângulo matemático
            % (anti-horário a partir do Leste), convenção esperada por triangulateLOS.
            AoA = mod(90 - angMaxPwr, 360);
            
            % Converte as coordenadas geográficas dos pontos selecionados em
            % coordenadas cartesianas (projeção equal-area), usando a 1ª medida
            % como origem do referencial.
            origin = [specRawTable.Latitude(1), specRawTable.Longitude(1), 0];
            [xpos, ypos] = grn2eqa(specRawTable.Latitude(selectedMeasurementIndices), specRawTable.Longitude(selectedMeasurementIndices), origin);
            zpos = zeros(height(xpos),1);

            % Conjunto de detecções (uma por ponto de medida) para o triangulador.
            detectionSetDT = cell(1,height(selectedMeasurementIndices));

            for indx = 1:height(selectedMeasurementIndices)
                mp = struct( ...
                    'Frame','Spherical', ...
                    'OriginPosition',[xpos(indx), ypos(indx), zpos(indx)], ...
                    'OriginVelocity',zeros(1,3), ...
                    'Orientation', eye(3), ...
                    'HasAzimuth', true, ...
                    'HasElevation', true, ...
                    'HasRange', false, ...
                    'HasVelocity', false, ...
                    'IsParentToChild', true ...
                );

                detectionDT = objectDetection(indx, [AoA(indx); 0], 'MeasurementNoise',0.01*eye(2), 'SensorIndex', indx, 'MeasurementParameters', mp);
                detectionSetDT{indx} = detectionDT; % adiciona a detecção ao conjunto
            end

            % Triangula a posição do emissor a partir das linhas de visada (LOS).
            [estPos,~] = triangulateLOS(detectionSetDT');
            
            % Reverte as coordenadas cartesianas do emissor para coordenadas
            % geográficas (lat/lon).
            [estimatedLatitude, estimatedLongitude] = eqa2grn(estPos(1), estPos(2), origin);

            % CÁLCULO DO RAIO DE INCERTEZA (abordagem por GDOP geométrico).
            % Cria os sites de Tx (emissor triangulado) e Rx (pontos medidos)
            % e obtém a distância de cada medida ao emissor estimado.
            tx = txsite(Name="Triangulado", ...
                Latitude=estimatedLatitude, ...
                Longitude=estimatedLongitude);
            rx = rxsite(Name="Medidas", ...
                Latitude=specRawTable.Latitude(selectedMeasurementIndices), ...
                Longitude=specRawTable.Longitude(selectedMeasurementIndices));
            distanceToSource = distance(tx,rx);

            % Matriz de direção dos azimutes: cada linha é [cos(θ), sin(θ)].
            AoA_rad = AoA * pi / 180;
            A = [cos(AoA_rad), sin(AoA_rad)];

            % GDOP = sqrt(trace(inv(A'*A))): mede a degradação geométrica
            % (valor alto → pontos quase colineares → estimativa instável).
            AtA = A' * A;
            if rcond(AtA) > 1e-10
                gdop = sqrt(trace(inv(AtA)));
            else
                gdop = 10; % geometria degenerada: usar valor conservador
            end

            % Modelo conservador baseado na covariância angular e na distância máxima.
            % Captura a propagação do erro angular até o ponto mais distante
            % (onde a alavancagem — e portanto o erro de posição — é maior).
            maxDistanceToSource = max(distanceToSource);
            
            % Desvio angular: usa a amplitude (max-min) da confiança como proxy.
            % Normalizar pela amplitude evita subestimar o erro quando o
            % confidenceLevel varia numa faixa estreita (ex.: 70-95%).
            confidenceLevelLocal = confidenceLevel(chFreqCenterIdx, selectedMeasurementIndices)';
            confidenceRange = max(confidenceLevelLocal) - min(confidenceLevelLocal) + 1;  % +1 evita divisão por 0
            
            % σ_az_max = (100 / amplitude_confiança) × π/180 [rad].
            % Quanto menor a variação de confiança, menos informação temos e,
            % portanto, maior o erro angular assumido.
            sigmaAzimuthMax = (100.0 / confidenceRange) * (pi/180);  % radianos
            
            % O GDOP já captura a geometria; aqui propagamos para a distância cartesiana:
            %   R = GDOP × d_max × σ_az × fator_escala_não_linear
            % O fator empírico absorve não-linearidades da triangulação.
            nonlinearScaleFactor = 25;
            
            % Raio final saturado no intervalo [300, 1000] metros.
            uncertaintyRadius = min(max(gdop * maxDistanceToSource * sigmaAzimuthMax * nonlinearScaleFactor, 300), 1000);
        end


        %-----------------------------------------------------------------%
        function [estimatedLatitude, estimatedLongitude, uncertaintyRadius] = poA(specData, frequencyCenterMHz, bandWidthKHz, localizationParams)
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

            % Transformando dBm em dBuV
            if strcmp(specData.MetaData.LevelUnit,'dBm')
                specRawTable.ChannelPower = specRawTable.ChannelPower + 107;
            end
            % Função que encontra os indices dos pontos utilizados na
            % triangulação
            [estimatedLatitude, estimatedLongitude, uncertaintyRadius] = RF.Geolocation.estimateLocationViaPowerOfArrival(specRawTable);
        end  


        %-----------------------------------------------------------------%
        function [powerLevel, azimuthValue, confidenceLevel] = extractSpectralData(specData, frequencyCenterMHz, bandWidthKHz)
            % Calcula potência do canal por varredura, mas a função espera que seja
            % passado "chLimits", com os limites em "Hertz" do canal.
            chFrequencyHertz = frequencyCenterMHz * 1e+6; % MHz >> Hertz
            chBandWidthHertz = bandWidthKHz * 1e+3; % kHz >> Hertz
            
            chInferiorLimit = chFrequencyHertz - chBandWidthHertz/2; 
            chSuperiorLimit = chFrequencyHertz + chBandWidthHertz/2; 
            
            chLimits = [chInferiorLimit, chSuperiorLimit];
            chLimits(1) = max(chLimits(1), specData.MetaData.FreqStart);
            chLimits(2) = min(chLimits(2), specData.MetaData.FreqStop);
            
            aCoef = (specData.MetaData.FreqStop - specData.MetaData.FreqStart) ./ (specData.MetaData.DataPoints - 1);
            bCoef = specData.MetaData.FreqStart - aCoef;
            idx1 = round((chLimits(1) - bCoef)/aCoef);
            idx2 = round((chLimits(2) - bCoef)/aCoef);
            
            powerLevel = double(specData.Data{2}(idx1:idx2, :));

            azimuthValue = [];
            confidenceLevel = [];
            if numel(specData.Data) > 3
                azimuthValue = double(specData.Data{4}(idx1:idx2, :)); 
                confidenceLevel = double(specData.Data{5}(idx1:idx2, :)); 
            end            
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
            chFreqCenterIdx = round(height(powerLevel)/2);
            
            % indices nos quais a confiança reportada é menor que o threshold
            % confFilter são retirados
            lowConfidenceMask = confidenceLevel(chFreqCenterIdx, :) < localizationParams.confidenceThreshold;
            
            powerWithHighConfidence = powerLevel(chFreqCenterIdx, :);
            powerWithHighConfidence(lowConfidenceMask) = 0;

            grouping = @(x){x};
            powerByBin = splitapply(grouping,powerWithHighConfidence',binIndices);

            % transformações e smooth dos Az somete para os conjutos sem nenhuma medida
            % com confiança abaixo do threshold (ex. 80%);
            % Filtrar pontos a serem triangulados por ordem de maior potência recebida,
            % usando Desvio Padrão (ou outras medidas) para determinar quantos pontos serão
            % utilizados automaticamente
            smoothFunc = @(x){smoothdata(x, 'rloes', 10)};
            center = azimuthAngle(chFreqCenterIdx, :);
            azMeasCenter = splitapply(smoothFunc, center', binIndices);
            
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
            minLevel = max(maxPotGroups(1, linearIndices)) - localizationParams.powerStandardDeviationFactor * std(maxPotGroups(1,linearIndices));
            
            % Manter apenas índices acima do limiar
            index = linearIndices(maxPotGroups(1,linearIndices) > minLevel);
            
            % Converter índices de grupo 2D para índices lineares 1D
            selectedMeasurementIndices = (index-1)*floor(height(powerWithHighConfidence')/20)+ind(:,index);
            selectedMeasurementIndices = reshape(selectedMeasurementIndices,[],1);

            % Filtro final: validar qualidade de medição por bin
            % Manter pontos onde:
            % 1) Desvio de azimute < máximo permitido (robustez angular)
            % 2) Número de pontos no bin > mínimo (confiabilidade estatística)
            %
            % triangulateLOS exige ao menos 2 detecções, portanto a função
            % garante o retorno de no mínimo 2 índices.
            minimumRequiredPoints = 2;
            candidateMeasurementIndices = selectedMeasurementIndices;

            % Se a seleção por potência não produziu candidatos suficientes,
            % usar como fallback os pontos de maior potência (com confiança
            % acima do limiar).
            if numel(candidateMeasurementIndices) < minimumRequiredPoints
                [~, powerRankedIndices] = sort(powerWithHighConfidence(:), 'descend');
                nKeep = min(minimumRequiredPoints, numel(powerRankedIndices));
                selectedMeasurementIndices = sort(powerRankedIndices(1:nKeep));
                return
            end

            candidateBinIndices = binIndices(candidateMeasurementIndices);
            candidateAzimuthStd = azimuthStandardDeviation(candidateBinIndices);
            candidatePointCount = cell2mat(binMeasurementCount(candidateBinIndices));

            qualityMask = ...
                (candidateAzimuthStd < localizationParams.maximumAzimuthStandardDeviation) & ...
                (candidatePointCount > localizationParams.minimumPointsPerBin);

            if sum(qualityMask) >= minimumRequiredPoints
                % Caso normal: há candidatos suficientes que satisfazem todos os critérios
                selectedMeasurementIndices = candidateMeasurementIndices(qualityMask);
            else
                % Fallback: menos de 2 candidatos passaram no filtro estrito de
                % qualidade (típico de medição fixa, onde o azimute é ruidoso e o
                % desvio por bin é alto). Para garantir as 2 detecções exigidas
                % por triangulateLOS, ordena-se os candidatos por qualidade
                % angular (menor desvio padrão de azimute; empate resolvido pelo
                % maior número de medições no bin) e mantêm-se os melhores.
                candidateAzimuthStd(isnan(candidateAzimuthStd)) = inf;
                rankingMetric = candidateAzimuthStd - 1e-6 * candidatePointCount;
                [~, rankingOrder] = sort(rankingMetric, 'ascend');
                nKeep = min(minimumRequiredPoints, numel(candidateMeasurementIndices));
                selectedMeasurementIndices = sort(candidateMeasurementIndices(rankingOrder(1:nKeep)));
            end
        end


        %----------------------------------------------------------------%
        function [estimatedLatitude, estimatedLongitude, uncertaintyRadius] = estimateLocationViaPowerOfArrival(specRawTable)
            % Retorna lat, long e raio calculados do emissor para a
            % triangulação via PoA

            distanceToleranceMeters = 450; % threshold em torno da curva que delimita pontos a serem triangulados
            rssiPercentileArray = 5:3:26; % percentual de pontos a serem utilizados no fit da curva dist X Pot
            latEmissor      = zeros(height(rssiPercentileArray'),1);
            longEmissor     = zeros(height(rssiPercentileArray'),1);
            residualEmissor = NaN(height(rssiPercentileArray'),1);  % resíduo médio |d_geom - d_model| por iteração

            % Bounding box geográfica das medições (com margem de 0.5° ~ 55 km)
            latMargin = 0.25;
            lonMargin = 0.25;
            latBounds = [min(specRawTable.Latitude) - latMargin, max(specRawTable.Latitude) + latMargin];
            lonBounds = [min(specRawTable.Longitude) - lonMargin, max(specRawTable.Longitude) + lonMargin];
            
            %pathLossConstant = 600; constante livre da curva dist x Pot
            minimumReceivedPowerThreshold = min(100, prctile(specRawTable.ChannelPower, 98));
            referenceReceivedPower = max(specRawTable.ChannelPower);
            referenceDistanceMeters = 25;
            pathLossExponent = 1.2;%2.7;
            
            for ind = 1 : height(rssiPercentileArray')
                % selecionando os 'ind' max valores de potência recebida
                [maxValues, maxValuesIdxs] = maxk(specRawTable.ChannelPower, ceil((rssiPercentileArray(ind)/100)*height(specRawTable.ChannelPower)));
                
                % Filtrando rssi mínimo recebido
                maxValuesIdxs = maxValuesIdxs(maxValues > minimumReceivedPowerThreshold);
               
                if height(maxValuesIdxs) < height(maxValues)/2
                    % testa se todos os pontos max são maiores que o limite pré-estabelecido (minimumReceivedPowerThreshold)
                    %  - reduzir o limite mínimo para maxValue (para contemplar emissores de
                    % menor potência);
                    minimumReceivedPowerThreshold = minimumReceivedPowerThreshold - 0.05 * abs(minimumReceivedPowerThreshold);
                    %  - atualizar valores de linear Indices
                    %  - ampliar a distância de referência do modelo para acomodar cenários mais fracos
                    %pathLossConstant = pathLossConstant - 30;
                    referenceDistanceMeters = referenceDistanceMeters * 1.05;
                    continue

                else
                    % 1. Triangular ORIGEM PARA OS MaxValues calculados
                    pot = specRawTable.ChannelPower(maxValuesIdxs);
                    %distAferida = 10.^7.2*exp(-0.115*pot2)+pathLossConstant;
                    distAferida = RF.Geolocation.estimateDistanceFromReceivedPower( ...
                        pot, referenceReceivedPower, referenceDistanceMeters, pathLossExponent);
                    latMax = specRawTable.Latitude(maxValuesIdxs);
                    longMax = specRawTable.Longitude(maxValuesIdxs);

                    [xpos,ypos,utmzone] = matlab.deg2utm(latMax, longMax);
                    txPosition = [xpos';ypos'];
                    rxPosition = matlab.blePositionEstimate(txPosition,"lateration", ... 
                    distAferida');

                    % 2. Calcular distância de todos valores medidos no DT
                    % (specRawTable.Latitude e specRawTable.Longitude), para a fonte
                    % calculada em 1
                    [lat_reverted, lon_reverted] = matlab.utm2deg(rxPosition(1), rxPosition(2), utmzone(1,:));

                    % Rejeitar posição fora da bounding box das medições
                    if lat_reverted < latBounds(1) || lat_reverted > latBounds(2) || ...
                       lon_reverted < lonBounds(1) || lon_reverted > lonBounds(2)
                        continue
                    end

                    tx = txsite(Name="Medido", ...
                        Latitude=specRawTable.Latitude, ...
                        Longitude=specRawTable.Longitude);
                    rx = rxsite(Name="Triangulado", ...
                        Latitude=lat_reverted, ...
                        Longitude=lon_reverted);
                    distEmissorParcial = distance(tx,rx);

                    % 3. Filtrar pontos para todos valores de potência usando um modelo log-distância genérico +/- threshold
                    %distAferida = 10.^7.2*exp(-0.115*pot2)+pathLossConstant;
                    distAferidaTotal = RF.Geolocation.estimateDistanceFromReceivedPower( ...
                        specRawTable.ChannelPower, referenceReceivedPower, referenceDistanceMeters, pathLossExponent);
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
            
                [xpos,ypos,utmzone] = matlab.deg2utm(latMax, longMax);
                txPosition = [xpos';ypos'];

                pot2 = specRawTable.ChannelPower(selectedMeasurementIndices>0);
                %distAferida = 10.^7.2*exp(-0.115*pot2)+pathLossConstant;
                distAferida = RF.Geolocation.estimateDistanceFromReceivedPower( ...
                    pot2, referenceReceivedPower, referenceDistanceMeters, pathLossExponent);

                localizationMethod = "lateration";

                % Triangulação

                rxPosition = matlab.blePositionEstimate(txPosition,localizationMethod, ... 
                    distAferida');
            
                [lat_reverted, lon_reverted] = matlab.utm2deg(rxPosition(1), rxPosition(2), utmzone(1,:));

                % Rejeitar posição fora da bounding box das medições
                if lat_reverted < latBounds(1) || lat_reverted > latBounds(2) || ...
                   lon_reverted < lonBounds(1) || lon_reverted > lonBounds(2)
                    continue
                end

                latEmissor(ind)  = lat_reverted;
                longEmissor(ind) = lon_reverted;

                % Opção E: resíduo médio |distância geométrica - distância modelada|
                txResidual = txsite(Name="Triangulado", Latitude=lat_reverted, Longitude=lon_reverted);
                rxResidual = rxsite(Name="Medidas", ...
                    Latitude=latMax, ...
                    Longitude=longMax);
                distGeometrica = distance(txResidual, rxResidual);
                residualEmissor(ind) = mean(abs(distGeometrica - distAferida));
            end
            
            validMask   = latEmissor ~= 0;
            latEmissor      = latEmissor(validMask);
            longEmissor     = longEmissor(validMask);
            residualEmissor = residualEmissor(validMask);

            % Nenhuma iteração produziu uma estimativa válida
            if isempty(latEmissor)
                estimatedLatitude  = NaN;
                estimatedLongitude = NaN;
                uncertaintyRadius  = NaN;
                return
            end

            % Com menos de 3 pontos, pular remoção de outliers
            if numel(latEmissor) < 3
                estimatedLatitude  = median(latEmissor);
                estimatedLongitude = median(longEmissor);
                uncertaintyRadius  = 0;
                return
            end

            medLat  = median(latEmissor);
            stdLat  = std(latEmissor);
            locLat  = (latEmissor  > (medLat  + 1.0*stdLat)) | (latEmissor  < (medLat  - 1.0*stdLat));
            medLong = median(longEmissor);
            stdLong = std(longEmissor);
            locLong = (longEmissor > (medLong + 1.0*stdLong)) | (longEmissor < (medLong - 1.0*stdLong));

            [~, IndOut] = rmoutliers(latEmissor, OutlierLocations=(locLong|locLat));

            % Se rmoutliers eliminar tudo, usar mediana bruta
            if all(IndOut)
                estimatedLatitude  = medLat;
                estimatedLongitude = medLong;
                uncertaintyRadius  = median(residualEmissor, 'omitnan');
                return
            end

            % Conversão para desenho de círculo de erro
            estimatedLatitude  = median(latEmissor(~IndOut));
            estimatedLongitude = median(longEmissor(~IndOut));

            % Opção E: raio = mediana dos resíduos |d_geom - d_model| das iterações válidas
            uncertaintyRadius = min(max(3 * median(residualEmissor(~IndOut), 'omitnan'), 300), 1000);
        end


        %-----------------------------------------------------------------%
        function estimatedDistanceMeters = estimateDistanceFromReceivedPower(receivedPowerDbm, referenceReceivedPowerDbm, referenceDistanceMeters, pathLossExponent)
            % Modelo log-distância genérico: d = d0 * 10^((Pr0 - Pr) / (10*n))
            relativeDistance = 10.^((referenceReceivedPowerDbm - receivedPowerDbm) ./ (10 * pathLossExponent));
            estimatedDistanceMeters = referenceDistanceMeters .* max(relativeDistance, 1);
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
                    channelObj = class.ChannelLib('appAnalise');
                    update(specData, 'UserData:Emissions', 'Add', newIndex, newFreq, newBW_MHz*1000, Method, [], channelObj)
                end

                emissionsTable = specData(1).UserData.Emissions;
                classifications = emissionsTable.Classification;

                validMask = arrayfun(@(classification) ...
                    classification.UserModified.Station > -1, classifications);

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
                uncertaintyRadius = varargin{3} / (111320 * cosd(estimatedLatitude)); % metros >> graus

                delete(findobj(axesHandle.Children, 'Tag', 'estimatedEmissorLocation'))

                if any(isnan([estimatedLatitude,estimatedLongitude]))
                    warning('o valor foi NAN')
                    return
                end
                images.roi.Circle(axesHandle, 'Center', [estimatedLatitude, estimatedLongitude], 'Radius', uncertaintyRadius, 'LineWidth', 1, 'Deletable', 0, 'FaceSelectable', 0, 'InteractionsAllowed', 'none', 'Color', 'red', 'Tag', 'estimatedEmissorLocation');
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