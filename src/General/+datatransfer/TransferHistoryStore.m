classdef TransferHistoryStore < handle
    % TRANSFERHISTORYSTORE Own SchemaVersion 1 JSON history with atomic writes, legacy-shape deletion, and quarantine of other malformed files.

    properties (SetAccess = private)
        FilePath (1,:) char
        Entries
        WasCorrupt (1,1) logical = false
    end

    methods
        function obj = TransferHistoryStore(filePath)
            % TRANSFERHISTORYSTORE Load or initialize the version-1 history at filePath.
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
                if isstruct(document) && isscalar(document) && ...
                    isfield(document, 'Entries') && isstruct(document.Entries)
                    inputFields = fieldnames(document.Entries);
                    legacyFields = {'SourceURL', 'TargetPath', 'DownloadedBytes'};
                    hasLegacyFields = any(ismember(legacyFields, inputFields));
                    hasTransferIdentity = any(ismember( ...
                        {'Direction', 'URL', 'LocalPath'}, inputFields));
                    hasOldShape = ~hasTransferIdentity && all(ismember( ...
                        {'EntryID', 'LogicalFileID', 'TaskID', 'TemporaryPath', ...
                         'TempFolder', 'LifecycleState'}, inputFields));
                    if hasLegacyFields || hasOldShape
                        obj.WasCorrupt = true;
                        deleteFailed = false;
                        try
                            delete(obj.FilePath)
                        catch
                            deleteFailed = true;
                        end
                        if ~deleteFailed && isfile(obj.FilePath)
                            deleteFailed = true;
                        end
                        if deleteFailed
                            try
                                warning( ...
                                    'datatransfer:TransferHistoryStore:legacyDeleteFailed', ...
                                    'Não foi possível excluir o histórico legado "%s".', ...
                                    obj.FilePath)
                            catch
                            end
                        end
                        return
                    end
                end
                if ~isstruct(document) || ~isscalar(document) || ...
                        ~isfield(document, 'SchemaVersion') || ...
                        document.SchemaVersion ~= 1 || ~isfield(document, 'Entries')
                    error('datatransfer:TransferHistoryStore:invalidSchema', ...
                          'The transfer history schema is not supported.')
                end
                obj.Entries = normalizeEntries(document.Entries);
            catch
                obj.WasCorrupt = true;
                quarantineFile(obj.FilePath);
            end
        end

        function entries = getEntries(obj)
            % GETENTRIES Return the normalized history entries.
            entries = obj.Entries;
        end

        function entry = getEntry(obj, entryID)
            % GETENTRY Return the entry matching entryID, or empty when absent.
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
            % REMOVEENTRY Remove entryID and atomically persist the history.
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
            % UPSERT Insert or replace one normalized history entry.
            entry = normalizeEntries(entry);
            if numel(entry) ~= 1
                error('datatransfer:TransferHistoryStore:invalidEntry', ...
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
            % REPLACE Replace all normalized history entries.
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
                    error('datatransfer:TransferHistoryStore:folderUnavailable', '%s', message)
                end
            end

            document = struct('SchemaVersion', 1, 'Entries', obj.Entries);
            jsonText = jsonencode(document, 'PrettyPrint', true);
            temporaryPath = [tempname(folderPath), '.tmp'];
            fileID = fopen(temporaryPath, 'wb');
            if fileID == -1
                error('datatransfer:TransferHistoryStore:fileOpenFailed', ...
                      'Could not open a temporary history file in "%s".', folderPath)
            end
            cleanup = onCleanup(@() cleanupTemporaryWrite(fileID, temporaryPath)); %#ok<NASGU>
            bytes = unicode2native(jsonText, 'UTF-8');
            bytesWritten = fwrite(fileID, bytes, 'uint8');
            if bytesWritten ~= numel(bytes)
                error('datatransfer:TransferHistoryStore:fileWriteFailed', ...
                      'Could not write the complete transfer history.')
            end
            fclose(fileID);

            [moved, message] = movefile(temporaryPath, obj.FilePath, 'f');
            if ~moved
                error('datatransfer:TransferHistoryStore:replaceFailed', ...
                      'Could not replace the transfer history file: %s', message)
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
    error('datatransfer:TransferHistoryStore:invalidEntries', ...
          'History entries must be a struct array.')
end

requiredFields = {'EntryID', 'Direction', 'LogicalFileID', 'TaskID', ...
                  'URL', 'LocalPath', 'TemporaryPath', ...
                  'ChunkPath', 'BackupPath', 'TempFolder', 'StartedAt', ...
                  'CompletedAt', 'UpdatedAt', 'LifecycleState', ...
                  'TransferredBytes', 'MeasuredSpeed', 'RateSource', ...
                  'ErrorMessages', 'AttemptedTimestamps', 'isAvailable', ...
                  'Protocol', 'UploadURL', 'UploadOffset', 'LocalBytes', ...
                  'LocalModifiedAt', 'Response'};
inputFields = fieldnames(inputEntries);
for fieldIndex = 1:numel(requiredFields)
    if ~ismember(requiredFields{fieldIndex}, inputFields)
        error('datatransfer:TransferHistoryStore:invalidEntries', ...
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
    stringFields = {'EntryID', 'Direction', 'LogicalFileID', 'TaskID', 'URL', ...
                    'LocalPath', 'TemporaryPath', 'ChunkPath', 'BackupPath', ...
                    'TempFolder', 'StartedAt', 'CompletedAt', 'UpdatedAt', ...
                    'LifecycleState', 'RateSource', 'Protocol', 'UploadURL', ...
                    'LocalModifiedAt'};
    for fieldIndex = 1:numel(stringFields)
        fieldName = stringFields{fieldIndex};
        fieldValue = entry.(fieldName);
        if isstring(fieldValue) && isscalar(fieldValue)
            fieldValue = char(fieldValue);
        end
        if ~ischar(fieldValue) || (~isrow(fieldValue) && ~isempty(fieldValue))
            error('datatransfer:TransferHistoryStore:invalidEntries', ...
                  '%s must be a character vector or scalar string.', fieldName)
        end
        entry.(fieldName) = fieldValue;
    end
    if ~isempty(entry.LocalPath)
        entry.LocalPath = absolutePath(entry.LocalPath);
    end
    if ~ismember(entry.Direction, {'download', 'upload'})
        error('datatransfer:TransferHistoryStore:invalidEntries', ...
              'Direction must be download or upload.')
    end
    if ~isnumeric(entry.TransferredBytes) || ~isscalar(entry.TransferredBytes) || ...
            ~isfinite(entry.TransferredBytes) || entry.TransferredBytes < 0
        error('datatransfer:TransferHistoryStore:invalidEntries', ...
              'TransferredBytes must be a finite nonnegative scalar.')
    end
    entry.TransferredBytes = double(entry.TransferredBytes);
    if ~isempty(entry.LocalBytes)
        if ~isnumeric(entry.LocalBytes) || ~isscalar(entry.LocalBytes) || ...
                ~isfinite(entry.LocalBytes) || entry.LocalBytes < 0
            error('datatransfer:TransferHistoryStore:invalidEntries', ...
                  'LocalBytes must be empty or a finite nonnegative scalar.')
        end
        entry.LocalBytes = double(entry.LocalBytes);
    end
    if ~isnumeric(entry.UploadOffset) || ~isscalar(entry.UploadOffset) || ...
            ~isfinite(entry.UploadOffset) || entry.UploadOffset < 0
        error('datatransfer:TransferHistoryStore:invalidEntries', ...
              'UploadOffset must be a finite nonnegative scalar.')
    end
    entry.UploadOffset = double(entry.UploadOffset);
    if ~isempty(entry.MeasuredSpeed) && ...
            (~isnumeric(entry.MeasuredSpeed) || ~isscalar(entry.MeasuredSpeed) || ...
             ~isfinite(entry.MeasuredSpeed) || entry.MeasuredSpeed < 0)
        error('datatransfer:TransferHistoryStore:invalidEntries', ...
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
        error('datatransfer:TransferHistoryStore:invalidEntries', ...
              'ErrorMessages must be a string array.')
    end
    if ischar(entry.AttemptedTimestamps)
        entry.AttemptedTimestamps = {entry.AttemptedTimestamps};
    elseif isstring(entry.AttemptedTimestamps)
        entry.AttemptedTimestamps = cellstr(entry.AttemptedTimestamps);
    elseif isempty(entry.AttemptedTimestamps)
        entry.AttemptedTimestamps = {};
    elseif ~iscell(entry.AttemptedTimestamps)
        error('datatransfer:TransferHistoryStore:invalidEntries', ...
              'AttemptedTimestamps must be a string array.')
    end
    entry.AttemptedTimestamps = cellfun(@char, entry.AttemptedTimestamps, ...
                                        'UniformOutput', false);
    if ~islogical(entry.isAvailable) || ~isscalar(entry.isAvailable)
        error('datatransfer:TransferHistoryStore:invalidEntries', ...
              'isAvailable must be a logical scalar.')
    end
    if ~isempty(entry.Response)
        responseFields = {'FileName', 'CompletedAt', 'Success', 'StatusCode', ...
                          'Message', 'OutcomeUncertain'};
        if ~isstruct(entry.Response) || ~isscalar(entry.Response) || ...
                numel(fieldnames(entry.Response)) ~= numel(responseFields) || ...
                ~all(ismember(responseFields, fieldnames(entry.Response)))
            error('datatransfer:TransferHistoryStore:invalidEntries', ...
                  'Response must be empty or a scalar summary struct.')
        end
        for responseFieldIndex = [1, 2, 5]
            fieldName = responseFields{responseFieldIndex};
            fieldValue = entry.Response.(fieldName);
            if isstring(fieldValue) && isscalar(fieldValue)
                fieldValue = char(fieldValue);
            end
            if ~ischar(fieldValue) || (~isrow(fieldValue) && ~isempty(fieldValue))
                error('datatransfer:TransferHistoryStore:invalidEntries', ...
                      'Response.%s must be a character vector or scalar string.', ...
                      fieldName)
            end
            entry.Response.(fieldName) = fieldValue;
        end
        if ~islogical(entry.Response.Success) || ~isscalar(entry.Response.Success) || ...
                ~islogical(entry.Response.OutcomeUncertain) || ...
                ~isscalar(entry.Response.OutcomeUncertain)
            error('datatransfer:TransferHistoryStore:invalidEntries', ...
                  'Response success and uncertainty values must be logical scalars.')
        end
        if ~isempty(entry.Response.StatusCode) && ...
                (~isnumeric(entry.Response.StatusCode) || ...
                 ~isscalar(entry.Response.StatusCode) || ...
                 ~isfinite(entry.Response.StatusCode))
            error('datatransfer:TransferHistoryStore:invalidEntries', ...
                  'Response.StatusCode must be empty or a finite scalar.')
        end
    end
    entries(entryIndex) = entry;
end
end

function entry = emptyEntry()
entry = struct('EntryID', '', ...
                'Direction', '', ...
                'LogicalFileID', '', ...
                'TaskID', '', ...
                'URL', '', ...
                'LocalPath', '', ...
                'TemporaryPath', '', ...
                'ChunkPath', '', ...
                'BackupPath', '', ...
                'TempFolder', '', ...
                'StartedAt', '', ...
                'CompletedAt', '', ...
                'UpdatedAt', '', ...
                'LifecycleState', '', ...
                'TransferredBytes', 0, ...
                'MeasuredSpeed', [], ...
                'RateSource', 'none', ...
                'ErrorMessages', {{}}, ...
                'AttemptedTimestamps', {{}}, ...
                'isAvailable', false, ...
                'Protocol', '', ...
                'UploadURL', '', ...
                'UploadOffset', 0, ...
                'LocalBytes', [], ...
                'LocalModifiedAt', '', ...
                'Response', []);
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