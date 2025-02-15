classdef SpecDataBase < handle

    properties
        %-----------------------------------------------------------------%
        Receiver     (1,:) char
        MetaData     (1,1) struct = model.SpecDataBase.templateMetaData()
        Data         cell
        GPS          struct
        RelatedFiles table = table('Size', [0,10],                                                                                                  ...
                                   'VariableTypes', {'cell', 'cell', 'double', 'cell', 'datetime', 'datetime', 'double', 'double', 'cell', 'cell'}, ...
                                   'VariableNames', {'File', 'Task', 'ID', 'Description', 'BeginTime', 'EndTime', 'nSweeps', 'RevisitTime', 'GPS', 'uuid'})
        FileMap
        Enable       (1,1) matlab.lang.OnOffSwitchState = 'on'              % 1 | 0 | 'on' | 'off' | true | false
    end

    
    methods
        %-----------------------------------------------------------------%
        function [obj, varargout] = read(obj, fileFullName, readType, varargin)
            arguments
                obj
                fileFullName char
                readType     char {mustBeMember(readType, {'MetaData', 'SpecData', 'SingleFile'})} = 'SingleFile'
            end

            arguments (Repeating)
                varargin
            end

            varargout = {[]};
            [~, ~, fileExt] = fileparts(fileFullName);
            
            switch lower(fileExt)
                case '.bin'
                    switch model.SpecDataBase.checkBINFormat(fileFullName)
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
                    [obj, varargout{1}] = model.fileReader.MAT(obj, fileFullName, readType);
            end

            if ismember(readType, {'SpecData', 'SingleFile'})
                basicStats(obj)
            end
        end

        %-----------------------------------------------------------------%
        function copyObj = copy(obj, fields2remove)            
            copyObj  = model.SpecDataBase();
            propList = setdiff(properties(copyObj), fields2remove);

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
                nSweeps      = sum(obj(ii).RelatedFiles.nSweeps);
    
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
            IDs = arrayfun(@(x) x.RelatedFiles.ID(1), obj);
        end

        %-----------------------------------------------------------------%
        function estimatedMemory = estimateMemory(obj)
            estimatedMemory = sum(arrayfun(@(x) 4 * sum(x.RelatedFiles.nSweeps) .* x.MetaData.DataPoints, obj)) .* 1e-6; % MB
        end

        %-----------------------------------------------------------------%
        function sweepsPerThread = sweepsPerThread(obj)
            sweepsPerThread = arrayfun(@(x) sum(x.RelatedFiles.nSweeps), obj)';
        end

        %-----------------------------------------------------------------%
        function basicStats(obj)
            for ii = 1:numel(obj)
                if obj(ii).Enable
                    obj(ii).Data{3} = [ min(obj(ii).Data{2}, [], 2), ...
                                       mean(obj(ii).Data{2},     2), ...
                                        max(obj(ii).Data{2}, [], 2)];
                end
            end
        end
    end


    methods (Static = true)
        %-----------------------------------------------------------------%
        function fileFormatName = checkBINFormat(fileFullName)
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
                error('Unexpected file format')
            end
        end

        %-----------------------------------------------------------------%
        function str = id2str(Type, ID)
            % Em tese, os IDs do Detector deveriam ser apenas 1 a 4 representando,
            % respectivamente, "Sample", "Average/RMS", "Positive Peak" e "Negative Peak".
            %
            % Notei, contudo, arquivos de monitoração gerados pelo appColeta v. 1.11 
            % nos quais esse ID estava igual a "0". Foram monitorações conduzidas 
            % com o R&S EB500.

            switch Type
                case 'TraceMode'
                    switch ID
                        case 1; str = 'ClearWrite';
                        case 2; str = 'Average';
                        case 3; str = 'MaxHold';
                        case 4; str = 'MinHold';
                    end

                case 'Detector'
                    switch ID
                        case {0, 1}; str = 'Sample';
                        case 2;      str = 'Average/RMS';
                        case 3;      str = 'Positive Peak';
                        case 4;      str = 'Negative Peak';
                    end        

                case 'LevelUnit'
                    switch ID
                        case 1; str = 'dBm';
                        case 2; str = 'dBµV';
                        case 3; str = 'dBµV/m';
                    end
            end        
        end

        %-----------------------------------------------------------------%
        function ID = str2id(Type, Value)
            switch Type
                case 'TraceMode'
                    switch Value
                        case 'ClearWrite'; ID = 1;
                        case 'Average';    ID = 2;
                        case 'MaxHold';    ID = 3;
                        case 'MinHold';    ID = 4;
                    end
        
                case 'Detector'
                    switch Value
                        case 'Sample';        ID = 1;
                        case 'Average/RMS';   ID = 2;
                        case 'Positive Peak'; ID = 3;
                        case 'Negative Peak'; ID = 4;
                    end
        
                case 'LevelUnit'
                    switch Value
                        case 'dBm';                ID = 1;
                        case {'dBµV', 'dBμV'};     ID = 2;
                        case {'dBµV/m', 'dBμV/m'}; ID = 3;
                    end
            end        
        end

        %-----------------------------------------------------------------%
        function Value = str2str(Value)
            Value = replace(Value, 'μ', 'µ');
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
                                      'LevelUnit',        [], ...
                                      'DataPoints',       [], ...
                                      'Resolution',       -1, ...
                                      'VBW',              -1, ...
                                      'Threshold',        -1, ...
                                      'TraceMode',        '', ...
                                      'TraceIntegration', -1, ...
                                      'Detector',         '', ...
                                      'Antenna',          [], ...
                                      'Others',           '');
        end

        %-----------------------------------------------------------------%
        function secundaryMetaData = secundaryMetaData(fileFormatName, originalMetaData)
            switch fileFormatName
                case 'RFlookBin v.2'
                    fieldsList = {'Receiver',         ...
                                  'AntennaInfo',      ...
                                  'ID',               ...
                                  'Description',      ...
                                  'FreqStart',        ...
                                  'FreqStop',         ...
                                  'DataPoints',       ...
                                  'Resolution',       ...
                                  'VBW',              ...
                                  'Unit',             ...
                                  'TraceMode',        ...
                                  'TraceIntegration', ...
                                  'Detector',         ...
                                  'gpsType',          ...
                                  'Latitude',         ...
                                  'Longitude'};
                otherwise
                    fieldsList = {};
            end

            fieldList2Remove  = fieldnames(originalMetaData);
            fieldList2Remove  = fieldList2Remove(ismember(fieldList2Remove, fieldsList));

            secundaryMetaData = rmfield(originalMetaData, fieldList2Remove);
            secundaryMetaData.FileFormat = fileFormatName;

            secundaryMetaData = structUtil.sortByFieldNames(secundaryMetaData);
            secundaryMetaData = jsonencode(secundaryMetaData);
        end
    end
end