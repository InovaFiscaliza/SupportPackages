function specData = CellPlanDBM(specData, fileName, ReadType)
    %-----------------------------------------------------------------------------------------------%
    % Autor.: Eric Magalhães Delgado / Marcelo Lúcio Nunes
    % Data...: 09 de abril de2026
    % Versão: 1.20
    % Descrição:
    %   Leitura de arquivos .dBm gerados pela CellPlan usando a DLL IQWrapper.
    %   O método suporta leitura de metadados (FreqStart, FreqStop, DataPoints, Resolution) e níveis de potência (dBm) para arquivos de espectro.
    %   O método é compatível com arquivos de espectro únicos ou divididos em bloc  os pela CellPlan, associando cada bloco à entrada de specData correspondente por meio de comparação de metadados.
    %   O tipo de leitura é controlado pelo argumento ReadType, que pode ser 'MetaData' (apenas metadados), 'SingleFile' (metadados + níveis) ou 'SpecData' (níveis para entradas pré-existentes).
    %   O método também extrai informações de GPS e timestamps.
    % Uso:
    %   specData = CellPlanDBM(specData, fileName, ReadType)
    %   - specData: array de objetos SpecData (pode ser vazio para leitura de metadados)
    %   - fileName: string com o caminho do arquivo .dBm a ser lido
    %   - ReadType: string indicando o tipo de leitura ('MetaData', 'SingleFile' ou 'SpecData')
    %   Retorno: array de objetos SpecData preenchidos com os dados lidos do arquivo .dBm
    % Observações:
    %   - A DLL IQWrapper deve estar presente na pasta 'CellPlanDBM' localizada no mesmo diretório deste arquivo.
    %   - O método garante o fechamento do arquivo e descarregamento da DLL mesmo em caso de erros durante a leitura.
    %   - O método é compatível com arquivos de espectro únicos ou divididos em blocos pela CellPlan, associando cada bloco à entrada de specData correspondente por meio de comparação de metadados.
    %   - O método extrai informações de GPS e timestamps diretamente dos campos do struct hdr  retornado pela DLL, eliminando a necessidade de parsing manual de bytes para essas informações.
    %-----------------------------------------------------------------------------------------------%
    arguments
        specData
        fileName   char
        ReadType   char   = 'SingleFile'
    end

    % Antes de entrar na IQWrapper, fazemos um pre-check barato do arquivo.
    % A intenção é barrar DBMs vazios ou com cabeçalho claramente inválido
    % antes de chamar a DLL, evitando popup modal e travamento em OpenFile.
    Fcn_PrecheckDbmHeader(fileName);

    % A DLL IQWrapper é carregada dinamicamente a partir da pasta 'CellPlanDBM'
    % localizada no mesmo diretório deste arquivo.
    dllFolder  = fullfile(fileparts(mfilename('fullpath')), 'CellPlanDBM');
    rootFolder = pwd;
    cd(dllFolder)

    % Garantia de retorno ao diretório original mesmo em caso de erro durante
    % a leitura DLL.
    cleanupCD = onCleanup(@() cd(rootFolder));

    Fcn_LoadDLL(dllFolder);

    if ~calllib('IQWrapper', 'IQWrapper_Load_Library')
        error('model:fileReader:CellPlanDBM:LoadLibraryFailed', 'Failed to load IQWrapper library.')
    end

    try
        switch ReadType
            case {'MetaData', 'SingleFile'}
                specData = Fcn_MetaDataReader(specData, fileName, ReadType);

            case 'SpecData'
                specData = copy(specData, {});
                specData = Fcn_SpecDataReader(specData, fileName);
        end

    catch ME
        try
            evalc('calllib("IQWrapper", "IQWrapper_CloseFile");');
        catch
        end

        try
            calllib('IQWrapper', 'IQWrapper_Unload_Library');
        catch
        end

        rethrow(ME)
    end

    try
        calllib('IQWrapper', 'IQWrapper_Unload_Library');
    catch
    end
end


%-------------------------------------------------------------------------%
% Valida o cabeçalho textual esperado pela IQWrapper antes de acionar a DLL
%-------------------------------------------------------------------------%
function Fcn_PrecheckDbmHeader(fileName)
    expectedIdentifier = '[CellSpec RawBuffer 009]';
    headerReadLength   = 256;

    % O check de tamanho só trata o caso exato de arquivo vazio.
    % Não usamos limiar arbitrário porque isso seria frágil para DBMs
    % válidos com compressão muito eficiente no ZIP.
    fileInfo = dir(fileName);
    if isempty(fileInfo) || fileInfo.bytes == 0
        error('model:fileReader:CellPlanDBM:EmptyFile', ...
            'DBM file is empty.')
    end

    fileId = fopen(fileName, 'r');
    if fileId == -1
        error('model:fileReader:CellPlanDBM:FileNotFound', ...
            'File not found or access denied.')
    end
    cleanupFile = onCleanup(@() fclose(fileId));

    % Lemos apenas o prefixo do arquivo porque a DLL também decide a
    % validade do DBM logo no cabeçalho. Assim, o pre-check continua leve.
    headerBytes = fread(fileId, [1, headerReadLength], '*uint8');
    if isempty(headerBytes)
        error('model:fileReader:CellPlanDBM:EmptyFile', ...
            'DBM file is empty.')
    end

    headerText = char(headerBytes(headerBytes ~= 0));
    if isempty(strtrim(headerText))
        error('model:fileReader:CellPlanDBM:InvalidHeader', ...
            ['Invalid binary file header. Expected identifier: %s. ', ...
             'Identifier found: <empty>.'], ...
            expectedIdentifier)
    end

    if ~contains(headerText, expectedIdentifier)
        printableMask = headerBytes >= 32 & headerBytes <= 126;
        headerSnippet = strtrim(char(headerBytes(printableMask)));
        headerSnippet = regexprep(headerSnippet, '\s+', ' ');

        if isempty(headerSnippet)
            headerSnippet = '<empty>';
        elseif strlength(string(headerSnippet)) > 96
            headerSnippet = char(extractBefore(string(headerSnippet), 97));
        end

        error('model:fileReader:CellPlanDBM:InvalidHeader', ...
            ['Invalid binary file header. Expected identifier: %s. ', ...
             'Identifier found: %s'], ...
            expectedIdentifier, headerSnippet)
    end

    clear cleanupFile
end


%-------------------------------------------------------------------------%
% Carrega a DLL IQWrapper (apenas uma vez por sessão MATLAB)
%-------------------------------------------------------------------------%
function Fcn_LoadDLL(dllFolder)
    if libisloaded('IQWrapper')
        return
    end

    dllFile   = fullfile(dllFolder, 'IQWrapper.dll');
    protoFile = fullfile(dllFolder, 'IQWrapperProto.m');

    if exist(protoFile, 'file')
        loadlibrary(dllFile, @IQWrapperProto);
    else
        loadlibrary(dllFile, fullfile(dllFolder, 'IQWrapper.h'), ...
            'mfilename', fullfile(dllFolder, 'IQWrapperProto'));
    end
end


%-------------------------------------------------------------------------%
% Inicializa os ponteiros usados pela DLL em cada leitura
%-------------------------------------------------------------------------%
function [hdrPtr, dBmPtr, totPtr, medPtr] = Fcn_InitPointers()
    hdr = struct( ...
        'latitude',                double(0), ...
        'longitude',               double(0), ...
        'altitude',                double(0), ...
        'year',                    uint16(0), ...
        'month',                   uint16(0), ...
        'dayOfWeek',               uint16(0), ...
        'day',                     uint16(0), ...
        'hour',                    uint16(0), ...
        'minute',                  uint16(0), ...
        'second',                  uint16(0), ...
        'milliseconds',            uint16(0), ...
        'packet_timeStamp_sec',    uint32(0), ...
        'packet_timeStamp_psec',   uint64(0), ...
        'ext_NoiseLevelOffset',    double(0), ...
        'ext_Tech',                int32(0),  ...
        'ext_Band',                int32(0),  ...
        'ext_Channel',             int32(0),  ...
        'ext_freq',                double(0), ...
        'ext_ReducedFreqSpan_MHz', double(0), ...
        'ext_FullFreqSpan_MHz',    double(0), ...
        'ext_ResBw_kHz',           double(0), ...
        'ext_Decimation',          int32(0),  ...
        'ext_SamplesPerPacket',    int32(0),  ...
        'ext_PacketsPerBlock',     int32(0),  ...
        'ext_ppm',                 double(0), ...
        'ext_NominalGain',         int32(0),  ...
        'RecordSize',              int32(0),  ...
        'Buffer_nElems',           int32(0),  ...
        'ext_SCS_kHz',             int32(0),  ...
        'DuplexMode',              int32(0)   ...
        );

    hdrPtr = libpointer('CapturedRawBuffer_C', hdr);
    dBmPtr = libpointer('singlePtr', single(zeros(1, 10000)));
    totPtr = libpointer('int32Ptr', 0);   % 3º arg = comprimento (nº de bins)
    medPtr = libpointer('int32Ptr', 0);   % 4º arg = indicador de bloco médio (0 ou 1)
end


%-------------------------------------------------------------------------%
% Lê os metadados do arquivo .dBm e preenche as entradas de specData com as informações de FreqStart,
% FreqStop, DataPoints e Resolution.
% O método também extrai informações de GPS e timestamps diretamente dos campos do struct hdr retornado
% pela DLL.
%-------------------------------------------------------------------------%
function specData = Fcn_MetaDataReader(specData, fileName, ReadType)
    gpsData = struct('Status', 0, 'Matrix', []);

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
        threadID = str2double([fileNameToken.Scan, fileNameToken.Operation]);
    end

    metaDataInfo           = model.SpecDataBase.templateMetaData();
    metaDataInfo.DataType  = 1000;
    metaDataInfo.LevelUnit = 'dBm';
    metaDataInfo.TraceMode = traceMode;
    metaDataInfo.Detector  = 'Sample';

    % Abertura do arquivo via DLL
    nBlocksPtr = libpointer('int32Ptr', 0);
    if ~calllib('IQWrapper', 'IQWrapper_OpenFile', fileName, nBlocksPtr)
        error('model:fileReader:CellPlanDBM:OpenFileFailed', 'Failed to open file.')
    end

    [hdrPtr, dBmPtr, totPtr, medPtr] = Fcn_InitPointers();

    % tempTS{idx}  – datetime row vector (um timestamp por sweep)
    % tempLvl{idx} – single matrix (DataPoints × nSweeps), apenas para SingleFile
    tempTS   = {};
    tempLvl  = {};

    try
        while calllib('IQWrapper', 'IQWrapper_MoreBlocksAvailable')
            calllib('IQWrapper', 'IQWrapper_dBm_NextBlock', hdrPtr, dBmPtr, totPtr, medPtr);

            hdr = hdrPtr.Value;
            tot = double(totPtr.Value);   % número de bins (DataPoints) neste bloco

            ext_freq_Hz  = hdr.ext_freq;
            ext_ResBw_Hz = double(hdr.ext_ResBw_kHz) * 1000;

            metaDataInfo.FreqStart  = ext_freq_Hz - ext_ResBw_Hz * tot / 2;
            metaDataInfo.FreqStop   = ext_freq_Hz + ext_ResBw_Hz * (tot/2 - 1);
            metaDataInfo.DataPoints = tot;
            metaDataInfo.Resolution = ext_ResBw_Hz;

            [specData, idx] = checkNewBlock(specData, metaDataInfo);
            gpsData = Read_GPSInfo(gpsData, hdr);

            ts = Read_TimeStamp(hdr);
            if numel(tempTS) < idx || isempty(tempTS{idx})
                tempTS{idx} = ts;
            else
                tempTS{idx}(end+1) = ts;
            end

            if strcmp(ReadType, 'SingleFile')
                lvl = single(dBmPtr.Value(1:tot))';
                if numel(tempLvl) < idx || isempty(tempLvl{idx})
                    tempLvl{idx} = lvl;
                else
                    tempLvl{idx}(:, end+1) = lvl;
                end
            end
        end

    catch ME
        evalc('calllib("IQWrapper", "IQWrapper_CloseFile");');
        rethrow(ME)
    end

    evalc('calllib("IQWrapper", "IQWrapper_CloseFile");');

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
% Verifica se o bloco lido pela DLL corresponde a um bloco já presente em
% specData (comparando os metadados).
% Se corresponder, retorna o índice do bloco existente. Caso contrário,
% cria uma nova entrada em specData para o % novo bloco e retorna seu índice.
% O método é utilizado para associar cada bloco lido pela DLL à entrada de
% specData correspondente, garantindo que os dados sejam organizados
% corretamente mesmo quando a CellPlan divide o espectro em múltiplos blocos.
% O método é chamado dentro de Fcn_MetaDataReader para cada bloco lido,
% permitindo a construção incremental de specData à medida que os blocos
% são processados.
% A comparação de metadados é feita considerando uma tolerância de 1 Hz para
% FreqStart e FreqStop, para acomodar pequenas variações que podem ocorrer
% entre blocos adjacentes.
% O método também garante que, se um novo bloco for identificado, uma nova
%  entrada em specData seja criada com os metadados correspondentes e um
% FileMap vazio, preparando a estrutura para o preenchimento dos dados posteriormente.
%-------------------------------------------------------------------------%
function [specData, idx] = checkNewBlock(specData, metaDataInfo)
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
% Lê os níveis de potência (dBm) do arquivo .dBm usando a DLL IQWrapper e
% preenche as entradas de specData correspondentes.
% O método associa cada bloco lido pela DLL à entrada de specData correspondente
% por meio de comparação de metadados, garantindo que os níveis sejam organizados
% corretamente mesmo quando a CellPlan divide o espectro em múltiplos blocos.
% O método também acumula os timestamps de cada bloco para cada entrada de specData,
%  registrando o timestamp da sub-faixa de menor frequência como o timestamp
% representativo do sweep.
%-------------------------------------------------------------------------%
function specData = Fcn_SpecDataReader(specData, fileName)
    nBlocksPtr = libpointer('int32Ptr', 0);
    if ~calllib('IQWrapper', 'IQWrapper_OpenFile', fileName, nBlocksPtr)
        error('model:fileReader:CellPlanDBM:OpenFileFailed', 'Failed to open file.')
    end

    [hdrPtr, dBmPtr, totPtr, medPtr] = Fcn_InitPointers();

    nEntries      = numel(specData);
    subBandBuffer = cell(nEntries, 1);   % níveis por sub-faixa de frequência
    tempTS        = cell(nEntries, 1);   % timestamps por entrada

    try
        while calllib('IQWrapper', 'IQWrapper_MoreBlocksAvailable')
            calllib('IQWrapper', 'IQWrapper_dBm_NextBlock', hdrPtr, dBmPtr, totPtr, medPtr);

            hdr = hdrPtr.Value;
            tot = double(totPtr.Value);

            ext_freq_Hz  = hdr.ext_freq;
            ext_ResBw_Hz = double(hdr.ext_ResBw_kHz) * 1000;
            blkFreqStart = ext_freq_Hz - ext_ResBw_Hz * tot / 2;
            blkFreqStop  = ext_freq_Hz + ext_ResBw_Hz * (tot/2 - 1);

            % Associa o bloco à entrada de specData correspondente
            jj = find(arrayfun(@(x) ...
                abs(x.MetaData.FreqStart - blkFreqStart) < 1 || ...
                (blkFreqStart >= x.MetaData.FreqStart - 1 && blkFreqStop <= x.MetaData.FreqStop + 1), ...
                specData), 1);

            if isempty(jj)
                continue
            end

            lvl = single(dBmPtr.Value(1:tot))';

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
                ts = Read_TimeStamp(hdr);
                if isempty(tempTS{jj})
                    tempTS{jj} = ts;
                else
                    tempTS{jj}(end+1) = ts;
                end
            end
        end

    catch ME
        evalc('calllib("IQWrapper", "IQWrapper_CloseFile");');
        rethrow(ME)
    end

    evalc('calllib("IQWrapper", "IQWrapper_CloseFile");');

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
% Lê o timestamp do struct hdr retornado pela DLL e converte para datetime.
%-------------------------------------------------------------------------%
function timeStamp = Read_TimeStamp(hdr)
    timeStamp = datetime([ ...
        double(hdr.year), ...
        double(hdr.month), ...
        double(hdr.day), ...
        double(hdr.hour), ...
        double(hdr.minute), ...
        double(hdr.second) + double(hdr.milliseconds)/1000 ...
    ]);
end


%-------------------------------------------------------------------------%
% Lê as informações de GPS do struct hdr retornado pela DLL e acumula em gpsData.
%-------------------------------------------------------------------------%
function gpsData = Read_GPSInfo(gpsData, hdr)
    if (hdr.latitude ~= -200) && (hdr.longitude ~= -200)
        gpsData.Matrix(end+1,:) = [hdr.latitude, hdr.longitude];
    end
end
