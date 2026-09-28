classdef DownloadHistoryStore < handle

    properties (SetAccess = private)
        FilePath (1,:) char
        Entries
        WasCorrupt (1,1) logical = false
    end

    methods
        function obj = DownloadHistoryStore(filePath)
            arguments
                filePath (1,:) char {mustBeNonempty}
            end

            obj.FilePath = absolutePath(filePath);
            obj.Entries = emptyEntries();
            if ~isfile(obj.FilePath)
                return
            end

            try
                document = jsondecode(fileread(obj.FilePath));
                if ~isstruct(document) || ~isscalar(document) || ...
                        ~isfield(document, 'SchemaVersion') || ...
                        document.SchemaVersion ~= 1 || ~isfield(document, 'Entries')
                    error('download:DownloadHistoryStore:invalidSchema', ...
                          'The download history schema is not supported.')
                end
                obj.Entries = normalizeEntries(document.Entries);
            catch
                obj.WasCorrupt = true;
                quarantineFile(obj.FilePath);
            end
        end

        function entries = getEntries(obj)
            entries = obj.Entries;
        end

        function entry = getEntry(obj, entryID)
            entry = [];
            if isempty(obj.Entries)
                return
            end
            entryIndex = find(strcmp({obj.Entries.EntryID}, entryID), 1);
            if ~isempty(entryIndex)
                entry = obj.Entries(entryIndex);
            end
        end

        function removed = removeEntry(obj, entryID)
            entryIndex = find(strcmp({obj.Entries.EntryID}, entryID), 1);
            removed = ~isempty(entryIndex);
            if ~removed
                return
            end
            previousEntries = obj.Entries;
            obj.Entries(entryIndex) = [];
            try
                obj.writeAtomic();
            catch exception
                obj.Entries = previousEntries;
                rethrow(exception)
            end
        end

        function upsert(obj, entry)
            entry = normalizeEntries(entry);
            if numel(entry) ~= 1
                error('download:DownloadHistoryStore:invalidEntry', ...
                      'Exactly one history entry must be written at a time.')
            end
            previousEntries = obj.Entries;
            if isempty(obj.Entries)
                obj.Entries = entry;
            else
                entryIndex = find(strcmp({obj.Entries.EntryID}, entry.EntryID), 1);
                if isempty(entryIndex)
                    obj.Entries(end+1) = entry;
                else
                    obj.Entries(entryIndex) = entry;
                end
            end
            try
                obj.writeAtomic();
            catch exception
                obj.Entries = previousEntries;
                rethrow(exception)
            end
        end

        function replace(obj, entries)
            entries = normalizeEntries(entries);
            previousEntries = obj.Entries;
            obj.Entries = entries;
            try
                obj.writeAtomic();
            catch exception
                obj.Entries = previousEntries;
                rethrow(exception)
            end
        end
    end

    methods (Access = private)
        function writeAtomic(obj)
            folderPath = fileparts(obj.FilePath);
            if isempty(folderPath)
                folderPath = pwd;
            end
            if ~isfolder(folderPath)
                [created, message] = mkdir(folderPath);
                if ~created && ~isfolder(folderPath)
                    error('download:DownloadHistoryStore:folderUnavailable', '%s', message)
                end
            end

            document = struct('SchemaVersion', 1, 'Entries', obj.Entries);
            jsonText = jsonencode(document, 'PrettyPrint', true);
            temporaryPath = [tempname(folderPath), '.tmp'];
            fileID = fopen(temporaryPath, 'wb');
            if fileID == -1
                error('download:DownloadHistoryStore:fileOpenFailed', ...
                      'Could not open a temporary history file in "%s".', folderPath)
            end
            cleanup = onCleanup(@() cleanupTemporaryWrite(fileID, temporaryPath)); %#ok<NASGU>
            bytes = unicode2native(jsonText, 'UTF-8');
            bytesWritten = fwrite(fileID, bytes, 'uint8');
            if bytesWritten ~= numel(bytes)
                error('download:DownloadHistoryStore:fileWriteFailed', ...
                      'Could not write the complete download history.')
            end
            fclose(fileID);

            [moved, message] = movefile(temporaryPath, obj.FilePath, 'f');
            if ~moved
                error('download:DownloadHistoryStore:replaceFailed', ...
                      'Could not replace the download history file: %s', message)
            end
        end
    end
end


function entries = normalizeEntries(inputEntries)
entries = emptyEntries();
if isempty(inputEntries)
    return
end
if ~isstruct(inputEntries)
    error('download:DownloadHistoryStore:invalidEntries', ...
          'History entries must be a struct array.')
end

requiredFields = {'EntryID', 'LogicalFileID', 'TaskID', 'SourceURL', ...
                  'TargetPath', 'TemporaryPath', 'ChunkPath', 'BackupPath', ...
                  'TempFolder', 'StartedAt', 'CompletedAt', 'UpdatedAt', ...
                  'LifecycleState', 'DownloadedBytes', 'MeasuredSpeed', ...
                  'RateSource', 'ErrorMessages', 'AttemptedTimestamps', ...
                  'isAvailable'};
inputFields = fieldnames(inputEntries);
if ~ismember('AttemptedTimestamps', inputFields)
    for entryIndex = 1:numel(inputEntries)
        inputEntries(entryIndex).AttemptedTimestamps = {};
    end
    inputFields = fieldnames(inputEntries);
end
for fieldIndex = 1:numel(requiredFields)
    if ~ismember(requiredFields{fieldIndex}, inputFields)
        error('download:DownloadHistoryStore:invalidEntries', ...
              'A history entry is missing the %s field.', requiredFields{fieldIndex})
    end
end

entries = repmat(emptyEntry(), size(inputEntries));
for entryIndex = 1:numel(inputEntries)
    source = inputEntries(entryIndex);
    entry = emptyEntry();
    for fieldIndex = 1:numel(requiredFields)
        fieldName = requiredFields{fieldIndex};
        entry.(fieldName) = source.(fieldName);
    end
    stringFields = {'EntryID', 'LogicalFileID', 'TaskID', 'SourceURL', ...
                    'TargetPath', 'TemporaryPath', 'ChunkPath', 'BackupPath', ...
                    'TempFolder', 'StartedAt', 'CompletedAt', 'UpdatedAt', ...
                    'LifecycleState', 'RateSource'};
    for fieldIndex = 1:numel(stringFields)
        entry.(stringFields{fieldIndex}) = char(entry.(stringFields{fieldIndex}));
    end
    if ~isnumeric(entry.DownloadedBytes) || ~isscalar(entry.DownloadedBytes) || ...
            ~isfinite(entry.DownloadedBytes) || entry.DownloadedBytes < 0
        error('download:DownloadHistoryStore:invalidEntries', ...
              'DownloadedBytes must be a finite nonnegative scalar.')
    end
    if ~isempty(entry.MeasuredSpeed) && ...
            (~isnumeric(entry.MeasuredSpeed) || ~isscalar(entry.MeasuredSpeed) || ...
             ~isfinite(entry.MeasuredSpeed) || entry.MeasuredSpeed < 0)
        error('download:DownloadHistoryStore:invalidEntries', ...
              'MeasuredSpeed must be empty or a finite nonnegative scalar.')
    end
    if ischar(entry.ErrorMessages)
        if isempty(entry.ErrorMessages)
            entry.ErrorMessages = {};
        else
            entry.ErrorMessages = {entry.ErrorMessages};
        end
    elseif isempty(entry.ErrorMessages)
        entry.ErrorMessages = {};
    elseif isstring(entry.ErrorMessages)
        entry.ErrorMessages = cellstr(entry.ErrorMessages);
    elseif ~iscell(entry.ErrorMessages)
        error('download:DownloadHistoryStore:invalidEntries', ...
              'ErrorMessages must be a string array.')
    end
    if ischar(entry.AttemptedTimestamps)
        entry.AttemptedTimestamps = {entry.AttemptedTimestamps};
    elseif isstring(entry.AttemptedTimestamps)
        entry.AttemptedTimestamps = cellstr(entry.AttemptedTimestamps);
    elseif isempty(entry.AttemptedTimestamps)
        entry.AttemptedTimestamps = {};
    elseif ~iscell(entry.AttemptedTimestamps)
        error('download:DownloadHistoryStore:invalidEntries', ...
              'AttemptedTimestamps must be a string array.')
    end
    entry.AttemptedTimestamps = cellfun(@char, entry.AttemptedTimestamps, ...
                                        'UniformOutput', false);
    if ~islogical(entry.isAvailable) || ~isscalar(entry.isAvailable)
        error('download:DownloadHistoryStore:invalidEntries', ...
              'isAvailable must be a logical scalar.')
    end
    entries(entryIndex) = entry;
end
end

function entry = emptyEntry()
entry = struct('EntryID', '', ...
                'LogicalFileID', '', ...
                'TaskID', '', ...
                'SourceURL', '', ...
                'TargetPath', '', ...
                'TemporaryPath', '', ...
                'ChunkPath', '', ...
                'BackupPath', '', ...
                'TempFolder', '', ...
                'StartedAt', '', ...
                'CompletedAt', '', ...
                'UpdatedAt', '', ...
                'LifecycleState', '', ...
                'DownloadedBytes', 0, ...
                'MeasuredSpeed', [], ...
                'RateSource', 'none', ...
                'ErrorMessages', {{}}, ...
                'AttemptedTimestamps', {{}}, ...
                'isAvailable', false);
end

function entries = emptyEntries()
entries = repmat(emptyEntry(), 0, 1);
end

function value = absolutePath(pathValue)
try
    fileObject = java.io.File(pathValue);
    value = char(fileObject.getCanonicalPath());
catch
    if isAbsolutePath(pathValue)
        value = pathValue;
    else
        value = fullfile(pwd, pathValue);
    end
end
end

function tf = isAbsolutePath(pathValue)
tf = startsWith(pathValue, filesep) || startsWith(pathValue, '\\') || ...
     (numel(pathValue) >= 2 && pathValue(2) == ':');
end

function quarantineFile(filePath)
folderPath = fileparts(filePath);
if isempty(folderPath)
    folderPath = pwd;
end
quarantinePath = [tempname(folderPath), '.corrupt'];
movefile(filePath, quarantinePath);
end

function cleanupTemporaryWrite(fileID, temporaryPath)
try
    fclose(fileID);
catch
end
if isfile(temporaryPath)
    try
        delete(temporaryPath)
    catch
    end
end
end