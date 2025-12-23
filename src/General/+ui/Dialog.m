function varargout = Dialog(hFigure, type, msg, varargin)
    arguments
        hFigure matlab.ui.Figure
        type    {mustBeMember(type, {'error', 'warning', 'info', 'success', 'none', 'progressdlg', 'uiconfirm', 'uigetfile', 'uiputfile'})}
        msg     {mustBeTextScalar} = ''
    end

    arguments (Repeating)
        varargin
    end
    
    if ~isempty(msg)
        msg = textFormatGUI.HTMLParagraph(msg);
    end

    switch type
        case {'error', 'warning', 'info', 'success', 'none'}
            switch type
                case 'error';   uialert(hFigure, msg, '', 'Interpreter', 'html', 'Icon', 'error',   varargin{:})
                case 'warning'; uialert(hFigure, msg, '', 'Interpreter', 'html', 'Icon', 'warning', varargin{:})
                case 'info';    uialert(hFigure, msg, '', 'Interpreter', 'html', 'Icon', 'info',    varargin{:})
                case 'success'; uialert(hFigure, msg, '', 'Interpreter', 'html', 'Icon', 'success', varargin{:})
                case 'none';    uialert(hFigure, msg, '', 'Interpreter', 'html', 'Icon', '',        varargin{:})
            end
            varargout = {[]};
            beep
            
        case 'progressdlg'
            dlg = uiprogressdlg(hFigure, 'Indeterminate', 'on', 'Interpreter', 'html', 'Message', msg, varargin{:});
            varargout{1} = dlg;

        case 'uiconfirm'
            % O uiconfirm trava a execução, aguardando retorno do
            % usuário. Diferente do uialert, por exemplo, em que
            % continua a execução. A validação abaixo garante a
            % emulação do uiconfirm como uialert, com a vantagem de
            % travar a execução, caso seja esse o objetivo.
            if isscalar(varargin{1})
                Icon = 'warning';
            else
                Icon = 'question';
            end

            userSelection = uiconfirm(hFigure, msg, '', 'Options', varargin{1}, 'DefaultOption', varargin{2}, 'CancelOption', varargin{3}, 'Interpreter', 'html', 'Icon', Icon);
            varargout{1} = userSelection;

        case {'uigetfile', 'uiputfile'}
            switch type
                case 'uigetfile'
                    fileFormats       = varargin{1};
                    lastVisitedFolder = varargin{2};
                    otherParameters   = {};
                    if nargin == 6
                        otherParameters = varargin{3};
                    end
                    [fileName, fileFolder] = uigetfile(fileFormats, '', lastVisitedFolder, otherParameters{:});

                otherwise
                    nameFormatMap   = varargin{1};
                    defaultFilename = varargin{2};
                    [fileName, fileFolder] = uiputfile(nameFormatMap, '', defaultFilename);
            end
            
            executionMode = appEngine.util.ExecutionMode(hFigure);
            if ~strcmp(executionMode, 'webApp')
                figure(hFigure)
            end

            if isequal(fileName, 0)
                varargout = {[], [], [], []};
                return
            end

            fileFullPath    = fullfile(fileFolder, fileName);
            [~, ~, fileExt] = fileparts(fileName);

            varargout = {fileFullPath, fileFolder, lower(fileExt), fileName};
    end
end