function MessageBox(comp, msg, varargin)

    arguments
        comp {ccTools.validators.mustBeAppContainer}
        msg  {ccTools.validators.mustBeScalarText}
    end

    arguments (Repeating)
        varargin
    end
    
    % ccTools.fcn.compatibilityWarning('MessageBox')

    % nargin validation
    if mod(nargin-2, 2)
        error('Name-value parameters must be in pairs.')
    end

    warning('off', 'MATLAB:structOnObject')
    warning('off', 'MATLAB:ui:javaframe:PropertyToBeRemoved')
    
    % main variables
    pathToMFILE = fileparts(mfilename('fullpath'));
    [webWin, compTag] = ccTools.fcn.componentInfo(comp);

    % MessageBox model
    p = ccTools.fcn.InputParser({'winWidth', 'winHeight', 'winBackgroundColor', ...
        'iconFullFile', 'iconWidth', 'iconHeight',                              ...
        'msgFontFamily', 'msgFontSize', 'msgFontColor', 'msgTextAlign',         ...
        'buttonWidth', 'buttonHeight', 'buttonBackgroundColor', 'buttonBorderRadius', 'buttonBorderWidth', 'buttonBorderColor', 'buttonFontFamily', 'buttonFontSize', 'buttonFontColor', 'buttonTextAlign'}, varargin{:});

    dataTag      = char(matlab.lang.internal.uuid());
    uniqueSuffix = datestr(now, '_THHMMSSFFF');

    [imgFormat, imgBase64] = ccTools.fcn.img2base64(p.iconFullFile, 'ccTools.MessageBox');
    [winWidth,  winHeight] = ccTools.fcn.winSize(comp, msg, p);
    
    jsCodeOnCreation = sprintf(replace(fileread(fullfile(pathToMFILE, 'css&js', 'MessageBox.js')), '<uniqueSuffix>', uniqueSuffix),                                         ...
        dataTag, dataTag, dataTag, winWidth, winHeight, p.winBackgroundColor, p.iconWidth, p.buttonWidth, p.iconHeight, p.buttonHeight, imgFormat, imgBase64,               ...
        p.winBackgroundColor, p.msgFontFamily, p.msgFontSize, p.msgFontColor, p.msgTextAlign, replace(msg, newline, '<br>'), p.buttonBackgroundColor, p.buttonBorderRadius, ...
        p.buttonBorderWidth, p.buttonBorderColor, p.buttonFontFamily, p.buttonFontSize, p.buttonFontColor, p.buttonTextAlign);

    jsCodeOnCleanup = '';

    % JS
    pause(.001)
    try
        ccTools.class.modalDialog('MessageBox', webWin, compTag, dataTag, jsCodeOnCreation, jsCodeOnCleanup, pathToMFILE);
    catch
    end
end