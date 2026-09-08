function text = getMessage(messageID, varargin)
%GETMESSAGE Retrieves localized text from the auth message catalog.

    language = currentLanguage();
    catalog = loadCatalog(language);

    if ~isKey(catalog, messageID) && ~strcmp(language, 'en')
        catalog = loadCatalog('en');
    end

    if ~isKey(catalog, messageID)
        error('ws:auth:MessageCatalog:messageNotFound', ...
              'Message "%s" was not found in the auth catalog.', messageID)
    end

    text = sprintf(catalog(messageID), varargin{:});
end


function language = currentLanguage()
    locale = feature('locale');
    language = lower(regexp(locale.messages, '^[A-Za-z]+', 'match', 'once'));

    resourcesFolder = fullfile(fileparts(mfilename('fullpath')), 'resources');
    if isempty(language) || ~isfolder(fullfile(resourcesFolder, language))
        language = 'en';
    end
end


function catalog = loadCatalog(language)
    persistent cachedCatalogs

    if isempty(cachedCatalogs)
        cachedCatalogs = containers.Map('KeyType', 'char', 'ValueType', 'any');
    end
    if isKey(cachedCatalogs, language)
        catalog = cachedCatalogs(language);
        return
    end

    catalogPath = fullfile(fileparts(mfilename('fullpath')), 'resources', language, 'catalog.m');
    if ~isfile(catalogPath)
        error('ws:auth:MessageCatalog:catalogNotFound', ...
              'Message catalog not found: %s', catalogPath)
    end

    catalog = containers.Map('KeyType', 'char', 'ValueType', 'char');
    lines = regexp(fileread(catalogPath), '\r\n|\n|\r', 'split');

    for lineIndex = 1:numel(lines)
        line = lines{lineIndex};
        if isempty(line) || startsWith(strtrim(line), {'%', '#'})
            continue
        end

        separatorIndex = find(line == '=', 1);
        if isempty(separatorIndex)
            error('ws:auth:MessageCatalog:invalidCatalog', ...
                  'Invalid entry at %s:%d.', catalogPath, lineIndex)
        end

        key = line(1:separatorIndex-1);
        catalog(key) = line(separatorIndex+1:end);
    end

    cachedCatalogs(language) = catalog;
end