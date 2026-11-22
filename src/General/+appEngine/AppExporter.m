classdef AppExporter
    % Conversão entre ".MLAPP" e "<nome>_exported.m" que independe de projeto
    % do MATLAB: basta informar as pastas (varridas recursivamente) onde estão
    % os arquivos. Dessa forma, atende tanto apps de projetos (appAnalise,
    % appColeta, monitorRNI, monitorSPED, SCH) quanto apps compartilhados que
    % residem em SupportPackages (como "General\+auxApp").
    %
    % O papel do app é identificado pelo caminho do arquivo:
    % • Apps renderizados em container: arquivos dentro de qualquer pacote
    %   (pasta "+nome"), como "+auxApp", "+auxApp\+RFDataHub" e, no SCH,
    %   "+mainApp" (versões desktop e mobile). Além do sufixo "_exported", o
    %   construtor passa a receber o container onde o app deve ser renderizado,
    %   sendo criada uma nova uifigure apenas se o container for vazio ("[]").
    % • App principal/launcher: arquivos fora de pacotes (como 
    %   "src\winAppColeta.mlapp" e "src\winSCH.mlapp"). A versão .M tem apenas 
    %   o nome da classe e do construtor alterados (sufixo "_exported").
    %
    % O MATLAB não permite renderizar um .MLAPP dentro de um container de outro
    % .MLAPP pois cada um cria a sua própria uifigure. Para contornar essa
    % limitação, geram-se versões .M ("<nome>_exported.m") dos apps, que podem
    % ser renderizados em abas (uitab) ou popups (uipanel) da figura do app
    % principal, além de possibilitar o versionamento e a edição do código fora
    % do App Designer (os .MLAPP são binários).
    %
    % Pressupõe-se que os apps renderizados em container ("secondaryApp" ou
    % "secondaryDockApp") cumpram os requisitos de "appEngine.checkRole", em
    % especial:
    % (1) Tenha a uifigure como componente "UIFigure" e, como seu filho direto,
    %     o uigridlayout "GridLayout" (todos os demais componentes devem estar
    %     dentro dele), pois "GridLayout" passa a ser filho do container
    %     ("app.Container"). Exceção aos menus de contexto da uifigure.
    % (2) Declare, na seção de propriedades, "Container" e "isDocked".
    % (3) Possua "startupFcn" como nome do callback de inicialização, a qual é
    %     executada pelo construtor.
    %
    % As propriedades da uifigure (Position, Color, callbacks etc) são mantidas,
    % mas aplicadas apenas quando o app cria a sua própria figura.
    %
    % Sem "appNames", todos os arquivos das pastas são convertidos. Caso
    % contrário, apenas os listados (nomes das classes, como {'winConfig'}).
    %
    % "toMLAPP" é a operação inversa: restaura os trechos gerados pelo App
    % Designer (gravados temporariamente em "<nome>.m") e cria o .MLAPP por
    % "m2mlapp" (que deve estar no path do MATLAB). As propriedades da uifigure
    % são recuperadas do próprio "_exported.m".
    %
    % Limitações de "toMLAPP":
    % - "pathToMLAPP" só é restaurado se usado em outro ponto do código.
    % - O app não deve estar aberto no App Designer, que manteria uma cópia 
    %   desatualizada.
    % - O .MLAPP existente é substituído (metadados são preservados por 
    %   "m2mlapp"), então convém ter o .MLAPP versionado antes.
    %
    % Os "preCompile.m" dos projetos chamam esta classe com a pasta "src" do
    % projeto. Apps compartilhados em SupportPackages são convertidos chamando-a
    % diretamente.
    %
    % Uso:
    % appEngine.AppExporter.toExported('C:\SupportPackages\src\General')
    % appEngine.AppExporter.toExported({'C:\InovaFiscaliza\appAnalise\src', 'C:\SupportPackages\src\General'}, {'winRFDataHub'})
    % appEngine.AppExporter.toMLAPP('C:\SupportPackages\src\General', {'winRFDataHub'})

    methods (Static)
        %-----------------------------------------------------------------%
        function toExported(folders, appNames)
            arguments
                folders  {mustBeText}
                appNames cell {mustBeText} = {}
            end

            % .MLAPP >> .M (exported)
            MLAPPFiles = findAppFiles(folders, '.mlapp', appNames);

            for ii = 1:numel(MLAPPFiles)
                [~, oldClassName] = fileparts(MLAPPFiles(ii).name);
                newClassName      = [oldClassName '_exported'];
                fileBaseName      = fullfile(MLAPPFiles(ii).folder, oldClassName);
                appRole           = getAppRole(MLAPPFiles(ii).folder);

                try
                    matlabCode = getMFileContent(fileBaseName);

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
                            % Salva a versão original do .M em pasta temporária, de
                            % forma que seja possível comparar, linha a linha no 
                            % MATLAB, o original com o "_exported.m".
                            writematrix(matlabCode, fullfile(tempdir, [oldClassName '.m']), 'FileType', 'text', 'WriteMode', 'overwrite', 'QuoteStrings', 'none', 'Encoding', 'UTF-8')

                            % Trechos gerados pelo App Designer que serão substituídos:
                            % (1) declaração da classe, (2) de "createComponents" até 
                            % a criação do "GridLayout" e (3) do construtor até o fim.
                            oldTag1 = sprintf('classdef %s < matlab.apps.AppBase', oldClassName);
                            oldTag2 = 'function createComponents(app)';
                            oldTag3 = 'app.GridLayout = uigridlayout(app.UIFigure);';
                            oldTag4 = sprintf('function app = %s(varargin)',       oldClassName);

                            % VALIDAÇÃO
                            if any(cellfun(@(x) ~contains(matlabCode, x), {oldTag1, oldTag2, oldTag3, oldTag4}))
                                error('Não identificado uma das tags! :(')
                            end

                            % SUBSTITUIÇÃO 1: ClassName
                            matlabCode  = replace(matlabCode, oldTag1, getInjectedCodeBlock('classDeclaration', newClassName));

                            % SUBSTITUIÇÃO 2: CreateComponents+FigureProperties
                            matCodePart = char(extractBetween(matlabCode, oldTag2, oldTag3, 'Boundaries', 'inclusive'));
                            figureLines = getFigureCreationLinesFromMLAPP(matCodePart);
                            matlabCode  = replace(matlabCode, matCodePart, getInjectedCodeBlock('createComponents', newClassName, figureLines));

                            % SUBSTITUIÇÃO 3: ClassName+Constructor+Delete
                            matlabCode  = replace(matlabCode, [oldTag4 extractAfter(matlabCode, oldTag4)], getInjectedCodeBlock('constructorAndDelete', newClassName));
                    end

                    matlabCode = strjoin(splitlines(matlabCode), '\r\n');
                    writematrix(matlabCode, [fileBaseName '_exported.m'], 'FileType', 'text', 'WriteMode', 'overwrite', 'QuoteStrings', 'none', 'Encoding', 'UTF-8')
                    fprintf('Criado o arquivo %s\n', [fileBaseName '_exported.m'])

                catch ME
                    fprintf('ERRO ao processar o arquivo %s. %s\n', [fileBaseName '.mlapp'], ME.message)
                end
            end
        end

        %-----------------------------------------------------------------%
        function toMLAPP(folders, appNames)
            arguments
                folders  {mustBeText}
                appNames cell {mustBeText} = {}
            end

            % .M (exported) >> .MLAPP
            exportedFiles = findAppFiles(folders, '_exported.m', appNames);

            for ii = 1:numel(exportedFiles)
                exportedFile = fullfile(exportedFiles(ii).folder, exportedFiles(ii).name);
                newClassName = replace(exportedFiles(ii).name, '_exported.m', '');
                oldClassName = [newClassName '_exported'];
                tempMFile    = fullfile(exportedFiles(ii).folder, [newClassName '.m']);
                appRole      = getAppRole(exportedFiles(ii).folder);

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
                            figureLines = getFigureCreationLinesFromExported(matCodePart);
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
    end
end

%-------------------------------------------------------------------------%
function files = findAppFiles(folders, suffix, appNames)
    % Varre recursivamente as pastas e retorna os arquivos "*<suffix>", 
    % restritos aos nomes de classe em "appNames" (se informado).
    folders = cellstr(folders);

    invalidFolders = folders(~cellfun(@isfolder, folders));
    if ~isempty(invalidFolders)
        error('AppExporter:FolderNotFound', 'Pasta não encontrada: %s.', strjoin(invalidFolders, ', '))
    end

    files = cellfun(@(x) dir(fullfile(x, '**', ['*' suffix])), folders, 'UniformOutput', false);
    files = vertcat(files{:});

    % Pastas aninhadas (ou repetidas) resultariam em arquivos duplicados.
    [~, idxUnique] = unique(fullfile({files.folder}, {files.name}), 'stable');
    files          = files(idxUnique);

    classNames = replace({files.name}, suffix, '');
    if ~isempty(appNames)
        missingApps = setdiff(appNames, classNames);
        if ~isempty(missingApps)
            error('AppExporter:AppNotFound', 'Não encontrado arquivo "*%s" para: %s.', suffix, strjoin(missingApps, ', '))
        end

        isSelected = ismember(classNames, appNames);
        files      = files(isSelected);
        classNames = classNames(isSelected);
    end

    % Classes homônimas em pastas distintas do path: uma "esconde" a outra.
    [~, idxFirst] = unique(classNames, 'stable');
    duplicated    = classNames(setdiff(1:numel(classNames), idxFirst));
    if ~isempty(duplicated)
        warning('AppExporter:DuplicatedClassName', 'Classes com o mesmo nome em mais de uma pasta: %s.', strjoin(unique(duplicated), ', '))
    end
end

%-------------------------------------------------------------------------%
function appRole = getAppRole(folder)
    % Apps renderizados em container (auxiliares em "+auxApp" e, no SCH, as 
    % versões desktop e mobile em "+mainApp") residem em pacotes. Apps fora de 
    % pacote (como "winAppColeta" e o launcher "winSCH") apenas têm o nome 
    % da classe alterado.
    if any(startsWith(split(string(folder), filesep), '+'))
        appRole = 'auxApp'; % 'secondaryApp' | 'secondaryDockApp' | 'mainApp' desktop/mobile
    else
        appRole = 'mainApp';
    end
end

%-------------------------------------------------------------------------%
function matlabCode = getMFileContent(fileBaseName)
    readerObj  = appdesigner.internal.serialization.FileReader([fileBaseName '.mlapp']);
    matlabCode = readerObj.readMATLABCodeText();
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
function figureLines = getFigureCreationLinesFromMLAPP(matCodePart)
    % Retorna, sem alteração, as linhas "app.UIFigure..." que criam e 
    % configuram a uifigure no .MLAPP (cor, callbacks, HandleVisibility etc), 
    % localizadas entre a criação de "UIFigure" e a de "GridLayout".
    codeLines = strtrim(splitlines(matCodePart));
    idxStart  = find(startsWith(codeLines, 'app.UIFigure = uifigure('), 1);
    idxEnd    = find(startsWith(codeLines, 'app.GridLayout = uigridlayout('), 1);

    if isempty(idxStart) || isempty(idxEnd) || idxStart > idxEnd
        error([ ...
            'Não identificado o bloco de criação da uifigure ou do uigridlayout. ' ...
            'Para que sejam corretamente identificados, a classe deve possuir como ' ...
            'propriedades "UIFigure" (uifigure) e "GridLayout" (uigridlayout).' ...
        ])
    end

    figureLines = codeLines(idxStart:idxEnd-1);
    figureLines(~startsWith(figureLines, 'app.UIFigure')) = [];
end

%-------------------------------------------------------------------------%
function figureLines = getFigureCreationLinesFromExported(matCodePart)
    % Retorna as linhas "app.UIFigure..." do ramo em que o app cria a sua
    % própria figura (container vazio), conforme gerado por "toExported".
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
function codeBlock = getInjectedCodeBlock(blockName, newClassName, figureLines)
    arguments
        blockName {mustBeMember(blockName, {'classDeclaration', 'createComponents', 'constructorAndDelete'})}
        newClassName
        figureLines = {}
    end

    switch blockName
        case 'classDeclaration'
            codeBlock = sprintf('classdef %s < matlab.apps.AppBase', newClassName);

        case 'createComponents'
            figureCode = strjoin(figureLines, [newline repmat(' ', 1, 16)]);
            codeBlock  = sprintf([ ...
                'function createComponents(app, Container)\n\n' ...
                '            %% Get the file path for locating images\n' ...
                '            pathToMLAPP = fileparts(mfilename(''fullpath''));\n\n' ...
                '            %% Create UIFigure and hide until all components are created\n' ...
                '            if isempty(Container)\n' ...
                '                %s\n\n' ...
                '                app.Container = app.UIFigure;\n\n' ...
                '            else\n' ...
                '                children = Container.Children;\n' ...
                '                if isa(Container, ''matlab.ui.Figure'') && isprop(Container, ''RunningAppInstance'') && isprop(Container.RunningAppInstance, ''jsBackDoor'')\n' ...
                '                    children(children == Container.RunningAppInstance.jsBackDoor) = [];\n' ...
                '                end\n' ...
                '                delete(children)\n\n' ...
                '                app.UIFigure  = ancestor(Container, ''figure'');\n' ...
                '                app.Container = Container;\n' ...
                '                if ~isprop(Container, ''RunningAppInstance'')\n' ...
                '                    addprop(app.Container, ''RunningAppInstance'');\n' ...
                '                end\n' ...
                '                app.Container.RunningAppInstance = app;\n' ...
                '                app.isDocked  = true;\n' ...
                '            end\n\n' ...
                '            %% Create GridLayout\n' ...
                '            app.GridLayout = uigridlayout(app.Container);' ...
            ], figureCode);

        case 'constructorAndDelete'
            codeBlock = sprintf([ ...
                'function app = %s(Container, varargin)\n\n' ...
                '            %% Create UIFigure and components\n' ...
                '            createComponents(app, Container)\n\n' ...
                '            %% Execute the startup function\n' ...
                '            runStartupFcn(app, @(app)startupFcn(app, varargin{:}))\n\n' ...
                '            if nargout == 0\n' ...
                '                clear app\n' ...
                '            end\n' ...
                '        end\n\n' ...
                '        %% Code that executes before app deletion\n' ...
                '        function delete(app)\n\n' ...
                '            %% Delete UIFigure when app is deleted\n' ...
                '            if app.isDocked\n' ...
                '                children = app.Container.Children;\n' ...
                '                if isa(app.Container, ''matlab.ui.Figure'') && isprop(app.Container, ''RunningAppInstance'') && isprop(app.Container.RunningAppInstance, ''jsBackDoor'')\n' ...
                '                    children(children == app.Container.RunningAppInstance.jsBackDoor) = [];\n' ...
                '                end\n' ...
                '                delete(children)\n' ...
                '            else\n' ...
                '                delete(app.UIFigure)\n' ...
                '            end\n' ...
                '        end\n' ...
                '    end\n' ...
                'end' ...
            ], newClassName);
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
