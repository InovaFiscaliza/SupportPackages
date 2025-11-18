classdef (Abstract) sourceCode

    %TODO
    % (a) HTML link element
    % ...

    methods (Static = true)
        %-----------------------------------------------------------------%
        function htmlContent = htmlCreation(reportTemplate, varargin)
            [componentType, componentData, componentIntro, componentError, componentLineBreak] = reportLib.sourceCode.TemplateParser(reportTemplate);
            reportLib.sourceCode.ComponentTypeCheck(componentType)
            [txtClass, txtStyle, tableStyle] = reportLib.sourceCode.Style(componentType);
            
            htmlContent = '';
            switch componentType
                %---------------------------------------------------------%
                case {'ItemN1', 'ItemN2', 'ItemN3', 'Paragraph', 'Footnote'}
                    htmlContent = sprintf('<p class="%s" contenteditable="%s"%s>%s</p>\n\n', txtClass, componentData.Editable, txtStyle, componentData.Text);        
        
                %---------------------------------------------------------%
                case 'List'
                    htmlContent = '<ul style="margin-left: 80px;">';
                    for ii = 1:numel(componentData)
                        htmlContent = sprintf(['%s\n'                                            ...
                                               '\t<li>\n'                                        ...
                                               '\t\t<p class="%s" contenteditable="%s">%s</p>\n' ...
                                               '\t</li>'], htmlContent, txtClass, componentData(ii).Editable, componentData(ii).Text);
                    end
                    htmlContent = sprintf('%s\n</ul>\n\n', htmlContent);        
        
                %---------------------------------------------------------%
                case 'Image'
                    imgFullPath = varargin{1};
                    
                    if ~isempty(imgFullPath)
                        global ID_img
                        ID_img = ID_img+1;

                        [imgExt, imgString] = imageUtil.img2base64(imgFullPath);
                        
                        htmlContent = reportLib.sourceCode.AuxiliarHTMLBlock(htmlContent, 'Introduction', componentIntro);                        
                        htmlContent = sprintf(['%s<figure id="image_%.0f">\n'                                                                             ...
                                               '\t<p class="Texto_Centralizado"><img src="data:image/%s;base64,%s" style="width:%s; height:%s;" /></p>\n' ...
                                               '\t<figcaption>\n'                                                                                         ...
                                               '\t\t<p class="%s" style="text-align:center;"><strong>Imagem %.0f. %s</strong></p>\n'                      ...
                                               '\t</figcaption>\n'                                                                                        ...
                                               '</figure>\n\n'], htmlContent, ID_img, imgExt, imgString, componentData.Settings.Width, componentData.Settings.Height, txtClass, ID_img, componentData.Caption);
        
                        htmlContent = reportLib.sourceCode.AuxiliarHTMLBlock(htmlContent, 'LineBreak', componentLineBreak);
        
                    else
                        htmlContent = reportLib.sourceCode.AuxiliarHTMLBlock(htmlContent, 'Error', componentError);
                    end        
        
                %---------------------------------------------------------%
                case 'Table'
                    Table = varargin{1};
        
                    if ~isempty(Table)
                        global ID_tab
                        ID_tab  = ID_tab+1;

                        ROWS    = height(Table);
                        COLUMNS = width(Table);
                        
                        % INTRODUCTION
                        htmlContent = reportLib.sourceCode.AuxiliarHTMLBlock(htmlContent, 'Introduction', componentIntro);

                        % HEADER
                        htmlContent = sprintf(['%s<table class="%s" id="table_%.0f">\n'                 ...
                                             '\t<caption>\n'                                            ...
                                             '\t\t<p class="Tabela_Texto_8" style="text-align:center;"><strong>Tabela %.0f. %s</strong></p>\n' ...
                                             '\t</caption>\n'                                           ...
                                             '\t<thead>\n'                                              ...
                                             '\t\t<tr>'], htmlContent, tableStyle, ID_tab, ID_tab, componentData.Caption);
                    
                        rowTemplate = {};
                        for jj = 1:COLUMNS
                            value = '';
                            if componentData.Settings(jj).Width ~= "auto"
                                value = sprintf(' style="width: %s;"', componentData.Settings(jj).Width);
                            end
                            columnName  = Table.Properties.VariableNames{jj};
                    
                            htmlContent = sprintf(['%s\n'                                              ...
                                                 '\t\t\t<th scope="col"%s>\n'                          ...
                                                 '\t\t\t\t<p class="%s" contenteditable="%s">%s</p>\n' ...
                                                 '\t\t\t</th>'], htmlContent, value, txtClass, componentData.Settings(jj).Editable, columnName);

                            containerCustomStyle = '';
                            if isfield(componentData.Settings(jj), 'ContainerStyle')
                                containerCustomStyle = componentData.Settings(jj).ContainerStyle;
                            end
                            
                            textCustomStyle = '';
                            if isfield(componentData.Settings(jj), 'TextStyle')
                                textCustomStyle = componentData.Settings(jj).TextStyle;
                            end
                    
                            rowTemplate{jj} = sprintf(['\t\t\t<td%s>\n'                                           ...
                                                       '\t\t\t\t<p class="%s" contenteditable="%s"%s>%%s</p>\n' ...
                                                       '\t\t\t</td>'], containerCustomStyle, txtClass, componentData.Settings(jj).Editable, textCustomStyle);
                        end                    
                        htmlContent = sprintf(['%s\n'       ...
                                             '\t\t</tr>\n'  ...
                                             '\t</thead>\n' ...
                                             '\t<tbody>'], htmlContent);
                    
                        % BODY
                        for ii = 1:ROWS
                            htmlContent = sprintf('%s\n\t\t<tr>', htmlContent);

                            for jj = 1:COLUMNS
                                cellValue   = reportLib.sourceCode.TableCellValue(Table{ii, jj}, componentData.Settings(jj), txtClass, 1);
                                htmlContent = sprintf('%s\n%s', htmlContent, sprintf(rowTemplate{jj}, cellValue));
                            end
                    
                            htmlContent = sprintf('%s\n\t\t</tr>', htmlContent);
                        end
                    
                        htmlContent = sprintf('%s\n\t</tbody>\n</table>\n\n', htmlContent);        
                        htmlContent = reportLib.sourceCode.AuxiliarHTMLBlock(htmlContent, 'LineBreak', componentLineBreak);
        
                    else
                        htmlContent = reportLib.sourceCode.AuxiliarHTMLBlock(htmlContent, 'Error', componentError);
                    end
            end
        end
    end


    methods (Static = true)
        %-----------------------------------------------------------------%
        function ComponentTypeCheck(componentType)
            if ~ismember(componentType, {'ItemN1', 'ItemN2', 'ItemN3', 'Paragraph', 'Footnote', 'List', 'Image', 'Table'})
                error('report:sourceCode:ComponentTypeCheck', 'Lib supports only "ItemN1", "ItemN2", "ItemN3", "Paragraph", "Footnote", "List", "Image" and "Table" HTML components.')
            end
        end


        %-----------------------------------------------------------------%
        function [txtClass, txtStyle, tableStyle] = Style(componentType)
            txtStyle   = '';
            tableStyle = '';

            switch componentType
                case 'ItemN1';    txtClass = 'Item_Nivel1';
                case 'ItemN2';    txtClass = 'Item_Nivel2';
                case 'ItemN3';    txtClass = 'Item_Nivel3';
                case 'Paragraph'; txtClass = 'Texto_Justificado';
                case 'Footnote';  txtClass = 'Tabela_Texto_8';    txtStyle = ' style="color: #808080;"';
                case 'List';      txtClass = 'Texto_Justificado';
                case 'Image';     txtClass = 'Tabela_Texto_8';
                case 'Table';     txtClass = 'Tabela_Texto_8';    tableStyle = 'tabela_corpo';
            end        
        end


        %-----------------------------------------------------------------%
        function [componentType, componentData, componentIntro, componentError, componentLineBreak] = TemplateParser(reportTemplate)
            componentType      = reportTemplate.Type;
            componentData      = reportTemplate.Data;
            componentIntro     = '';
            componentError     = '';
            componentLineBreak = 0;

            if isfield(componentData, 'Intro')
                componentIntro = componentData.Intro;
            end

            if isfield(componentData, 'Error')
                componentError = componentData.Error;
            end

            if isfield(componentData, 'LineBreak')
                componentLineBreak = componentData.LineBreak;
            end
        end
        
        
        %-----------------------------------------------------------------%
        function htmlContent = AuxiliarHTMLBlock(htmlContent, controlType, controlRawData)
            % - "Introduction"
            %   "Intro": ""
            %   "Intro": "{\"Type\":\"ItemN2\",\"Text\":\"Uma informação qualquer antes de renderização de um componente imagem ou tabela...\"}"
            %
            % - "LineBreak"
            %   "LineBreak": 0
            %   "LineBreak": 1
            %
            % - "Error"
            %   "Error": ""
            %   "Error": "{\"Type\":\"Paragraph\",\"Text\":\"Uma informação qualquer caso ocorra erro na renderização de um componente imagem ou tabela...\"}"
        
            if isempty(controlRawData) || ...
                    (isnumeric(controlRawData) && (~controlRawData || ~isvector(controlRawData)))
                return
            end
        
            switch controlType
                case {'Introduction', 'Error'}
                    if ~isempty(controlRawData)
                        controlStruct     = jsondecode(controlRawData);
        
                        htmlComponentType = controlStruct.Type;
                        htmlComponentText = controlStruct.Text;
                    end
        
                case 'LineBreak'
                    if controlRawData
                        htmlComponentType = 'Paragraph';
                        htmlComponentText = '&nbsp;';
                    end
            end
        
            htmlContent = sprintf('%s%s', htmlContent, reportLib.sourceCode.htmlCreation(struct('Type', htmlComponentType, 'Data', struct('Editable', 'false', 'Text', htmlComponentText, 'Variable', []))));
        end


        %-----------------------------------------------------------------%
        function htmlLineBreak = LineBreak()
            htmlLineBreak = reportLib.sourceCode.htmlCreation(struct('Type', 'Paragraph', 'Data', struct('Editable', 'false', 'Text', '&nbsp;', 'Variable', [])));
        end
    
    
        %-----------------------------------------------------------------%
        function htmlSeparator = Separator()
            htmlSeparator = reportLib.sourceCode.htmlCreation(struct('Type', 'Footnote',  'Data', struct('Editable', 'false', 'Text', repmat('_', 1, 45), 'Variable', [])));
        end


        %-----------------------------------------------------------------%
        function editedCellValue = TableCellValue(cellValue, componentSettings, txtClass, recorrenceIndex)            
            editedCellValue = '';

            if islogical(cellValue)
                editedCellValue = char(strjoin(string(cellValue), '<br>'));

            elseif isnumeric(cellValue)
                editedCellValue = double(cellValue);
                
                if any(isnan(editedCellValue))
                    editedCellValue = '';
                    return
                end

                if recorrenceIndex == 1
                    numberPrecision = componentSettings.Precision;
                else
                    dec = 6;
                    tol = 10^-dec;
    
                    roundedCellValue = round(cellValue, dec);
                    for kk = 0:dec                        
                        if all(abs(10^kk * roundedCellValue - round(10^kk * roundedCellValue)) <= tol)
                            dec = kk;
                            break
                        end
                    end
                    numberPrecision = sprintf('%%.%.0ff', dec);
                end

                editedCellValue = strtrim(sprintf([numberPrecision '\n'], cellValue));

            else                
                cellClass = class(cellValue);
                switch cellClass
                    case {'char', 'string', 'categorical'}
                        editedCellValue = strjoin(cellstr(cellValue), '<br>');

                    case 'datetime'
                        editedCellValue = strjoin(cellstr(datestr(cellValue, 'dd/mm/yyyy HH:MM:SS')), '<br>');

                    case 'cell'
                        for ii = 1:numel(cellValue)
                            subCellValue = reportLib.sourceCode.TableCellValue(cellValue{ii}, componentSettings, txtClass, recorrenceIndex+1);
                            if ~isempty(subCellValue)
                                if isempty(editedCellValue)
                                    editedCellValue = subCellValue;
                                else
                                    editedCellValue = strjoin({editedCellValue, subCellValue}, '<br>');
                                end
                            end
                        end
                end
            end
        end
    end
end