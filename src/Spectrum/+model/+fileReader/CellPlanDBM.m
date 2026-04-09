function specData = CellPlanDBM(specData, fileName, ReadType)

    % Author.: Eric Magalhães Delgado
    % Date...: February 13, 2025
    % Modified: April 09, 2026 by Augusto Peterle
    % Version: 1.13

    arguments
        specData
        fileName   char
        ReadType   char   = 'SingleFile'
    end

    fileID1 = fopen(fileName);
    if fileID1 == -1
        error('File not found.');
    end
    fclose(fileID1);
    
    % Como a estrutura do arquivo binário gerado pelo CellSpectrum não é
    % conhecida, mas a CellPlan disponibilizou uma API para extração de
    % alguns dos seus metadados, além da matriz de níveis, inicialmente, 
    % gera-se um arquivo temporário (no formato .bin), o qual possui uma
    % estrutura conhecida.
    % O fluxo legado continua o mesmo: o executavel externo gera um .bin
    % temporario e o MATLAB interpreta esse conteudo conhecido. A unica
    % diferenca aqui e que a chamada externa passa a ser supervisionada
    % para evitar travamentos indefinidos quando o .dbm vier malformado.
    rawData = convertCellPlanDbmToRawData(fileName);

    switch ReadType
        case {'MetaData', 'SingleFile'}
            specData = Fcn_MetaDataReader(specData, rawData, fileName);

            if strcmp(ReadType, 'SingleFile')
                specData = Fcn_SpecDataReader(specData, rawData);
            end
            
        case 'SpecData'
            specData = copy(specData, {});
            specData = Fcn_SpecDataReader(specData, rawData);
    end
    
end


%-------------------------------------------------------------------------%
% Converte o .dbm em um .bin temporario via reader externo
%-------------------------------------------------------------------------%
% A essencia do reader continua a mesma: o executavel externo gera um
% arquivo temporario conhecido e o MATLAB interpreta esse conteudo. A
% protecao adicionada aqui existe apenas para evitar popup, hang e falhas
% silenciosas na geracao do .bin.
function rawData = convertCellPlanDbmToRawData(fileName)
    exePath  = getCellPlanReaderExecutablePath();
    tempFile = [tempname '.bin'];
    process  = [];

    cleanupTempFile = onCleanup(@() safeDeleteFile(tempFile));

    try
        [exeFolder, ~, ~] = fileparts(exePath);

        % Em vez de system(...) + cd(...), usamos Process/.NET para manter
        % o diretorio de trabalho local ao processo externo, aplicar
        % timeout e encerrar explicitamente o reader quando necessario.
        process = System.Diagnostics.Process();
        processInfo = System.Diagnostics.ProcessStartInfo();
        processInfo.FileName = exePath;
        processInfo.WorkingDirectory = exeFolder;
        processInfo.Arguments = sprintf('"%s" "%s"', fileName, tempFile);
        processInfo.UseShellExecute = false;
        processInfo.CreateNoWindow = true;
        processInfo.WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden;
        process.StartInfo = processInfo;

        started = process.Start();
        if ~started
            error('model:CellPlanDBM:ProcessStartFailed', ...
                'Falha ao iniciar CellPlan_dBmReader.exe.');
        end

        % O timeout evita que um popup/modal do reader externo ou um .dbm
        % corrompido deixem o MATLAB preso indefinidamente.
        timeoutMilliseconds = int32(round(getCellPlanTimeoutSeconds() * 1000));
        hasExited = process.WaitForExit(timeoutMilliseconds);
        if ~hasExited
            try
                process.Kill();
            catch
            end
            try
                process.WaitForExit();
            catch
            end

            error('model:CellPlanDBM:ProcessTimeout', ...
                ['Timeout ao processar arquivo CellPlan DBM. ', ...
                 'O processo externo foi encerrado para evitar travamento.']);
        end
    catch ME
        disposeProcess(process);
        rethrow(ME)
    end

    disposeProcess(process);

    % Alguns ambientes devolvem o controle do processo externo um pouco
    % antes de o .bin ficar visivel no filesystem. Em vez de pausar sempre
    % 100 ms, aguardamos apenas o necessario.
    waitForTempFile(tempFile, 0.10)

    % Se o .bin nao apareceu ao final da execucao, o caso mais comum e
    % falha do reader externo em um .dbm malformado ou nao suportado.
    fileID2 = fopen(tempFile);
    if fileID2 == -1
        error('model:CellPlanDBM:TempfileNotFound', ...
            'Conversao do arquivo DBM nao gerou o arquivo temporario esperado.');
    end

    cleanupFileHandle = onCleanup(@() fclose(fileID2));
    rawData = fread(fileID2, [1, inf], 'uint8=>uint8');
    fclose(fileID2);
    clear cleanupFileHandle
    clear cleanupTempFile
end


%-------------------------------------------------------------------------%
% Timeout opcional para o reader externo
%-------------------------------------------------------------------------%
% Mantemos um default seguro e permitimos override por variavel de
% ambiente para nao exigir recompilacao em caso de ajuste fino.
function timeoutSeconds = getCellPlanTimeoutSeconds()
    timeoutSeconds = 30;

    envCandidates = { ...
        getenv('CELLPLAN_DBM_TIMEOUT_SECONDS'), ...
        getenv('REPOSFI_CELLPLAN_TIMEOUT_SECONDS')};

    for ii = 1:numel(envCandidates)
        envValue = envCandidates{ii};
        if isempty(envValue)
            continue
        end

        parsedValue = str2double(envValue);
        if ~isnan(parsedValue) && isfinite(parsedValue) && (parsedValue > 0)
            timeoutSeconds = parsedValue;
            return
        end
    end
end


%-------------------------------------------------------------------------%
% Localiza o CellPlan_dBmReader.exe
%-------------------------------------------------------------------------%
% O comportamento preferido continua sendo o do reader original: buscar o
% executavel ao lado da propria pasta CellPlanDBM empacotada com este
% reader.
function exePath = getCellPlanReaderExecutablePath()
    baseFolder = fileparts(mfilename('fullpath'));
    exePath = fullfile(baseFolder, 'CellPlanDBM', 'CellPlan_dBmReader.exe');

    if isfile(exePath)
        return
    end

    modelReaderPath = which('model.fileReader.CellPlanDBM');
    if ~isempty(modelReaderPath)
        fallbackPath = fullfile(fileparts(modelReaderPath), 'CellPlanDBM', 'CellPlan_dBmReader.exe');
        if isfile(fallbackPath)
            exePath = fallbackPath;
            return
        end
    end

    error('model:CellPlanDBM:ReaderExecutableNotFound', ...
        'CellPlan_dBmReader.exe nao encontrado ao lado de model.fileReader.CellPlanDBM.');
end


%-------------------------------------------------------------------------%
% Remove arquivo temporario sem mascarar o erro principal
%-------------------------------------------------------------------------%
function safeDeleteFile(filePath)
    try
        if isfile(filePath)
            delete(filePath);
        end
    catch
    end
end


%-------------------------------------------------------------------------%
% Aguarda o .bin aparecer por um curto intervalo
%-------------------------------------------------------------------------%
function waitForTempFile(filePath, timeoutSeconds)
    if isfile(filePath)
        return
    end

    waitTimer = tic;
    while toc(waitTimer) < timeoutSeconds
        pause(0.01)
        if isfile(filePath)
            return
        end
    end
end


%-------------------------------------------------------------------------%
% Libera o objeto .NET Process sem propagar falha de cleanup
%-------------------------------------------------------------------------%
function disposeProcess(process)
    try
        if ~isempty(process)
            process.Dispose();
        end
    catch
    end
end


%-------------------------------------------------------------------------%
function specData = Fcn_MetaDataReader(specData, rawData, fileName)

    % Criação das variáveis principais (specData e gpsData)
    gpsData    = struct('Status', 0, 'Matrix', []);

    % Busca pelas expressões que delimitam os blocos de espectro:
    [startIndex, stopIndex] = findIndexArrays(rawData);
    if isempty(startIndex) || isempty(stopIndex)
        return
    end

    % INFORMAÇÕES EXTRAÍDAS DO NOME DO ARQUIVO
    % 'CWSM21100020_E1_A1_Spec Frq=98.000 Span=20.000 RBW=10.000 [2022-09-25,22-51-30-090-8012].dbm'
    % 'CWSM21100020_E2_A2_Peak Frq=98.000 Span=20.000 RBW=20.000 [2022-09-25,22-51-29-089-2962].dBm'
    % 'CWSM21100020_E2_A3_Mean Frq=98.000 Span=20.000 RBW=20.000 [2022-09-25,22-51-34-097-8392].dBm'
    [~, file, ext] = fileparts(fileName);
    fileNameToken  = regexpi(file, '(?<Receiver>CWSM2\d{6,7})_E(?<Scan>\d*)_A(?<Operation>\d*)_(?<TraceMode>\w*).*', 'names');

    if isempty(fileNameToken)
        receiver  = 'CWSM2110000';
        traceMode = 'ClearWrite';
        threadID  = 1;
    else
        receiver  = fileNameToken.Receiver;
        switch fileNameToken.TraceMode
            case 'Spec'; traceMode = 'ClearWrite';
            case 'Peak'; traceMode = 'MaxHold';
            case 'Mean'; traceMode = 'Average';
        end
        threadID  = str2double([fileNameToken.Scan, fileNameToken.Operation]);
    end

    % Bloco espectral...
    metaDataInfo = model.SpecDataBase.templateMetaData();
    metaDataInfo.DataType  = 1000;
    metaDataInfo.LevelUnit = 'dBm';
    metaDataInfo.TraceMode = traceMode;
    metaDataInfo.Detector  = 'Sample';

    nBlocks = numel(startIndex);
    for ii = 1:nBlocks
        % Índices:
        metaIndex1 = startIndex(ii);
        metaIndex2 = startIndex(ii)+79;
        specIndex1 = startIndex(ii)+80;
        specIndex2 = stopIndex(ii);

        % Blocos:
        metaBlockArray = rawData(metaIndex1:metaIndex2);
        specBlockArray = rawData(specIndex1:specIndex2);

        % Lista completa de metadados incluídos no bloco:
      % NumberOfBlocksInFile    = typecast(metaBlockArray( 1: 4), 'int32');
        DataPoints              = double(typecast(metaBlockArray( 5: 8), 'int32'));
      % ext_NoiseLevelOffset    = typecast(metaBlockArray( 9:16), 'double');
        ext_freq_Hz             = typecast(metaBlockArray(17:24), 'double');
      % ext_ReducedFreqSpan_MHz = typecast(metaBlockArray(25:32), 'double');
      % ext_FullFreqSpan_MHz    = typecast(metaBlockArray(33:40), 'double');
        ext_ResBw_Hz            = typecast(metaBlockArray(41:48), 'double') * 1000;
      % ext_Decimation          = typecast(metaBlockArray(49:52), 'int32');
      % ext_SamplesPerPacket    = typecast(metaBlockArray(53:56), 'int32');
      % ext_PacketsPerBlock     = typecast(metaBlockArray(57:60), 'int32');
      % ext_ppm                 = typecast(metaBlockArray(61:68), 'double');
      % ext_NominalGain         = typecast(metaBlockArray(69:72), 'int32');
      % RecordSize              = typecast(metaBlockArray(73:76), 'int32');
      % Buffer_nElems           = typecast(metaBlockArray(77:80), 'int32');

        % Lista calculada de metadados:
        % (formulação passada por email pela CellPlan)
        metaDataInfo.FreqStart  = ext_freq_Hz - ext_ResBw_Hz * DataPoints/2;
        metaDataInfo.FreqStop   = ext_freq_Hz + ext_ResBw_Hz * (DataPoints/2 - 1);
        metaDataInfo.DataPoints = DataPoints;
        metaDataInfo.Resolution = ext_ResBw_Hz;

        % Mapeamento da leitura dos dados de espectro, além de identificação
        % do fluxo de GPS.
        [specData, idx] = checkNewBlock(specData, metaDataInfo, specIndex1, specIndex2);
        if idx == 1
            gpsData = Read_GPSInfo(gpsData, specBlockArray);
        end        
    end

    % GPS
    if ~isempty(gpsData.Matrix)
        gpsData.Status  = 1;
    end
    gpsSummary = gpsLib.summary(gpsData);

    % Confirma que se tratam de fluxos diferentes, ou apenas um único fluxo
    % que a CellPlan dividiu em diversos blocos por extrapolar o limite de
    % 40 ou 100 MHz.
    if ~isscalar(specData)
        freqStartArray  = arrayfun(@(x) x.MetaData.FreqStart,  specData);
        freqStopArray   = arrayfun(@(x) x.MetaData.FreqStop,   specData);
        dataPointsArray = arrayfun(@(x) x.MetaData.DataPoints, specData);
        stepWidthArray  = (freqStopArray - freqStartArray) ./ (dataPointsArray - 1);
        nSweepsArray    = arrayfun(@(x) height(x.FileMap{1}), specData);

        if isscalar(unique(nSweepsArray)) && ...
                isequal(unique(freqStartArray(2:end) - freqStopArray(1:end-1)), unique(stepWidthArray))

            specData(1).MetaData.FreqStart  = min(freqStartArray);
            specData(1).MetaData.FreqStop   = max(freqStopArray);
            specData(1).MetaData.DataPoints = sum(dataPointsArray);
            specData(1).FileMap             = arrayfun(@(x) x.FileMap{1}, specData, UniformOutput=false);
            
            delete(specData(2:end))
            specData(2:end) = [];
        end
    end

    for jj = 1:numel(specData)
        specData(jj).Receiver = receiver;
        specData(jj).GPS      = rmfield(gpsSummary, 'Matrix');

        nSweeps = height(specData(jj).FileMap{1});
        [beginTime, endTime, revisitTime] = Read_ObservationTime(specData(jj), rawData, nSweeps);
        specData(jj).RelatedFiles(1, {'File', 'Task', 'Id', 'Description', 'BeginTime', 'EndTime', 'NumSweeps', 'RevisitTime', 'GPS'}) = {[file ext], 'Undefined', threadID, 'Undefined', beginTime, endTime, nSweeps, revisitTime, {gpsSummary}};
    end
end


%-------------------------------------------------------------------------%
function [specData, idx] = checkNewBlock(specData, metaDataInfo, specIndex1, specIndex2)

    if isempty(specData)
        idx = 1;
    else
        idx = find(arrayfun(@(x) isequal(metaDataInfo, x), [specData.MetaData]), 1);
        if isempty(idx)
            idx = numel(specData)+1;
        end
    end

    if idx > numel(specData)
        specData(idx).MetaData = metaDataInfo;
        specData(idx).FileMap  = {table('Size',          [0, 2],               ...
                                        'VariableTypes', {'double', 'double'}, ...
                                        'VariableNames', {'StartByte', 'StopByte'})};
    end

    specData(idx).FileMap{1}(end+1,:) = {specIndex1, specIndex2};
end


%-------------------------------------------------------------------------%
function specData = Fcn_SpecDataReader(specData, rawData)
    
    for ii = 1:numel(specData)
        if specData(ii).Enable
            preallocateData(specData(ii))

            nSweeps = specData(ii).RelatedFiles.NumSweeps;
            nBlocks = numel(specData(ii).FileMap);
            
            for jj = 1:nSweeps
                specMergedArray = [];

                for kk = 1:nBlocks
                    specIndex1      = specData(ii).FileMap{kk}.StartByte(jj);
                    specIndex2      = specData(ii).FileMap{kk}.StopByte(jj);
                    specBlockArray  = rawData(specIndex1:specIndex2);
                    specMergedArray = [specMergedArray; (typecast(specBlockArray(25:end), 'single'))'];

                    if kk == 1
                        specData(ii).Data{1}(jj) = Read_TimeStamp(specBlockArray);
                    end
                end

                specData(ii).Data{2}(:,jj) = specMergedArray;
            end
        end
    
        specData(ii).FileMap = [];
    end
end


%-------------------------------------------------------------------------%
function TimeStamp = Read_TimeStamp(specBlockArray)

    Date_Year     = double(specBlockArray(1)) + 2000;
    Date_Month    = double(specBlockArray(2));
    Date_Day      = double(specBlockArray(3));
    Time_Hours    = double(specBlockArray(4));
    Time_Minutes  = double(specBlockArray(5));
    Time_Seconds  = double(specBlockArray(6));
    Time_milliSec = double(typecast(specBlockArray(7:8), 'uint16'));
   
    TimeStamp     = datetime([Date_Year, Date_Month, Date_Day, Time_Hours, Time_Minutes, (Time_Seconds+Time_milliSec/1000)]);
end


%-------------------------------------------------------------------------%
function gpsData = Read_GPSInfo(gpsData, specBlockArray)

    lat  = typecast(specBlockArray( 9:16), 'double');
    long = typecast(specBlockArray(17:24), 'double');

    if (lat ~= -200) && (long ~= -200)
        gpsData.Matrix(end+1,:) = [lat, long];
    end    
end


%-------------------------------------------------------------------------%
function [BeginTime, EndTime, RevisitTime] = Read_ObservationTime(specData, rawData, nSweeps)

    BeginTime = Read_TimeStamp(rawData(specData.FileMap{1}.StartByte(1)  :specData.FileMap{1}.StopByte(1)));
    EndTime   = Read_TimeStamp(rawData(specData.FileMap{1}.StartByte(end):specData.FileMap{1}.StopByte(end)));

    BeginTime.Format = 'dd/MM/yyyy HH:mm:ss';
    EndTime.Format   = 'dd/MM/yyyy HH:mm:ss';

    RevisitTime      = seconds(EndTime-BeginTime)/(nSweeps-1);    
end


%-------------------------------------------------------------------------%
function [startIndex, stopIndex] = findIndexArrays(rawData)
    startIndex = strfind(char(rawData), 'StArT') + 5;
    stopIndex  = strfind(char(rawData), 'StOp')  - 1;

    concIndex  = [];
    try
        concIndex  = zeros(1, numel(startIndex)+numel(stopIndex));
        concIndex(1:2:end) = startIndex;
        concIndex(2:2:end) = stopIndex;
    catch
    end

    if (numel(startIndex) ~= numel(stopIndex)) || (~isempty(concIndex) && ~issorted(concIndex))
        [startIndex, stopIndex] = fixIndexArrays(startIndex, stopIndex);
    end
end


%-------------------------------------------------------------------------%
function [startIndex, stopIndex] = fixIndexArrays(startIndex, stopIndex)
    if isempty(startIndex) || isempty(stopIndex)
        return
    end

    ii = 1;
    while true
        NN = numel(startIndex);
        MM = numel(stopIndex);
        if ii > NN
            break
        end

        if startIndex(ii) > stopIndex(ii)
            stopIndex(ii) = [];
            continue
        elseif (NN > ii) && (startIndex(ii+1) < stopIndex(ii))
            startIndex(ii) = [];
            continue
        end
        ii = ii+1;
    end

    if NN < MM
        startIndex(MM+1:end) = [];
    elseif NN > MM
        stopIndex(NN+1:end)  = [];
    end
end
