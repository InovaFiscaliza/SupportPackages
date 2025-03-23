function varargout = OperationSystem(operationType, varargin)

    arguments
        operationType char {mustBeMember(operationType, {'platform',                   ...
                                                         'ver',                        ...
                                                         'userPath',                   ...
                                                         'programData',                ...
                                                         'desktopStandaloneAppFolder', ...
                                                         'computerName',               ...
                                                         'userName',                   ...
                                                         'pythonExecutable',           ...
                                                         'openFile',                   ...
                                                         'terminateProcessImmediately'})}
    end

    arguments (Repeating)
        varargin
    end

    if ~ispc && ~ismac && ~isunix
        error('Platform not supported')
    end

    switch operationType
        case 'platform'
            varargout{1} = computer('arch');

        case 'ver'
            if ispc
                [~, OS] = system('ver');
            elseif ismac
                [~, OS] = system('sw_vers -productVersion');
            elseif isunix
                [status, OS] = system('lsb_release -d');
                if status
                    [~, OS] = system('uname -r');
                end
            end
            varargout{1} = strtrim(OS);

        case 'userPath'
            if ispc
                userPaths = {fullfile(getenv('USERPROFILE'), 'Documents'), ...
                             fullfile(getenv('USERPROFILE'), 'Downloads')};
            else
                userPaths = {fullfile(getenv('HOME'), 'Documents'),  ...
                             fullfile(getenv('HOME'), 'Documentos'), ...
                             fullfile(getenv('HOME'), 'Downloads')};
            end
            userPaths(~isfolder(userPaths)) = [];

            varargout{1} = userPaths;

        case 'programData'
            if ispc
                programDataFolder = getenv('PROGRAMDATA');
            elseif ismac
                programDataFolder = '/Users/Shared';
            else % isunix
                programDataFolder = '/etc';
            end
            varargout{1} = programDataFolder;

        case 'desktopStandaloneAppFolder'
            status  = false;
            appName = varargin{1};
            if ispc
                [~, result]     = system('path');    
                executionFolder = char(regexpi(result, 'Path=(.*?);', 'tokens', 'once'));
                if isfile(fullfile(executionFolder, [appName '.exe']))
                    status = true;
                end
            elseif ismac
                executionFolder = fileparts(fileparts(fileparts(fileparts(ctfroot))));
                if isfolder(fullfile(executionFolder, [appName '.app']))
                    status = true;
                end
            else
                % !! PENDENTE !!
                error('Pendente análise de como as distribuições Linux descompactam o arquivo compilado no MATLAB. :(')
            end
            varargout = {status, executionFolder};

        case 'computerName'
            if ispc
                computerName = getenv('COMPUTERNAME');
            else % ismac | isunix
                [~, computerName] = system('hostname');
                computerName = strtrim(computerName);
            end
            varargout{1} = computerName;

        case 'userName'
            if ispc
                userName = getenv('USERNAME');
            else % ismac | isunix
                [~, userName] = system('whoami');
                userName = strtrim(userName);
            end
            varargout{1} = userName; 

        case 'pythonExecutable'
            if ispc
                pyFileName = 'python.exe';
            else % ismac
                pyFileName = 'python3';
            end
            varargout{1} = pyFileName;

        case 'openFile'
            fileName = varargin{1};

            if ispc
                winopen(fileName)
            elseif ismac
                system(sprintf('open "%s" &', fileName));
            else
                system(sprintf('xdg-open "%s" &', fileName));
            end

        case 'terminateProcessImmediately'
            pidMatlab = varargin{1};

            if ispc
                system(sprintf('taskkill /F /PID %d', pidMatlab));
            else
                system(sprintf('kill -9 %d', pidMatlab));
            end
    end
end