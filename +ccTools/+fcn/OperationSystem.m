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
                [~, OS] = system('lsb_release -d');
            end
            varargout{1} = strtrim(OS);

        case 'userPath'
            if ispc
                userPaths = {fullfile(getenv('USERPROFILE'), 'Documents'), fullfile(getenv('USERPROFILE'), 'Downloads')};
            else
                userPaths = {fullfile(getenv('HOME'), 'Documents'), fullfile(getenv('HOME'), 'Downloads')};
            end
            varargout{1} = userPaths;

        case 'executionExt'
            if ispc
                executionExt = '.exe';
            elseif ismac
                executionExt = '.app';
            elseif isunix
                executionExt = '';
            end
            varargout{1} = executionExt;
    end

end