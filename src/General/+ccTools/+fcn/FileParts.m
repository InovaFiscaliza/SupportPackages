function [fFullPath, fPath, fName, fExt] = FileParts(fFullPath)

    [fPath, fName, fExt] = fileparts(fFullPath);
    if isempty(fPath)
        fPath = fileparts(which(fFullPath));
        fFullPath = fullfile(fPath, [fName fExt]);
    end

end