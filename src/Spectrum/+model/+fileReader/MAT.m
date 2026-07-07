function specData = MAT(specData, fileName, readType, varargin)

    % Leitor de arquivos .MAT gerados pelo RF.Fusion, os quais são produzidos
    % a partir de conjuntos de arquivos .DBM.
    %
    % Em 05/03/2026, o esquema da tabela "RelatedFiles", propriedade da classe
    % model.SpecDataBase, foi alterado. Para manter a compatibilidade com
    % arquivos gerados por versões anteriores e futuras, a função interna
    % Fcn_MetaDataReader realiza a atribuição das propriedades individualmente,
    % em vez de efetuar uma cópia direta da estrutura.
    %
    % Por razão desconhecida, evidenciou-se que arquivos .MAT gerados pelas 
    % primeiras versões do RF.Fusion não mantiveram informação da coluna "GPS" 
    % da tabela "RelatedFiles". Essa informação, portanto, é reconstruída
    % usando propriedade "GPS" (valor sumarizado de todas as capturas).

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
        specData(end).MetaData = ensureSchemaCompatibility(specData(end).MetaData, out(ii).MetaData);
        specData(end).Data = out(ii).Data;
        specData(end).GPS = ensureSchemaCompatibility(rmfield(gpsLib.getTemplate(), 'Matrix'), out(ii).GPS);
        specData(end).RelatedFiles = ensureSchemaCompatibility(specData(end).RelatedFiles, out(ii).RelatedFiles);

        for jj = 1:height(specData(end).RelatedFiles)
            gpsData = specData(end).RelatedFiles.GPS{jj};

            if isempty(gpsData)
                if specData(end).GPS.Count
                    gpsData = struct('Status', specData(end).GPS.Status, 'Matrix', [specData(end).GPS.Latitude, specData(end).GPS.Longitude]);
                else
                    gpsData = struct('Status', 0, 'Matrix', [-1,-1]);
                end

                specData(end).RelatedFiles.GPS{jj} = gpsLib.summary(gpsData);
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

%-------------------------------------------------------------------------%
function refData = ensureSchemaCompatibility(refData, inputData)
    if isstruct(refData)
        fieldNames = fieldnames(refData);
    
        for ii = 1:numel(fieldNames)
            field = fieldNames{ii};
    
            if isfield(inputData, field)
                refData.(field) = inputData.(field);
            end
        end

    elseif istable(refData)
        commonColumns = intersect(refData.Properties.VariableNames, inputData.Properties.VariableNames, 'stable');

        for ii = 1:height(inputData)
            refData(end+1, commonColumns) = inputData(ii, commonColumns);
        end
    end
end