function [status, errorMsg] = compCustomization(comp, varargin)

    arguments
        comp {ccTools.validators.mustBeBuiltInComponent}
    end

    arguments (Repeating)
        varargin
    end

    status   = true;
    errorMsg = '';
    
    % ccTools.fcn.compatibilityWarning('compCustomization')

    % nargin validation
    if nargin == 1
        error('At least one Name-Value parameters must be passed to the function.')
    elseif mod(nargin-1, 2)
        error('Name-value parameters must be in pairs.')
    end

    warning('off', 'MATLAB:structOnObject')
    warning('off', 'MATLAB:ui:javaframe:PropertyToBeRemoved')
    
    % main variables
    [webWin, compTag] = ccTools.fcn.componentInfo(comp);
    if isempty(webWin)
        return
    end

    % customizations...
    switch class(comp)
    %---------------------------------------------------------------------%
        case 'matlab.ui.Figure'
            propStruct = InputParser({'windowMinSize'}, varargin{:});

            for ii = 1:numel(propStruct)
                switch propStruct(ii).name
                    case 'windowMinSize'
                        try
                            webWin.setMinSize(propStruct(ii).value)
                        catch  ME
                            status   = false;
                            errorMsg = getReport(ME);
                        end
                        return
                end
            end


    %---------------------------------------------------------------------%
        case {'matlab.ui.container.ButtonGroup',  ...
              'matlab.ui.container.CheckBoxTree', ...
              'matlab.ui.container.Panel',        ...
              'matlab.ui.container.Tree'}
            propStruct = InputParser({'backgroundColor', ...
                                      'borderRadius', 'borderWidth', 'borderColor'}, varargin{:});

            jsCommand = '';
            for ii = 1:numel(propStruct)
                jsCommand = sprintf(['%sdocument.querySelector(''div[data-tag="%s"]'').style.%s = "%s";\n' ...
                                       'document.querySelector(''div[data-tag="%s"]'').children[0].style.%s = "%s";\n'], jsCommand, compTag, propStruct(ii).name, propStruct(ii).value, compTag, propStruct(ii).name, propStruct(ii).value);
            end


    %---------------------------------------------------------------------%
        case 'matlab.ui.container.GridLayout'
            propStruct = InputParser({'backgroundColor'}, varargin{:});
            jsCommand  = sprintf('document.querySelector(''div[data-tag="%s"]'').style.backgroundColor = "%s";\n', compTag, propStruct.value);


    %---------------------------------------------------------------------%
        case 'matlab.ui.container.TabGroup'
            propStruct = InputParser({'backgroundColor', 'backgroundHeaderColor',   ...
                                      'borderRadius', 'borderWidth', 'borderColor', ...
                                      'fontFamily', 'fontStyle', 'fontWeight', 'fontSize', 'color'}, varargin{:});

            jsCommand = '';
            for ii = 1:numel(propStruct)
                switch propStruct(ii).name
                    case 'backgroundColor'
                        jsCommand = sprintf(['%sdocument.querySelector(''div[data-tag="%s"]'').style.backgroundColor = "transparent";\n' ...
                                               'document.querySelector(''div[data-tag="%s"]'').children[0].style.backgroundColor = "transparent"\n'], jsCommand, compTag, compTag);
                        for jj = 1:numel(comp.Children)
                            [~, ChildrenTag] = ccTools.fcn.componentInfo(comp.Children(jj));
                            jsCommand   = sprintf('%sdocument.querySelector(''div[data-tag="%s"]'').style.backgroundColor = "%s";\n', jsCommand, ChildrenTag, propStruct(ii).value);
                        end

                    case 'backgroundHeaderColor'
                        jsCommand = sprintf(['%sdocument.querySelector(''div[data-tag="%s"]'').style.backgroundColor = "transparent";\n' ...
                                               'document.querySelector(''div[data-tag="%s"]'').children[1].style.backgroundColor = "%s";\n'], jsCommand, compTag, compTag, propStruct(ii).value);

                    case {'borderRadius', 'borderWidth', 'borderColor'}
                        jsCommand = sprintf('%sdocument.querySelector(''div[data-tag="%s"]'').style.%s = "%s";\n', jsCommand, compTag, propStruct(ii).name, propStruct(ii).value);
                end
            end

            % Font Properties (iterative process, going through all the tabs)
            idx = find(cellfun(@(x) ~isempty(x), cellfun(@(x) find(strcmp({'fontFamily', 'fontStyle', 'fontWeight', 'fontSize', 'color'}, x), 1), {propStruct.name}, 'UniformOutput', false)));
            if ~isempty(idx)
                jsCommand = sprintf(['%svar elements = document.querySelector(''div[data-tag="%s"]'').getElementsByClassName("mwTabLabel");\n' ...
                                       'for (let ii = 1; ii < elements.length; ii++) {\n'], jsCommand, compTag);
                for ll = idx
                    jsCommand = sprintf('%selements[ii].style.%s = "%s";\n', jsCommand, propStruct(ll).name, propStruct(ll).value);
                end
                jsCommand = sprintf('%s}\nelements = undefined;\n', jsCommand);
            end


    %---------------------------------------------------------------------%
        case 'matlab.ui.container.Tab'
            propStruct = InputParser({'backgroundColor'}, varargin{:});
            [~, ParentTag] = ccTools.fcn.componentInfo(comp.Parent);
            jsCommand  = sprintf(['document.querySelector(''div[data-tag="%s"]'').style.backgroundColor = "transparent";\n', ...
                                  'document.querySelector(''div[data-tag="%s"]'').style.backgroundColor = "%s";\n'], ParentTag, compTag, propStruct.value);


    %---------------------------------------------------------------------%
        case {'matlab.ui.control.Button',           ...
              'matlab.ui.control.DropDown',         ...
              'matlab.ui.control.EditField',        ...
              'matlab.ui.control.ListBox',          ...
              'matlab.ui.control.NumericEditField', ...
              'matlab.ui.control.StateButton'}
            propStruct = InputParser({'borderRadius', 'borderWidth', 'borderColor'}, varargin{:});

            jsCommand = '';
            for ii = 1:numel(propStruct)
                jsCommand = sprintf('%sdocument.querySelector(''div[data-tag="%s"]'').children[0].style.%s = "%s";\n', jsCommand, compTag, propStruct(ii).name, propStruct(ii).value);
            end


    %---------------------------------------------------------------------%
        case 'matlab.ui.control.TextArea'
            propStruct = InputParser({'backgroundColor',                            ...
                                      'borderRadius', 'borderWidth', 'borderColor', ...
                                      'textAlign'}, varargin{:});

            jsCommand = '';
            for ii = 1:numel(propStruct)
                switch propStruct(ii).name
                    case 'backgroundColor'
                        jsCommand = sprintf(['%sdocument.querySelector(''div[data-tag="%s"]'').style.backgroundColor = "transparent";\n' ...
                                               'document.querySelector(''div[data-tag="%s"]'').children[0].style.backgroundColor = "%s";\n'], jsCommand, compTag, compTag, propStruct(ii).value);

                    case 'textAlign'
                        jsCommand = sprintf('%sdocument.querySelector(''div[data-tag="%s"]'').getElementsByTagName("textarea")[0].style.textAlign = "%s";\n', jsCommand, compTag, propStruct(ii).value);
                    
                    otherwise
                        jsCommand = sprintf('%sdocument.querySelector(''div[data-tag="%s"]'').children[0].style.%s = "%s";\n', jsCommand, compTag, propStruct(ii).name, propStruct(ii).value);
                end
            end


    %---------------------------------------------------------------------%
        case 'matlab.ui.control.CheckBox'
            propStruct = InputParser({'backgroundColor',                            ...
                                      'borderRadius', 'borderWidth', 'borderColor'}, varargin{:});

            jsCommand = '';
            for ii = 1:numel(propStruct)
                jsCommand = sprintf('%sdocument.querySelector(''div[data-tag="%s"]'').getElementsByClassName("mwCheckBoxRadioIconNode")[0].style.%s = "%s";\n', jsCommand, compTag, propStruct(ii).name, propStruct(ii).value);
            end


    %---------------------------------------------------------------------%
        case 'matlab.ui.control.Table'
            propStruct = InputParser({'backgroundColor', 'backgroundHeaderColor',   ...
                                      'borderRadius', 'borderWidth', 'borderColor', ...
                                      'textAlign', 'fontFamily', 'fontStyle', 'fontWeight', 'fontSize', 'color'}, varargin{:});

            jsCommand = '';
            for ii = 1:numel(propStruct)
                switch propStruct(ii).name
                    case 'backgroundColor'
                        jsCommand = sprintf(['%sdocument.querySelector(''div[data-tag="%s"]'').children[0].style.backgroundColor = "transparent";\n' ...
                                               'document.querySelector(''div[data-tag="%s"]'').children[0].children[0].style.backgroundColor = "%s";\n'], jsCommand, compTag, compTag, propStruct(ii).value);

                    case 'backgroundHeaderColor'
                        jsCommand = sprintf('%sdocument.querySelector(''div[data-tag="%s"]'').children[0].children[0].children[0].style.backgroundColor = "%s";\n', jsCommand, compTag, propStruct(ii).value);

                    case 'borderRadius'
                        jsCommand = sprintf(['%sdocument.querySelector(''div[data-tag="%s"]'').children[0].style.borderRadius = "%s";\n'             ...
                                               'document.querySelector(''div[data-tag="%s"]'').children[0].children[0].style.borderRadius = "%s";\n'], jsCommand, compTag, propStruct(ii).value, compTag, propStruct(ii).value);

                    case {'borderWidth', 'borderColor'}
                        jsCommand = sprintf('%sdocument.querySelector(''div[data-tag="%s"]'').children[0].children[0].style.%s = "%s";\n', jsCommand, compTag, propStruct(ii).name, propStruct(ii).value);
                end
            end

            % Font text align (iterative process, going through all the columns)
            idx1 = find(strcmp('textAlign', {propStruct.name}), 1);
            if ~isempty(idx1)
                jsCommand = sprintf(['%svar elements = document.querySelector(''div[data-tag="%s"]'').getElementsByClassName("mw-table-header-row")[0].children;\n' ...
                                       'for (let ii = 0; ii < elements.length; ii++) {\n'], jsCommand, compTag);
                for jj = idx1
                    jsCommand = sprintf('%selements[ii].style.%s = "%s";\n', jsCommand, propStruct(jj).name, propStruct(jj).value);
                end
                jsCommand = sprintf('%s}\nelements = undefined;\n', jsCommand);
            end

            % Others font properties (iterative process, going through all the columns)
            idx2 = find(cellfun(@(x) ~isempty(x), cellfun(@(x) find(strcmp({'fontFamily', 'fontStyle', 'fontWeight', 'fontSize', 'color'}, x), 1), {propStruct.name}, 'UniformOutput', false)));
            if ~isempty(idx2)
                % Row-like table header (Default)
                jsCommand = sprintf(['%svar elements = document.querySelector(''div[data-tag="%s"]'').getElementsByClassName("mw-default-header-cell");\n' ...
                                       'for (let ii = 0; ii < elements.length; ii++) {\n'], jsCommand, compTag);
                for ll = idx2
                    jsCommand = sprintf('%selements[ii].style.%s = "%s";\n', jsCommand, propStruct(ll).name, propStruct(ll).value);
                end
                jsCommand = sprintf('%s}\nelements = undefined;\n\n', jsCommand);


                % Column-like table header
                jsCommand = sprintf(['%svar elements = document.querySelector(''div[data-tag="%s"]'').querySelectorAll(".mw-table-row-header .mw-string-renderer");\n' ...
                                       'for (let ii = 0; ii < elements.length; ii++) {\n'], jsCommand, compTag);
                for mm = idx2
                    jsCommand = sprintf('%selements[ii].style.%s = "%s";\n', jsCommand, propStruct(mm).name, propStruct(mm).value);
                end
                jsCommand = sprintf('%s}\nelements = undefined;', jsCommand);
            end


    %---------------------------------------------------------------------%
        otherwise
            error('ccTools does not cover the customization of ''%s'' class properties.', class(comp))
    end


    % JS
    pause(.001)
    try
        webWin.executeJS(jsCommand);
    catch ME
        status   = false;
        errorMsg = getReport(ME);
    end
end


function propStruct = InputParser(propList, varargin)    
    p = inputParser;
    d = [];

    for ii = 1:numel(propList)
        switch(propList{ii})
            % Window
            case 'windowMinSize';         addParameter(p, 'windowMinSize',         d, @(x) ccTools.validators.mustBeNumericArray(x, 2, 'NonNegativeInteger'))

            % BackgroundColor
            case 'backgroundColor';       addParameter(p, 'backgroundColor',       d, @(x) ccTools.validators.mustBeColor(x, 'all'))
            case 'backgroundHeaderColor'; addParameter(p, 'backgroundHeaderColor', d, @(x) ccTools.validators.mustBeColor(x, 'all'))

            % Border
            case 'borderRadius';          addParameter(p, 'borderRadius',          d, @(x) ccTools.validators.mustBeCSSProperty(x, 'border-radius'))
            case 'borderWidth';           addParameter(p, 'borderWidth',           d, @(x) ccTools.validators.mustBeCSSProperty(x, 'border-width'))
            case 'borderColor';           addParameter(p, 'borderColor',           d, @(x) ccTools.validators.mustBeColor(x, 'all'))

            % Font
            case 'textAlign';             addParameter(p, 'textAlign',             d, @(x) ccTools.validators.mustBeCSSProperty(x, 'text-align'))
            case 'fontFamily';            addParameter(p, 'fontFamily',            d, @(x) ccTools.validators.mustBeCSSProperty(x, 'font-family'))
            case 'fontStyle';             addParameter(p, 'fontStyle',             d, @(x) ccTools.validators.mustBeCSSProperty(x, 'font-style'))
            case 'fontWeight';            addParameter(p, 'fontWeight',            d, @(x) ccTools.validators.mustBeCSSProperty(x, 'font-weight'))
            case 'fontSize';              addParameter(p, 'fontSize',              d, @(x) ccTools.validators.mustBeCSSProperty(x, 'font-size'))
            case 'color';                 addParameter(p, 'color',                 d, @(x) ccTools.validators.mustBeColor(x, 'all'))
        end
    end
            
    parse(p, varargin{:});

    propStruct = struct('name', {}, 'value', {});
    propName   = setdiff(p.Parameters, p.UsingDefaults);

    for ll = 1:numel(propName)
        propValue = p.Results.(propName{ll});

        if ismember(propName{ll}, {'backgroundColor', 'backgroundHeaderColor', 'borderColor', 'color'})
            if isnumeric(p.Results.(propName{ll}))
                propValue = ccTools.fcn.rgb2hex(propValue);
            else
                propValue = char(propValue);
            end
        end

        propStruct(ll) = struct('name',  propName{ll}, ...
                                'value', propValue);
    end
end