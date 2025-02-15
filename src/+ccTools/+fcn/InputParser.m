function propStruct = InputParser(propList, varargin)    
    p = inputParser;
    d = struct('winWidth',              '302px',     ...
               'winHeight',             '162px',     ...
               'winBackgroundColor',     '#f5f5f5',  ...
               'iconFullFile',           '',         ...
               'iconWidth',             '35px',      ...
               'iconHeight',            '35px',      ...
               'msgFontFamily',         'Helvetica', ...
               'msgFontSize',           '12px',      ...
               'msgFontColor',          '#212121',   ...
               'msgTextAlign',          'justify',   ...
               'buttonWidth',           '90px',      ...
               'buttonHeight',          '24px',      ...
               'buttonBackgroundColor', '#f5f5f5',   ...
               'buttonBorderRadius',    '5px',       ...
               'buttonBorderWidth',     '1px',       ...
               'buttonBorderColor',     '#7d7d7d',   ...
               'buttonFontFamily',      'Helvetica', ...
               'buttonFontSize',        '12px',      ...
               'buttonFontColor',       '#212121',   ...
               'buttonTextAlign',       'center',    ...
               'size',                  '40px',      ...
               'color',                 '#d95319');

    for ii = 1:numel(propList)
        switch(propList{ii})
            % Message Box
            case 'winWidth';              addParameter(p, 'winWidth',              d.winWidth,              @(x) ccTools.validators.mustBeCSSProperty(x, 'width'))
            case 'winHeight';             addParameter(p, 'winHeight',             d.winHeight,             @(x) ccTools.validators.mustBeCSSProperty(x, 'height'))
            case 'winBackgroundColor';    addParameter(p, 'winBackgroundColor',    d.winBackgroundColor,    @(x) ccTools.validators.mustBeColor(x, 'all'))
                
            case 'iconFullFile';          addParameter(p, 'iconFullFile',          d.iconFullFile,          @(x) ccTools.validators.mustBeScalarText(x))
            case 'iconWidth';             addParameter(p, 'iconWidth',             d.iconWidth,             @(x) ccTools.validators.mustBeCSSProperty(x, 'width'))
            case 'iconHeight';            addParameter(p, 'iconHeight',            d.iconHeight,            @(x) ccTools.validators.mustBeCSSProperty(x, 'height'))
            
            case 'msgFontFamily';         addParameter(p, 'msgFontFamily',         d.msgFontFamily,         @(x) ccTools.validators.mustBeCSSProperty(x, 'font-family'))
            case 'msgFontSize';           addParameter(p, 'msgFontSize',           d.msgFontSize,           @(x) ccTools.validators.mustBeCSSProperty(x, 'font-size'))
            case 'msgFontColor';          addParameter(p, 'msgFontColor',          d.msgFontColor,          @(x) ccTools.validators.mustBeColor(x, 'all'))
            case 'msgTextAlign';          addParameter(p, 'msgTextAlign',          d.msgTextAlign,          @(x) ccTools.validators.mustBeCSSProperty(x, 'text-align'))

            case 'buttonWidth';           addParameter(p, 'buttonWidth',           d.buttonWidth,           @(x) ccTools.validators.mustBeCSSProperty(x, 'width'))
            case 'buttonHeight';          addParameter(p, 'buttonHeight',          d.buttonHeight,          @(x) ccTools.validators.mustBeCSSProperty(x, 'height'))
            case 'buttonBackgroundColor'; addParameter(p, 'buttonBackgroundColor', d.buttonBackgroundColor, @(x) ccTools.validators.mustBeColor(x, 'all'))            
            case 'buttonBorderRadius';    addParameter(p, 'buttonBorderRadius',    d.buttonBorderRadius,    @(x) ccTools.validators.mustBeCSSProperty(x, 'border-radius'))
            case 'buttonBorderWidth';     addParameter(p, 'buttonBorderWidth',     d.buttonBorderWidth,     @(x) ccTools.validators.mustBeCSSProperty(x, 'border-width'))
            case 'buttonBorderColor';     addParameter(p, 'buttonBorderColor',     d.buttonBorderColor,     @(x) ccTools.validators.mustBeColor(x, 'all'))
            case 'buttonFontFamily';      addParameter(p, 'buttonFontFamily',      d.buttonFontFamily,      @(x) ccTools.validators.mustBeCSSProperty(x, 'font-family'))
            case 'buttonFontSize';        addParameter(p, 'buttonFontSize',        d.buttonFontSize,        @(x) ccTools.validators.mustBeCSSProperty(x, 'font-size'))
            case 'buttonFontColor';       addParameter(p, 'buttonFontColor',       d.buttonFontColor,       @(x) ccTools.validators.mustBeColor(x, 'all'))
            case 'buttonTextAlign';       addParameter(p, 'buttonTextAlign',       d.buttonTextAlign,       @(x) ccTools.validators.mustBeCSSProperty(x, 'text-align'))

            % Progress Dialog
            case 'size';                  addParameter(p, 'size',                  d.size,                  @(x) ccTools.validators.mustBeCSSProperty(x, 'size'))
            case 'color';                 addParameter(p, 'color',                 d.color,                 @(x) ccTools.validators.mustBeColor(x, 'all'))
        end
    end
            
    parse(p, varargin{:});

    propStruct = struct;
    for ll = 1:numel(p.Parameters)
        propValue = p.Results.(p.Parameters{ll});

        if ismember(p.Parameters{ll}, {'winBackgroundColor', 'msgFontColor', 'buttonBackgroundColor', 'buttonBorderColor', 'buttonFontColor', 'color'})
            if isnumeric(p.Results.(p.Parameters{ll}))
                propValue = ccTools.fcn.rgb2hex(propValue);
            else
                propValue = char(propValue);
            end
        end

        propStruct.(p.Parameters{ll}) = propValue;
    end
end