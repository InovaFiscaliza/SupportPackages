function [prjTable, msgError] = projectSummary(prjFolder, cacheFolder)
    arguments
        prjFolder
        cacheFolder = 'D:\OneDrive - ANATEL\InovaFiscaliza\ProjectSummary'
    end

    [~, prjName] = fileparts(prjFolder);
    prjTable     = sortrows(fileDir(prjFolder), "CodeLines", "descend");
    cacheFile    = [fullfile(cacheFolder, sprintf('%s_%s', prjName, datestr(now,'yyyy.mm.dd_THH.MM.SS'))) '.mat'];

    try
        save(cacheFile, '-mat', 'prjTable', 'prjFolder')
        msgError = '';
    catch ME
        msgError = ME.message;
    end
end

%-------------------------------------------------------------------------%
function t = fileDir(prjFolder)
    t = table('Size',          [0,8],                                                                          ...
              'VariableTypes', {'cell', 'double', 'double', 'double', 'double', 'double', 'double', 'double'}, ...
              'VariableNames', {'File', 'Bytes', 'Lines', 'CodeLines', 'CommentLines', 'EmptyLines', 'CodeChars', 'CommentChars'});

    d = dir(prjFolder);
    
    for ii = 1:numel(d)
        if ismember(d(ii).name, {'.', '..'})
            continue
        end

        fileFullName = fullfile(d(ii).folder, d(ii).name);

        if d(ii).isdir
            t = [t; fileDir(fileFullName)];
        else
            if isfile(fileFullName)
                [~, fileName, fileExt] = fileparts(fileFullName);
                switch lower(fileExt)
                    case '.m'
                    case '.mlapp'
                        fileRelated = {[fileName '_exported.m'], [fileName '_new.mlapp']};
                        if any(ismember(fileRelated, {d.name}))
                            continue
                        end

                    otherwise
                        continue
                end

                [nLines,        ...
                 nCodeLines,    ...
                 nCommentLines, ...
                 nEmptyLines,   ...
                 nCodeChars,    ...
                 nCommentChars] = fileSummary(fileFullName, fileExt);

                t(end+1,:) = {fileFullName, d(ii).bytes, nLines, nCodeLines, nCommentLines, nEmptyLines, nCodeChars, nCommentChars};
            end
        end
    end
end

%-------------------------------------------------------------------------%
function [nLines, nCodeLines, nCommentLines, nEmptyLines, nCodeChars, nCommentChars] = fileSummary(fileFullName, fileExt)
    switch lower(fileExt)
        case '.mlapp'
            readerObj  = appdesigner.internal.serialization.FileReader(fileFullName);
            matlabCode = readerObj.readMATLABCodeText();
        case '.m'
            matlabCode = fileread(fileFullName);
    end

    matlabCellCode  = splitlines(matlabCode);
    matlabTrimCode  = strtrim(matlabCellCode);

    nLines          = numel(matlabCellCode);

    idxCommentLines = find(startsWith(matlabTrimCode, '%'));
    idxEmptyLines   = find(cellfun(@(x) isempty(x), matlabTrimCode));
    idxCodeLines    = setdiff((1:nLines)', [idxCommentLines; idxEmptyLines]);
    
    nCommentLines   = numel(idxCommentLines);
    nEmptyLines     = numel(idxEmptyLines);
    nCodeLines      = nLines-nCommentLines-nEmptyLines;

    nCodeChars       = sum(cellfun(@(x) numel(x), matlabTrimCode(idxCodeLines)));
    nCommentChars    = sum(cellfun(@(x) numel(x), matlabTrimCode(idxCommentLines)));
end