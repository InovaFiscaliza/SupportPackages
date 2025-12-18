function [fPath, fName, fExt, fFullPath] = fileparts(fFullPath)
    [fPath, fName, fExt] = fileparts(fFullPath);
    
    if isempty(fPath)
        if isfile(fullfile(pwd, [fName, fExt]))
            fPath = pwd;
        elseif ~isempty(which(fFullPath))
            [fPath, fName, fExt] = fileparts(which(fFullPath));
        end
    end

    fFullPath = fullfile(fPath, [fName fExt]);
end