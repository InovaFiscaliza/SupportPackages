function varargout = OperationSystem(operationType)

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

        case 'executionExt'
            if ispc
                executionExt = 'exe';
            elseif ismac
                executionExt = 'app';
            elseif isunix
                executionExt = 'sh';
            end
            varargout{1} = executionExt;

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
    end

end