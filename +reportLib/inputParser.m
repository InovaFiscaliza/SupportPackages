function [reportInfo, dataOverview] = inputParser(reportInfo, dataOverview)
    
    % reportInfo
    if ~isstruct(reportInfo) || any(~ismember({'App', 'Version', 'Path', 'Model', 'Function'}, fields(reportInfo)))
        error('reportInfo must be a struct with at least the fields "App", "Version", "Path", "Model", and "Function".')
    end

    versionInfo = struct('machine',    report.Constants.MachineVersion(), ...
                         'matlab',     report.Constants.MatlabVersion(),  ...
                         'reportLib',  report.Constants.ReportLib(),      ...
                         'callingApp', reportInfo.Version.App);

    reportInfo.Version               = versionInfo;
    reportInfo.Path.libFolder        = report.Path();
    reportInfo.Function.var_Index    = '-1';

    % dataOverview
    if ~isstruct(dataOverview) || any(~ismember({'ID', 'InfoSet', 'HTML'}, fields(dataOverview)))
        error('dataOverview must be a struct with at least the fields "ID", "InfoSet" and "HTML".')
    end

end


%-------------------------------------------------------------------------%
function fileContent = FileContent(reportInfo, fileName)

    appConnectionFilePath = fullfile(reportInfo.Path.appConnection,          fileName);
    reportLibFilePath     = fullfile(reportInfo.Path.rootFolder, 'Template', fileName);

    if isfile(appConnectionFilePath)
        fileContent = jsondecode(fileread(appConnectionFilePath));
    else
        fileContent = jsondecode(fileread(reportLibFilePath));
    end

end