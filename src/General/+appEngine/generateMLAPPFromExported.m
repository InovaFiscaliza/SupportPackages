function generateMLAPPFromExported(appName, prjInfo, appNames)
    arguments
        appName  char {mustBeMember(appName, {'appAnalise', 'appColeta', 'monitorRNI', 'monitorSPED', 'SCH'})}
        prjInfo  matlab.project.Project = matlab.project.Project.empty
        appNames cell {mustBeText} = {}
    end

    % Operação inversa de "appEngine.generateExportedApps": gera o .MLAPP a
    % partir do "<nome>_exported.m", possibilitando que o código seja editado 
    % no VS Code sem transcrição manual para o App Designer.
    %
    % O "<nome>_exported.m" tem os trechos gerados pelo App Designer 
    % substituídos por versões que aceitam um container (apps auxiliares) 
    % ou que alteram o nome da classe (todos os apps). Aqui esses trechos 
    % são restaurados à forma original, gravada temporariamente em "<nome>.m", 
    % e o .MLAPP é criado por "m2mlapp" (que deve estar no path do MATLAB). 
    % As propriedades da uifigure são recuperadas do próprio "_exported.m".
    %
    % Limitações:
    % - "pathToMLAPP" só é restaurado se usado em outro ponto do código.
    % - O app não deve estar aberto no App Designer, que manteria uma cópia 
    %   desatualizada.
    % - O .MLAPP existente é substituído (metadados são preservados por 
    %   "m2mlapp"), então convém ter o .MLAPP versionado antes.
    %
    % Uso:
    % appEngine.generateMLAPPFromExported('appColeta', currentProject, {'winConfig'})
    % Sem "appNames", todos os "_exported.m" do projeto são convertidos.

    if isempty(prjInfo)
        prjInfo = currentProject;
    end

    if ~strcmp(prjInfo.Name, appName)
        error('generateMLAPPFromExported:UnexpectedProject', 'O projeto aberto é "%s", mas era esperado "%s".', prjInfo.Name, appName)
    end

    srcFolder     = fullfile(prjInfo.RootFolder, 'src');
    exportedFiles = dir(fullfile(srcFolder, '**', '*_exported.m'));
    classNames    = replace({exportedFiles.name}, '_exported.m', '');

    if ~isempty(appNames)
        missingApps = setdiff(appNames, classNames);
        if ~isempty(missingApps)
            error('generateMLAPPFromExported:AppNotFound', 'Não encontrado "_exported.m" para: %s.', strjoin(missingApps, ', '))
        end

        exportedFiles = exportedFiles(ismember(classNames, appNames));
    end

    for ii = 1:numel(exportedFiles)
        exportedFile = fullfile(exportedFiles(ii).folder, exportedFiles(ii).name);
        newClassName = replace(exportedFiles(ii).name, '_exported.m', '');
        oldClassName = [newClassName '_exported'];
        tempMFile    = fullfile(exportedFiles(ii).folder, [newClassName '.m']);

        if strcmpi(exportedFiles(ii).folder, srcFolder)
            appRole = 'mainApp';
        else
            appRole = 'auxApp'; % 'secondaryApp' | 'secondaryDockApp'
        end

        try
            if isfile(tempMFile)
                error('Já existe o arquivo "%s", que seria sobrescrito.', tempMFile)
            end

            matlabCode = readTextFile(exportedFile);

            switch appRole
                case 'mainApp'
                    % SUBSTITUIÇÃO: ClassName
                    oldTags = {sprintf('classdef %s < matlab.apps.AppBase', oldClassName), ...
                               sprintf('function app = %s',                 oldClassName)};

                    % VALIDAÇÃO
                    if any(cellfun(@(x) ~contains(matlabCode, x), oldTags))
                        error('Não identificado uma das tags! :(')
                    end

                    newTags = {sprintf('classdef %s < matlab.apps.AppBase', newClassName), ...
                               sprintf('function app = %s',                 newClassName)};

                    matlabCode = replace(matlabCode, oldTags, newTags);

                case 'auxApp'
                    oldTag1 = sprintf('classdef %s < matlab.apps.AppBase',      oldClassName);
                    oldTag2 = 'function createComponents(app, Container)';
                    oldTag3 = 'app.GridLayout = uigridlayout(app.Container);';
                    oldTag4 = sprintf('function app = %s(Container, varargin)', oldClassName);

                    % VALIDAÇÃO
                    if any(cellfun(@(x) ~contains(matlabCode, x), {oldTag1, oldTag2, oldTag3, oldTag4}))
                        error('Não identificado uma das tags! :(')
                    end

                    % SUBSTITUIÇÃO 1: ClassName
                    matlabCode  = replace(matlabCode, oldTag1, getOriginalCodeBlock('classDeclaration', newClassName));

                    % SUBSTITUIÇÃO 2: CreateComponents+FigureProperties
                    matCodePart = char(extractBetween(matlabCode, oldTag2, oldTag3, 'Boundaries', 'inclusive'));
                    figureLines = getFigureCreationLines(matCodePart);
                    usesImagePath = contains(replace(matlabCode, matCodePart, ''), 'pathToMLAPP');
                    matlabCode  = replace(matlabCode, matCodePart, getOriginalCodeBlock('createComponents', newClassName, figureLines, usesImagePath));

                    % SUBSTITUIÇÃO 3: ClassName+Constructor+Delete
                    idxConstructor = strfind(matlabCode, oldTag4);
                    matlabCode  = [matlabCode(1:idxConstructor(1)-1) getOriginalCodeBlock('constructorAndDelete', newClassName)];
            end

            % O .M temporário é necessário apenas durante a execução de "m2mlapp".
            writeTextFile(tempMFile, matlabCode)
            cleanupObj = onCleanup(@() deleteIfFile(tempMFile));

            mlappFile = m2mlapp(tempMFile);
            if isempty(mlappFile)
                error('Falha na execução de "m2mlapp".')
            end
            fprintf('Criado o arquivo %s\n', mlappFile)

        catch ME
            fprintf('ERRO ao processar o arquivo %s. %s\n', exportedFile, ME.message)
        end

        clear cleanupObj
    end
end

%-------------------------------------------------------------------------%
function matlabCode = readTextFile(filePath)
    % "fileread" substitui caracteres fora do BMP (como emojis).
    fileID     = fopen(filePath, 'r');
    matlabCode = native2unicode(fread(fileID, Inf, '*uint8')', 'UTF-8');
    fclose(fileID);

    matlabCode = regexprep(matlabCode, '\r\n?', '\n');
end

%-------------------------------------------------------------------------%
function writeTextFile(filePath, matlabCode)
    fileID = fopen(filePath, 'w');
    fwrite(fileID, unicode2native(matlabCode, 'UTF-8'), 'uint8');
    fclose(fileID);
end

%-------------------------------------------------------------------------%
function deleteIfFile(filePath)
    if isfile(filePath)
        delete(filePath)
    end
end

%-------------------------------------------------------------------------%
function figureLines = getFigureCreationLines(matCodePart)
    % Retorna as linhas "app.UIFigure..." do ramo em que o app cria a sua
    % própria figura (container vazio), conforme gerado por 
    % "appEngine.generateExportedApps".
    codeLines = strtrim(splitlines(matCodePart));
    idxStart  = find(startsWith(codeLines, 'if isempty(Container)'), 1);
    idxEnd    = find(startsWith(codeLines, 'app.Container = app.UIFigure;'), 1);

    if isempty(idxStart) || isempty(idxEnd) || idxStart > idxEnd
        error('Não identificado o bloco de criação da uifigure no ramo "if isempty(Container)".')
    end

    figureLines = codeLines(idxStart+1:idxEnd-1);
    figureLines(cellfun(@isempty, figureLines)) = [];

    if isempty(figureLines) || ~startsWith(figureLines{1}, 'app.UIFigure = uifigure(') || any(~startsWith(figureLines, 'app.UIFigure'))
        error('Bloco de criação da uifigure inesperado. Esperadas apenas linhas "app.UIFigure...", iniciando pela criação da uifigure.')
    end
end

%-------------------------------------------------------------------------%
function codeBlock = getOriginalCodeBlock(blockName, newClassName, figureLines, usesImagePath)
    arguments
        blockName {mustBeMember(blockName, {'classDeclaration', 'createComponents', 'constructorAndDelete'})}
        newClassName
        figureLines   = {}
        usesImagePath = false
    end

    switch blockName
        case 'classDeclaration'
            codeBlock = sprintf('classdef %s < matlab.apps.AppBase', newClassName);

        case 'createComponents'
            figureCode = strjoin(figureLines, [newline repmat(' ', 1, 12)]);
            imagePath  = '';
            if usesImagePath
                imagePath = [ ...
                    '            %% Get the file path for locating images\n' ...
                    '            pathToMLAPP = fileparts(mfilename(''fullpath''));\n\n' ...
                ];
            end

            codeBlock  = sprintf([ ...
                'function createComponents(app)\n\n' ...
                imagePath ...
                '            %% Create UIFigure and hide until all components are created\n' ...
                '            %s\n\n' ...
                '            %% Create GridLayout\n' ...
                '            app.GridLayout = uigridlayout(app.UIFigure);' ...
            ], figureCode);

        case 'constructorAndDelete'
            codeBlock = sprintf([ ...
                'function app = %s(varargin)\n\n' ...
                '            %% Create UIFigure and components\n' ...
                '            createComponents(app)\n\n' ...
                '            %% Register the app with App Designer\n' ...
                '            registerApp(app, app.UIFigure)\n\n' ...
                '            %% Execute the startup function\n' ...
                '            runStartupFcn(app, @(app)startupFcn(app, varargin{:}))\n\n' ...
                '            if nargout == 0\n' ...
                '                clear app\n' ...
                '            end\n' ...
                '        end\n\n' ...
                '        %% Code that executes before app deletion\n' ...
                '        function delete(app)\n\n' ...
                '            %% Delete UIFigure when app is deleted\n' ...
                '            delete(app.UIFigure)\n' ...
                '        end\n' ...
                '    end\n' ...
                'end' ...
            ], newClassName);
    end
end
