function specData = MAT(specData, fileName, readType, varargin)
    arguments
        specData
        fileName char
        readType (1,:) char {mustBeMember(readType, {'MetaData', 'SpecData', 'SingleFile'})}
    end

    arguments (Repeating)
        varargin
    end

    switch readType
        case {'MetaData', 'SingleFile'}
            out = Fcn_LoadData(fileName, varargin{:});
            specData = Fcn_MetaDataReader(specData, out);
            
        case 'SpecData'
            specData = copy(specData, {});

            if ~isscalar(specData) || any(arrayfun(@(x) isempty(x.Data), specData))
                out = Fcn_LoadData(fileName, varargin{:});
                specData = Fcn_SpecDataReader(specData, out);
            end
    end
end

%-------------------------------------------------------------------------%
function out = Fcn_LoadData(fileName, varargin)
    load(fileName, '-mat', 'out')
    if ~isempty(varargin)
        out = out(varargin{1});
    end
end

%-------------------------------------------------------------------------%
function specData = Fcn_MetaDataReader(specData, out)
    for ii = 1:numel(out)
        specData(end+1).Receiver = out(ii).Receiver;        

        refMetaDataFields = fieldnames(specData(end).MetaData);
        for jj = 1:numel(refMetaDataFields)
            refField = refMetaDataFields{jj};
            if isfield(out(ii).MetaData, refField)
                specData(end).MetaData.(refField) = out(ii).MetaData.(refField);
            end
        end

        specData(end).Data = out(ii).Data;

        refColumnNames  = specData(end).RelatedFiles.Properties.VariableNames;
        fileColumnNames = out(ii).RelatedFiles.Properties.VariableNames;
        if all(ismember(refColumnNames, fileColumnNames))
            specData(end).RelatedFiles = out(ii).RelatedFiles(:, refColumnNames);
        end

        refGpsFields  = setdiff(fieldnames(gpsLib.getTemplate()), 'Matrix');
        fileGpsFields = fieldnames(out(ii).GPS);
        if isempty(setdiff(refGpsFields, fileGpsFields))
            specData(end).GPS = out(ii).GPS;
        end

        for kk = 1:height(specData(end).RelatedFiles)
            if isempty(specData(end).RelatedFiles.GPS{kk}) && specData(end).GPS.Count
                gpsData = struct('Status', specData(end).GPS.Status, 'Matrix', [specData(end).GPS.Latitude, specData(end).GPS.Longitude]);
                specData(end).RelatedFiles.GPS{kk} = gpsLib.summary(gpsData);
            end
        end
    end
end

%-------------------------------------------------------------------------%
function specData = Fcn_SpecDataReader(specData, out)
    if numel(specData) ~= numel(out)
        error('model:fileReader:MAT:DimensionMismatch', 'Dimension mismatch between input objects')
    end

    for ii = 1:numel(specData)
        specData(ii).Data = out(ii).Data;
    end
end