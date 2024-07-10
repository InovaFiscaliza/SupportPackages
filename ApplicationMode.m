function [rootFolder, executionMode] = ApplicationMode(appName, MFilePath)

    rootFolder = MFilePath;

    if isdeployed
        [~, result]     = system('path');
    
        executionFolder = char(regexpi(result, 'Path=(.*?);', 'tokens', 'once'));
        executionExt    = ccTools.fcn.OperationSystem('executionExt');
    
        if isfile(fullfile(executionFolder, sprintf('%s.%s', appName, executionExt)))
            executionMode = 'desktopStandaloneApp';
            rootFolder    = executionFolder;
        else
            executionMode = 'webApp';
        end
    else
        executionMode = 'MATLABEnvironment';
    end

end