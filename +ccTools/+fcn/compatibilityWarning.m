function compatibilityWarning(moduleName)
    if ~ismember(version('-release'), {'2021b', '2022a', '2022b', '2023a', '2023b'})
        warning('ccTools.%s was tested only in four MATLAB releases (R2021b, R2022b, R2023a and R2023b).', moduleName)
    end
end