function specData = MAT(specData, fileName, readType, varargin)
    arguments
        specData
        fileName char
        readType (1,:) char {mustBeMember(readType, {'MetaData', 'SpecData', 'SingleFile'})}
    end

    arguments (Repeating)
        varargin
    end

    load(fileName, '-mat', 'out')
    if ~isempty(varargin)
        out = out(varargin{1});
    end

    switch readType
        case {'MetaData', 'SingleFile'}
            specData = Fcn_MetaDataReader(specData, out);

            if strcmp(readType, 'SingleFile')
                specData = Fcn_SpecDataReader(specData, out);
            end
            
        case 'SpecData'
            specData = copy(specData, {});
            specData = Fcn_SpecDataReader(specData, out);
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

        refColumnNames  = specData(end).RelatedFiles.Properties.VariableNames;
        fileColumnNames = out(ii).RelatedFiles.Properties.VariableNames;
        if isempty(setdiff(refColumnNames, fileColumnNames))
            specData(end).RelatedFiles = out(ii).RelatedFiles;
        end

        refGpsFields  = setdiff(fieldnames(gpsLib.getTemplate()), 'Matrix');
        fileGpsFields = fieldnames(out(ii).GPS);
        if isempty(setdiff(refGpsFields, fileGpsFields))
            specData(end).GPS = out(ii).GPS;
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