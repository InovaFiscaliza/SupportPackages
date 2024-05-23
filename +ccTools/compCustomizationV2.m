function compCustomizationV2(jsBackDoor, comp, varargin)

    arguments
        jsBackDoor {isa(jsBackDoor, 'matlab.ui.control.HTML')}
        comp       {ccTools.validators.mustBeBuiltInComponent}
    end

    arguments (Repeating)
        varargin
    end
    
    % ccTools.fcn.compatibilityWarning('compCustomizationV2')

    % nargin validation
    if nargin <= 2
        error('At least one Name-Value parameters must be passed to the function.')
    elseif mod(nargin-2, 2)
        error('Name-value parameters must be in pairs.')
    end

    warning('off', 'MATLAB:structOnObject')
    warning('off', 'MATLAB:ui:javaframe:PropertyToBeRemoved')
    
    % main variables
    releaseVersion = version('-release');
    releaseYear    = str2double(releaseVersion(1:4));

    if releaseYear <= 2022
        compTag = struct(comp).Controller.ProxyView.PeerNode.Id;
    else
        compTag = struct(comp).Controller.ViewModel.Id;
    end

    % customizations...
    switch class(comp)
    %---------------------------------------------------------------------%
        case {'matlab.ui.container.ButtonGroup',  ...
              'matlab.ui.container.CheckBoxTree', ...
              'matlab.ui.container.Panel',        ...
              'matlab.ui.container.Tree'}
            propStruct = InputParser({'backgroundColor', ...
                                      'borderRadius', 'borderWidth', 'borderColor'}, varargin{:});

        case 'matlab.ui.container.GridLayout'
            propStruct = InputParser({'backgroundColor'}, varargin{:});

        case 'matlab.ui.container.TabGroup'
            propStruct = InputParser({'backgroundColor', 'backgroundHeaderColor', 'transparentHeader', ...
                                      'borderRadius', 'borderWidth', 'borderColor',                    ...
                                      'fontFamily', 'fontStyle', 'fontWeight', 'fontSize', 'color'}, varargin{:});

        case {'matlab.ui.control.Button',           ...
              'matlab.ui.control.DropDown',         ...
              'matlab.ui.control.EditField',        ...
              'matlab.ui.control.ListBox',          ...
              'matlab.ui.control.NumericEditField', ...
              'matlab.ui.control.StateButton'}
            propStruct = InputParser({'borderRadius', 'borderWidth', 'borderColor'}, varargin{:});

        case 'matlab.ui.control.TextArea'
            propStruct = InputParser({'backgroundColor',                            ...
                                      'borderRadius', 'borderWidth', 'borderColor', ...
                                      'textAlign'}, varargin{:});

        case 'matlab.ui.control.Label'
            propStruct = InputParser({'textAlign'}, varargin{:});

        case 'matlab.ui.control.CheckBox'
            propStruct = InputParser({'backgroundColor',                            ...
                                      'borderRadius', 'borderWidth', 'borderColor'}, varargin{:});

        case 'matlab.ui.control.Table'
            propStruct = InputParser({'backgroundColor', 'backgroundHeaderColor',   ...
                                      'borderRadius', 'borderWidth', 'borderColor', ...
                                      'textAlign', 'paddingTop', 'fontFamily', 'fontStyle', 'fontWeight', 'fontSize', 'color'}, varargin{:});
        otherwise
            error('ccTools does not cover the customization of ''%s'' class properties.', class(comp))
    end


    % JS
    pause(.001)
    for ii = 1:numel(propStruct)
        sendEventToHTMLSource(jsBackDoor, "compCustomization", struct("Class",    class(comp),         ...
                                                                      "DataTag",  compTag,             ...
                                                                      "Property", propStruct(ii).name, ...
                                                                      "Value",    propStruct(ii).value));
    end
end


%-------------------------------------------------------------------------%
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
            case 'transparentHeader';     addParameter(p, 'transparentHeader',     d, @(x) ccTools.validators.mustBeColor(x, 'all'))

            % Border
            case 'borderRadius';          addParameter(p, 'borderRadius',          d, @(x) ccTools.validators.mustBeCSSProperty(x, 'border-radius'))
            case 'borderWidth';           addParameter(p, 'borderWidth',           d, @(x) ccTools.validators.mustBeCSSProperty(x, 'border-width'))
            case 'borderColor';           addParameter(p, 'borderColor',           d, @(x) ccTools.validators.mustBeColor(x, 'all'))

            % Font
            case 'textAlign';             addParameter(p, 'textAlign',             d, @(x) ccTools.validators.mustBeCSSProperty(x, 'text-align'))
            case 'paddingTop';            addParameter(p, 'paddingTop',            d, @(x) ccTools.validators.mustBeCSSProperty(x, 'paddingTop'))
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