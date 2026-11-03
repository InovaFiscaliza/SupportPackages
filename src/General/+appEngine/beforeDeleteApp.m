function beforeDeleteApp(progressDialog, tempDir, tabGroupController, executionMode)
    % O try/catch garante que qualquer erro durante a limpeza não interrompa o 
    % fechamento do app, em especial a liberação de sessão do MATLAB Runtime 
    % pelo MATLAB Web Server.
    try
        % TIMER
        h = timerfindall;
        if ~isempty(h)
            stop(h); delete(h); clear h
        end

        % PROGRESS DIALOG
        delete(progressDialog)

        % DELETE TEMP FILES
        if isfolder(tempDir)
            try
                rmdir(tempDir, 's');
            catch
            end
        end

        % DELETE APPS
        if isdeployed
            delete(findall(groot, 'Type', 'Figure'))
        else
            delete(tabGroupController)
        end
    catch
    end

    % MATLAB RUNTIME
    % Ao fechar um webapp, o MATLAB Web Server demora uns 10 segundos para
    % fechar o Runtime que suportava a sessão do webapp. Dessa forma, a 
    % liberação do recurso, que ocorre com a inicialização de uma nova 
    % sessão do Runtime, fica comprometida.
    appEngine.util.killingMATLABRuntime(executionMode)
end