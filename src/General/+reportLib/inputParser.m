function reportInfo = inputParser(reportInfo, dataOverview)
    
    % reportInfo
    if ~isstruct(reportInfo) || any(~ismember({'App', 'Version', 'Path', 'Model', 'Function'}, fields(reportInfo)))
        error('reportInfo must be a struct with at least the fields "App", "Version", "Path", "Model", and "Function".')
    end

    reportInfo.Version.reportLib     = reportLib.Constants.ReportLib();
    reportInfo.Path.libFolder        = reportLib.Path();
    reportInfo.Function.var_Index    = '-1';

    % dataOverview
    if ~isstruct(dataOverview) || any(~ismember({'ID', 'InfoSet', 'HTML'}, fields(dataOverview)))
        error('dataOverview must be a struct with at least the fields "ID", "InfoSet" and "HTML".')
    end

end