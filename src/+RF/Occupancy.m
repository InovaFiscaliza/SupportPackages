classdef (Abstract) Occupancy

    % TODO
    % (1) Implementar ocupação orientada à "channel".
    
    methods (Static = true)
        %-----------------------------------------------------------------%
        function Threshold = Threshold(Method, occInfo, varargin)
            arguments
                Method  char {mustBeMember(Method, {'Linear fixo (COLETA)', ... % 'Fixed' (?)
                                                    'Linear fixo',          ... % 'Fixed'
                                                    'Linear adaptativo',    ... % 'Adaptive Linear'
                                                    'Envoltória do ruído'})}    % 'Offset Noise-Envelope'
                occInfo struct
            end

            arguments (Repeating)
                varargin
            end

            switch Method
                case 'Linear fixo (COLETA)'
                    Threshold   = occInfo.THRCaptured;

                case 'Linear fixo'
                    Threshold   = occInfo.THR;

                case {'Linear adaptativo', 'Envoltória do ruído'}
                    specData    = varargin{1};
                    Orientation = varargin{2};

                    Threshold   = RF.Occupancy.adaptiveThreshold(Method, occInfo, specData, Orientation);
            end
        end

        %-----------------------------------------------------------------%
        function occTHR = adaptiveThreshold(Method, occInfo, specData, Orientation)
            arguments
                Method      char {mustBeMember(Method, {'Linear adaptativo', 'Envoltória do ruído'})}
                occInfo     struct
                specData    model.SpecData
                Orientation char {mustBeMember(Orientation, {'bin', 'channel'})} = 'bin'
            end

            switch Orientation
                case 'bin'
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
                    
                    switch Method
                        case 'Linear adaptativo'
                            switch occInfo.noiseFcn
                                case 'mean';   averageNoise =   mean(sortedData);
                                case 'median'; averageNoise = median(sortedData);
                            end
        
                            occTHR   = ceil(averageNoise + occInfo.Offset);
                            
                        case 'Envoltória do ruído'
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

                case 'Channel'
                    % !! PENDENTE !!
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
                        case {'Linear fixo', 'Envoltória do ruído'}
                            occMatrix = single(Matrix(:, idx) > occTHR);

                        case 'Linear adaptativo'
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