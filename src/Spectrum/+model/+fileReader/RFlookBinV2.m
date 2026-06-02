function specData = RFlookBinV2(specData, fileName, readType)
    arguments
        specData
        fileName char
        readType char = 'SingleFile'
    end
    
    fileID = fopen(fileName, 'r');
    if fileID == -1
        error('File not found.');
    end

    rawData = fread(fileID, [1, inf], 'uint8=>uint8');
    fclose(fileID);

    fileFormat = char(rawData(1:15));
    if ~contains(fileFormat, 'RFlookBin v.2')
        error('It is not a RFlookBinV2 file! :(')
    end

    switch readType
        case {'MetaData', 'SingleFile'}
            specData = Fcn_MetaDataReader(specData, rawData, fileFormat, fileName);

            if strcmp(readType, 'SingleFile')
                specData = Fcn_SpecDataReader(specData, rawData, fileFormat);
            end
            
        case 'SpecData'
            specData = copy(specData, {});
            specData = Fcn_SpecDataReader(specData, rawData, fileFormat);
    end
end


%-------------------------------------------------------------------------%
function specData = Fcn_MetaDataReader(specData, rawData, fileFormat, fileName)
    gpsData = struct('Status', 0, 'Matrix', []);

    % Busca pelas expressões que delimitam os blocos de espectro:
    blockStart = strfind(char(rawData), 'StArT') + 5;
    blockStop  = strfind(char(rawData), 'StOp')  - 1;

    % Valida paridade e ordenação dos índices. O reshape intercala os vetores
    % em [start1 stop1 start2 stop2 ...], que deve ser estritamente crescente.
    if numel(blockStart) ~= numel(blockStop) || ~issorted(reshape([blockStart; blockStop], 1, []))
        [blockStart, blockStop] = fixIndexArrays(blockStart, blockStop);
    end

    if isempty(blockStart) || isempty(blockStop)
        return
    end

    % Leitura dos principais metadados escritos em arquivo:
    bitsPerSample = rawData(16);                                            % 8 | 16 | 32 (bits)
    attModeId     = rawData(17);                                            % 0 (manual) | 1 (auto)
    gpsModeId     = rawData(18);                                            % 0 (manual) | 1 (Built-in) | 2 (External)
    metaJsonSize  = typecast(rawData(19:22), 'uint32');
    meta          = jsondecode(native2unicode(rawData(23:22+metaJsonSize)));

    specData(1).Receiver = meta.Receiver;

    specData.MetaData.DataType   = 2;
    specData.MetaData.FreqStart  = meta.FreqStart;
    specData.MetaData.FreqStop   = meta.FreqStop;
    specData.MetaData.LevelUnit  = model.SpecDataBase.str2str(meta.Unit);
    specData.MetaData.DataPoints = meta.DataPoints;

    specData.MetaData.Resolution = str2double(extractBefore(meta.Resolution, 'kHz'))*1000;
    if isfield(meta, 'VBW')
        % Campo VBW pode vir no formato "100 kHz" ou "auto".
        vbw = str2double(extractBefore(meta.VBW, 'kHz'))*1000;
        if ~isnan(vbw)
            specData.MetaData.VBW = vbw;
        end
    end

    specData.MetaData.TraceMode = meta.TraceMode;

    if ~strcmp(meta.TraceMode, 'ClearWrite')
        specData.MetaData.TraceIntegration = meta.TraceIntegration;
    end

    specData.MetaData.Detector = meta.Detector;
    specData.MetaData.Antenna  = meta.AntennaInfo;
    specData.MetaData.Others   = model.SpecDataBase.secundaryMetaData(fileFormat, meta);

    % Número de bytes do cabeçalho dos blocos de espectro:
    % (a) blockOffset1: gps e atenuação
    % (b) blockOffset2: RefLevel
    if     gpsModeId && attModeId
        blockOffset1 = 10;
    elseif gpsModeId
        blockOffset1 =  9;
    elseif attModeId
        blockOffset1 =  1;
    else
        blockOffset1 =  0;
    end

    if bitsPerSample == 8
        blockOffset2 = 2;
    else
        blockOffset2 = 0;
    end

    specData.FileMap = struct( ...
        'bitsPerSample', bitsPerSample, ...
        'blockOffset1', blockOffset1, ...
        'blockOffset2', blockOffset2, ...
        'idxTable', table(blockStart', blockStop', 'VariableNames', {'startByte', 'stopByte'}), ...
        'attData', struct('Mode', attModeId, 'Array', []) ...
    );

    % O gpsModeId pode ser 0 (manual), 1 (Built-in) ou 2 (External).
    % (a) Se gpsModeId = 0     >> gpsData.Status = -1
    % (b) Se gpsModeId = 1 | 2 >> gpsData.Status = 0 (invalid) | 1 (valid)
    nSweeps = numel(blockStart);

    if gpsModeId
        gpsMatrix = zeros(nSweeps, 3);
        for ii = 1:nSweeps
            blockArray = rawData(blockStart(ii):blockStop(ii));

            if ii == 1
                beginTime = observationTime(blockArray);
            end

            if ii == nSweeps
                endTime = observationTime(blockArray);
            end

            gpsMatrix(ii,:) = [ ...
                single(blockArray(9)), ...  % STATUS
                typecast(blockArray(10:13), 'single'), ...  % LATITUDE
                typecast(blockArray(14:17), 'single') ... % LONGITUDE
            ];
        end
        gpsData = gpsLib.interpolation(gpsMatrix);

    else
        beginTime = observationTime(rawData(blockStart(1):blockStop(1)));
        endTime   = observationTime(rawData(blockStart(end):blockStop(end)));

        if isfield(meta, 'Latitude') && isfield(meta, 'Longitude')
            gpsData.Status = -1;
            gpsData.Matrix(end+1,:) = [meta.Latitude, meta.Longitude];
        end
    end

    gpsSummary     = gpsLib.summary(gpsData);
    [~, file, ext] = fileparts(fileName);
    revisitTime    = seconds(endTime-beginTime)/(nSweeps-1);

    specData.GPS = rmfield(gpsSummary, 'Matrix');
    specData.RelatedFiles(end+1, {'File', 'Task', 'Id', 'Description', 'BeginTime', 'EndTime', 'NumSweeps', 'RevisitTime', 'GPS'}) = ...
        {[file ext], meta.Task, meta.ID, meta.Description, beginTime, endTime, nSweeps, revisitTime, {gpsSummary}};
end


%-------------------------------------------------------------------------%
function specData = Fcn_SpecDataReader(specData, rawData, fileFormat)

    if isempty(specData)
        return
    end

    if specData.Enable
        nSweeps = specData.RelatedFiles.NumSweeps;
        dataPoints = specData.MetaData.DataPoints;
        offset = [];
        
        if specData.FileMap.attData.Mode
            specData.FileMap.attData.Array = zeros(nSweeps, 1, 'uint8');
        end
    
        % Apenas para simplificar a notação...
        bitsPerSample = specData.FileMap.bitsPerSample;    
        startIndex    = specData.FileMap.idxTable.startByte;
        stopIndex     = specData.FileMap.idxTable.stopByte;    
        blockOffset1  = specData.FileMap.blockOffset1;
        blockOffset2  = specData.FileMap.blockOffset2;

        % Quais dados foram compactados usando GZIP? "ByteStream" ou versão 
        % "uint8" do vetor de níveis?
        isByteStream  = ismember(fileFormat, {'RFlookBin v.2/1', 'RFlookBin v.2/2'});
        hasAzimuth    = ismember(fileFormat, {'RFlookBin v.2/2', 'RFlookBin v.2/4'});

        % Buffer local, evitando a baixa performance no preenchimento das matrizes
        % da propriedade Data do objeto model.SpecDataBase.
        dataTime = repmat(datetime([0 0 0 0 0 0], 'Format', 'dd/MM/yyyy HH:mm:ss'), 1, nSweeps);
        dataLevel = zeros(dataPoints, nSweeps, 'single');

        if hasAzimuth
            dataAzimuth = zeros(dataPoints, nSweeps, 'single');
            dataConfidence = zeros(dataPoints, nSweeps, 'single');
        end

        errorIndex = [];
    
        for ii = 1:nSweeps
            try
                blockArray = rawData(startIndex(ii):stopIndex(ii));
        
                if bitsPerSample == 8
                    refLevel = double(typecast(blockArray(blockOffset1+9:blockOffset1+10), 'int16'));
                    offset = refLevel - 127.5;
                end
        
                compressedArray = blockArray(blockOffset1+blockOffset2+9:end);
                processedArray  = matlabCommunity.CompressLib.decompress(compressedArray, isByteStream);
                newArray = newArrayParsing(processedArray, bitsPerSample, offset, dataPoints, fileFormat);

                dataTime(ii) = observationTime(blockArray);
                dataLevel(:, ii) = newArray(:,1);

                if hasAzimuth
                    dataAzimuth(:, ii) = newArray(:,2);
                    dataConfidence(:, ii) = newArray(:,3);
                end

            catch
                errorIndex(end+1) = ii;
            end
        end

        specData.Data = {dataTime, dataLevel, zeros(dataPoints, 3, 'single')};

        if hasAzimuth
            specData.Data{4} = dataAzimuth;
            specData.Data{5} = dataConfidence;
        end

        if ~isempty(errorIndex)
            switch specData.MetaData.LevelUnit
                case 'dBm';    noiseLevel = -107;
                case 'dBµV';   noiseLevel =    0;
                case 'dBµV/m'; noiseLevel =   13;
            end

            xTimeIndex = setdiff(1:numel(specData.Data{1}), errorIndex);
            yTimeStamp = specData.Data{1}(xTimeIndex);

            specData.Data{1}(errorIndex)   = interp1(xTimeIndex, yTimeStamp, errorIndex, 'linear', 'extrap');
            specData.Data{2}(:,errorIndex) = noiseLevel;
        end
    
        beginTime   = specData.Data{1}(1);
        endTime     = specData.Data{1}(end);
        revisitTime = seconds(endTime-beginTime)/(nSweeps-1);
    
        specData.RelatedFiles(1, {'BeginTime', 'EndTime', 'NumSweeps', 'RevisitTime'}) = {beginTime, endTime, nSweeps, revisitTime};
    end

    specData.FileMap = [];
end


%-------------------------------------------------------------------------%
function newArray = newArrayParsing(processedArray, bitsPerSample, offset, dataPoints, fileFormat)
    newArray(:,1) = newArrayDecompress(processedArray(1:dataPoints), bitsPerSample, offset);

    if ismember(fileFormat, {'RFlookBin v.2/2', 'RFlookBin v.2/4'})
        switch bitsPerSample
            case  8
                kk = 2;
            case 16
                kk = 1;
            case 32
                kk = 1/2;
        end

        idx11 = dataPoints+1;
        idx12 = (kk+1)*dataPoints;
        idx21 = idx12+1;
        idx22 = numel(processedArray);
        
        newArray(:,2) = newArrayDecompress(typecast(processedArray(idx11:idx12), 'uint16'), 16, -1);
        newArray(:,3) = newArrayDecompress(typecast(processedArray(idx21:idx22), 'uint16'), 16, -1);
    end
end


%-------------------------------------------------------------------------%
function newArray = newArrayDecompress(processedArray, bitsPerSample, offset)
    switch bitsPerSample
        case  8
            newArray = single(processedArray)./2 + offset;
        case 16
            newArray = single(processedArray)./100;
        case 32
            newArray = processedArray;
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


%-------------------------------------------------------------------------%
function specificTime = observationTime(blockArray)

    specificTime  = datetime(double(blockArray(1))+2000, ...                % Year
                             double(blockArray(2)),      ...                % Month
                             double(blockArray(3)),      ...                % Date
                             double(blockArray(4)),      ...                % Hour
                             double(blockArray(5)),      ...                % Minute
                             double(blockArray(6)),      ...                % Second
                             double(typecast(blockArray(7:8), 'uint16')));  % Milisecond
end