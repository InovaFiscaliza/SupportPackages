classdef Table < matlab.ui.componentcontainer.ComponentContainer

    % Author.: Eric Magalhães Delgado
    % Date...: June 24, 2023
    % Version: 1.01

    %% PROPERTIES
    properties (Access = private, Transient, NonCopyable, UsedInUpdate = false, AbortSet)
        PromptPanel     matlab.ui.container.Panel
        PromptGrid      matlab.ui.container.GridLayout
        PromptWarn      matlab.ui.control.Image
        PromptEntry     matlab.ui.control.HTML
        PromptLabel     matlab.ui.control.Label
        Grid            matlab.ui.container.GridLayout
        Filters         matlab.ui.control.Label
        Tool_Filter     matlab.ui.control.Image
        Tool_Last       matlab.ui.control.Image
        Tool_NextRight  matlab.ui.control.Image
        Tool_NextLeft   matlab.ui.control.Image
        Tool_First      matlab.ui.control.Image
        Tool_Range      matlab.ui.control.Label
        Tool_Summary    matlab.ui.control.Label
        HTML            matlab.ui.control.HTML
    end


    properties (AbortSet)
        Data                    table
        Selection               double {ccTools.validators.mustBeTableProperty(Selection,       'Selection')}       = 0
    end


    properties (AbortSet, UsedInUpdate = false)
        ColumnName        (1,:) cell   {ccTools.validators.mustBeTableProperty(ColumnName,      'ColumnName')}      = {'auto'}
        ColumnEditable    (1,:) double {ccTools.validators.mustBeTableProperty(ColumnEditable,  'ColumnEditable')}  = 0
        ColumnWidth       (1,:) cell   {ccTools.validators.mustBeTableProperty(ColumnWidth,     'ColumnWidth')}     = {'auto'}
        ColumnAlign       (1,:) cell   {ccTools.validators.mustBeTableProperty(ColumnAlign,     'ColumnAlign')}     = {'auto'}
        ColumnPrecision   (1,:) cell   {ccTools.validators.mustBeTableProperty(ColumnPrecision, 'ColumnPrecision')} = {'auto'}

        FilterToolbar     (1,1) logical                                                                             = true
        FilteredIndex     (:,1) double                                                                              = []

        % Header
        hFontFamily       (1,1) ccTools.enum.FontFamily                                                             = ccTools.enum.FontFamily.Helvetica
        hFontSize         (1,1) double {ccTools.validators.mustBeUnsignedNumber(hFontSize, 'nonZero')}              = 12
        hFontWeight       (1,1) ccTools.enum.FontWeight                                                             = ccTools.enum.FontWeight.bold
        hFontAlign        (1,1) ccTools.enum.HorizontalAlign                                                        = ccTools.enum.HorizontalAlign.left
        hFontColor        (1,:) char   {ccTools.validators.mustBeColor}                                             = 'white'
        hCapitalLetter    (1,1) logical                                                                             = false
        hClickable        (1,1) logical                                                                             = true

        % Body
        bFontFamily       (1,1) ccTools.enum.FontFamily                                                             = ccTools.enum.FontFamily.Helvetica
        bFontSize         (1,1) double {ccTools.validators.mustBeUnsignedNumber(bFontSize, 'nonZero')}              = 10
        bFontWeight       (1,1) ccTools.enum.FontWeight                                                             = ccTools.enum.FontWeight.normal
        bFontColor        (1,:) char   {ccTools.validators.mustBeColor}                                             = 'black'
        bStripingColor    (1,:) char   {ccTools.validators.mustBeColor}                                             = '#f0f0f0'
        bHoverColor       (1,:) char   {ccTools.validators.mustBeColor}                                             = '#bfe5ff'
        bSelectedColor    (1,:) char   {ccTools.validators.mustBeColor}                                             = '#bfe5ff'
    end


    properties (Access = protected, UsedInUpdate = false)
        pathToMFILE
        pathToTempFolder        
        OnCleanup

        Startup           (1,1) logical                                                                             = true
        EventName         (1,:) char                                                                                = ''
        EventQueue        (1,:) cell
        pTable_MaxRows    (1,1) double                                                                              = 1000
        pTable_Page       (1,1) double                                                                              = 1
        TableSize         (1,1) double                                                                              = 0

        ColumnRawName
        ColumnRawClass
        ColumnClass

        Cell                    struct {ccTools.validators.mustBeTableProperty(Cell,            'Cell')}            = struct('Row', {}, 'Column', {}, 'PreviousValue', {}, 'Value', {})
    end


    %% EVENTS
    events (HasCallbackProperty, NotifyAccess = private)
        SelectionChanged
        CellEdited
        DataFiltered
    end


    %% MAIN METHODS: SETUP & UPDATE
    methods (Access = protected)
        % SETUP (entry point)
        function setup(comp)
            comp.pathToMFILE = fileparts(mfilename('fullpath'));
            
            tempFolder = tempname;
            comp.pathToTempFolder = tempFolder;
            comp.OnCleanup = onCleanup(@()ccTools.fcn.deleteTempFolder(tempFolder));

            comp.Position = [1 1 520 320];
            comp.BackgroundColor = [0.5 0.5 0.5];

            comp.Grid = uigridlayout(comp);
            comp.Grid.ColumnWidth = {'1x', '1x', 17, 17, 17, 17, 17};
            comp.Grid.RowHeight = {'1x', 0, 17, 0};
            comp.Grid.ColumnSpacing = 5;
            comp.Grid.RowSpacing = 2;
            comp.Grid.Padding = [2 2 2 2];
            comp.Grid.BackgroundColor = [1 1 1];

            comp.HTML = uihtml(comp.Grid, Data='', DataChangedFcn=matlab.apps.createCallbackFcn(comp, @HTMLDataChanged, true), HTMLSource=fullfile(comp.pathToMFILE, 'html', 'emptyTable.html'));
            comp.HTML.Layout.Row = 1;
            comp.HTML.Layout.Column = [1 7];

            comp.Filters = uilabel(comp.Grid);
            comp.Filters.VerticalAlignment = 'bottom';
            comp.Filters.WordWrap = 'on';
            comp.Filters.FontSize = 10;
            comp.Filters.FontColor = [0.651 0.651 0.651];
            comp.Filters.Layout.Row = 2;
            comp.Filters.Layout.Column = [1 7];
            comp.Filters.Text = '';

            comp.Tool_Summary = uilabel(comp.Grid);
            comp.Tool_Summary.VerticalAlignment = 'bottom';
            comp.Tool_Summary.FontSize = 10;
            comp.Tool_Summary.FontColor = [0.651 0.651 0.651];
            comp.Tool_Summary.Layout.Row = 3;
            comp.Tool_Summary.Layout.Column = [1 2];
            comp.Tool_Summary.Text = '0 OF 0 ROWS';

            comp.Tool_Range = uilabel(comp.Grid);
            comp.Tool_Range.HorizontalAlignment = 'right';
            comp.Tool_Range.VerticalAlignment = 'bottom';
            comp.Tool_Range.FontSize = 10;
            comp.Tool_Range.FontColor = [0.651 0.651 0.651];
            comp.Tool_Range.Layout.Row = 3;
            comp.Tool_Range.Layout.Column = 2;
            comp.Tool_Range.Text = '0-0';

            comp.Tool_First = uiimage(comp.Grid);
            comp.Tool_First.ImageClickedFcn = matlab.apps.createCallbackFcn(comp, @toolClicked, true);
            comp.Tool_First.Layout.Row = 3;
            comp.Tool_First.Layout.Column = 3;
            comp.Tool_First.Tag = 'ToolArrow';
            comp.Tool_First.ImageSource = fullfile(comp.pathToMFILE, 'icons', 'arrow_move2first.png');
            comp.Tool_First.Enable = 0;

            comp.Tool_NextLeft = uiimage(comp.Grid);
            comp.Tool_NextLeft.ImageClickedFcn = matlab.apps.createCallbackFcn(comp, @toolClicked, true);
            comp.Tool_NextLeft.Layout.Row = 3;
            comp.Tool_NextLeft.Layout.Column = 4;
            comp.Tool_NextLeft.Tag = 'ToolArrow';
            comp.Tool_NextLeft.ImageSource = fullfile(comp.pathToMFILE, 'icons', 'arrow_move2left.png');
            comp.Tool_NextLeft.Enable = 0;

            comp.Tool_NextRight = uiimage(comp.Grid);
            comp.Tool_NextRight.ImageClickedFcn = matlab.apps.createCallbackFcn(comp, @toolClicked, true);
            comp.Tool_NextRight.Layout.Row = 3;
            comp.Tool_NextRight.Layout.Column = 5;
            comp.Tool_NextRight.Tag = 'ToolArrow';
            comp.Tool_NextRight.ImageSource = fullfile(comp.pathToMFILE, 'icons', 'arrow_move2right.png');
            comp.Tool_NextRight.Enable = 0;

            comp.Tool_Last = uiimage(comp.Grid);
            comp.Tool_Last.ImageClickedFcn = matlab.apps.createCallbackFcn(comp, @toolClicked, true);
            comp.Tool_Last.Layout.Row = 3;
            comp.Tool_Last.Layout.Column = 6;
            comp.Tool_Last.Tag = 'ToolArrow';
            comp.Tool_Last.ImageSource = fullfile(comp.pathToMFILE, 'icons', 'arrow_move2end.png');
            comp.Tool_Last.Enable = 0;

            comp.Tool_Filter = uiimage(comp.Grid);
            comp.Tool_Filter.ImageClickedFcn = matlab.apps.createCallbackFcn(comp, @toolClicked, true);
            comp.Tool_Filter.Layout.Row = 3;
            comp.Tool_Filter.Layout.Column = 7;
            comp.Tool_Filter.ImageSource = fullfile(comp.pathToMFILE, 'icons', 'filter.png');
            comp.Tool_Filter.Enable = 0;

            comp.PromptPanel = uipanel(comp.Grid);
            try % BorderColor property is available since Matlab R2023a release 
                comp.PromptPanel.BorderColor = [0.902 0.902 0.902];
            catch
            end
            comp.PromptPanel.BackgroundColor = [1 1 1];
            comp.PromptPanel.Layout.Row = 4;
            comp.PromptPanel.Layout.Column = [1 7];

            comp.PromptGrid = uigridlayout(comp.PromptPanel);
            comp.PromptGrid.ColumnWidth = {0, 17, '1x'};
            comp.PromptGrid.RowHeight = {'1x'};
            comp.PromptGrid.ColumnSpacing = 5;
            comp.PromptGrid.RowSpacing = 3;
            comp.PromptGrid.Padding = [2 2 2 2];
            comp.PromptGrid.BackgroundColor = [1 1 1];

            comp.PromptWarn = uiimage(comp.PromptGrid);
            comp.PromptWarn.Layout.Row = 1;
            comp.PromptWarn.Layout.Column = 1;
            comp.PromptWarn.ImageSource = fullfile(comp.pathToMFILE, 'icons', 'warn.png');
            
            comp.PromptLabel = uilabel(comp.PromptGrid);
            comp.PromptLabel.HorizontalAlignment = 'center';
            comp.PromptLabel.FontName = 'Consolas';
            comp.PromptLabel.FontWeight = 'bold';
            comp.PromptLabel.FontColor = "#d95319"; % [0.651 0.651 0.651]
            comp.PromptLabel.Layout.Row = 1;
            comp.PromptLabel.Layout.Column = 2;
            comp.PromptLabel.Text = '>>';

            comp.PromptEntry = uihtml(comp.PromptGrid);
            comp.PromptEntry.HTMLSource = fileread(fullfile(comp.pathToMFILE, 'html', 'uiTextBox.html'));
            comp.PromptEntry.DataChangedFcn = matlab.apps.createCallbackFcn(comp, @toolClicked, true);
            comp.PromptEntry.Layout.Row = 1;
            comp.PromptEntry.Layout.Column = 3;
        end
        
        
        % UPDATE (public property trigger)
        function update(comp)
            if isempty(comp.HTML.Data) || ~ismember(comp.HTML.Data.Event, {'SelectionChanged_js2mat', 'CellEdited_js2mat'})
                if ismember('DataChanged', comp.EventQueue)
                    columnClass = {};
                    for ii = 1:width(comp.Data)
                        columnClass{ii} = class(comp.Data{:,ii});
                    end
    
                    if ~isequal(comp.ColumnClass, columnClass)
                        comp.Startup = true;
                    end
                    tableCreation(comp)
    
                elseif ismember('SelectionChanged', comp.EventQueue) 
                    if comp.Selection && ~ismember(comp.Selection, comp.FilteredIndex)
                        comp.Selection = 0;
                    else
                        idx1 = find(comp.FilteredIndex == comp.Selection, 1) - (comp.pTable_Page-1)*comp.pTable_MaxRows;
                        if isempty(idx1)
                            idx1 = 0;
                        end

                        if (idx1 >= 0) && (idx1 <= comp.pTable_MaxRows)
                            comp.HTML.Data = struct('Event', 'SelectionChanged_mat2js', 'Value', idx1);
                        end
                    end
                end
            end
    
            comp.EventName  = '';
            comp.EventQueue = {};

            if ~isempty(comp.HTML.Data) && ismember(comp.HTML.Data.Event, {'SelectionChanged_js2mat', 'CellEdited_js2mat'})
                comp.HTML.Data = '';
            end
        end
        

        % JS >> MATLAB EVENTS
        function HTMLDataChanged(comp, event)
            switch comp.HTML.Data.Event
                case 'SelectionChanged_js2mat'
                    newSelection = comp.HTML.Data.Value;
                    if newSelection
                        newSelection = comp.FilteredIndex(newSelection+(comp.pTable_Page-1)*comp.pTable_MaxRows);
                    end

                    comp.EventName = 'SelectionChanged_js2mat';
                    comp.Selection = newSelection;                          % update() trigger

                    notify(comp, 'SelectionChanged')

                case 'CellEdited_js2mat'
                    newCell = comp.HTML.Data.Value;
                    newCell.Row = comp.FilteredIndex(newCell.Row+(comp.pTable_Page-1)*comp.pTable_MaxRows);
                    if ~isnumeric(newCell.Value)
                        newCell.Value = string(newCell.Value);
                    end

                    comp.EventName = 'CellEdited_js2mat';
                    comp.Data{newCell.Row, newCell.Column} = newCell.Value;  % update() trigger

                    comp.Cell = newCell;
                    notify(comp, 'CellEdited')
            end
        end
        
        
        % TOOLBAR EVENTS
        function toolClicked(comp, event)
            Flag = false;
            switch event.Source
                case comp.Tool_Filter
                    if comp.Grid.RowHeight{4}; comp.Grid.RowHeight{4} = 0;
                    else;                      comp.Grid.RowHeight{4} = 24;
                    end
                
                case comp.PromptEntry
                    if ~isequal(comp.PromptEntry.Data, comp.Filters.Text)
                        Flag = true;
                        comp.pTable_Page = 1;
                    end

                otherwise
                    nPages = ceil(str2double(extractBefore(comp.Tool_Summary.Text, 'OF')) / comp.pTable_MaxRows);

                    switch event.Source                
                        case comp.Tool_First
                            if comp.pTable_Page > 1
                                Flag = true;
                                comp.pTable_Page = 1;
                            end
        
                        case comp.Tool_NextLeft
                            if comp.pTable_Page > 1
                                Flag = true;
                                comp.pTable_Page = comp.pTable_Page-1;
                            end
        
                        case comp.Tool_NextRight
                            if comp.pTable_Page < nPages
                                Flag = true;
                                comp.pTable_Page = comp.pTable_Page+1;
                            end
        
                        case comp.Tool_Last
                            if comp.pTable_Page < nPages
                                Flag = true;
                                comp.pTable_Page = nPages;
                            end
                    end
            end

            if Flag
                tableCreation(comp)
            end            
        end


        % COMPONENT STARTUP, DATA FILTERING AND SO ON...
        function tableCreation(comp)
            % Filled table startup
            if comp.Startup
                comp.Startup = false;

                comp.PromptEntry.Data = '';
                comp.Filters.Text     = '';                    
                comp.pTable_Page      = 1;
                comp.TableSize        = height(comp.Data);

                if isempty(comp.Data.Properties.VariableNames)
                    comp.HTML.HTMLSource = fullfile(comp.pathToMFILE, 'html', 'emptyTable.html');
                    comp.Grid.RowHeight(2:4) = {0, 17, 0};
                    htmlPaginationTable(comp, table);
                else
                    startup_PropertiesCheck(comp);
                    [editFlag, hTable] = startup_DataTypeCheck(comp);
                    comp.FilteredIndex = (1:height(hTable))';
    
                    if editFlag
                        comp.Data = hTable;                                 % update() trigger
                        pause(.001)
                    else
                        htmlConstructor(comp, hTable);
                    end
                end

            else
                % FilterToolbar visibility
                if ~comp.FilterToolbar
                    if height(comp.Data) <= comp.pTable_MaxRows
                        comp.Grid.RowHeight(2:4) = {0,0,0};
                    else
                        comp.Grid.RowHeight(3) = {17};
                    end
                end
    
                % Filtering
                initialFilteredIndex = comp.FilteredIndex;
    
                if isempty(comp.PromptEntry.Data)
                    fTable    = comp.Data;
                    fIndex    = (1:height(comp.Data))';
                    fSentence = '';
                    fValid    = true;
                else
                    [fTable, fIndex, fTableParser, fSentence, fValid] = ccTools.fcn.TableFilter(comp.Data, comp.PromptEntry.Data);

                    fPrecision = fTableParser(strcmp(fTableParser.Operation, 'PRECISION'),:);
                    for ii = 1:height(fPrecision)
                        comp.ColumnPrecision(fPrecision.Column(ii)) = lower(extractBetween(fPrecision.Value{ii}, '"', '"'));
                    end
                end

                comp.FilteredIndex = fIndex;
                comp.Filters.Text  = fSentence;
    
                if ~isempty(comp.Filters.Text); comp.Grid.RowHeight{2} = 17;
                else;                           comp.Grid.RowHeight{2} = 0;
                end
    
                if fValid; comp.PromptGrid.ColumnWidth{1} = 0;
                else;      comp.PromptGrid.ColumnWidth{1} = 17;
                end
    
                % Selection property reset
                if ~ismember(comp.Selection, comp.FilteredIndex)
                    comp.Selection = 0;
                end
    
                if ~isempty(comp.Cell)
                    comp.Cell(1) = [];
                end

                % HTML
                htmlConstructor(comp, fTable);
    
                % Event
                if ~isequal(initialFilteredIndex, comp.FilteredIndex) || (height(comp.Data) ~= comp.TableSize)
                    comp.TableSize = height(comp.Data);
                    notify(comp, 'DataFiltered')
                end
            end
        end


        function hTable = startup_EmptyTable(comp)
            COLUMNS = numel(comp.ColumnName);
            
            variableNames = comp.ColumnName;
            variableTypes = comp.ColumnPrecision;
            
            if isequal(variableNames, {'auto'}) && isequal(variableTypes, {'auto'})
                hTable = table;
                return

            elseif isequal(variableNames, {'auto'})
                COLUMNS = numel(comp.ColumnPrecision);

                variableNames = repmat({''}, 1, COLUMNS);
                for ii = 1:COLUMNS
                    variableNames{ii} = sprintf('Column%d', ii);
                end
                variableTypes = repmat({'string'}, 1, COLUMNS);

            else
                variableNames = repmat({''}, 1, COLUMNS);
                for ii = 1:COLUMNS
                    variableNames{ii} = columnNameAdjust(comp, ii);
                end
                variableTypes = repmat({'string'}, 1, COLUMNS);
            end           

            hTable = table('Size', [0, COLUMNS], 'VariableTypes', variableTypes, 'VariableNames', variableNames);
        end


        function startup_PropertiesCheck(comp)
            hTable  = comp.Data;
            COLUMNS = width(hTable);

            % ColumnName
            if isequal(comp.ColumnName, {'auto'}) || (numel(comp.ColumnName) ~= COLUMNS)
                comp.ColumnName = hTable.Properties.VariableNames;
            end

            % ColumnEditable
            if numel(comp.ColumnEditable) ~= COLUMNS
                comp.ColumnEditable = zeros(1, COLUMNS);
            end

            % ColumnWidth
            if isequal(comp.ColumnWidth, {'auto'}) || (numel(comp.ColumnWidth) ~= COLUMNS)
                comp.ColumnWidth = repmat({'auto'}, [1, COLUMNS]);
            end

            % ColumnAlign, ColumnPrecision
            Flag = false;
            if isequal(comp.ColumnAlign, {'auto'}) || (numel(comp.ColumnAlign) ~= COLUMNS) || ...
                    isequal(comp.ColumnPrecision, {'auto'}) || (numel(comp.ColumnPrecision) ~= COLUMNS)
                Flag = true;
            end

            if Flag
                Align      = {};
                Precision  = {};
                for ii = 1:COLUMNS
                    if ismember(class(hTable{:,ii}), ["cell", "string", "datetime", "categorical"])
                        Align{ii}      = 'left';
                        Precision{ii}  = '%s';
                    elseif islogical(hTable{:,ii}) || isinteger(hTable{:,ii})
                        Align{ii}      = 'right';
                        Precision{ii}  = '%.0f';    
                    elseif isfloat(hTable{:,ii})
                        dec = 6;
                        tol = 10^-dec;
    
                        nArray = round(hTable{:,ii}, dec);
                        for jj = 0:dec                        
                            if all(abs(10^jj * nArray - round(10^jj * nArray)) <= tol)
                                dec = jj;
                                break
                            end
                        end
                        Align{ii}      = 'right';
                        Precision{ii}  = sprintf('%%.%.0ff', dec);    
                    else
                        error('ccTools.Table accepts only text ("cell", "string" and "categorical"), datetime, logical and numeric ("double", "single", "uint8", "int8" and so on) as data classes.')
                    end
                end

                if isequal(comp.ColumnAlign, {'auto'}) || (numel(comp.ColumnAlign) ~= COLUMNS)
                    comp.ColumnAlign = Align;
                end

                if isequal(comp.ColumnPrecision, {'auto'}) || (numel(comp.ColumnPrecision) ~= COLUMNS)
                    comp.ColumnPrecision = Precision;
                end
            end
        end


        % TABLE DATATYPES (keep only numeric & string data types)
        function [editFlag, hTable] = startup_DataTypeCheck(comp)
            editFlag = false;
            hTable   = comp.Data;
            COLUMNS  = width(hTable);

            columnRawClass = {};
            columnClass    = {};
            
            for ii = 1:COLUMNS
                columnRawClass{ii} = class(hTable{:,ii});

                if     isnumeric(hTable{:,ii}); columnClass{ii} = columnRawClass{ii}; continue
                elseif islogical(hTable{:,ii}); columnClass{ii} = 'double';
                else;                           columnClass{ii} = 'string';
                end
                
                switch columnRawClass{ii}
                    case 'logical'
                        hTable = convertvars(hTable, ii, 'double');         % logical >> double
                        continue

                    case 'categorical'                                      % categorical >> string
                        hTable = convertvars(hTable, ii, 'string');

                    case 'datetime'                                         % datetime >> string
                        hTable{:,ii}.Format = 'dd/MM/yyyy HH:mm:ss';
                        hTable = convertvars(hTable, ii, 'string');

                    case 'cell'                                             % cell >> string
                        subColumnClass = unique(cellfun(@(x) class(x), hTable{:,ii}, 'UniformOutput', false));

                        for jj = 1:numel(subColumnClass)
                            idx = cellfun(@(x) strcmp(class(x), subColumnClass{jj}), hTable{:,ii});

                            try
                                switch subColumnClass{jj}
                                    case 'char'
                                    case 'cell'
                                        for kk = find(idx)'
                                            try
                                                hTable{kk,ii} = {strjoin(hTable{kk,ii}{1}, '<br>')};
                                            catch
                                                hTable{kk,ii} = {'-'};
                                            end
                                        end
                                    otherwise % string, categorical and so on...
                                        hTable{idx,ii} = cellfun(@(x) {char(strjoin(string(x), '<br>'))}, hTable{idx,ii});
                                end
                            catch
                                hTable{idx,ii} = {'-'};
                            end
                        end
                        hTable = convertvars(hTable, ii, 'string');
                end
                % Replacing special characters to allow linebreak ("newline") and to avoid filter error (";", "&&" and "||").
                hTable{:,ii} = replace(hTable{:,ii}, {newline, ';', '&&', '||'}, {'<br>', ',', '&', '|'});
            end

            comp.ColumnRawName  = hTable.Properties.VariableNames;
            comp.ColumnRawClass = columnRawClass;
            comp.ColumnClass    = columnClass;

            if ~isequal(columnRawClass, columnClass) || ~isequal(hTable, comp.Data)
                editFlag = true;
                if isequal(hTable, comp.Data)
                    hTable = addprop(hTable, {'Event'}, {'table'});
                    hTable.Properties.CustomProperties.Event = 'DataTypeConversion';
                end
            end
        end
    end

    
    %% HTML SOURCE CODE CONSTRUCTOR
    methods (Access = protected)        
        function htmlConstructor(comp, fTable)
            pTable  = htmlPaginationTable(comp, fTable);

            ROWS    = height(pTable);
            COLUMNS = width(pTable);

            % TEMP FILE
            tempFile = fullfile(comp.pathToTempFolder, sprintf('TableView_%s.html', datestr(now, 'yyyymmdd_THHMMSS')));
            if ~isfolder(comp.pathToTempFolder)
                mkdir(comp.pathToTempFolder)
            end
            fileID = fopen(tempFile, 'w'); 
            
            % HEADER
            fwrite(fileID, sprintf(['<!DOCTYPE html>\n<html>\n%s\n\n<body>\n' ...
                                    '<table id="ccTable">\n\t<thead>\n\t\t<tr>'], htmlHeaderTemplate(comp)), 'char');

            for jj = 1:COLUMNS
                switch comp.EventName
                    case 'emptyTable' % component startup
                        fwrite(fileID, sprintf('\n\t\t\t<th scope="col">%s</th>', fTable.Properties.VariableNames{jj}), 'char');

                    otherwise
                        % ColumnWidth
                        if strcmp(comp.ColumnWidth{jj}, 'auto'); columnWidth = '';
                        else;                                    columnWidth = sprintf(' style="width: %s;"', comp.ColumnWidth{jj});
                        end

                        % ColumnName
                        columnName = columnNameAdjust(comp, jj);
        
                        % ColumnEditable
                        if comp.ColumnEditable(jj); columnEditable = ' contenteditable="true"';
                        else;                       columnEditable = '';
                        end
        
                        fwrite(fileID, sprintf('\n\t\t\t<th scope="col"%s>%s</th>', columnWidth, columnName), 'char');
                        rowTemplate{jj} = sprintf('<td class="%s"%s>%s</td>', comp.ColumnAlign{jj}, columnEditable, comp.ColumnPrecision{jj});
                end
            end
            fwrite(fileID, sprintf('\n\t\t</tr>\n\t</thead>\n\n\t<tbody>'), 'char');
            
            % BODY
            selectedRow = find(comp.FilteredIndex == comp.Selection, 1) - (comp.pTable_Page-1)*comp.pTable_MaxRows;
            for ii = 1:ROWS
                % SelectedRow
                if (ii == selectedRow); selectedRowTag = ' class="selected"';
                else;                   selectedRowTag = '';
                end

                fwrite(fileID, sprintf('\n\t\t<tr contenteditable="false"%s>', selectedRowTag), 'char');

                for jj = 1:COLUMNS
                    value = pTable{ii, jj};          
                    fwrite(fileID, sprintf(rowTemplate{jj}, value), 'char');
                end            
                fwrite(fileID, '</tr>', 'char');
            end            
            fwrite(fileID, [sprintf('\n\t</tbody>\n</table>\n\n'), htmlScriptTemplate(comp), sprintf('\n</body>\n</html>')], 'char');
            fclose(fileID);

            comp.HTML.HTMLSource = tempFile;
        end


        % COLUMNNAME
        function columnName = columnNameAdjust(comp, jj)
            columnName = comp.ColumnName{jj};
            if iscell(columnName); columnName = strjoin(columnName, '<br>');
            end
            columnName = replace(columnName, {newline, '|'}, '<br>');
            if comp.hCapitalLetter; columnName = upper(columnName);
            end
        end


        % PAGINATION TABLE (pTable) & TOOLBAR LAYOUT
        function pTable = htmlPaginationTable(comp, fTable)
            ROWS = height(fTable);
            
            if ROWS
                idx1   = (comp.pTable_Page - 1) * comp.pTable_MaxRows + 1;
                idx2   = min([idx1 + comp.pTable_MaxRows - 1, ROWS]);
                pTable = fTable(idx1:idx2, :);

                comp.Tool_Range.Text    = sprintf('%d-%d', idx1, idx2);
                comp.Tool_Filter.Enable = 1;
            else
                pTable = fTable;

                comp.Tool_Range.Text    = '0-0';
                comp.Tool_Filter.Enable = 0;
            end
            comp.Tool_Summary.Text = sprintf('%d OF %d ROWS', ROWS, height(comp.Data));

            nPages = ceil(ROWS / comp.pTable_MaxRows);
            if nPages > 1
                set(findobj(comp.Grid.Children, 'Tag', 'ToolArrow'), 'Enable', 1)
                if comp.pTable_Page == 1
                    comp.Tool_First.Enable     = 0;
                    comp.Tool_NextLeft.Enable  = 0;
                elseif comp.pTable_Page == nPages
                    comp.Tool_NextRight.Enable = 0;
                    comp.Tool_Last.Enable      = 0;
                end                
            else
                set(findobj(comp.Grid.Children, 'Tag', 'ToolArrow'), 'Enable', 0)
            end
        end


        % CSS
        function htmlHeader = htmlHeaderTemplate(comp)
            ColumnType = {};
            for ii = 1:numel(comp.ColumnPrecision)
                if strcmp(comp.ColumnPrecision{ii}, '%s'); ColumnType{ii} = 'text';
                else;                                      ColumnType{ii} = 'numeric';
                end
            end

            BackGroundColor     = uint8(255*comp.BackgroundColor);
            htmlBackGroundColor = sprintf('rgb(%d, %d, %d)', BackGroundColor(1), BackGroundColor(2), BackGroundColor(3));

            htmlTemplate = ['<head>\n<style type="text/css">\n'                           ...
                            fileread(fullfile(comp.pathToMFILE, 'css&js', 'ccTable.css')) ...
                            '\n</style>\n<meta name="column-type" content="%s">\n</head>'];

            htmlHeader   = sprintf(htmlTemplate, comp.hFontFamily, comp.hFontSize, comp.hFontWeight, comp.hFontAlign, comp.hFontColor, htmlBackGroundColor,                       ...
                                                 comp.bFontFamily, comp.bFontSize, comp.bFontWeight, comp.bFontColor, comp.bStripingColor, comp.bHoverColor, comp.bSelectedColor, ...
                                                 strjoin(ColumnType, ','));
        end


        % JS
        function htmlScript = htmlScriptTemplate(comp)
            Clickable = '';
            if comp.hClickable; Clickable = '=';
            end

            htmlTemplate = ['<script type="text/javascript">\n'                          ...
                            fileread(fullfile(comp.pathToMFILE, 'css&js', 'ccTable.js')) ...
                            '\n</script>'];

            htmlScript   = sprintf(htmlTemplate, Clickable);
        end
    end


    %% SET/GET OF MAIN PUBLIC PROPERTIES (DATA, SELECTION AND ROW)
    methods
        function set.Data(comp, value)
            set(comp, 'EventName', 'DataChanged')
            comp.Data = value;
        end

        function set.Selection(comp, value)
            set(comp, 'EventName', 'SelectionChanged')
            comp.Selection = value;
        end

        function set.EventName(comp, value)
            comp.EventName = value;
            if ismember(value, {'DataChanged', 'SelectionChanged'})
                set(comp, 'EventQueue', {value})
            end
        end

        function set.EventQueue(comp, value)
            if isempty(char(value))
                comp.EventQueue = {};
            elseif ~ismember(value, comp.EventQueue)
                comp.EventQueue(end+1) = value;
            end
        end
    end
end