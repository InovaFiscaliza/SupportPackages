function specData = RFlookBinV1(specData, fileName, ReadType)

    % Author.: Eric Magalhães Delgado
    % Date...: February 18, 2025
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

    rawData = fread(fileID, [1, inf], 'uint8=>uint8');
    fclose(fileID);

    fileFormat = char(rawData(1:15));
    if ~contains(fileFormat, 'RFlookBin v.1')
        error('It is not a RFlookBinV1 file! :(')
    end

    switch ReadType
        case {'MetaData', 'SingleFile'}
            specData = Fcn_MetaDataReader(specData, rawData, fileFormat, fileName);

            if strcmp(ReadType, 'SingleFile')
                specData = Fcn_SpecDataReader(specData);
            end
            
        case 'SpecData'
            specData = copy(specData, {});
            specData = Fcn_SpecDataReader(specData);
    end
end


%-------------------------------------------------------------------------%
function specData = Fcn_MetaDataReader(specData, rawData, fileFormat, fileName)

    % Criação das variáveis principais (specData e gpsData).
    gpsData  = struct('Status', 0, 'Matrix', []);

    [FileHeaderBlock, gpsTimestampBlock, SpectralBlock] = Fcn_FileMemoryMap(rawData, fileName);
    nSweeps = double(FileHeaderBlock.WritedSamples);
    if ~nSweeps
        return
    end

    [TaskName, ID, Description, Receiver, AntennaInfo, IntegrationFactor] = Fcn_TextBlockRead(rawData(FileHeaderBlock.Offset3+1:end));

    % Metadados principais.
    specData(1).Receiver         = Receiver;
    specData.MetaData.DataType   = 1;
    specData.MetaData.FreqStart  = double(FileHeaderBlock.F0);
    specData.MetaData.FreqStop   = double(FileHeaderBlock.F1);
    specData.MetaData.LevelUnit  = model.SpecDataBase.id2str('LevelUnit', FileHeaderBlock.LevelUnit);
    specData.MetaData.DataPoints = double(FileHeaderBlock.DataPoints);
    specData.MetaData.Resolution = double(FileHeaderBlock.Resolution);
    specData.MetaData.TraceMode  = model.SpecDataBase.id2str('TraceMode', FileHeaderBlock.TraceMode);

    if ~strcmp(specData.MetaData.TraceMode, 'ClearWrite')
        specData.MetaData.TraceIntegration = IntegrationFactor;
    end
    
    specData.MetaData.Detector   = model.SpecDataBase.id2str('Detector', FileHeaderBlock.Detector);
    specData.MetaData.Antenna    = AntennaInfo;
    specData.MetaData.Others     = model.SpecDataBase.secundaryMetaData(fileFormat, FileHeaderBlock);


    % GPS.
    switch FileHeaderBlock.gpsType
        case 0                                                                                      % MANUAL
            gpsData.Status = -1;
            gpsData.Matrix = [double(FileHeaderBlock.Latitude), double(FileHeaderBlock.Longitude)];
        
        otherwise                                                                                   % AUTO (1: BUILT-IN; 2: EXTERNAL)
            gpsArray = zeros(nSweeps, 3, 'single');
            for ii = 1:nSweeps
                gpsArray(ii,:) = [single(gpsTimestampBlock.Data(ii).gpsStatus), gpsTimestampBlock.Data(ii).Latitude, gpsTimestampBlock.Data(ii).Longitude];
            end

            gpsStatus = max(gpsArray(:,1));
            if gpsStatus
                gpsData = gpsLib.interpolation(gpsArray);
            else
                if FileHeaderBlock.gpsStatus
                    gpsData.Status = FileHeaderBlock.gpsStatus;
                    gpsData.Matrix = [double(FileHeaderBlock.Latitude), double(FileHeaderBlock.Longitude)];
                end
            end
    end
    gpsSummary = gpsLib.summary(gpsData);

    % Metadados secundários (incluso na tabela "RelatedFiles"), além de
    % informação acerca do mapeamento do arquivo (para fins de leitura dos
    % dados de espectro).
    [~, file, ext] = fileparts(fileName);
    BeginTime      = datetime(gpsTimestampBlock.Data(1).localTimeStamp,   'Format', 'dd/MM/yyyy HH:mm:ss') + years(2000);
    EndTime        = datetime(gpsTimestampBlock.Data(end).localTimeStamp, 'Format', 'dd/MM/yyyy HH:mm:ss') + years(2000);
    RevisitTime    = seconds(EndTime-BeginTime)/(nSweeps-1);    
    
    specData.GPS = rmfield(gpsSummary, 'Matrix');
    specData.RelatedFiles(end+1,:) = {[file ext], TaskName, ID, Description, BeginTime, EndTime, nSweeps, RevisitTime, {gpsSummary}, char(matlab.lang.internal.uuid())};

    specData.FileMap.BitsPerPoint      = FileHeaderBlock.BitsPerPoint;
    specData.FileMap.gpsTimestampBlock = gpsTimestampBlock;
    specData.FileMap.SpectralBlock     = SpectralBlock;
end


%-------------------------------------------------------------------------%
function specData = Fcn_SpecDataReader(specData)

    if isempty(specData)
        return
    end

    if specData.Enable
        preallocateData(specData)
    
        nSweeps           = specData.RelatedFiles.nSweeps;
        BitsPerPoint      = specData.FileMap.BitsPerPoint;
        gpsTimestampBlock = specData.FileMap.gpsTimestampBlock;
        SpectralBlock     = specData.FileMap.SpectralBlock;
    
        for ii = 1:nSweeps
            specData.Data{1}(ii) = datetime(gpsTimestampBlock.Data(ii).localTimeStamp);
    
            switch BitsPerPoint
                case 8
                    OFFSET = single(gpsTimestampBlock.Data(ii).Offset) - 127.5;
                    specData.Data{2}(:,ii) = single(SpectralBlock.Data.Array(:,ii))./2 + OFFSET;
                case 16
                    specData.Data{2}(:,ii) = single(SpectralBlock.Data.Array(:,ii)) ./ 100;
                case 32
                    specData.Data{2}(:,ii) = SpectralBlock.Data.Array(:,ii);
            end
        end
        
        specData.Data{1} = specData.Data{1} + years(2000);
    end

    specData.FileMap = [];
end


%-------------------------------------------------------------------------%
function [FileHeaderBlock, gpsTimestampBlock, SpectralBlock] = Fcn_FileMemoryMap(rawData, fileName)

    FileHeaderBlock = struct('FileName',         char(rawData(1:15)),                ...
                             'BitsPerPoint',     rawData(16),                        ...
                             'EstimatedSamples', typecast(rawData(17:20), 'uint32'), ...
                             'WritedSamples',    typecast(rawData(21:24), 'uint32'), ...
                             'F0',               typecast(rawData(25:28), 'single'), ...
                             'F1',               typecast(rawData(29:32), 'single'), ...
                             'Resolution',       typecast(rawData(33:36), 'single'), ...
                             'DataPoints',       typecast(rawData(37:38), 'uint16'), ...
                             'TraceMode',        typecast(rawData(39),    'int8'),   ...
                             'Detector',         typecast(rawData(40),    'int8'),   ...
                             'LevelUnit',        typecast(rawData(41),    'int8'),   ...
                             'Preamp',           typecast(rawData(42),    'int8'),   ...
                             'attMode',          typecast(rawData(43),    'int8'),   ...
                             'attFactor',        typecast(rawData(44),    'int8'),   ...
                             'SampleTime',       typecast(rawData(45:48), 'single'), ...
                             'gpsType',          rawData(51),                        ...
                             'gpsStatus',        typecast(rawData(52),    'int8'),   ...
                             'Latitude',         typecast(rawData(53:56), 'single'), ...
                             'Longitude',        typecast(rawData(57:60), 'single'), ...
                             'utcTimeStamp',     typecast(rawData(61:66), 'int8'),   ...
                             'utcTimeStamp_ms',  typecast(rawData(67:68), 'int16'),  ...
                             'Offset1',          typecast(rawData(69:72), 'uint32'), ...
                             'Offset2',          typecast(rawData(73:76), 'uint32'), ...
                             'Offset3',          typecast(rawData(77:80), 'uint32'));
    
    switch FileHeaderBlock.BitsPerPoint
        case  8; dataFormat = 'uint8';
        case 16; dataFormat = 'int16';
        case 32; dataFormat = 'single';
    end
    
    DataPoints    = double(FileHeaderBlock.DataPoints);
    WritedSamples = double(FileHeaderBlock.WritedSamples);
    
    if WritedSamples > 0
        gpsTimestampBlock  = memmapfile(fileName, 'Offset', FileHeaderBlock.Offset1,                ...
                                                  'Format', {'int8',   [1  6], 'localTimeStamp';    ...
                                                             'int16',  [1  1], 'localTimeStamp_ms'; ...
                                                             'int16',  [1  1], 'Offset';            ...
                                                             'uint8',  [1  1], 'attFactor';         ...
                                                             'uint8',  [1  1], 'gpsStatus';         ...
                                                             'single', [1  1], 'Latitude';          ...
                                                             'single', [1  1], 'Longitude'},        ...
                                                  'Repeat', WritedSamples);
        
        SpectralBlock      = memmapfile(fileName, 'Offset', FileHeaderBlock.Offset2,                            ...
                                                  'Format', {dataFormat, [DataPoints, WritedSamples], 'Array'}, ...
                                                  'Repeat', 1);
    else
        gpsTimestampBlock  = [];
        SpectralBlock      = [];
    end
end


%-------------------------------------------------------------------------%
function [TaskName, ID, Description, Receiver, AntennaInfo, IntegrationFactor] = Fcn_TextBlockRead(metaByteStream)

    % - appColeta v. 1.00
    %   "TaskName", "ThreadID", "Description", "Node", "Antenna", "AntennaHeight", 
    %   "AntennaAzimuth" (*), "AntennaElevation" (*) e "RevisitTime" (**).
    %
    % - appColeta v. 1.11
    %   Incluso o campo "IntegrationFactor".
    %
    % - appColeta v. 1.49
    %   Eliminados os campos "AntennaHeight", "AntennaAzimuth" e "AntennaElevation".
    %   As informações sobre a antena estão estruturadas num único campo chamado
    %   "Antenna" (***).
    %
    % - Notas:
    %   *   Campos incluídos apenas se a antena for diretiva.
    %   **  Campo "RevisitTime" contém informação ainda não explorada na atual versão 
    %       do appAnalise.
    %   *** A nova estrutura "Antenna" é formada pelos campos "Name", "TrackingMode", 
    %       "Height", "Azimuth", "Elevation" e "Polarization", a depender do tipo de 
    %       antena. "Height" é uma string no formato "2m" (diferente do antigo campo 
    %       "AntennaHeight" que era numérico).

    metaStruct  = jsondecode(native2unicode(metaByteStream));

    TaskName    = metaStruct.TaskName;
    ID          = metaStruct.ThreadID;
    Description = metaStruct.Description;
    Receiver    = metaStruct.Node;

    if isstruct(metaStruct.Antenna)
        AntennaInfo = metaStruct.Antenna;
    else
        AntennaInfo = struct('Name', metaStruct.Antenna, 'TrackingMode', 'Manual');
    end

    if isfield(metaStruct, 'AntennaHeight')
        AntennaInfo.Height    = sprintf('%dm', metaStruct.AntennaHeight);
    end

    if isfield(metaStruct, 'AntennaAzimuth')
        AntennaInfo.Azimuth   = metaStruct.AntennaAzimuth;
    end

    if isfield(metaStruct, 'AntennaElevation')
        AntennaInfo.Elevation = metaStruct.AntennaElevation;
    end
    
    if isfield(metaStruct, 'IntegrationFactor')
        IntegrationFactor     = metaStruct.IntegrationFactor;
    else
        IntegrationFactor     = -1;
    end
end