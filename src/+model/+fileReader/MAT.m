function [specData, prjInfo] = MAT(fileName, ReadType)

    % Author.: Eric Magalhães Delgado
    % Date...: February 20, 2025
    % Version: 1.01

    arguments
        fileName char
        ReadType char = 'SingleFile'
    end

    load(fileName, '-mat', 'prj_Type', 'prj_Version')
    if ~ismember(prj_Type, {'Spectral data', 'Project data'})
        error('Unexpected project type')
    elseif prj_Version ~= 3
        error('Unexpected project MAT-file version')
    end

    switch ReadType
        case 'MetaData'
            specData = Fcn_MetaDataReader(fileName);
            prjInfo  = [];
            
        case {'SpecData', 'SingleFile'}
            [specData, prjInfo] = Fcn_SpecDataReader(fileName);
    end
end

%-------------------------------------------------------------------------%
function specData = Fcn_MetaDataReader(fileName)
    load(fileName, '-mat', 'prj_metaData')
    
    specData = prj_metaData;
    checkIfMissingMetaData(specData)
end

%-------------------------------------------------------------------------%
function [specData, prjInfo] = Fcn_SpecDataReader(fileName)
    load(fileName, '-mat', 'prj_specData', 'prj_Info')
    
    specData = prj_specData;
    checkIfMissingMetaData(specData)
    
    prjInfo  = prj_Info;    
end

%-------------------------------------------------------------------------%
function checkIfMissingMetaData(specData)
    % Recentemente, foi inserido o parâmetro "VBW" dentre os metadados.
    % Para que não ocorra incompatibilidade com o appAnalise, esse passo 
    % garante que sejam incluídos os metadados com seus valores padrões
    % sempre que a informação não estiver no .MAT (salvo numa versão antiga
    % do app).

    currentMetaData     = model.SpecDataBase.templateMetaData();
    currentMetaDataList = fields(currentMetaData);
    ProjectMetaDataList = fields(specData(1).MetaData);

    checkIndex          = find(cellfun(@(x) ~ismember(x, ProjectMetaDataList), currentMetaDataList))';
    if ~isempty(checkIndex)
        for ii = 1:numel(specData)
            for jj = checkIndex
                specData(ii).MetaData.(currentMetaDataList{jj}) = currentMetaData.(currentMetaDataList{jj});
            end
        end
    end
end