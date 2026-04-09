function specData = ProtectedCellPlanDBM(specData, fileName, ReadType)
% ProtectedCellPlanDBM - Reader protegido para arquivos CellPlan .dbm.
%
% O objetivo deste wrapper e evitar que o processo principal do repoSFI
% fique preso em chamadas sincronas ao CellPlan_dBmReader.exe quando um
% arquivo .dbm estiver corrompido ou em formato inesperado. O parser de
% metadados/espectro continua equivalente ao reader original; o que muda
% aqui e a forma de invocar e supervisionar o executavel externo.
%
% Importante: este wrapper nao tenta "julgar" se o .dbm parece valido
% antes da leitura. A responsabilidade principal aqui e:
%   - chamar o CellPlan_dBmReader.exe
%   - capturar falhas de arquivo malformado
%   - aplicar timeout/kill se o executavel externo travar
%   - devolver o mesmo parsing do fluxo legado quando a conversao funcionar

    arguments
        specData
        fileName   char
        ReadType   char = 'SingleFile'
    end

    guardTimer = tic;
    % Esse bloco de log e apenas observabilidade do wrapper; ele nao
    % participa da decisao de leitura nem tenta classificar o .dbm.
    logDetails = struct( ...
        'FilePath', string(fileName), ...
        'ReadType', string(ReadType), ...
        'TimeoutSeconds', getCellPlanTimeoutSeconds());
    logVerboseInfo( ...
        'handlers.internal.ProtectedCellPlanDBM', ...
        'Iniciando leitura protegida de arquivo CellPlan DBM.', ...
        logDetails);

    fileID1 = fopen(fileName);
    if fileID1 == -1
        error('handlers:ProtectedCellPlanDBM:FileNotFound', ...
            'File not found: %s', fileName);
    end
    fclose(fileID1);
    
    try
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

        logDetails.DurationSeconds = toc(guardTimer);
        logDetails.SpectraCount = numel(specData);
        logVerboseInfo( ...
            'handlers.internal.ProtectedCellPlanDBM', ...
            sprintf('Leitura protegida de DBM concluida em %.3f s.', logDetails.DurationSeconds), ...
            logDetails);
    catch ME
        logDetails.DurationSeconds = toc(guardTimer);
        logDetails.Identifier = string(ME.identifier);
        logDetails.ErrorMessage = string(ME.message);
        server.RuntimeLog.logWarning( ...
            'handlers.internal.ProtectedCellPlanDBM', ...
            'Falha na leitura protegida de arquivo CellPlan DBM.', ...
            logDetails);
        rethrow(ME)
    end
end


%-------------------------------------------------------------------------%
% Le timeout opcional do reader externo
%-------------------------------------------------------------------------%
% Mantemos um default seguro para producao e permitimos override por
% variavel de ambiente sem exigir recompilacao do executavel.
function timeoutSeconds = getCellPlanTimeoutSeconds()
    timeoutSeconds = 30;

    envValue = getenv('REPOSFI_CELLPLAN_TIMEOUT_SECONDS');
    if isempty(envValue)
        return
    end

    parsedValue = str2double(envValue);
    if ~isnan(parsedValue) && isfinite(parsedValue) && (parsedValue > 0)
        timeoutSeconds = parsedValue;
    end
end


%-------------------------------------------------------------------------%
% Flag de log fino do pipeline de leitura
%-------------------------------------------------------------------------%
% O default e "off" para reduzir overhead no caminho feliz. Quando
% ativado, esse wrapper registra etapas intermediarias no RuntimeLog.
function enabled = shouldLogVerboseReadFlow()
    persistent cachedEnabled isInitialized

    if isempty(isInitialized)
        envValue = lower(strtrim(char(string(getenv('REPOSFI_VERBOSE_READ_LOGS')))));
        cachedEnabled = ismember(envValue, {'1', 'true', 'on', 'yes'});
        isInitialized = true;
    end

    enabled = cachedEnabled;
end


%-------------------------------------------------------------------------%
% Log informativo condicionado ao modo verbose
%-------------------------------------------------------------------------%
% O wrapper usa esse helper para evitar espalhar ifs de verbose pelo
% codigo principal e manter o caminho feliz mais limpo.
function logVerboseInfo(source, message, details)
    if nargin < 3
        details = [];
    end

    if shouldLogVerboseReadFlow()
        server.RuntimeLog.logInfo(source, message, details);
    end
end


%-------------------------------------------------------------------------%
% Converte o .dbm em um .bin temporario via reader externo
%-------------------------------------------------------------------------%
% Este e o nucleo da protecao. O fluxo e:
%   1. localiza o CellPlan_dBmReader.exe
%   2. executa o processo externo com timeout
%   3. mata o processo se ele travar
%   4. abre o .bin gerado e devolve o rawData para o parser legado
function rawData = convertCellPlanDbmToRawData(fileName)
    processDetails = struct( ...
        'ExecutablePath', "", ...
        'WorkingDirectory', "", ...
        'TempFilePath', "", ...
        'DurationSeconds', 0);

    exePath = getCellPlanReaderExecutablePath();
    [exeFolder, ~, ~] = fileparts(exePath);
    tempFile = [tempname '.bin'];

    % Esses detalhes entram apenas em warning/erro quando houver problema
    % no processo externo ou quando o verbose estiver ligado.
    processDetails.ExecutablePath = string(exePath);
    processDetails.WorkingDirectory = string(exeFolder);
    processDetails.TempFilePath = string(tempFile);

    process = [];
    processTimer = tic;
    try
        % Em vez de system(...), usamos Process/.NET para conseguir aplicar
        % timeout e encerrar explicitamente o executavel externo se ele
        % abrir popup modal ou parar de responder.
        process = System.Diagnostics.Process();
        processInfo = System.Diagnostics.ProcessStartInfo();
        processInfo.FileName = exePath;
        processInfo.WorkingDirectory = exeFolder;
        processInfo.Arguments = sprintf('"%s" "%s"', fileName, tempFile);
        processInfo.UseShellExecute = false;
        processInfo.CreateNoWindow = true;
        processInfo.WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden;
        process.StartInfo = processInfo;

        % Se o processo nem iniciar, nao ha o que recuperar alem de
        % propagar um erro claro para o chamador.
        started = process.Start();
        if ~started
            error('handlers:ProtectedCellPlanDBM:ProcessStartFailed', ...
                'Falha ao iniciar CellPlan_dBmReader.exe.');
        end

        % O timeout existe para evitar que popup/modal ou travamento do
        % reader externo deixem o repoSFI preso indefinidamente.
        timeoutMilliseconds = int32(round(getCellPlanTimeoutSeconds() * 1000));
        hasExited = process.WaitForExit(timeoutMilliseconds);
        processDetails.DurationSeconds = toc(processTimer);

        if ~hasExited
            % Ao detectar hang, encerramos explicitamente o processo e
            % devolvemos erro ao nivel MATLAB em vez de deixar o listener
            % inteiro sem resposta.
            try
                process.Kill();
            catch
            end
            try
                process.WaitForExit();
            catch
            end

            server.RuntimeLog.logWarning( ...
                'handlers.internal.ProtectedCellPlanDBM', ...
                'Timeout ao aguardar o processo CellPlan_dBmReader.exe; processo encerrado.', ...
                processDetails);
            error('handlers:ProtectedCellPlanDBM:ProcessTimeout', ...
                ['Timeout ao processar arquivo CellPlan DBM. ', ...
                 'O processo externo foi encerrado para evitar travamento do servico.']);
        end
        processDetails.DurationSeconds = toc(processTimer);
    catch ME
        % Em qualquer falha, limpamos o temporario e liberamos o objeto
        % Process antes de propagar a excecao.
        safeDeleteFile(tempFile);
        disposeProcess(process);
        rethrow(ME)
    end

    disposeProcess(process);

    % O reader externo pode retornar antes de o arquivo temporario estar
    % totalmente visivel no filesystem. Em vez de pausar 100 ms sempre,
    % esperamos apenas o necessario para reduzir latencia no caminho feliz.
    waitForTempFile(tempFile, 0.10)

    % Se nao existe .bin ao final da execucao, o caso mais comum e falha
    % do reader externo em um .dbm malformado.
    fileID2 = fopen(tempFile);
    if fileID2 == -1
        safeDeleteFile(tempFile);
        error('handlers:ProtectedCellPlanDBM:TempfileNotFound', ...
            'Conversao do arquivo DBM nao gerou o arquivo temporario esperado.');
    end

    cleaner = onCleanup(@() fclose(fileID2));
    rawData = fread(fileID2, [1, inf], 'uint8=>uint8');
    fclose(fileID2);
    clear cleaner

    safeDeleteFile(tempFile);
end


%-------------------------------------------------------------------------%
% Localiza o CellPlan_dBmReader.exe em desenvolvimento e no compilado
%-------------------------------------------------------------------------%
% A prioridade e reproduzir o comportamento do reader legado e, quando o
% layout do compilado variar, fazer fallback controlado nas raizes mais
% provaveis sem exigir ajuste manual do usuario.
function exePath = getCellPlanReaderExecutablePath()
    % O caminho do executavel da CellPlan tende a ser estavel durante toda
    % a vida do processo. Fazemos cache para evitar custo repetido de
    % descoberta a cada .dbm processado.
    persistent cachedExePath

    if ~isempty(cachedExePath) && isfile(cachedExePath)
        exePath = cachedExePath;
        return
    end

    candidates = {};
    searchRoots = {};

    % Primeiro tentamos localizar o reader legado a partir do proprio
    % model.fileReader.CellPlanDBM. Isso replica a estrategia original e
    % funciona melhor no modo compilado, onde o MATLAB extrai os recursos
    % do CTF e o `which(...)` ja costuma apontar para o local real em uso.
    modelReaderPath = which('model.fileReader.CellPlanDBM');
    if ~isempty(modelReaderPath)
        modelReaderFolder = fileparts(modelReaderPath);
        % Dependendo de como o recurso foi empacotado, o executavel pode
        % estar em uma subpasta CellPlanDBM ou diretamente ao lado do
        % reader .m extraido pelo compilado.
        candidates{end+1} = fullfile(modelReaderFolder, 'CellPlanDBM', 'CellPlan_dBmReader.exe'); %#ok<AGROW>
        candidates{end+1} = fullfile(modelReaderFolder, 'CellPlan_dBmReader.exe'); %#ok<AGROW>
        searchRoots{end+1} = modelReaderFolder; %#ok<AGROW>
    end

    thisFileFolder = fileparts(mfilename('fullpath'));
    supportPackagesRoot = fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(thisFileFolder))))));

    % Candidatos do modo de desenvolvimento e do layout mais comum do
    % ctfroot apos a extracao do executavel compilado. Estes caminhos
    % cobrem o uso local no repositrio e tambem layouts simples do
    % empacotamento em que o Spectrum e preservado quase intacto.
    candidates{end+1} = fullfile(supportPackagesRoot, 'src', 'Spectrum', '+model', '+fileReader', 'CellPlanDBM', 'CellPlan_dBmReader.exe'); %#ok<AGROW>
    candidates{end+1} = fullfile(supportPackagesRoot, 'Spectrum', '+model', '+fileReader', 'CellPlanDBM', 'CellPlan_dBmReader.exe'); %#ok<AGROW>

    if isdeployed
        % No compilado, o CTF pode ser expandido de formas ligeiramente
        % diferentes entre versoes do MATLAB Compiler e ambientes alvo.
        % Por isso cobrimos as duas variantes mais provaveis.
        candidates{end+1} = fullfile(ctfroot, 'src', 'Spectrum', '+model', '+fileReader', 'CellPlanDBM', 'CellPlan_dBmReader.exe'); %#ok<AGROW>
        candidates{end+1} = fullfile(ctfroot, 'Spectrum', '+model', '+fileReader', 'CellPlanDBM', 'CellPlan_dBmReader.exe'); %#ok<AGROW>
        searchRoots{end+1} = ctfroot; %#ok<AGROW>
    end

    candidates = unique(candidates, 'stable');

    for ii = 1:numel(candidates)
        if isfile(candidates{ii})
            % Assim que encontramos um caminho valido, ele vira a
            % referencia oficial para as proximas leituras deste processo.
            cachedExePath = candidates{ii};
            exePath = cachedExePath;
            return
        end
    end

    % No compilado, o Application Compiler pode extrair os recursos em um
    % layout levemente diferente do esperado. Como fallback, buscamos o
    % executavel dentro das raizes mais provaveis e mantemos o resultado em
    % cache para nao pagar esse custo a cada leitura de .dbm. Essa busca
    % mais ampla so entra quando os candidatos diretos nao bateram.
    exePath = findReaderExecutableRecursively(searchRoots);
    if ~isempty(exePath)
        cachedExePath = exePath;
        return
    end

    error('handlers:ProtectedCellPlanDBM:ReaderExecutableNotFound', ...
        'CellPlan_dBmReader.exe nao encontrado. Candidatos testados: %s', ...
        strjoin(candidates, ' | '));
end


%-------------------------------------------------------------------------%
% Busca recursiva de fallback do executavel
%-------------------------------------------------------------------------%
% So entra quando os candidatos "diretos" nao bateram. A ideia aqui e
% tolerar pequenas variacoes do layout extraido pelo MATLAB Compiler.
function exePath = findReaderExecutableRecursively(searchRoots)
    % Fallback usado apenas quando o layout do compilado nao corresponde a
    % nenhum dos caminhos previstos acima.
    exePath = '';
    if isempty(searchRoots)
        return
    end

    searchRoots = unique(searchRoots, 'stable');
    for ii = 1:numel(searchRoots)
        currentRoot = searchRoots{ii};
        if ~(isfolder(currentRoot) || isfile(currentRoot))
            continue
        end

        matches = dir(fullfile(currentRoot, '**', 'CellPlan_dBmReader.exe'));
        if isempty(matches)
            continue
        end

        % Preferimos um diretorio que tambem contenha as DLLs da CellPlan,
        % pois isso tende a refletir o layout correto extraido pelo
        % compilado e reduz a chance de achar um executavel "solto" sem as
        % dependencias nativas ao lado.
        for jj = 1:numel(matches)
            candidatePath = fullfile(matches(jj).folder, matches(jj).name);
            if isfile(fullfile(matches(jj).folder, 'IQ_dBm_FileReader.dll'))
                exePath = candidatePath;
                return
            end
        end

        exePath = fullfile(matches(1).folder, matches(1).name);
        return
    end
end


%-------------------------------------------------------------------------%
% Remove arquivo temporario sem interromper o fluxo principal
%-------------------------------------------------------------------------%
% Cleanup de temporario nunca deve substituir o erro real do reader.
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
% Alguns ambientes devolvem o controle do processo externo um pouco antes
% de o arquivo temporario ficar visivel no filesystem.
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
% Libera o objeto .NET Process sem propagar falha de dispose
%-------------------------------------------------------------------------%
% O objetivo e nao trocar o erro principal do reader por um erro secundario
% de cleanup do wrapper.
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

    gpsData    = struct('Status', 0, 'Matrix', []);

    [startIndex, stopIndex] = findIndexArrays(rawData);
    if isempty(startIndex) || isempty(stopIndex)
        return
    end

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

    metaDataInfo = model.SpecDataBase.templateMetaData();
    metaDataInfo.DataType  = 1000;
    metaDataInfo.LevelUnit = 'dBm';
    metaDataInfo.TraceMode = traceMode;
    metaDataInfo.Detector  = 'Sample';

    nBlocks = numel(startIndex);
    for ii = 1:nBlocks
        metaIndex1 = startIndex(ii);
        metaIndex2 = startIndex(ii)+79;
        specIndex1 = startIndex(ii)+80;
        specIndex2 = stopIndex(ii);

        metaBlockArray = rawData(metaIndex1:metaIndex2);
        specBlockArray = rawData(specIndex1:specIndex2);

        DataPoints              = double(typecast(metaBlockArray( 5: 8), 'int32'));
        ext_freq_Hz             = typecast(metaBlockArray(17:24), 'double');
        ext_ResBw_Hz            = typecast(metaBlockArray(41:48), 'double') * 1000;

        metaDataInfo.FreqStart  = ext_freq_Hz - ext_ResBw_Hz * DataPoints/2;
        metaDataInfo.FreqStop   = ext_freq_Hz + ext_ResBw_Hz * (DataPoints/2 - 1);
        metaDataInfo.DataPoints = DataPoints;
        metaDataInfo.Resolution = ext_ResBw_Hz;

        [specData, idx] = checkNewBlock(specData, metaDataInfo, specIndex1, specIndex2);
        if idx == 1
            gpsData = Read_GPSInfo(gpsData, specBlockArray);
        end
    end

    if ~isempty(gpsData.Matrix)
        gpsData.Status  = 1;
    end
    gpsSummary = gpsLib.summary(gpsData);

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
        specData(jj).RelatedFiles(1, {'File', 'Task', 'Id', 'Description', 'BeginTime', 'EndTime', 'NumSweeps', 'RevisitTime', 'GPS'}) = ...
            {[file ext], 'Undefined', threadID, 'Undefined', beginTime, endTime, nSweeps, revisitTime, {gpsSummary}};
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
                    specMergedArray = [specMergedArray; (typecast(specBlockArray(25:end), 'single'))']; %#ok<AGROW>

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
