classdef SpecDataBase < handle

    properties
        %-----------------------------------------------------------------%
        Receiver     (1,:) char
        MetaData     (1,1) struct = model.SpecDataBase.templateMetaData()
        Data         cell
        GPS          struct
        RelatedFiles table = table('Size', [0, 9],                                                                                          ...
                                   'VariableTypes', {'cell', 'cell', 'double', 'cell', 'datetime', 'datetime', 'double', 'double', 'cell'}, ...
                                   'VariableNames', {'File', 'Task', 'Id', 'Description', 'BeginTime', 'EndTime', 'NumSweeps', 'RevisitTime', 'GPS'})
        FileMap
        Enable       (1,1) matlab.lang.OnOffSwitchState = 'on' % 1 | 0 | 'on' | 'off' | true | false
    end

    
    methods
        %-----------------------------------------------------------------%
        function [obj, projectData] = read(obj, fileFullName, readType, varargin)
            arguments
                obj
                fileFullName char {mustBeFile}
                readType     char {mustBeMember(readType, {'MetaData', 'SpecData', 'SingleFile'})} = 'SingleFile'
            end

            arguments (Repeating)
                varargin
            end

            projectData = [];
            [~, fileName, fileExt] = fileparts(fileFullName);
            
            switch lower(fileExt)
                case '.zip'
                    [obj, projectData] = model.SpecDataBase.readZipTolerant(obj, fileFullName, readType);
                    return

                case '.bin'
                    switch model.SpecDataBase.checkBinaryFormat(fileFullName)
                        case 'CRFS'
                            obj = model.fileReader.CRFSBin(obj, fileFullName, readType);
                        case 'RFlookBin v.1'
                            obj = model.fileReader.RFlookBinV1(obj, fileFullName, readType);
                        case 'RFlookBin v.2'
                            obj = model.fileReader.RFlookBinV2(obj, fileFullName, readType);
                    end
                case '.dbm'
                    obj = model.fileReader.CellPlanDBM(obj, fileFullName, readType);
                case '.sm1809'
                    obj = model.fileReader.SM1809(obj, fileFullName, readType);
                case '.csv'
                    obj = model.fileReader.ArgusCSV(obj, fileFullName, readType);
                case '.mat'
                    [obj, projectData] = model.fileReader.MAT(fileFullName, readType);
                otherwise
                    error('Unexpected file format "%s"\n%s', fileExt, [fileName, fileExt])
            end

            if ismember(readType, {'SpecData', 'SingleFile'})
                basicStats(obj)
            end
        end

        %-----------------------------------------------------------------%
        function copyObj = copy(obj, fieldsToRemove)
            arguments
                obj
                fieldsToRemove = {}
            end
            % A classe "model.SpecData", do appAnalise, extende a presente classe. 
            % Por essa razão, utiliza-se "eval(class(obj))" de forma que seja criada 
            % uma instância da classe sob análise ("model.SpecData" ou "model.SpecDataBase"). 
            % Essa cópia do objeto é limitada às suas propriedades públicas.

            copyObj  = eval(class(obj));
            propList = setdiff(properties(copyObj), fieldsToRemove);

            for ii = 1:numel(obj)
                for jj = 1:numel(propList)
                    copyObj(ii).(propList{jj}) = obj(ii).(propList{jj});                
                end
            end
        end

        %-----------------------------------------------------------------%
        function preallocateData(obj, fileFormatName)
            arguments
                obj
                fileFormatName = ''
            end

            for ii = 1:numel(obj)
                dataPoints   = obj(ii).MetaData.DataPoints;
                nSweeps      = sum(obj(ii).RelatedFiles.NumSweeps);
    
                obj(ii).Data = {repmat(datetime([0 0 0 0 0 0], 'Format', 'dd/MM/yyyy HH:mm:ss'), 1, nSweeps), ...
                                zeros(dataPoints, nSweeps, 'single'),                                         ...
                                zeros(dataPoints, 3,       'single')};
    
                if ismember(fileFormatName, {'RFlookBin v.2/2', 'RFlookBin v.2/4'})
                    obj(ii).Data{4} = zeros(obj(ii).MetaData.DataPoints, nSweeps, 'single');
                    obj(ii).Data{5} = zeros(obj(ii).MetaData.DataPoints, nSweeps, 'single');
                end
            end
        end

        %-----------------------------------------------------------------%
        function IDs = idList(obj)
            IDs = arrayfun(@(x) x.RelatedFiles.Id(1), obj);
        end

        %-----------------------------------------------------------------%
        function estimatedMemory = computeEstimatedMemory(obj)
            estimatedMemory = sum(arrayfun(@(x) 4 * sum(x.RelatedFiles.NumSweeps) .* x.MetaData.DataPoints, obj)); % Bytes
        end

        %-----------------------------------------------------------------%
        function nSweeps = computeSweepNumber(obj)
            nSweeps = arrayfun(@(x) sum(x.RelatedFiles.NumSweeps), obj)';
        end

        %-----------------------------------------------------------------%
        function basicStats(obj)
            for ii = 1:numel(obj)
                obj(ii).Data{3} = [ min(obj(ii).Data{2}, [], 2), ...
                                   mean(obj(ii).Data{2},     2), ...
                                    max(obj(ii).Data{2}, [], 2)];
            end
        end
    end


    methods (Static = true)
        %-----------------------------------------------------------------%
        function [obj, projectData] = readZipTolerant(obj, fileFullName, readType)
            projectData = [];
            [fileList, tempFolder] = model.fileReader.zipUtils.Zip.extractToWorkspace(fileFullName);
            cleanupFolder = onCleanup(@() model.fileReader.zipUtils.Zip.safeCleanup(tempFolder));

            failedCount = 0;
            firstFailureIdentifier = "";
            firstFailureMessage = "";

            for ii = 1:numel(fileList)
                try
                    tmpObj = read(model.SpecDataBase.empty, fileList{ii}, readType);

                    if ~isempty(tmpObj)
                        obj(end+1) = tmpObj;
                    end

                catch ME
                    failedCount = failedCount + 1;
                    if strlength(firstFailureIdentifier) == 0
                        firstFailureIdentifier = string(ME.identifier);
                        firstFailureMessage = string(ME.message);
                    end
                end
            end

            if failedCount > 0
                if isempty(obj)
                    error('model:SpecDataBase:NoReadableFilesInZip', ...
                        ['Nenhum arquivo legivel foi encontrado no ZIP: %s\n', ...
                         'Primeira falha identificada: [%s] %s'], ...
                        fileFullName, firstFailureIdentifier, firstFailureMessage);
                end

                warning('model:SpecDataBase:ZipPartialRead', ...
                    ['Leitura parcial do ZIP: %d membro(s) falharam em %s. ', ...
                     'Primeira falha: [%s] %s'], ...
                    failedCount, fileFullName, firstFailureIdentifier, firstFailureMessage);
            end
        end

        %-----------------------------------------------------------------%
        function fileFormatName = checkBinaryFormat(fileFullName)
            % O formato .BIN é muito comum, sendo gerado pelo Logger, appColeta
            % e outras tantas aplicações. Essencial, portanto, ler os primeiros
            % bytes do arquivo, identificando no cabeçalho do arquivo o formato.

            fileID     = fopen(fileFullName);
            fileHeader = fread(fileID, [1 36], '*char');
            fclose(fileID);

            if     contains(fileHeader, 'CRFS',          'IgnoreCase', true)
                fileFormatName = 'CRFS';
            elseif contains(fileHeader, 'RFlookBin v.1', 'IgnoreCase', true)
                fileFormatName = 'RFlookBin v.1';
            elseif contains(fileHeader, 'RFlookBin v.2', 'IgnoreCase', true)
                fileFormatName = 'RFlookBin v.2';
            else
                [~, fileName, fileExt] = fileparts(fileFullName);
                error('model:SpecDataBase:UnexpectedHeader', 'Unexpected header for a "bin" file\n%s', [fileName, fileExt])
            end
        end

        %-----------------------------------------------------------------%
        function value = id2str(type, id)
            % Em tese, os IDs do Detector deveriam ser apenas 1 a 4 representando,
            % respectivamente, "Sample", "Average/RMS", "Positive Peak" e "Negative Peak".
            %
            % Foi observado, contudo, arquivos de monitoração gerados pelo appColeta 
            % v. 1.11 nos quais esse ID estava igual a "0". Foram monitorações 
            % conduzidas com o R&S EB500.

            switch type
                case 'TraceMode'
                    switch id
                        case 1; value = 'ClearWrite';
                        case 2; value = 'Average';
                        case 3; value = 'MaxHold';
                        case 4; value = 'MinHold';
                    end

                case 'Detector'
                    switch id
                        case {0, 1}; value = 'Sample';
                        case 2; value = 'Average/RMS';
                        case 3; value = 'Positive Peak';
                        case 4; value = 'Negative Peak';
                    end        

                case 'LevelUnit'
                    switch id
                        case 1; value = 'dBm';
                        case 2; value = 'dBµV';
                        case 3; value = 'dBµV/m';
                    end
            end        
        end

        %-----------------------------------------------------------------%
        function id = str2id(type, value)
            switch type
                case 'TraceMode'
                    switch value
                        case 'ClearWrite'; id = 1;
                        case 'Average';    id = 2;
                        case 'MaxHold';    id = 3;
                        case 'MinHold';    id = 4;
                    end
        
                case 'Detector'
                    switch value
                        case 'Sample';        id = 1;
                        case 'Average/RMS';   id = 2;
                        case 'Positive Peak'; id = 3;
                        case 'Negative Peak'; id = 4;
                    end
        
                case 'LevelUnit'
                    switch value
                        case 'dBm';                id = 1;
                        case {'dBµV', 'dBμV'};     id = 2;
                        case {'dBµV/m', 'dBμV/m'}; id = 3;
                    end
            end        
        end

        %-----------------------------------------------------------------%
        function value = str2str(value)
            value = replace(value, 'μ', 'µ');
        end

        %-----------------------------------------------------------------%
        function templateMetaData = templateMetaData()
            % A propriedade "MetaData" é uma estrutura com os campos aqui
            % abaixo definidos, podendo ser estendida.

            % • DataType: RFlookBin (1-2), CRFSBin (4, 7-8, 60-65 e 67-69), 
            %   Argus (167-168), CellPlan (1000) e SM1809 (1809)
            % • FreqStart/FreqStop: Valor numérico em Hertz
            % • LevelUnit: dBm | dBµV | dBµV/m
            % • Resolution: Valor numérico em Hertz ou -1 (caso não registrado
            %   em arquivo)
            % • TraceMode: "ClearWrite" | "Average" | "MaxHold" | "MinHold" | 
            %   "OCC" | "SingleMeasurement" | "Mean" | "Peak" | "Minimum"
            % • Detector: "Sample" | "Average/RMS" | "Positive Peak" | "Negative Peak"

            templateMetaData = struct('DataType',         [], ...
                                      'FreqStart',        [], ...
                                      'FreqStop',         [], ...
                                      'DataPoints',       [], ...
                                      'Resolution',       -1, ...
                                      'VBW',              -1, ...
                                      'Threshold',        -1, ...
                                      'TraceMode',        '', ...
                                      'TraceIntegration', -1, ...
                                      'Detector',         '', ...
                                      'LevelUnit',        [], ...
                                      'Antenna',          [], ...
                                      'Others',           '');
        end

        %-----------------------------------------------------------------%
        function secundaryMetaData = secundaryMetaData(fileFormatName, originalMetaData)
            % A propriedade "MetaData" tem um campo "Others" para armazenar
            % metadados que constam no arquivo sob análise, mas que não são
            % contemplados em outros campos do objeto model.SpecDataBase.

            % Abaixo a lista de metadados já contemplados em outros campos
            % e que, por essa razão, não constarão em "Others". Inicialmente, 
            % análise restrita ao formato de arquivo gerado pelo appColeta.

            if contains(fileFormatName, 'RFlookBin v.1', 'IgnoreCase', true)
                fieldsList = {'FileName',         ...
                              'EstimatedSamples', ...
                              'WritedSamples',    ...
                              'F0',               ...
                              'F1',               ...
                              'Resolution',       ...
                              'DataPoints',       ...
                              'TraceMode',        ...
                              'Detector',         ...
                              'LevelUnit',        ...
                              'Alignment',        ...
                              'Offset1',          ...
                              'Offset2',          ...
                              'Offset3'};

            elseif contains(fileFormatName, 'RFlookBin v.2', 'IgnoreCase', true)
                fieldsList = {'Receiver',         ...
                              'AntennaInfo',      ...
                              'ID',               ...
                              'Description',      ...
                              'FreqStart',        ...
                              'FreqStop',         ...
                              'DataPoints',       ...
                              'Resolution',       ...
                              'Unit',             ...
                              'TraceMode',        ...
                              'TraceIntegration', ...
                              'Detector'};

            else
                fieldsList = {};
            end

            fieldList2Remove  = fieldnames(originalMetaData);
            fieldList2Remove  = fieldList2Remove(ismember(fieldList2Remove, fieldsList));

            secundaryMetaData = rmfield(originalMetaData, fieldList2Remove);
            secundaryMetaData.FileFormat = fileFormatName;

            secundaryMetaData = structUtil.sortByFieldNames(secundaryMetaData);
            secundaryMetaData = jsonencode(secundaryMetaData);
        end

        %-----------------------------------------------------------------%
        function comparableData = comparableMetaData(specData, generalSettings)
            fieldsToRemove = {'Others'};
            if generalSettings.context.FILE.spectrumConsolidationPolicy.antennaPolicy == "remove"
                fieldsToRemove{end+1} = 'Antenna';
            end
            if generalSettings.context.FILE.spectrumConsolidationPolicy.dataTypePolicy == "remove"
                fieldsToRemove{end+1} = 'DataType';
            end

            for ii = 1:numel(specData)
                tempStruct = rmfield(specData(ii).MetaData, fieldsToRemove);
                tempStruct.Receiver = specData(ii).Receiver;

                if isfield(tempStruct, 'Antenna') && ~isempty(tempStruct.Antenna)
                    antennaFields = fields(tempStruct.Antenna);
                    antennaFieldsToRemove = antennaFields(~ismember(antennaFields, generalSettings.context.FILE.spectrumConsolidationPolicy.antennaAttributes));
                    
                    tempStruct.Antenna = rmfield(tempStruct.Antenna, antennaFieldsToRemove);
                end
        
                comparableData(ii) = tempStruct;
            end
        end
    end
end