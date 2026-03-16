classdef (Abstract) Occupancy

    properties (Constant)
        %-----------------------------------------------------------------%
        ParametersTemplate = struct( ...
            'Method',                  {}, ... % 'Linear fixo (COLETA)' | 'Linear fixo' | 'Linear adaptativo' | 'Envoltória do ruído'
            'IntegrationTime',         {}, ...
            'Threshold',               {}, ...
            'Offset',                  {}, ...
            'CeilingFactor',           {}, ...
            'NoiseEstimator',          {}, ...
            'NoiseDiscardFraction',    {}, ...
            'NoiseSampleFraction',     {} ...
        );
    end

    
    methods (Static = true)
        %-----------------------------------------------------------------%
        function varargout = run(timeStamp, levelMatrix, method, threshold, integrationTime, outputType)
            % A aferição da ocupação pode ser realizada por meio de um tempo 
            % de integração INFINITO ou FINITO (1, 5, 15, 30 ou 60 minutos).            
            % • INFINITO
            %   Todas as varreduras são avaliadas p/ obtenção de um único
            %   valor de ocupação por bin (ou ponto de medição de frequência).            
            % • FINITO
            %   As varreduras são agrupadas em janelas temporais. Dessa forma,
            %   será obtido um valor de ocupação por bin para cada janela
            %   temporal.

            % Já o THRESHOLD pode ser um único valor (-70 dBm, por exemplo, no
            % método "Linear fixo"), ou um vetor com um valor por varredura
            % (no método "Linear adaptativo") ou um vetor de tamanho "DataPoints" 
            % (no método "Envoltória do ruído").

            % A saída pode ser apenas a matriz de ocupação (DataPoints x 1, caso 
            % integração infinita, ou DataPoints x ceil(ObservationTime/IntegrationFactor).
            % Ou, opcionalmente, um cellarray em que o primeiro elemento é o vetor
            % de TimeStamp, o segundo é a matriz de ocupação, e o terceiro
            % é a sumarização dessa matriz (mínimo, média e máximo).

            % <VALIDATION>
            arguments
                timeStamp datetime {mustBeVector}
                levelMatrix        {mustBeNumeric}
                method             {mustBeMember(method, {'Linear fixo', 'Linear adaptativo', 'Envoltória do ruído'})}                
                threshold          {mustBeNumeric, mustBeVector}
                integrationTime    {mustBeNumeric}
                outputType         {mustBeMember(outputType, {'OnlyMatrix', 'TimeStamp+Matrix+BasicStats'})} = 'TimeStamp+Matrix+BasicStats'
            end

            try
                mustBeMember(integrationTime, [1, 5, 15, 30, 60, inf]) % em minutos
                
                dataPoints = height(levelMatrix);
                numSweeps  = width(levelMatrix);

                if strcmp(method, 'Linear fixo') && ~isscalar(threshold)
                    error('RF:Occupancy:UnexpectedThreshold', 'Threshold must be a scalar value.')
                elseif strcmp(method, 'Linear adaptativo') && numel(threshold) ~= numSweeps
                    error('RF:Occupancy:UnexpectedThreshold', 'Threshold must be an array with the same number of elements as the number of columns in the Matrix.')
                elseif strcmp(method, 'Envoltória do ruído') && numel(threshold) ~= dataPoints
                    error('RF:Occupancy:UnexpectedThreshold', 'Threshold must be an array with the same number of elements as the number of rows in the Matrix.')
                end

                if numel(timeStamp) ~= numSweeps
                    error('RF:Occupancy:UnmatchArrays', 'The timeStamp array must have the same number of elements as the number of columns in the matrix.')
                end

            catch ME
                error(ME.message)
            end
            % </VALIDATION>

            % <PROCESS>
            if isinf(integrationTime)
                occMatrix = levelMatrix > threshold;

                if outputType == "OnlyMatrix"
                    varargout = {occMatrix};
                else
                    occData = {timeStamp(1),                   ...
                               zeros(dataPoints, 1, 'single'), ...
                               zeros(dataPoints, 3, 'single')};
                    occData{2}(:) = 100 * sum(occMatrix, 2) / width(occMatrix);
                    occData{3}(:) = repmat(occData{2}, 1, 3);

                    varargout = {occData};
                end

            else
                % Estimativa da quantidade de amostras que poderá ter o fluxo de 
                % ocupação, pré-alocando espaço em memória (para fins de tornar 
                % mais eficiente a operação).
                observation = minutes(timeStamp(end) - timeStamp(1));
                occSamples  = ceil(observation / integrationTime);
                occData     = {repmat(datetime(0,0,0), 1, occSamples),  ...
                               zeros(dataPoints, occSamples, 'single'), ...
                               zeros(dataPoints,          3, 'single')};
                
                % O horário de referência engloba a primeira amostra da varredura, 
                % sendo orientado ao tempo de integração. Por exemplo, caso escolhido 
                % 15min de integração, o horário de referência da monitoração cuja 
                % primeira varredura foi realizada 06-Oct-2023 20:47:37 será 
                % 06-Oct-2023 20:45:00.    
                % •  1min: 0:59
                % •  5min: 0:5:55
                % • 15min: [0,15,30,45]
                % • 30min: [0,30]
                % • 60min: 0    
                referenceTime = timeStamp(1);
                referenceTime.Minute = referenceTime.Minute - mod(referenceTime.Minute, integrationTime);
                referenceTime.Second = 0;
    
                occTimeStamp = 0;            
                while referenceTime < timeStamp(end)
                    [~, idx] = find((timeStamp >= referenceTime) & ...
                                    (timeStamp <  referenceTime + minutes(integrationTime)));
                    
                    if ~isempty(idx)
                        switch method
                            case {'Linear fixo', 'Envoltória do ruído'}
                                occMatrix = single(levelMatrix(:, idx) > threshold);
    
                            case 'Linear adaptativo'
                                occMatrix = single(levelMatrix(:, idx) > threshold(idx));
                        end

                        occTimeStamp = occTimeStamp + 1;                        
                        occData{1}(occTimeStamp)    = referenceTime;
                        occData{2}(:, occTimeStamp) = 100 * sum(occMatrix, 2) / width(occMatrix);
                    end
                    referenceTime = referenceTime + minutes(integrationTime);
                end
    
                % Elimina amostras relacionadas a períodos de tempo não
                % monitorados...            
                if occTimeStamp < occSamples
                    occData{1}(occTimeStamp+1:end)    = [];
                    occData{2}(:, occTimeStamp+1:end) = [];
                end

                occData{3}(:) = [ min(occData{2}, [], 2), ...
                                 mean(occData{2},     2), ...
                                  max(occData{2}, [], 2)];

                varargout = {occData};
            end
            % </PROCESS>
        end

        %-----------------------------------------------------------------%
        function defaultParameters = getDefaultParameters()
            defaultParameters = RF.Occupancy.ParametersTemplate;

            defaultParameters(1).Method = 'Linear adaptativo';
            defaultParameters.IntegrationTime = 15;
            defaultParameters.Offset = 12;
            defaultParameters.NoiseEstimator = 'mean';
            defaultParameters.NoiseDiscardFraction = 0.10;
            defaultParameters.NoiseSampleFraction = 0.20;
        end

        %-----------------------------------------------------------------%
        function parameters = applyRelatedParameters(method, varargin)
            arguments
                method  char {mustBeMember(method, {'Linear fixo (COLETA)', ...
                                                    'Linear fixo',          ...
                                                    'Linear adaptativo',    ...
                                                    'Envoltória do ruído'})}
            end

            arguments (Repeating)
                varargin
            end

            parameters = RF.Occupancy.ParametersTemplate;
            parameters(1).Method = method;

            switch method
                case {'Linear fixo (COLETA)', 'Linear fixo'}
                    parameters.IntegrationTime      = varargin{1};
                    parameters.Threshold            = varargin{2};

                case {'Linear adaptativo', 'Envoltória do ruído'}
                    parameters.IntegrationTime      = varargin{1};
                    parameters.Offset               = varargin{2};
                    parameters.NoiseEstimator       = varargin{3};
                    parameters.NoiseDiscardFraction = varargin{4};
                    parameters.NoiseSampleFraction  = varargin{5};

                    if method == "Envoltória do ruído"
                        parameters.CeilingFactor    = varargin{6};
                    end
            end
        end

        %-----------------------------------------------------------------%
        function threshold = getThreshold(method, parameters, varargin)
            arguments
                method        char {mustBeMember(method, {'Linear fixo (COLETA)', ...
                                                          'Linear fixo',          ...
                                                          'Linear adaptativo',    ...
                                                          'Envoltória do ruído'})}
                parameters struct
            end

            arguments (Repeating)
                varargin
            end

            switch method
                case 'Linear fixo (COLETA)'
                    threshold = parameters.ThresholdMeasured;

                case 'Linear fixo'
                    threshold = parameters.Threshold;

                case {'Linear adaptativo', 'Envoltória do ruído'}
                    specData = varargin{1};
                    orientation = varargin{2};
                    threshold = RF.Occupancy.computeThresholdPerSweep(method, parameters, specData, orientation);
            end
        end

        %-----------------------------------------------------------------%
        function threshold = computeThresholdPerSweep(method, parameters, specData, orientation)
            arguments
                method      char {mustBeMember(method, {'Linear adaptativo', 'Envoltória do ruído'})}
                parameters  struct
                specData    model.SpecData
                orientation char {mustBeMember(orientation, {'bin', 'channel'})} = 'bin'
            end

            switch orientation
                case 'bin'
                    dataPoints = specData.MetaData.DataPoints;
        
                    % Inicialmente, identificam-se os índices que limitarão as amostras 
                    % ordenadas de todas as varreduras (sortedData), o que possibilitará
                    % aferir a estimativa do piso de ruído.        
                    idx1 = max(1,                 ceil(parameters.NoiseDiscardFraction  * dataPoints));
                    idx2 = min(dataPoints, idx1 + ceil(parameters.NoiseSampleFraction * dataPoints));
                    
                    sortedData = sort(specData.Data{2});
                    sortedData = sortedData(idx1:idx2, :);
        
                    % O método "Linear adaptativo" é uma simples média (ou mediana)
                    % do piso de ruído acrescida do Offset. Já o método "Envoltória 
                    % do ruído adaptativo", por outro lado, é o sinal ceifado nos 
                    % limites [µ-k𝜎, µ+k𝜎].                    
                    switch method
                        case 'Linear adaptativo'
                            switch parameters.NoiseEstimator
                                case 'mean';   averageNoise =   mean(sortedData);
                                case 'median'; averageNoise = median(sortedData);
                            end
        
                            threshold = ceil(averageNoise + parameters.Offset);
                            
                        case 'Envoltória do ruído'
                            switch parameters.NoiseEstimator
                                case 'mean';   averageNoise =   mean(sortedData, 'all');
                                case 'median'; averageNoise = median(sortedData, 'all');
                            end
                            stdNoise = std(sortedData, 1, 'all');
                            
                            ceilingFactor = str2double(extractBefore(parameters.CeilingFactor, '𝜎'));
                            inferiorLim = averageNoise - ceilingFactor*stdNoise;
                            superioLim = averageNoise + ceilingFactor*stdNoise;
        
                            threshold = ceil(bsxfun(@min, bsxfun(@max, specData.Data{3}(:,2), inferiorLim), superioLim) + parameters.Offset);
                    end

                case 'channel'
                    % !! PENDENTE !!
            end
        end
    end
end