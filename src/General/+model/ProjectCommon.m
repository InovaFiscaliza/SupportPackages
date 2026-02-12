classdef ProjectCommon < handle

    % ## model.ProjectCommon (SCH + monitorRNI + monitorSPED) ##      
    % PUBLIC
    %   ├── initialization
    %   |   └── readReportTemplatesFile
    %   ├── validateReportRequirements
    %   ├── updateGeneratedFiles
    %   ├── updateUploadedFiles
    %   |   └── model.ProjectCommon.computeUploadedFileHash
    %   |── updateUiInfo
    %   ├── getGeneratedDocumentFileName
    %   |   └── updateGeneratedFiles
    %   ├── getUploadedFiles
    %   ├── getOrFetchIssueDetails
    %   |   └── getIssueDetailsFromCache
    %   └── getOrFetchEntityDetails
    %      └── getEntityDetailsFromCache
    % PRIVATE
    %   ├── readReportTemplatesFile
    %   ├── getIssueDetailsFromCache
    %   ├── getEntityDetailsFromCache
    %   ├── IndexedDBStatus
    %   └── IndexedDBTimer
    % STATIC
    %   └── computeUploadedFileHash

    properties
        %-----------------------------------------------------------------%
        name
        file
        hash

        modules
        report = struct('templates', [], 'settings',  [])
        
        issueDetails = struct('system', {}, 'issue', {}, 'details', {}, 'timestamp', {})
        entityDetails = struct('id', {}, 'details', {}, 'timestamp', {})
    end

    
    properties (Access = private)
        %-----------------------------------------------------------------%
        mainApp
        rootFolder
        indexedDB = struct('syncTimer', [], 'lastSyncAt', [], 'lastSyncHash', '')
    end


    methods
        %-----------------------------------------------------------------%
        function obj = ProjectCommon(mainApp, rootFolder)
            obj.mainApp    = mainApp;
            obj.rootFolder = rootFolder;
        end

        %-----------------------------------------------------------------%
        function initialization(obj, contextList, generalSettings)
            obj.name = '';
            obj.file = '';
            obj.hash = '';

            for ii = 1:numel(contextList)
                context = contextList{ii};
                obj.modules.(context) = struct( ...
                    'annotationTable', [], ...
                    'generatedFiles', struct( ...
                        'id', '', ...
                        'rawFiles', {{}}, ...
                        'lastHTMLDocFullPath', '', ...
                        'lastJSONFullPath', '', ...
                        'lastTableFullPath', '', ...
                        'lastTEAMSFullPath', '', ...
                        'lastZIPFullPath', '' ...
                    ), ...
                    'uploadedFiles', struct( ...
                        'hash', {}, ...
                        'system', {}, ...
                        'issue', {}, ...
                        'status', {}, ...
                        'timestamp', {} ...
                    ), ...
                    'ui', struct( ...
                        'system', '', ...
                        'unit',   '',  ...
                        'issue',  -1,  ...
                        'templates', {{}}, ...
                        'reportModel', '',  ...
                        'reportVersion', 'Preliminar', ...
                        'entityTypes', {{}},  ...
                        'entity', struct( ...
                            'type', '', ...
                            'name', '', ...
                            'id',   '', ...
                            'status', false ...
                        ) ...
                    ) ...
                );

                obj.modules.(context).ui.entityTypes = generalSettings.reportLib.entityType.options;
                obj.modules.(context).ui.entity.type = generalSettings.reportLib.entityType.default;
            end

            readReportTemplatesFile(obj, obj.rootFolder)
        end

        %-----------------------------------------------------------------%
        % ## VALIDATION ##
        %-----------------------------------------------------------------%
        function status = validateReportRequirements(obj, context, requirement)
            arguments
                obj 
                context
                requirement {mustBeMember(requirement, {'issue', 'unit', 'reportModel', 'entity'})}
            end

            switch requirement
                case 'issue'
                    issue  = obj.modules.(context).ui.issue;
                    status = (issue > 0) && (issue < inf);
                case 'unit'
                    status = ~isempty(obj.modules.(context).ui.unit);
                case 'reportModel'
                    status = ~isempty(obj.modules.(context).ui.reportModel);
                case 'entity'
                    entity = obj.modules.(context).ui.entity;
                    status = ~isempty(entity.type) && ~isempty(entity.name) && (strcmp(entity.type, 'Importador') || entity.status);
            end
        end

        %-----------------------------------------------------------------%
        % ## UPDATE ##
        %-----------------------------------------------------------------%
        function updateGeneratedFiles(obj, context, id, rawFiles, htmlFile, jsonFile, tableFile, teamsFile, zipFile)
            arguments
                obj
                context
                id        char = ''
                rawFiles  cell = {}
                htmlFile  char = ''
                jsonFile  char = ''
                tableFile char = ''
                teamsFile char = ''
                zipFile   char = ''
            end

            obj.modules.(context).generatedFiles.id                  = id;
            obj.modules.(context).generatedFiles.rawFiles            = rawFiles;
            obj.modules.(context).generatedFiles.lastHTMLDocFullPath = htmlFile;
            obj.modules.(context).generatedFiles.lastJSONFullPath    = jsonFile;
            obj.modules.(context).generatedFiles.lastTableFullPath   = tableFile;
            obj.modules.(context).generatedFiles.lastTEAMSFullPath   = teamsFile;
            obj.modules.(context).generatedFiles.lastZIPFullPath     = zipFile;
        end

        %-----------------------------------------------------------------%
        function updateUploadedFiles(obj, context, system, issue, status)
            obj.modules.(context).uploadedFiles(end+1) = struct( ...
                'hash', model.ProjectCommon.computeUploadedFileHash(system, issue, status), ...
                'system', system, ...
                'issue', issue, ...
                'status', status, ...
                'timestamp', datestr(now) ...
            );
        end

        %-----------------------------------------------------------------%
        function updateUiInfo(obj, context, fieldName, fieldValue)
            switch fieldName
                case {'name', 'file', 'hash'}
                    obj.(fieldName) = fieldValue;

                case 'issueDetails'
                    [~, issueIndex] = ismember(fieldValue.issue, [obj.issueDetails.issue]);
                    if ~issueIndex
                        issueIndex = numel(obj.issueDetails) + 1;
                    end                    
                    obj.issueDetails(issueIndex) = fieldValue;

                case 'entityDetails'
                    [~, entityIdIndex] = ismember(fieldValue.id, {obj.entityDetails.id});
                    if ~entityIdIndex
                        entityIdIndex = numel(obj.entityDetails) + 1;
                    end                    
                    obj.entityDetails(entityIdIndex) = fieldValue;

                otherwise
                    obj.modules.(context).ui.(fieldName) = fieldValue;
            end
        end

        %-----------------------------------------------------------------%
        % ## GET ##
        %-----------------------------------------------------------------%
        function fileName = getGeneratedDocumentFileName(obj, fileExt, context)
            arguments
                obj
                fileExt (1,:) char {mustBeMember(fileExt, {'.html', '.json', '.xlsx', '.teams', '.zip'})}
                context
            end

            switch fileExt
                case '.html'
                    fileName = obj.modules.(context).generatedFiles.lastHTMLDocFullPath;
                case '.json'
                    fileName = obj.modules.(context).generatedFiles.lastJSONFullPath;
                case '.xlsx'
                    fileName = obj.modules.(context).generatedFiles.lastTableFullPath;
                case '.teams'
                    fileName = obj.modules.(context).generatedFiles.lastTEAMSFullPath;
                case '.zip'
                    fileName = obj.modules.(context).generatedFiles.lastZIPFullPath;
            end

            if ismember(fileExt, {'.html', '.zip'}) && ~isempty(fileName) && ~isfile(fileName)
                fileName = '';
                updateGeneratedFiles(obj, context)
            end
        end

        %-----------------------------------------------------------------%
        function uploadedFiles = getUploadedFiles(obj, context, system, issue)
            arguments
                obj
                context
                system
                issue
            end

            uploadedFiles = obj.modules.(context).uploadedFiles;
            if ~isempty(uploadedFiles)
                uploadedFiles = uploadedFiles(strcmp({uploadedFiles.system}, system) & [uploadedFiles.issue] == issue);
            end
        end

        %-----------------------------------------------------------------%
        % ## GET/FETCH ##
        %-----------------------------------------------------------------%
        function [details, msgError] = getOrFetchIssueDetails(obj, system, issue, eFiscalizaObj)
            details  = getIssueDetailsFromCache(obj, system, issue);
            msgError = '';

            if isempty(details) && (issue > 0) && (issue < inf)
                try
                    env = strsplit(system);
                    if isscalar(env)
                        env = 'PD';
                    else
                        env = env{2};
                    end
    
                    issueInfo = struct( ...
                        'type', 'ATIVIDADE DE INSPEÇÃO', ...
                        'id', issue ...
                    );
                    
                    details = run(eFiscalizaObj, env, 'queryIssue', issueInfo);
                    if isstruct(details)
                        newIssueDetails = struct( ...
                            'system', system, ...
                            'issue', issue, ...
                            'details', details, ...
                            'timestamp', datestr(now) ...
                        );
                        updateUiInfo(obj, 'self', 'issueDetails', newIssueDetails)
    
                    else
                        error(details)
                    end    
                catch ME
                    msgError = ME.message;
                end              
            end
        end

        %-----------------------------------------------------------------%
        function [details, msgError] = getOrFetchEntityDetails(obj, id)
            details  = getEntityDetailsFromCache(obj, id);
            msgError = '';

            if isempty(details)
                [entityId, ~, details, msgError] = checkCNPJOrCPF(id, 'PublicAPI');

                if ~isempty(details)
                    updateUiInfo(obj, 'self', 'entityDetails', struct('id', entityId, 'details', details, 'timestamp', datestr(now)))
                end                
            end
        end
    end


    methods (Access = private)
        %-----------------------------------------------------------------%
        function readReportTemplatesFile(obj, rootFolder)
            [projectFolder, ...
             programDataFolder] = appEngine.util.Path(class.Constants.appName, rootFolder);
            projectFilePath  = fullfile(projectFolder,     'ReportTemplates.json');
            externalFilePath = fullfile(programDataFolder, 'ReportTemplates.json');

            try
                if ~isdeployed()
                    error('ForceDebugMode')
                end
                obj.report.templates = jsondecode(fileread(externalFilePath));
            catch
                obj.report.templates = jsondecode(fileread(projectFilePath));
            end

            % Identifica lista de templates por módulo...
            contextList = fieldnames(obj.modules);
            templateNameList = {obj.report.templates.Name};

            for ii = 1:numel(contextList)
                templateIndexes = ismember({obj.report.templates.Module}, contextList(ii));
                obj.modules.(contextList{ii}).ui.templates = [{''}, templateNameList(templateIndexes)];
            end
        end

        %-----------------------------------------------------------------%
        function details = getIssueDetailsFromCache(obj, system, issue)
            detailsIndex = find(strcmp({obj.issueDetails.system}, system) & [obj.issueDetails.issue] == issue, 1);
            
            if ~isempty(detailsIndex)
                details  = obj.issueDetails(detailsIndex).details;
            else
                details  = '';
            end
        end

        %-----------------------------------------------------------------%
        function details = getEntityDetailsFromCache(obj, id)
            [~, entityIndex] = ismember(id, {obj.entityDetails.id});
            
            if entityIndex
                details = obj.entityDetails(entityIndex).details;
            else
                details = '';      
            end
        end

        %-----------------------------------------------------------------%
        function status = IndexedDBStatus(obj)
            status = ~strcmp(obj.mainApp.executionMode, 'desktopStandaloneApp') && obj.mainApp.General.Report.indexedDBCache.status;
        end

        %-----------------------------------------------------------------%
        function IndexedDBTimer(obj)
            if ~IndexedDBStatus(obj)
                return
            end

            timerInterval = 60* obj.mainApp.General.Report.indexedDBCache.intervalMinutes; % minutes >> seconds
            
            obj.indexedDB.syncTimer = timer( ...
                "ExecutionMode", "fixedSpacing", ...
                "BusyMode", "drop", ...
                "StartDelay", timerInterval, ...
                "Period", timerInterval, ...
                "TimerFcn", @(~,~) IndexedDBCache(obj) ...
            );

            start(obj.indexedDB.syncTimer)
        end
    end


    methods (Static = true)
        %-----------------------------------------------------------------%
        % Hash do upload do relatório, utilizado para sinalizar ao usuário
        % os relatórios já enviados ao SEI durante a sessão corrente do app.
        %-----------------------------------------------------------------%
        function hash = computeUploadedFileHash(system, issue, status)
            hash = Hash.sha1(strjoin({system, num2str(issue), status}, ' - '));
        end
    end

end