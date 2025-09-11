function htmlReport = Controller(reportInfo, dataOverview)

    reportInfo = reportLib.inputParser(reportInfo, dataOverview);
    internalFcn_counterCreation()
    
    % HTML header (style)    
    htmlReport = '';
    if strcmp(reportInfo.Model.Version, 'preview')
        docTitle   = reportInfo.Model.Name;
        docType    = reportInfo.Model.DocumentType;
        docStyle   = sprintf(fileread(fullfile(reportLib.Path, 'html', 'docStyle.txt')), docTitle, docType);

        htmlReport = sprintf('%s\n\n', docStyle);
    end
    tableStyleFlag = 1;

    % HTML body
    jsonScript = reportInfo.Model.Script;
    for ii = 1:numel(jsonScript)
        parentNode = jsonScript(ii);
        parentType = parentNode.Type;

        if parentType ~= "ItemN1"
            continue
        end

        if ~isempty(parentNode.Data.Variable)
            parentNode.Data.Text = internalFcn_FillWords(reportInfo, [], parentNode, 1);
        end
        htmlReport = [htmlReport, reportLib.sourceCode.htmlCreation(parentNode)];

        if tableStyleFlag
            htmlReport = sprintf('%s%s\n\n', htmlReport, fileread(fullfile(reportLib.Path, 'html', 'docTableStyle.txt')));
            tableStyleFlag = 0;
        end

        NN = 1;
        if parentNode.Recurrence
            NN = numel(dataOverview);
        end

        for jj = 1:NN
            reportInfo.Function.var_Index = num2str(jj);
            analyzedData = dataOverview(jj);

            % Insere uma quebra de linha, caso exista recorrência no
            % item.
            if jj > 1
                htmlReport = [htmlReport, reportLib.sourceCode.LineBreak];
            end

            for kk = 1:numel(parentNode.Data.Component)
                % Component é uma estrutura com os campos "Type" e "Data". Se o 
                % campo "Type" for igual a "Image" ou "Table" e ocorrer um erro 
                % na leitura de uma imagem ou tabela externa, por exemplo, o erro 
                % retornado terá o formato "Configuration file error message: %s". 
                % Esse "%s" é uma mensagem JSON (e por isso deve ser deserializada) 
                % de um componente HTML textual ("ItemN2" ou "Paragraph", por 
                % exemplo).
                childNode  = parentNode.Data.Component(kk);
                childType = childNode.Type;

                try
                    switch childType
                        case {'ItemN2', 'ItemN3', 'Paragraph', 'List', 'Footnote'}
                            % Esse loop existe apenas por conta do componente do tipo "List"...
                            for ll = 1:numel(childNode.Data)
                                if ~isempty(childNode.Data(ll).Variable)
                                    childNode.Data(ll).Text = internalFcn_FillWords(reportInfo, analyzedData, childNode, ll);
                                end
                            end
                            vararginArgument = [];

                        case {'Image', 'Table'}
                            vararginArgument = eval(sprintf('internalFcn_%s(reportInfo, dataOverview, analyzedData, childNode.Data)', childType));

                        otherwise
                            error('Unexpected type "%s"', childType)
                    end

                    htmlReport = [htmlReport, reportLib.sourceCode.htmlCreation(childNode, vararginArgument)];

                catch ME
                    struct2table(ME.stack)
                    msgError = extractAfter(ME.message, 'Configuration file error message: ');

                    if ~isempty(msgError)
                        htmlReport = reportLib.sourceCode.AuxiliarHTMLBlock(htmlReport, 'Error', msgError);
                    end
                end
            end
        end
    end

    % HTML footnotes
    FootnoteList = fields(reportInfo.Version);
    FootnoteText = '';
        
    for ii = 1:numel(FootnoteList)
        FootnoteVersion = reportInfo.Version.(FootnoteList{ii});

        if ~isempty(FootnoteVersion)
            FootnoteFields = fields(FootnoteVersion);
            
            FootnoteFieldsText = {};
            for jj = 1:numel(FootnoteFields)
                switch FootnoteFields{jj}
                    case 'name'
                        FootnoteFieldsText{end+1} = sprintf('<b>__%s</b>', upper(FootnoteVersion.(FootnoteFields{jj})));
                    otherwise
                        FootnoteFieldsText{end+1} = sprintf('<b>%s</b>: %s', FootnoteFields{jj}, string(FootnoteVersion.(FootnoteFields{jj})));
                end
            end
            FootnoteFieldsText = strjoin(FootnoteFieldsText, ', ');
            FootnoteText       = [FootnoteText, reportLib.sourceCode.htmlCreation(struct('Type', 'Footnote', 'Data', struct('Editable', 'false', 'Text', FootnoteFieldsText, 'Variable', [])))];
        end
    end
    htmlReport = [htmlReport, reportLib.sourceCode.LineBreak, reportLib.sourceCode.Separator, FootnoteText, reportLib.sourceCode.LineBreak];

    % HTML trailer
    if strcmp(reportInfo.Model.Version, 'preview')
        htmlReport = sprintf('%s</body>\n</html>', htmlReport);
    end
end


%-------------------------------------------------------------------------%
function internalFcn_counterCreation()
    global ID_img
    global ID_tab

    ID_img = 0;
    ID_tab = 0;
end


%-------------------------------------------------------------------------%
function Text = internalFcn_FillWords(reportInfo, analyzedData, componentObj, componentObjIndex)

    % "analyzedData" e "callingApp" devem estar como argumentos de entrada porque
    % eles podem estar sendo passados como argumentos para as funções que retornam 
    % as variáveis, executadas por EVAL.

    listOfWords     = componentObj.Data(componentObjIndex).Variable;
    if ~iscellstr(listOfWords)
        listOfWords = cellstr(listOfWords);
    end
    numberOfWords   = numel(listOfWords);
    formattedWords  = repmat({''}, numberOfWords, 1);

    for ii = 1:numberOfWords
        variableName = listOfWords{ii};

        try
            if isfield(reportInfo.Function, variableName)
                try
                    variableValue = eval(reportInfo.Function.(variableName));
                catch
                    variableValue = reportInfo.Function.(variableName);
                end
    
            else
                error('UNKNOWN "%s" VARIABLE', variableName)
            end

        catch ME
            variableValue = sprintf('<span style="color: red;">%s</span>', ME.message);
        end

        formattedWords{ii} = variableValue;
    end

    Text = sprintf(componentObj.Data(componentObjIndex).Text, formattedWords{:});
end


%-------------------------------------------------------------------------%
function imgFullPath = internalFcn_Image(reportInfo, dataOverview, analyzedData, imgSettings)
    imgFullPath = '';
    imgOrigin   = imgSettings.Origin;
    imgSource   = imgSettings.Source;
    imgError    = imgSettings.Error;
    
    switch imgOrigin
        case 'FunctionEvaluation'
            imgIndex = any(strcmp(fields(reportInfo.Function), imgSource));
            if imgIndex
                imgFullPath = eval(reportInfo.Function.(imgSource));
            end

        case 'DataProperty'
            imgIndex = find(strcmp({analyzedData.HTML.Component}, 'Image') & strcmp({analyzedData.HTML.Source}, imgSource), 1);
            if ~isempty(imgIndex)
                imgFullPath = analyzedData.HTML(imgIndex).Value;
            end
    end

    if ~isfile(imgFullPath)
        error('Configuration file error message: %s', imgError)
    end
end


%-------------------------------------------------------------------------%
function Table = internalFcn_Table(reportInfo, dataOverview, analyzedData, tableSettings)
    Table        = [];
    tableOrigin  = tableSettings.Origin;
    tableColumns = tableSettings.Columns;
    tableError   = tableSettings.Error;
    
    tempSource   = strsplit(tableSettings.Source, '+');
    tableSource  = tempSource{1};
    tableOptArgs = tempSource(2:end);
    
    try
        switch tableOrigin
            case 'FunctionEvaluation'
                tableIndex = any(strcmp(fields(reportInfo.Function), tableSource));
                if tableIndex
                    Table = eval(reportInfo.Function.(tableSource));
                    Table = Table(:, tableColumns);
                end
    
            case 'DataProperty'
                tableIndex = find(strcmp({analyzedData.HTML.Component}, 'Table') & strcmp({analyzedData.HTML.Source}, tableSource), 1);
                if ~isempty(tableIndex)
                    tableInfo = analyzedData.HTML(tableIndex).Value;
    
                    if istable(tableInfo)
                        Table = tableInfo;
    
                    else
                        tableFullFile = tableInfo.Path;
                        tableSheetID  = tableInfo.SheetID;
            
                        [~,~,fileExt] = fileparts(tableFullFile);
                        switch lower(fileExt)
                            case '.json'
                                Table = struct2table(jsondecode(fileread(tableFullFile)));
            
                            case {'.xls', '.xlsx'}
                                Table = readtable(tableFullFile, "VariableNamingRule", "preserve", "Sheet", tableSheetID);
            
                            otherwise
                                Table = readtable(tableFullFile, "VariableNamingRule", "preserve");
                        end    
                        Table = Table(:, tableColumns);
                    end
                end
        end
    catch
    end

    if isempty(Table)
        error('Configuration file error message: %s', tableError)
    end
end