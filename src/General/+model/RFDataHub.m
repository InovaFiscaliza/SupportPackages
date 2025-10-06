classdef (Abstract) RFDataHub

    properties (Constant)
        %-----------------------------------------------------------------%
        FLOATDIFF = 1e-5
    end
    
    methods (Static = true)
        %-----------------------------------------------------------------%
        function read(appName, rootFolder, tempDir)
            arguments
                appName     char
                rootFolder  char
                tempDir     char = ''
            end

            global RFDataHub
            global RFDataHubLog
            global RFDataHub_info
            
            if isempty(RFDataHub) || isempty(RFDataHubLog) || isempty(RFDataHub_info)
                [projectFolder, ...
                 programDataFolder] = appUtil.Path(appName, rootFolder);

                projectFilePath     = fullfile(projectFolder,     'DataBase', 'RFDataHub.mat');
                programDataFilePath = fullfile(programDataFolder, 'DataBase', 'RFDataHub.mat');
        
                if isfile(programDataFilePath)
                    load(programDataFilePath, 'RFDataHub', 'RFDataHubLog', 'RFDataHub_info', '-mat')
                
                else
                    filename_parquet1  = fullfile(tempDir, 'estacoes.parquet.gzip');
                    filename_parquet2  = fullfile(tempDir, 'log.parquet.gzip');
                    filename_parquet3  = fullfile(tempDir, 'Release.json');
        
                    try
                        RFDataHub      = parquetread(filename_parquet1, "VariableNamingRule", "preserve");
                        RFDataHub      = model.RFDataHub.parquet2mat(RFDataHub);

                        RFDataHubLog   = parquetread(filename_parquet2, 'VariableNamingRule', 'preserve');
                        RFDataHubLog   = RFDataHubLog.Log;

                        FileVersion    = jsondecode(fileread(filename_parquet3));
                        RFDataHub_info = FileVersion.rfdatahub;
                                        
                        save(programDataFilePath, 'RFDataHub', 'RFDataHubLog', 'RFDataHub_info')
                    
                    catch ME
                        programDataFilePath_old = fullfile(programDataFolder, 'DataBase', 'RFDataHub_old.mat');        
                        if isfile(programDataFilePath_old)
                            backupPath = programDataFilePath_old;
                        else
                            backupPath = projectFilePath;
                        end
                        load(backupPath, 'RFDataHub', 'RFDataHubLog', 'RFDataHub_info', '-mat')
                    end
                end

                % Algumas transformações foram migradas p/ model.RFDataHub.parquet2mat
                % mas isso terá efeito apenas quando da atualização da base
                % (que virá numa nova versão). Cria-se validação, evitando
                % erros.
                if isa(RFDataHub.("Latitude"), 'single') || isa(RFDataHub.("Longitude"), 'single')
                    RFDataHub.("Latitude")    = double(RFDataHub.("Latitude"));
                    RFDataHub.("Longitude")   = double(RFDataHub.("Longitude"));
                end

                if any(~ismember({'ID', 'Description', '_Name', '_Location'}, RFDataHub.Properties.VariableNames))
                    RFDataHub = model.RFDataHub.createColumnsToGUI(RFDataHub);
                end
            end
        end

        %-----------------------------------------------------------------%
        function update(appName, rootFolder, tempDir, publicLinks)
            % Salva os arquivos PARQUET localmente...
            websave(fullfile(tempDir, 'estacoes.parquet.gzip'), publicLinks.Table);
            websave(fullfile(tempDir, 'log.parquet.gzip'),      publicLinks.Log);
            websave(fullfile(tempDir, 'Release.json'),          publicLinks.Release);

            % Muda o nome do arquivo antigo...
            [~, programDataFolder] = appUtil.Path(appName, rootFolder);
            programDataFilePath = fullfile(programDataFolder, 'DataBase', 'RFDataHub.mat');
            if isfile(programDataFilePath)
                movefile(programDataFilePath, fullfile(programDataFolder, 'DataBase', 'RFDataHub_old.mat'), 'f');
            end

            % Apaga as variáveis globais, lendo os novos arquivos.
            clear global RFDataHub
            clear global RFDataHubLog
            clear global RFDataHub_info

            model.RFDataHub.read(appName, rootFolder, tempDir)
        end

        %-----------------------------------------------------------------%
        function obj = parquet2mat(obj)
            % Em 28/11/2023 o RFDataHub se apresentava como uma tabela formada 
            % por 979522 linhas e 29 colunas. Todas as colunas eram categóricas 
            % (inclusive as de natureza numérica, como "Frequência", por exemplo).

            % Em 21/03/2024 o RFDataHub se apresenta como uma tabela formada 
            % por 1022917 linhas e 29 colunas. 28 das 29 colunas são categóricas 
            % (inclusive as de natureza numérica, como "Frequência", por exemplo). 
            % A única coluna não categórica é a "Log", cuja tipo de dado é
            % "int32".
            
            % Nomes e tipologia das principais colunas pós-conversões aqui 
            % realizadas:
            % Col.  1: "Frequência"           >> "Frequency" {double}
            % Col.  2: "Entidade"             >> "Name"      {categorical}
            % Col.  3: "Fistel"               >> "Fistel"    {int64}
            % Col.  4: "Serviço"              >> "Service"   {int16}
            % Col.  5: "Estação"              >> "Station"   {int32}
            % Col.  6: "Latitude"             >> "Latitude"  {single}
            % Col.  7: "Longitude"            >> "Longitude" {single}
            % Col. 13: "Largura_Emissão(kHz)" >> "BW"        {single}
            % Col. 29: "Relatório_Canal"      >> "URL"       {categorical}

            obj = model.RFDataHub.ColumnNames(obj, 'port2eng');
            obj = convertvars(obj, [1:7, 13], 'string');

            obj.Frequency = str2double(obj.Frequency);
            obj.Name      = categorical(regexprep(lower(obj.Name), '(\<\w)', '${upper($1)}'));
            obj.Fistel    = int64(str2double(obj.Fistel));
            obj.Service   = int16(str2double(obj.Service));
            obj.Station   = int32(str2double(obj.Station));

            % Contorna erro da função inROI, que retorna como se todos os
            % pontos estivessem internos ao ROI, quando as coordenadas
            % estão em float32. No float64 isso não acontece... aberto BUG
            % na Mathworks, que indicou ter resolvido o problema. Pendente 
            % confirmar!
            obj.Latitude  = str2double(obj.Latitude);
            obj.Longitude = str2double(obj.Longitude);

            obj.BW        = single(str2double(obj.BW));
            obj.Log       = obj.Log + 1;

            % LIMITES DE FREQUÊNCIA, LATITUDE E LONGITUDE
            msgError = {};
            if any(obj.Frequency <= 0)
                msgError{end+1} = 'Frequency column should only have positive values.';
            end
            
            if any(abs(obj.Latitude) > 90)
                msgError{end+1} = 'Latitude column should only have values in the range [-90, 90].';
            end

            if any(abs(obj.Longitude) > 180)
                msgError{end+1} = 'Longitude column should only have values in the range [-180, 180].';
            end

            stateList = {'-1', 'AC', 'AL', 'AM', 'AP', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MG', 'MS', 'MT', 'PA', 'PB', 'PE', 'PI', 'PR', 'RJ', 'RN', 'RO', 'RR', 'RS', 'SC', 'SE', 'SP', 'TO'};
            if any(~ismember(unique(obj.State), stateList))
                msgError{end+1} = sprintf('State column should only have values in the set {%s}.', strjoin(stateList, ', '));
            end

            if ~isempty(msgError)
                error(strjoin(msgError, '\n'))
            end

            % NAN >> -1
            for ii = 1:width(obj)
                if isnumeric(obj{:,ii})
                    idx = isnan(obj{:,ii});
                    obj{idx,ii} = -1;
                end
            end

            % Criar novas colunas p/ uso pelos apps:
            obj = model.RFDataHub.createColumnsToGUI(obj);
        end

        %-----------------------------------------------------------------%
        function obj = createColumnsToGUI(obj)
            obj.("ID")          = "#" + string((1:height(obj))');
            obj.("Description") = "[" + string(obj.Source) + "] " + string(obj.Status) + ", " + string(obj.StationClass) + ", " + string(obj.Name) + ", " + string(obj.Location) + "/" + string(obj.State) + " (M=" + string(obj.MergeCount) + ")";
            obj.("_Name")       = textAnalysis.preProcessedData(obj.("Name"),     true, false);
            obj.("_Location")   = textAnalysis.preProcessedData(obj.("Location"), true, false);
        end

        %-----------------------------------------------------------------%
        function varargout = ColumnNamesMapping(operationType, varargin)
            arguments
                operationType char {mustBeMember(operationType, {'columnArrays', 'label2name', 'name2label'})}
            end

            arguments (Repeating)
                varargin
            end

            rawColumnNames    = ["Frequência", "Entidade", "Fistel", "Serviço", "Estação", "Latitude", "Longitude", "Código_Município", "Município", "UF",                                      ... %  1 a 10
                                 "Classe", "Classe_Emissão", "Largura_Emissão(kHz)", "Validade_RF", "Status", "Fonte", "Multiplicidade","Log", "Cota_Base_Torre(m)", "Potência_Transmissor(W)", ... % 11 a 20
                                 "Ganho_Antena(dBd)", "Ângulo_Elevação_Antena", "Azimute_Antena", "Altura_Antena(m)", "Atenuação_Linha(db/100m)", "Perdas_Acessórias_Linha(db)",                ... % 21 a 26
                                 "Padrão_Antena(dBd)", "Comprimento_Linha(m)", "Relatório_Canal"];                                                                                                  % 27 a 29

            editedColumnNames = ["Frequency", "Name", "Fistel", "Service", "Station", "Latitude", "Longitude", "LocationID", "Location", "State",                                               ... %  1 a 10
                                 "StationClass", "EmissionClass", "BW", "SpectrumActValidity", "Status", "Source", "MergeCount", "Log", "TowerBaseElevation", "TransmitterPower",               ... % 11 a 20
                                 "AntennaGain", "AntennaElevation", "AntennaAzimuth", "AntennaHeight", "LineAttenuation", "LineAccessoryLosses", "AntennaPattern", "LineLength", "URL"];            % 21 a 29

            switch operationType
                case 'columnArrays'
                    varargout = {rawColumnNames, editedColumnNames};

                otherwise
                    switch operationType
                        case 'label2name'
                            nameDict  = dictionary(rawColumnNames, editedColumnNames);
                        case 'name2label'
                            nameDict  = dictionary(editedColumnNames, rawColumnNames);
                    end
                    varargout = {nameDict(varargin{1})};
            end            
        end

        %-----------------------------------------------------------------%
        function obj = ColumnNames(obj, Type)
            [rawColumnNames, ...
             editedColumnNames] = model.RFDataHub.ColumnNamesMapping('columnArrays');

            switch Type
                case 'port2eng'
                    obj = renamevars(obj, rawColumnNames, editedColumnNames);
                case 'eng2port'
                    obj = renamevars(obj, editedColumnNames, rawColumnNames);
            end
        end


        %-----------------------------------------------------------------%
        function stdDescription = Description(obj, idx, addAuxiliarInfo)
            arguments 
                obj
                idx
                addAuxiliarInfo logical = true
            end
            mergeCount = obj.MergeCount(idx);
            if mergeCount == "1"; mergeNote = '';
            else;                 mergeNote = sprintf(', M=%s', mergeCount);
            end

            stdDescription = sprintf('[%s] %s, %s, %s (Fistel=%d, Estação=%d%s), %s/%s', obj.Source(idx),       ...
                                                                                         obj.Status(idx),       ...
                                                                                         obj.StationClass(idx), ...
                                                                                         obj.Name(idx),         ...
                                                                                         obj.Fistel(idx),       ...
                                                                                         obj.Station(idx),      ...
                                                                                         mergeNote,             ...
                                                                                         obj.Location(idx),     ...
                                                                                         obj.State(idx));
            if addAuxiliarInfo
                stdDescription = sprintf('%s @ (Latitude=%.6fº, Longitude=%.6fº)', stdDescription, obj.Latitude(idx), obj.Longitude(idx));
            end
        end


        %-----------------------------------------------------------------%
        function stationInfo = query(obj, stationID, latNode, longNode)
            arguments
                obj 
                stationID string
                latNode   double
                longNode  double
            end

            % stationID é uma string com o número da estação real ou virtual 
            % (quando possui o caractere "#" à frente do número).  Em sendo 
            % passado como número, a validação feita no bloco arguments 
            % converte automaticamente para string
            % 
            % latNode e longNode são as coordenadas geográficas do local onde 
            % ocorreu a monitoração.

            if contains(stationID, '#')
                idx = str2double(extractAfter(stationID, '#'));
                if (idx < 1) || (idx > height(obj))
                    idx = [];
                end
            else
                idx = find(obj.Station == str2double(stationID));

                % Para contemplar os casos em que é inserido um número de uma
                % estação que foi sumarizada (SMP, por exemplo), busca-se no 
                % LOG da sumarização.
                if isempty(idx)
                    global RFDataHubLog
    
                    pattern = "(?<=[\[,\s])" + string(stationID) + "(?=[,\]\s])";
                    idx = find(~cellfun(@isempty, regexp(RFDataHubLog, pattern)), 1);    
                end
            end
            
            if isempty(idx)
                error('Estação não consta na base <i>offline</i>. Favor confirmar que foi digitado o número corretamente.')
            end
            
            Latitude    = obj.Latitude(idx(1));
            Longitude   = obj.Longitude(idx(1));
            try
                AntennaHeight = str2double(char(obj.AntennaHeight(idx(1))));
    
                mustBeFinite(AntennaHeight)
                mustBeNonnegative(AntennaHeight)
                mustBeNonempty(AntennaHeight)             
            catch
                AntennaHeight = 0;
            end

            Frequency   = sprintf('%.3f, ', obj.Frequency(idx));
            Frequency   = Frequency(1:end-2);
        
            ID          = strjoin(string(idx), ', ');
            Service     = obj.Service(idx(1));
            Station     = obj.Station(idx(1));
            Description = model.RFDataHub.Description(obj, idx(1));
            Details     = jsonencode(obj(idx(1), setdiff(obj.Properties.VariableNames, {'Service', 'Station', 'Latitude', 'Longitude', 'AntennaHeight'})));
                        
            Distance    = deg2km(distance(latNode, longNode, Latitude, Longitude));
            stationInfo = struct('ID', ID, 'Frequency', Frequency, 'Service', Service, 'Station', Station, 'Description', Description, 'Distance', Distance, 'Latitude', Latitude, 'Longitude', Longitude, 'AntennaHeight', AntennaHeight, 'Details', Details);
        end


        %-----------------------------------------------------------------%
        function [logInfo, msgError] = queryLog(RFDataHubLog, logIndex)
            logInfo  = '';
            msgError = '';

            try
                logInfo = jsondecode(RFDataHubLog(logIndex));
            catch ME
                msgError = ME.identifier;
            end
        end

        %-----------------------------------------------------------------%
        function [x1, q1] = parsingAntennaPattern(jsonLikePattern, nPoints)
            arguments
                jsonLikePattern char
                nPoints
            end
            
            FLOATDIFF = model.RFDataHub.FLOATDIFF;

            % Em 25/09/2024, identificados quatro formatos para o campo "AntennaPattern".
            % - Formato mais comum, com 25754 registros:
            %   {'0': 0.9177037335564537, '10': 0.6985564188945784, '20': 0.3638079796500947, '30': 0.22548594332662897, '40': 0.6638087500712568, '50': 1.2732547865907549, '60': 1.6272729749769972, '70': 1.1020136175353965, '80': 0.5082881578835625, '90': 0.09573089456722159, '100': 0, '110': 0.13782203775127294, '120': 0.4489664888753907, '130': 1.2552776209152927, '140': 1.9390081747423877, '150': 1.7968983557179696, '160': 1.4073300379153195, '170': 1.0986853581617657, '180': 0.9177037335564542, '190': 1.0986853581617655, '200': 1.4073300379153189, '210': 1.714016112197751, '220': 1.9613897867099028, '230': 1.7537327030695424, '240': 1.0670683005281094, '250': 0.4489664888753917, '260': 0, '270': 0.13881515303524697, '280': 0.6644095721365442, '290': 1.2369214875015437, '300': 1.515909313797403, '310': 1.1887904746355724, '320': 0.5393825405431028, '330': 0.13121677321905034, '340': 0.2821947863838239, '350': 0.6744149663170143}
            % - Formato com 269 registros:
            %   {'0': '6.77', '10': '7.25', '20': '8.10', '30': '8.30', '40': '8.53', '50': '8.80', '60': '9.10', '70': '9.41', '80': '9.75', '90': '10.09', '100': '10.43', '110': '10.77', '120': '11.11', '130': '11.43', '140': '11.73', '150': '12.00', '160': '12.24', '170': '12.45', '180': '12.61', '190': '12.73', '200': '12.79', '210': '12.79', '220': '8.99', '230': '5.37', '240': '3.25', '250': '1.41', '260': '0.04', '270': '0.00', '280': '5.93', '290': '7.19', '300': '3.76', '310': '4.70', '320': '6.60', '330': '8.02', '340': '8.27', '350': '7.60'}
            % - Formato com 46 registros:
            %   7    7    7    7    7    7    7    7    7    7    7    7    7    8    8    8    9    9    1    1    1    1    1    1    1    1    1    1    1    1    1    1    1    1    1    1    1    1    1    1    1    1    1    1    1    9    9    8    8    8    7    7    7    7    7    7    7    7    7    7    7    7    7    7    7    7    7    7    7    7    7    7
            % - Formato com 21 registros:
            %   1

            % O parser abaixo contempla os dois formatos mais comuns (99.8% 
            % dos registros).
            s = regexp(jsonLikePattern,'''(?<angle>\d+)''\s*:\s*''?(?<gain>[\d\.]+)''?', 'names');

            if ~isempty(s)
                x0 = deg2rad(str2double({s.angle}));
                q0 = str2double({s.gain});
    
                [x0, idxSort] = sort(x0);
                q0 = q0(idxSort);

            else
                % E o parser abaixo contempla o outro formato (0.2% dos registros). 
                % O algoritmo aqui implantado espelha o resultado mostrado no 
                % Relatório de Canal publicado no Mosaico.
                x0 = deg2rad(0:5:355);
                q0 = str2double(strsplit(jsonLikePattern));
                if isscalar(q0)
                    q0 = [q0, zeros(1, 71)];
                end
            end
    
            if (abs(x0(1)-0) <= FLOATDIFF) && (abs(x0(end)-2*pi) > FLOATDIFF)
                x0(end+1) = 2*pi;
                q0(end+1) = q0(1);
            elseif (abs(x0(1)-0) > FLOATDIFF) && (abs(x0(end)-2*pi) <= FLOATDIFF)
                x0 = [0, x0];
                q0 = [q0(end), q0];
            end

            x1 = linspace(0,2*pi,nPoints);
            q1 = interp1(x0, q0, x1, "spline", "extrap");
        end
    end
end