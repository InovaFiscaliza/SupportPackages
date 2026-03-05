function specData = SM1809(specData, fileName, ReadType)

    % Author.: Eric Magalhães Delgado
    % Date...: February 13, 2025
    % Version: 1.02

    arguments
        specData
        fileName char
        ReadType char = 'SingleFile'
    end
    
    fileID = fopen(fileName, 'r');
    if fileID == -1
        error('File not found.');
    end
    
    switch ReadType
        case {'MetaData', 'SingleFile'}
            specData = Fcn_MetaDataReader(specData, fileID, fileName);
            
            if strcmp(ReadType, 'SingleFile')
                specData = Fcn_SpecDataReader(specData, fileID);
            end
            
        case 'SpecData'
            specData = copy(specData, {});
            specData = Fcn_SpecDataReader(specData, fileID);
    end

    fclose(fileID);
end


%-------------------------------------------------------------------------%
function specData = Fcn_MetaDataReader(specData, fileID, fileName)

    % Criação das variáveis principais (specData e gpsData)
    gpsData  = struct('Status', 0, 'Matrix', []);

    [~, file, ext] = fileparts(fileName);
    
    while true
        extractedLine = fgetl(fileID);        
        if isempty(extractedLine)
            break
        end
        
        Field = extractBefore(extractedLine, ' ');
        Value = extractAfter(extractedLine,  ' ');
        
        switch Field
            case 'Latitude';             latDegree        = gpsConversionFormats(Value);
            case 'Longitude';            lngDegree        = gpsConversionFormats(Value);
            case 'FreqStart';            freqStart        = strsplit(Value, ';');
            case 'FreqStop';             freqStop         = strsplit(Value, ';');
            case 'AntennaType';          antennaType      = Value;
            case 'FilterBandwidth';      filterBandwidth  = strsplit(Value, ';');
            case 'LevelUnits';           levelUnits       = strsplit(Value, ';');
            case 'Date';                 referenceDate    = Value;
            case 'DataPoints';           dataPoints       = strsplit(Value, ';');
            case 'ScanTime';             revisitTime      = strsplit(Value, ';');
            case 'Detector';             detector         = strsplit(Value, ';');
            case 'TraceMode';            traceMode        = strsplit(Value, ';');
            case {'Samples', 'nSweeps'}; nSweeps          = str2double(Value);
            case {'Node', 'Receiver'};   receiver         = Value;
            case {'ThreadID', 'ID'};     id               = strsplit(Value, ';');
            case 'TaskName';             taskName         = Value;    
            case 'Description';          description      = strsplit(Value, ';');
            case 'ObservationTime';      observationTime  = Value;
        end
    end
    byteOffset = ftell(fileID);
    
    if exist('latDegree', 'var') && ~isempty(latDegree) && exist('lngDegree', 'var') && ~isempty(lngDegree)
        gpsData.Status = 1;
        gpsData.Matrix = [latDegree, lngDegree];
    end
    gpsSummary = gpsLib.summary(gpsData);
    
    for ii=1:numel(freqStart)
        specData(ii).Receiver             = receiver;

        specData(ii).MetaData.DataType    = 1809;
        specData(ii).MetaData.FreqStart   = str2double(freqStart{ii}) * 1e+3;
        specData(ii).MetaData.FreqStop    = str2double(freqStop{ii})  * 1e+3;
        specData(ii).MetaData.DataPoints  = str2double(dataPoints{ii});
        specData(ii).MetaData.TraceMode   = traceMode{ii};

        try
            specData(ii).MetaData.Antenna = jsondecode(antennaType);
        catch
            specData(ii).MetaData.Antenna = struct('Name', antennaType);
        end
        
        switch levelUnits{ii}
            case 'dBm'
                specData(ii).MetaData.LevelUnit = 'dBm';
            case 'dBuV'
                specData(ii).MetaData.LevelUnit = 'dBµV';
            case 'dBuV/m'
                specData(ii).MetaData.LevelUnit = 'dBµV/m';
        end
        
        if ~isempty(filterBandwidth{ii})
            specData(ii).MetaData.Resolution = str2double(filterBandwidth{ii}) * 1e+3;
        end
        
        if ~isempty(traceMode{ii})
            specData(ii).MetaData.TraceMode  = traceMode{ii};
        end
        
        try
            specData(ii).MetaData.Detector   = detector{ii};
        catch
        end

        specData(ii).GPS     = rmfield(gpsSummary, 'Matrix');
        specData(ii).FileMap = struct('ReferenceDate', referenceDate, 'ByteOffset', byteOffset);

        beginTime = datetime(extractBefore(observationTime, ' - '), 'InputFormat', 'dd/MM/yyyy HH:mm:ss', 'Format', 'dd/MM/yyyy HH:mm:ss');
        endTime   = datetime(extractAfter( observationTime, ' - '), 'InputFormat', 'dd/MM/yyyy HH:mm:ss', 'Format', 'dd/MM/yyyy HH:mm:ss');

        specData(ii).RelatedFiles(1, {'File', 'Task', 'Id', 'Description', 'BeginTime', 'EndTime', 'NumSweeps', 'RevisitTime', 'GPS'}) = {[file ext], taskName, str2double(id{ii}), description{ii}, beginTime, endTime, nSweeps, str2double(revisitTime{ii}), {gpsSummary}};
    end
end


%-------------------------------------------------------------------------%
function specData = Fcn_SpecDataReader(specData, fileID)

    fseek(fileID, specData(1).FileMap.ByteOffset, 'bof');
    
    arrayfun(@(x) preallocateData(x), specData)
    
    startDate = specData(1).FileMap.ReferenceDate;
    timeStamp = datetime([0 0 0 0 0 0], 'Format', 'dd/MM/yyyy HH:mm:ss');
    
    kk = zeros(1, numel(specData));
    while true
        extractedLine = fgetl(fileID);        
        if extractedLine == -1
            break

        else
            auxStream = strsplit(extractedLine, ';');
            
            for ii = 1:numel(specData)
                auxData = strsplit(auxStream{ii}, ',');
                
                if ii == 1
                    auxTimeStamp = datetime([startDate auxData{1}], 'InputFormat', 'yyyy-MM-ddHH:mm:ss', 'Format', 'dd/MM/yyyy HH:mm:ss');
                    
                    if auxTimeStamp > timeStamp
                        timeStamp = auxTimeStamp;
                    else
                        timeStamp = auxTimeStamp + days(1);
                        startDate = datestr(timeStamp, 'yyyy-mm-dd');
                    end
                end
                
                if numel(auxData) == specData(ii).MetaData.DataPoints + 1
                    kk(ii) = kk(ii)+1;
                    
                    specData(ii).Data{1}(kk(ii))   = timeStamp;
                    specData(ii).Data{2}(:,kk(ii)) = cellfun(@(x) str2double(x), auxData(2:end))';
                end
            end
        end
    end

    for ii = 1:numel(specData)
        if kk(ii) < specData(ii).RelatedFiles.NumSweeps(1)
            specData(ii).Data{1}(kk(ii)+1:end)   = [];
            specData(ii).Data{2}(:,kk(ii)+1:end) = [];
        end
    end
end


%-------------------------------------------------------------------------%
function outValue = gpsConversionFormats(inValue)
    
    outValue = [];

    if ~isempty(inValue)
        tempValue = strsplit(inValue(1:end-1), '.');
        outValue  = str2double(tempValue{1}) + str2double(tempValue{2})/60 + str2double(tempValue{3})/3600;

        if ismember(inValue(end), {'S', 'W'})
             outValue = -outValue;
        end
    end
end