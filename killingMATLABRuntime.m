function killingMATLABRuntime(executionMode)

    if ismember(executionMode, {'desktopStandaloneApp', 'webapp'})
        pidMatlab = feature('getpid');
        system(sprintf('taskkill /F /PID %d', pidMatlab));
    end

end