classdef (Abstract) Occupancy

    properties (Constant)
        %-----------------------------------------------------------------%
        ParametersTemplate = struct('Method',                  {}, ...
                                    'IntegrationTime',         {}, ...
                                    'IntegrationTimeCaptured', {}, ...
                                    'THR',                     {}, ...
                                    'THRCaptured',             {}, ...
                                    'Offset',                  {}, ...
                                    'ceilFactor',              {}, ...
                                    'noiseFcn',                {}, ...
                                    'noiseTrashSamples',       {}, ...
                                    'noiseUsefulSamples',      {});
    end

    
    methods (Static = true)
        %-----------------------------------------------------------------%
        function varargout = run(TimeStamp, Matrix, Method, Threshold, IntegrationTime, OutputType)
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
                TimeStamp datetime {mustBeVector}
                Matrix             {mustBeNumeric}
                Method             {mustBeMember(Method, {'Linear fixo', 'Linear adaptativo', 'Envoltória do ruído'})}                
                Threshold          {mustBeNumeric, mustBeVector}
                IntegrationTime    {mustBeNumeric}
                OutputType         {mustBeMember(OutputType, {'OnlyMatrix', 'TimeStamp+Matrix+BasicStats'})} = 'TimeStamp+Matrix+BasicStats'
            end

            try
                mustBeMember(IntegrationTime, [1, 5, 15, 30, 60, inf])                
                
                dataPoints = height(Matrix);
                numSweeps  = width(Matrix);

                if strcmp(Method, 'Linear fixo') && ~isscalar(Threshold)
                    error('Threshold must be a scalar value.')
                elseif strcmp(Method, 'Linear adaptativo') && numel(Threshold) ~= numSweeps
                    error('Threshold must be an array with the same number of elements as the number of columns in the Matrix.')
                elseif strcmp(Method, 'Envoltória do ruído') && numel(Threshold) ~= dataPoints
                    error('Threshold must be an array with the same number of elements as the number of rows in the Matrix.')
                end

                if numel(TimeStamp) ~= numSweeps
                    error('The TimeStamp array must have the same number of elements as the number of columns in the Matrix.')
                end

            catch ME
                error(ME.message)
            end
            % </VALIDATION>

            % <PROCESS>
            if isinf(IntegrationTime)
                occMatrix = Matrix > Threshold;

                if OutputType == "OnlyMatrix"
                    varargout = {occMatrix};
                else
                    occData = {TimeStamp(1),                   ...
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
                Observation = minutes(TimeStamp(end) - TimeStamp(1));
                occSamples  = ceil(Observation / IntegrationTime);
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
                referenceTime        = TimeStamp(1);
                referenceTime.Minute = referenceTime.Minute - mod(referenceTime.Minute, IntegrationTime);
                referenceTime.Second = 0;
    
                occTimeStamp = 0;            
                while referenceTime < TimeStamp(end)
                    [~, idx] = find((TimeStamp >= referenceTime) & ...
                                    (TimeStamp <  referenceTime + minutes(IntegrationTime)));
                    
                    if ~isempty(idx)
                        switch Method
                            case {'Linear fixo', 'Envoltória do ruído'}
                                occMatrix = single(Matrix(:, idx) > Threshold);
    
                            case 'Linear adaptativo'
                                occMatrix = single(Matrix(:, idx) > Threshold(idx));
                        end

                        occTimeStamp = occTimeStamp + 1;                        
                        occData{1}(occTimeStamp)   = referenceTime;
                        occData{2}(:,occTimeStamp) = 100 * sum(occMatrix, 2) / width(occMatrix);
                    end
                    referenceTime = referenceTime + minutes(IntegrationTime);
                end
    
                % Elimina amostras relacionadas a períodos de tempo não
                % monitorados...            
                if occTimeStamp < occSamples
                    occData{1}(occTimeStamp+1:end)   = [];
                    occData{2}(:,occTimeStamp+1:end) = [];
                end

                occData{3}(:) = [ min(occData{2}, [], 2), ...
                                 mean(occData{2},     2), ...
                                  max(occData{2}, [], 2)];

                varargout = {occData};
            end
            % </PROCESS>
        end

        %-----------------------------------------------------------------%
        function occParametersDefault = ParametersDefault()
            occParametersDefault                    = RF.Occupancy.ParametersTemplate;

            occParametersDefault(1).Method          = 'Linear adaptativo';
            occParametersDefault.IntegrationTime    = 15;
            occParametersDefault.Offset             = 12;
            occParametersDefault.noiseFcn           = 'mean';
            occParametersDefault.noiseTrashSamples  = 0.10;
            occParametersDefault.noiseUsefulSamples = 0.20;
        end

        %-----------------------------------------------------------------%
        function occParameters = Parameters(Method, varargin)
            arguments
                Method  char {mustBeMember(Method, {'Linear fixo (COLETA)', ... % 'Fixed' (?)
                                                    'Linear fixo',          ... % 'Fixed'
                                                    'Linear adaptativo',    ... % 'Adaptive Linear'
                                                    'Envoltória do ruído'})}    % 'Offset Noise-Envelope'
            end

            arguments (Repeating)
                varargin
            end

            occParameters = RF.Occupancy.ParametersTemplate;
            occParameters(1).Method = Method;

            switch Method
                case 'Linear fixo (COLETA)'
                    occParameters.IntegrationTimeCaptured = varargin{1};
                    occParameters.THRCaptured             = varargin{2};

                case 'Linear fixo'
                    occParameters.IntegrationTime         = varargin{1};
                    occParameters.THR                     = varargin{2};

                case {'Linear adaptativo', 'Envoltória do ruído'}
                    occParameters.IntegrationTime         = varargin{1};
                    occParameters.Offset                  = varargin{2};
                    occParameters.noiseFcn                = varargin{3};
                    occParameters.noiseTrashSamples       = varargin{4};
                    occParameters.noiseUsefulSamples      = varargin{5};

                    if Method == "Envoltória do ruído"
                        occParameters.ceilFactor          = varargin{6};
                    end
            end
        end

        %-----------------------------------------------------------------%
        function occTHR = Threshold(Method, occParameters, varargin)
            arguments
                Method        char {mustBeMember(Method, {'Linear fixo (COLETA)', ... % 'Fixed' (?)
                                                          'Linear fixo',          ... % 'Fixed'
                                                          'Linear adaptativo',    ... % 'Adaptive Linear'
                                                          'Envoltória do ruído'})}    % 'Offset Noise-Envelope'
                occParameters struct
            end

            arguments (Repeating)
                varargin
            end

            switch Method
                case 'Linear fixo (COLETA)'
                    occTHR = occParameters.THRCaptured;

                case 'Linear fixo'
                    occTHR = occParameters.THR;

                case {'Linear adaptativo', 'Envoltória do ruído'}
                    specData    = varargin{1};
                    Orientation = varargin{2};

                    occTHR = RF.Occupancy.adaptiveThreshold(Method, occParameters, specData, Orientation);
            end
        end

        %-----------------------------------------------------------------%
        function occTHR = adaptiveThreshold(Method, occParameters, specData, Orientation)
            arguments
                Method        char {mustBeMember(Method, {'Linear adaptativo', 'Envoltória do ruído'})}
                occParameters struct
                specData      model.SpecData
                Orientation   char {mustBeMember(Orientation, {'bin', 'channel'})} = 'bin'
            end

            switch Orientation
                case 'bin'
                    DataPoints  = specData.MetaData.DataPoints;
        
                    % Inicialmente, identificam-se os índices que limitarão as amostras 
                    % ordenadas de todas as varreduras (sortedData), o que possibilitará
                    % aferir a estimativa do piso de ruído.
        
                    idx1        = max(1,                 ceil(occParameters.noiseTrashSamples  * DataPoints));
                    idx2        = min(DataPoints, idx1 + ceil(occParameters.noiseUsefulSamples * DataPoints));
                    
                    sortedData  = sort(specData.Data{2});
                    sortedData  = sortedData(idx1:idx2,:);
        
                    % O método "Linear adaptativo" é uma simples média (ou mediana)
                    % do piso de ruído acrescida do Offset. Já o método "Envoltória 
                    % do ruído adaptativo", por outro lado, é o sinal ceifado nos 
                    % limites [µ-k𝜎, µ+k𝜎].
                    
                    switch Method
                        case 'Linear adaptativo'
                            switch occParameters.noiseFcn
                                case 'mean';   averageNoise =   mean(sortedData);
                                case 'median'; averageNoise = median(sortedData);
                            end
        
                            occTHR   = ceil(averageNoise + occParameters.Offset);
                            
                        case 'Envoltória do ruído'
                            switch occParameters.noiseFcn
                                case 'mean';   averageNoise =   mean(sortedData, 'all');
                                case 'median'; averageNoise = median(sortedData, 'all');
                            end
                            stdNoise = std(sortedData, 1, 'all');
                            
                            Factor   = str2double(extractBefore(occParameters.ceilFactor, '𝜎'));
                            Lim1     = averageNoise - Factor*stdNoise;
                            Lim2     = averageNoise + Factor*stdNoise;
        
                            occTHR   = ceil(bsxfun(@min, bsxfun(@max, specData.Data{3}(:,2), Lim1), Lim2) + occParameters.Offset);
                    end

                case 'channel'
                    % !! PENDENTE !!
            end
        end
    end
end