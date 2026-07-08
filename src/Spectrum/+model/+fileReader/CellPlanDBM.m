function specData = CellPlanDBM(specData, fileName, readType)
    %---------------------------------------------------------------------%
    % Leitura de arquivos .dBm gerados por estação de monitoração fornecida 
    % pela CellPlan. Arquivos comprimidos (CelZip) são descomprimidos via
    % CelZip64.dll; a leitura binária do formato .dBm é feita em MATLAB.
    % A DLL CelZip64.dll deve estar presente na subpasta "CellPlanDBM".
    % Author.: Eric Magalhães Delgado / Marcelo Lúcio Nuness
    % Date...: July 08, 2026
    % Version: 2.10
    %---------------------------------------------------------------------%
    arguments
        specData
        fileName (1,:) char
        readType (1,:) char {mustBeMember(readType, {'MetaData', 'SpecData', 'SingleFile'})}  = 'SingleFile'
    end

    % Garante retorno ao diretório original mesmo em caso de erro.
    initFolder = pwd;
    cleanupCD  = onCleanup(@() cd(initFolder));

    % Localiza a subpasta com a DLL e ajusta o PATH do Windows para que
    % as dependências de runtime da CelZip64 sejam encontradas.
    dllFolder = fullfile(fileparts(mfilename('fullpath')), 'CellPlanDBM');
    cd(dllFolder)

    prevPath    = getenv('PATH');
    cleanupPath = onCleanup(@() setenv('PATH', prevPath));
    setenv('PATH', [dllFolder pathsep prevPath]);

    % Descomprime o arquivo caso necessário e retorna o path legível.
    [readableFile, cleanupTemp] = Fcn_DecompressIfNeeded(fileName, dllFolder);

    switch readType
        case {'MetaData', 'SingleFile'}
            specData = Fcn_MetaDataReader(specData, readableFile, fileName, readType);

        case 'SpecData'
            specData = copy(specData, {});
            specData = Fcn_SpecDataReader(specData, readableFile);
    end
end

%-------------------------------------------------------------------------%
function [readableFile, cleanupTemp] = Fcn_DecompressIfNeeded(fileName, dllFolder)
    % Retorna o path de um arquivo .dBm diretamente legível (header ASCII
    % '[CellSpec RawBuffer 009]'). Se o arquivo original já for legível,
    % devolve-o sem modificação. Caso contrário, descomprime via
    % CelZip64.dll para um arquivo temporário e registra onCleanup para
    % sua remoção automática.

    fileInfo = dir(fileName);
    if isempty(fileInfo) || fileInfo.bytes == 0
        error('model:fileReader:CellPlanDBM:EmptyFile', 'File empty.')
    end

    fileId = fopen(fileName, 'r', 'ieee-le');
    if fileId == -1
        error('model:fileReader:CellPlanDBM:FileNotFound', 'File not found or access denied.')
    end
    fclose(fileId);

    if Fcn_IsRawDbm(fileName)
        % Arquivo já está no formato binário legível — sem decompressão.
        readableFile = fileName;
        cleanupTemp  = [];
        return
    end

    % Arquivo não legível diretamente: precisa da DLL de descompressão.
    if ~libisloaded('CelZip64')
        loadlibrary(fullfile(dllFolder, 'CelZip64.dll'), @CelZip64Proto);
    end

    % Arquivo comprimido: descomprime para arquivo temporário.
    tempFile = [tempname '.dBm'];
    cleanupTemp = onCleanup(@() Fcn_DeleteIfExists(tempFile));

    bufferPtr    = libpointer('voidPtr', 0);
    bufferPtrPtr = libpointer('voidPtrPtr', bufferPtr);

    outputSize = calllib('CelZip64', 'FullDecompression', bufferPtrPtr, fileName, tempFile);
    calllib('CelZip64', 'FreeComprMem', bufferPtr);

    if outputSize <= 0 || ~isfile(tempFile)
        error('model:fileReader:CellPlanDBM:DecompressionFailed', ...
            'CelZip64.dll falha ao descomprimir o arquivo (returned %d bytes): %s', outputSize, fileName)
    end

    if ~Fcn_IsRawDbm(tempFile)
        error('model:fileReader:CellPlanDBM:InvalidHeader', ...
            'Arquivo descomprimido não possui o header esperado "[CellSpec RawBuffer 009]": %s', fileName)
    end

    readableFile = tempFile;
end

%-------------------------------------------------------------------------%
function value = Fcn_IsRawDbm(fileName)
    % Retorna true se o arquivo já possui o header ASCII da CellPlan.
    fid = fopen(fileName, 'r', 'ieee-le');
    if fid < 0
        value = false;
        return
    end
    cleanupFid = onCleanup(@() fclose(fid));
    declaredLen = fread(fid, 1, 'uint8=>double');
    if isempty(declaredLen) || declaredLen <= 0 || declaredLen > 64
        value = false;
        return
    end
    raw = fread(fid, declaredLen, '*uint8')';
    value = strcmp(char(raw), '[CellSpec RawBuffer 009]');
end

%-------------------------------------------------------------------------%
function Fcn_DeleteIfExists(fileName)
    if isfile(fileName)
        delete(fileName);
    end
end

%-------------------------------------------------------------------------%
function specData = Fcn_MetaDataReader(specData, readableFile, originalFileName, ReadType)
    gpsData = struct('Status', 0, 'Matrix', []);

    [~, file, ext] = fileparts(originalFileName);
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
        threadID = str2double([fileNameToken.Scan, fileNameToken.Operation]);
    end

    metaDataInfo           = model.SpecDataBase.templateMetaData();
    metaDataInfo.DataType  = 1000;
    metaDataInfo.LevelUnit = 'dBm';
    metaDataInfo.TraceMode = traceMode;
    metaDataInfo.Detector  = 'Sample';

    % Leitura binária pura do arquivo .dBm descomprimido.
    fid = fopen(readableFile, 'r', 'ieee-le');
    if fid == -1
        error('model:fileReader:CellPlanDBM:OpenFileFailed', 'Falha ao abrir o arquivo: %s', readableFile)
    end
    cleanupFid = onCleanup(@() fclose(fid));

    fileHeader = Fcn_ReadDbmFileHeader(fid);

    % tempTS{idx}  – datetime row vector (um timestamp por sweep)
    % tempLvl{idx} – single matrix (DataPoints × nSweeps), apenas para SingleFile
    tempTS  = {};
    tempLvl = {};

    for sweepIdx = 1:fileHeader.numberOfRecords
        sweep = Fcn_ReadDbmSweep(fid, fileHeader, sweepIdx);

        ext_freq_Hz  = sweep.frequencyHz;
        ext_ResBw_Hz = sweep.resolutionBandwidthkHz * 1000;
        bufferElements = sweep.bufferNumberOfElements;
        tot            = Fcn_ExpectedDataPoints(fileHeader.frequencySpanMHz, ext_ResBw_Hz, bufferElements);
        cropStartIdx   = Fcn_CenterCropStartIndex(bufferElements, tot);

        metaDataInfo.FreqStart  = ext_freq_Hz - ext_ResBw_Hz * tot / 2;
        metaDataInfo.FreqStop   = ext_freq_Hz + ext_ResBw_Hz * (tot/2 - 1);
        metaDataInfo.DataPoints = tot;
        metaDataInfo.Resolution = ext_ResBw_Hz;

        [specData, idx] = findOrCreateFlow(specData, metaDataInfo);
        gpsData = appendValidGPSData(gpsData, sweep);

        ts = extractTimestamp(sweep);
        if numel(tempTS) < idx || isempty(tempTS{idx})
            tempTS{idx} = ts;
        else
            tempTS{idx}(end+1) = ts;
        end

        if strcmp(ReadType, 'SingleFile')
            lvl = single(sweep.spectrumData)';
            if numel(lvl) > tot
                lvl = lvl(cropStartIdx:cropStartIdx + tot - 1);
            end
            if numel(tempLvl) < idx || isempty(tempLvl{idx})
                tempLvl{idx} = lvl;
            else
                tempLvl{idx}(:, end+1) = lvl;
            end
        end
    end

    if isempty(specData)
        return
    end

    % GPS
    if ~isempty(gpsData.Matrix)
        gpsData.Status = 1;
    end
    gpsSummary = gpsLib.summary(gpsData);

    % Confirma se são diferentes fluxos ou um único fluxo que a CellPlan
    % dividiu em blocos por extrapolar o limite de 40 ou 100 MHz.
    if ~isscalar(specData)
        freqStartArray  = arrayfun(@(x) x.MetaData.FreqStart,  specData);
        freqStopArray   = arrayfun(@(x) x.MetaData.FreqStop,   specData);
        dataPointsArray = arrayfun(@(x) x.MetaData.DataPoints, specData);
        stepWidthArray  = (freqStopArray - freqStartArray) ./ (dataPointsArray - 1);
        nSweepsArray    = cellfun(@numel, tempTS);

        if isscalar(unique(nSweepsArray)) && ...
                isequal(unique(freqStartArray(2:end) - freqStopArray(1:end-1)), unique(stepWidthArray))

            specData(1).MetaData.FreqStart  = min(freqStartArray);
            specData(1).MetaData.FreqStop   = max(freqStopArray);
            specData(1).MetaData.DataPoints = sum(dataPointsArray);

            if strcmp(ReadType, 'SingleFile')
                tempLvl{1} = vertcat(tempLvl{:});
                tempLvl    = tempLvl(1);
            end

            tempTS = tempTS(1);
            delete(specData(2:end))
            specData(2:end) = [];
        end
    end

    for jj = 1:numel(specData)
        specData(jj).Receiver = receiver;
        specData(jj).GPS      = rmfield(gpsSummary, 'Matrix');
        specData(jj).FileMap  = [];

        tsArray        = tempTS{jj};
        tsArray.Format = 'dd/MM/yyyy HH:mm:ss';
        nSweeps        = numel(tsArray);
        beginTime      = tsArray(1);
        endTime        = tsArray(end);
        revisitTime    = seconds(endTime - beginTime) / max(nSweeps - 1, 1);

        specData(jj).RelatedFiles(1, {'File', 'Task', 'Id', 'Description', 'BeginTime', 'EndTime', 'NumSweeps', 'RevisitTime', 'GPS'}) = ...
            {[file ext], 'Undefined', threadID, 'Undefined', beginTime, endTime, nSweeps, revisitTime, {gpsSummary}};

        if strcmp(ReadType, 'SingleFile') && specData(jj).Enable
            preallocateData(specData(jj))
            specData(jj).Data{1} = tsArray;
            specData(jj).Data{2} = tempLvl{jj};
        end
    end
end

%-------------------------------------------------------------------------%
function specData = Fcn_SpecDataReader(specData, readableFile)
    fid = fopen(readableFile, 'r', 'ieee-le');
    if fid == -1
        error('model:fileReader:CellPlanDBM:OpenFileFailed', 'Failed to open file: %s', readableFile)
    end
    cleanupFid = onCleanup(@() fclose(fid));

    fileHeader = Fcn_ReadDbmFileHeader(fid);

    nEntries      = numel(specData);
    subBandBuffer = cell(nEntries, 1);   % níveis por sub-faixa de frequência
    tempTS        = cell(nEntries, 1);   % timestamps por entrada

    for sweepIdx = 1:fileHeader.numberOfRecords
        sweep = Fcn_ReadDbmSweep(fid, fileHeader, sweepIdx);

        ext_ResBw_Hz = sweep.resolutionBandwidthkHz * 1000;
        bufferElements = sweep.bufferNumberOfElements;
        tot            = Fcn_ExpectedDataPoints(fileHeader.frequencySpanMHz, ext_ResBw_Hz, bufferElements);
        cropStartIdx   = Fcn_CenterCropStartIndex(bufferElements, tot);
        blkFreqStart = sweep.frequencyHz - ext_ResBw_Hz * tot / 2;
        blkFreqStop  = sweep.frequencyHz + ext_ResBw_Hz * (tot/2 - 1);

        % Associa o sweep à entrada de specData correspondente
        jj = find(arrayfun(@(x) ...
            abs(x.MetaData.FreqStart - blkFreqStart) < 1 || ...
            (blkFreqStart >= x.MetaData.FreqStart - 1 && blkFreqStop <= x.MetaData.FreqStop + 1), ...
            specData), 1);

        if isempty(jj)
            continue
        end

        lvl = single(sweep.spectrumData)';
        if numel(lvl) > tot
            lvl = lvl(cropStartIdx:cropStartIdx + tot - 1);
        end

        % Localiza ou cria slot de sub-faixa no buffer
        sbIdx = [];
        if ~isempty(subBandBuffer{jj})
            sbIdx = find(abs([subBandBuffer{jj}.freqStart] - blkFreqStart) < 1, 1);
        end

        if isempty(sbIdx)
            sbIdx = numel(subBandBuffer{jj}) + 1;
            subBandBuffer{jj}(sbIdx).freqStart = blkFreqStart;
            subBandBuffer{jj}(sbIdx).levels    = lvl;
        else
            subBandBuffer{jj}(sbIdx).levels(:, end+1) = lvl;
        end

        % Timestamp registrado pela sub-faixa de menor frequência
        if blkFreqStart <= specData(jj).MetaData.FreqStart + 1
            ts = extractTimestamp(sweep);
            if isempty(tempTS{jj})
                tempTS{jj} = ts;
            else
                tempTS{jj}(end+1) = ts;
            end
        end
    end

    for jj = 1:nEntries
        if specData(jj).Enable && ~isempty(tempTS{jj})
            preallocateData(specData(jj))

            tsArray        = tempTS{jj};
            tsArray.Format = 'dd/MM/yyyy HH:mm:ss';
            specData(jj).Data{1} = tsArray;

            if ~isempty(subBandBuffer{jj})
                [~, order]           = sort([subBandBuffer{jj}.freqStart]);
                sortedBands          = subBandBuffer{jj}(order);
                specData(jj).Data{2} = vertcat(sortedBands.levels);
            end
        end
        specData(jj).FileMap = [];
    end
end

%-------------------------------------------------------------------------%
function [specData, idx] = findOrCreateFlow(specData, metaDataInfo)
    if isempty(specData)
        idx = 1;
    else
        idx = find(arrayfun(@(x) isequal(metaDataInfo, x), [specData.MetaData]), 1);
        if isempty(idx)
            idx = numel(specData) + 1;
        end
    end

    if idx > numel(specData)
        specData(idx).MetaData = metaDataInfo;
        specData(idx).FileMap  = [];
    end
end

%-------------------------------------------------------------------------%
function timeStamp = extractTimestamp(sweep)
    t = sweep.systemTime;
    timeStamp = datetime([ ...
        double(t.year), ...
        double(t.month), ...
        double(t.day), ...
        double(t.hour), ...
        double(t.minute), ...
        double(t.second) + double(t.millisecond)/1000 ...
    ]);
end

%-------------------------------------------------------------------------%
function gpsData = appendValidGPSData(gpsData, sweep)
    if (sweep.latitude ~= -200) && (sweep.longitude ~= -200)
        gpsData.Matrix(end+1,:) = [sweep.latitude, sweep.longitude];
    end
end

%-------------------------------------------------------------------------%
function fileHeader = Fcn_ReadDbmFileHeader(fid)
    maxCenterFrequencies = 8192;

    fileHeader = struct();
    fileHeader.fileIdentifier        = Fcn_ReadPrefixedString(fid, 0,   33);
    fileHeader.headerSize            = Fcn_ReadScalar(fid,  36, 'int32');
    fileHeader.numberOfRecords       = Fcn_ReadScalar(fid,  40, 'int32');
    fileHeader.recordSize            = Fcn_ReadScalar(fid,  44, 'int32');
    fileHeader.frequencySpanMHz      = Fcn_ReadScalar(fid, 136, 'double');
    fileHeader.resolutionBandwidthkHz = Fcn_ReadScalar(fid, 152, 'double');
    fileHeader.spectrumBufferType    = Fcn_ReadScalar(fid, 193, 'uint8');
    fileHeader.totalCenterFrequencies = Fcn_ReadScalar(fid, 200, 'int32');

    fseek(fid, 208, 'bof');
    centerFrequencies = fread(fid, maxCenterFrequencies, 'double=>double')';
    fileHeader.centerFrequenciesMHz = centerFrequencies(1:fileHeader.totalCenterFrequencies);
end

%-------------------------------------------------------------------------%
function sweep = Fcn_ReadDbmSweep(fid, fileHeader, sweepIndex)
    r = fileHeader.headerSize + (sweepIndex - 1) * fileHeader.recordSize;  % base offset

    sweep.latitude   = Fcn_ReadScalar(fid, r +  0, 'double');
    sweep.longitude  = Fcn_ReadScalar(fid, r +  8, 'double');

    sweep.systemTime = struct( ...
        'year',        Fcn_ReadScalar(fid, r + 24, 'uint16'), ...
        'month',       Fcn_ReadScalar(fid, r + 26, 'uint16'), ...
        'day',         Fcn_ReadScalar(fid, r + 30, 'uint16'), ...
        'hour',        Fcn_ReadScalar(fid, r + 32, 'uint16'), ...
        'minute',      Fcn_ReadScalar(fid, r + 34, 'uint16'), ...
        'second',      Fcn_ReadScalar(fid, r + 36, 'uint16'), ...
        'millisecond', Fcn_ReadScalar(fid, r + 38, 'uint16') ...
        );

    sweep.frequencyHz             = Fcn_ReadScalar(fid, r +  80, 'double');
    sweep.resolutionBandwidthkHz  = Fcn_ReadScalar(fid, r + 104, 'double');
    sweep.bufferNumberOfElements  = double(Fcn_ReadScalar(fid, r + 144, 'int32'));

    sweep.spectrumData = Fcn_ReadSpectrumBuffer( ...
        fid, r + 156, fileHeader.spectrumBufferType, sweep.bufferNumberOfElements);
end

%-------------------------------------------------------------------------%
function data = Fcn_ReadSpectrumBuffer(fid, offset, bufferType, elementCount)
    fseek(fid, offset, 'bof');
    switch double(bufferType)
        case 0   % Spectrum_2Bytes_dBm: int16 / 100
            raw  = fread(fid, elementCount, 'int16=>double')';
            data = raw / 100;
        case 1   % Spectrum_1Byte_dBm: int8 - 220
            raw  = fread(fid, elementCount, 'int8=>double')';
            data = raw - 220;
        otherwise
            error('model:fileReader:CellPlanDBM:UnsupportedBufferType', ...
                'Unsupported spectrum buffer type: %d', bufferType)
    end
end

%-------------------------------------------------------------------------%
function value = Fcn_ReadScalar(fid, offset, precision)
    fseek(fid, offset, 'bof');
    value = fread(fid, 1, [precision '=>' precision]);
end

%-------------------------------------------------------------------------%
function value = Fcn_ReadPrefixedString(fid, offset, fieldSize)
    fseek(fid, offset, 'bof');
    declaredLen = fread(fid, 1, 'uint8=>double');
    raw         = fread(fid, fieldSize - 1, '*uint8')';
    actualLen   = min(declaredLen, numel(raw));
    value       = char(raw(1:actualLen));
end

%-------------------------------------------------------------------------%
function tot = Fcn_ExpectedDataPoints(frequencySpanMHz, resolutionBandwidthHz, bufferElements)
    if frequencySpanMHz > 0 && resolutionBandwidthHz > 0
        tot = round((frequencySpanMHz * 1e6) / resolutionBandwidthHz) + 2;
    else
        tot = bufferElements;
    end
end

%-------------------------------------------------------------------------%
function cropStartIdx = Fcn_CenterCropStartIndex(bufferElements, tot)
    cropStartIdx = floor((bufferElements - tot) / 2) + 1;
    cropStartIdx = max(cropStartIdx, 1);
end
