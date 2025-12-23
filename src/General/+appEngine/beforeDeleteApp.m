function beforeDeleteApp(progressDialog, tempDir, tabGroupController, executionMode)
    % TIMER
    h = timerfindall;
    if ~isempty(h)
        stop(h); delete(h); clear h
    end

    % PROGRESS DIALOG
    delete(progressDialog)

    % DELETE TEMP FILES
    if isfolder(tempDir)
        rmdir(tempDir, 's');
    end

    % DELETE APPS
    if isdeployed
        delete(findall(groot, 'Type', 'Figure'))
    else
        delete(tabGroupController)
    end

    % MATLAB RUNTIME
    % Ao fechar um webapp, o MATLAB WebServer demora uns 10 segundos para
    % fechar o Runtime que suportava a sessão do webapp. Dessa forma, a 
    % liberação do recurso, que ocorre com a inicialização de uma nova 
    % sessão do Runtime, fica comprometida.
    appEngine.util.killingMATLABRuntime(executionMode)
end