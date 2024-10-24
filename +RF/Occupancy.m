classdef (Abstract) Occupancy
    
    methods (Static = true)
        %-----------------------------------------------------------------%
        function THR = Threshold(Method, occInfo, Orientation, varargin)
            arguments
                Method      char {mustBeMember(Method, {'Fixed', 'Adaptive Linear', 'Offset Noise-Envelope'})}
                occInfo     struct
                Orientation char {mustBeMember(Orientation, {'bin', 'channel'})}
            end

            arguments (Repeating)
                varargin
            end

            switch Method
                case 'Fixed'
                    THR = occInfo.THR;
                case 'Adaptive Linear'
                    THR = RF.Occupancy.adaptiveThreshold(specData, occInfo);
                case 'Offset Noise-Envelope'
                    THR = RF.Occupancy.adaptiveThreshold(specData, occInfo);
            end
        end

        %-----------------------------------------------------------------%
        function occTHR = adaptiveThreshold(specData, occInfo)

            DataPoints  = specData.MetaData.DataPoints;

            % Inicialmente, identificam-se os índices que limitarão as amostras 
            % ordenadas de todas as varreduras (sortedData), o que possibilitará
            % aferir a estimativa do piso de ruído.

            idx1        = max(1,                 ceil(occInfo.noiseTrashSamples  * DataPoints));
            idx2        = min(DataPoints, idx1 + ceil(occInfo.noiseUsefulSamples * DataPoints));
            
            sortedData  = sort(specData.Data{2});
            sortedData  = sortedData(idx1:idx2,:);

            % O método "Linear adaptativo" é uma simples média (ou mediana)
            % do piso de ruído acrescida do Offset. Já o método "Envoltória 
            % do ruído adaptativo", por outro lado, é o sinal ceifado nos 
            % limites [µ-k𝜎, µ+k𝜎].
            
            switch occInfo.Method
                case 'Adaptive Linear'
                    switch occInfo.noiseFcn
                        case 'mean';   averageNoise =   mean(sortedData);
                        case 'median'; averageNoise = median(sortedData);
                    end

                    occTHR   = ceil(averageNoise + occInfo.Offset);
                    
                case 'Offset Noise-Envelope'
                    switch occInfo.noiseFcn
                        case 'mean';   averageNoise =   mean(sortedData, 'all');
                        case 'median'; averageNoise = median(sortedData, 'all');
                    end
                    stdNoise = std(sortedData, 1, 'all');
                    
                    Factor   = str2double(extractBefore(occInfo.ceilFactor, '𝜎'));
                    Lim1     = averageNoise - Factor*stdNoise;
                    Lim2     = averageNoise + Factor*stdNoise;

                    occTHR   = ceil(bsxfun(@min, bsxfun(@max, specData.Data{3}(:,2), Lim1), Lim2) + occInfo.Offset);
            end
        end
  
        %-----------------------------------------------------------------%
        function occData = Analysis(TimeStamp, Matrix, occInfo, occTHR)
            % Estimativa da quantidade de amostras que poderá ter o fluxo de 
            % ocupação, pré-alocando espaço em memória (para fins de tornar 
            % mais eficiente a operação).
            Observation = minutes(TimeStamp(end) - TimeStamp(1));
            occSamples  = ceil(Observation / occInfo.IntegrationTime);
            occData     = {repmat(datetime(0,0,0), 1, occSamples),      ...
                           zeros(height(Matrix), occSamples, 'single'), ...
                           zeros(height(Matrix),          3, 'single')};
            
            % O horário de referência engloba a primeira amostra da varredura, 
            % sendo orientado ao tempo de integração. Por exemplo, caso escolhido 
            % 15min de integração, o horário de referência da monitoração cuja 
            % primeira varredura foi realizada 06-Oct-2023 20:47:37 será 
            % 06-Oct-2023 20:45:00.

            % -  1min: 0:59
            % -  5min: 0:5:55
            % - 15min: [0,15,30,45]
            % - 30min: [0,30]
            % - 60min: 0

            referenceTime        = TimeStamp(1);
            referenceTime.Minute = referenceTime.Minute - mod(referenceTime.Minute, occInfo.IntegrationTime);
            referenceTime.Second = 0;

            % Aqui começa a aferição da ocupação orientada ao BIN...
            occStamp = 1;            
            while referenceTime < TimeStamp(end)
                [~, idx] = find((TimeStamp >= referenceTime) & ...
                                (TimeStamp <  referenceTime + minutes(occInfo.IntegrationTime)));
                
                if ~isempty(idx)
                    switch occInfo.Method
                        case {'Fixed', 'Offset Noise-Envelope'}
                            occMatrix = single(Matrix(:, idx) > occTHR);

                        case 'Adaptive Linear'
                            occMatrix = single(Matrix(:, idx) > occTHR(idx));
                    end
                    
                    occData{1}(occStamp)   = referenceTime;
                    occData{2}(:,occStamp) = 100 * sum(occMatrix, 2) / width(occMatrix);

                    occStamp  = occStamp + 1;
                end
                referenceTime = referenceTime + minutes(occInfo.IntegrationTime);
            end

            % Elimina amostras relacionadas a períodos de tempo não
            % monitorados...            
            if occStamp-1 < occSamples
                occData{1}(occStamp:end)   = [];
                occData{2}(:,occStamp:end) = [];
            end

            occData{3} = [ min(occData{2}, [], 2), ...
                          mean(occData{2},     2), ...
                           max(occData{2}, [], 2)];
        end
    end
end