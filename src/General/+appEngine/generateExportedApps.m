function generateExportedApps(appName, prjInfo)
    arguments
        appName char {mustBeMember(appName, {'appAnalise', 'appColeta', 'monitorRNI', 'monitorSPED', 'SCH'})}
        prjInfo matlab.project.Project = matlab.project.Project.empty
    end

    % O MATLAB não permite renderizar um .MLAPP dentro de um container de
    % outro .MLAPP pois cada um cria a sua própria uifigure. Para contornar
    % essa limitação, criou-se a abordagem de gerar versões .M dos apps 
    % auxiliares, que podem ser renderizados dentro do app principal.
    % 
    % Dessa forma, os apps auxiliares são renderizados em abas (uitab) ou 
    % popups (uipanel) da sua figura. Esta função gera, para cada .MLAPP, 
    % uma versão "<nome>_exported.m" que viabiliza isso, além de possibilitar 
    % o versionamento e a edição do código fora do App Designer 
    % (os .MLAPP são binários).
    %
    % • App principal (.MLAPP diretamente em "src", como "src/winAppColeta.mlapp")
    %   A versão .M tem apenas o nome da classe e do construtor alterados 
    %   (sufixo "_exported").
    %
    % • Apps auxiliares (.MLAPP em "src/+auxApp", como "src/+auxApp/winConfig.mlapp")
    %   Além do sufixo, o construtor passa a receber o container onde o app 
    %   deve ser renderizado, sendo criada uma nova uifigure apenas se o 
    %   container for vazio ("[]").
    %
    % Pressupõe-se que os apps estejam organizados conforme descrito acima e
    % que os apps auxiliares ("secondaryApp" ou "secondaryDockApp") cumpram os
    % requisitos de "appEngine.checkRole", em especial:
    % (1) Tenha a uifigure como componente "UIFigure" e, como seu filho 
    %     direto, o uigridlayout "GridLayout" (todos os demais componentes 
    %     devem estar dentro dele), pois "GridLayout" passa a ser filho do 
    %     container ("app.Container"). Exceção aos menu de contexto da uifigure.
    % (2) Declare, na seção de propriedades, "Container" e "isDocked".
    % (3) Possua "startupFcn" como nome do callback de inicialização, a qual 
    %     é executada pelo construtor.
    %
    % As propriedades da uifigure (Position, Color, callbacks etc) são 
    % mantidas, mas aplicadas apenas quando o app cria a sua própria figura.

    if isempty(prjInfo)
        prjInfo = currentProject;
    end

    % Garante que a execução ocorra no projeto correto e que haja um único app 
    % principal (.MLAPP diretamente em "src"), sendo os demais auxiliares.
    if ~strcmp(prjInfo.Name, appName)
        error('generateExportedApps:UnexpectedProject', 'O projeto aberto é "%s", mas era esperado "%s".', prjInfo.Name, appName)
    end

    srcFolder  = fullfile(prjInfo.RootFolder, 'src');
    MLAPPFiles = dir(fullfile(srcFolder, '**', '*.mlapp'));

    isMainApp  = strcmpi({MLAPPFiles.folder}, srcFolder);
    if nnz(isMainApp) ~= 1
        error('generateExportedApps:MainAppNotFound', 'Esperado um único .MLAPP principal em "%s".', srcFolder)
    end
    
    for ii = 1:numel(MLAPPFiles)
        [~, oldClassName] = fileparts(MLAPPFiles(ii).name);
        newClassName      = [oldClassName '_exported'];
        fileBaseName      = fullfile(MLAPPFiles(ii).folder, oldClassName);

        if isMainApp(ii)
            appRole = 'mainApp';
        else
            appRole = 'auxApp'; % 'secondaryApp' | 'secondaryDockApp'
        end

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
                    figureLines = getFigureCreationLines(matCodePart);
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

%-------------------------------------------------------------------------%
function matlabCode = getMFileContent(fileBaseName)
    readerObj  = appdesigner.internal.serialization.FileReader([fileBaseName '.mlapp']);
    matlabCode = readerObj.readMATLABCodeText();
end

%-------------------------------------------------------------------------%
function figureLines = getFigureCreationLines(matCodePart)
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
                '                if ~isempty(Container.Children)\n' ...
                '                    delete(Container.Children)\n' ...
                '                end\n\n' ...
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
                '                delete(app.Container.Children)\n' ...
                '            else\n' ...
                '                delete(app.UIFigure)\n' ...
                '            end\n' ...
                '        end\n' ...
                '    end\n' ...
                'end' ...
            ], newClassName);
    end
end
