classdef TransferPanel < handle

    % TRANSFERPANEL Reusable asynchronous transfer queue UI.
    %
    % TransferPanel owns the presentation of multiple transfer
    % rows: the transfer avatar, the popup panel, progress aggregation,
    % pause/resume/cancel controls, conflict decisions, and cleanup of UI and
    % downloader handles. It deliberately does not know how authentication
    % or network transfer is implemented.
    %
    % The caller supplies TransferFactory. The factory receives a normalized
    % request containing the URL, LocalPath, temporary folder, file name,
    % task-scoped staging paths, and conflict actions. It must return an
    % object exposing start, pause, resume, stop, ProgressFcn, CompletedFcn,
    % and ErrorFcn.
    %
    % Temporary files are written below TempPath. Completed files use
    % LocalPath. Existing target and partial-file conflicts are shown
    % in the download row instead of being handled by modal dialogs.

    properties
        executionMode (1,:) char = 'MATLABEnvironment'
        TempPath (1,:) char = ''
        TargetPath (1,:) char = ''
        MaxUploadBytes (1,1) double {mustBePositive} = 200 * 1024^2
        CollisionPolicy (1,:) char = 'askInRow'
        PartialConflictPolicy (1,:) char = 'askInRow'
        CompletedFcn = []
        ErrorFcn = []
    end

    properties (SetAccess = private)
        AvatarHTML
        TransferFactory
        DestinationResolver
        SourceResolver
        Manager
        HistoryFile (1,:) char = ''
    end

    properties (Access = private)
        ParentContainer
        UIFigure
        TransferDialog
        TransferHeader
        TransferTitleLabel
        CloseImage
        TransferContent
        TransferStack
        TransferTasks = {}
        HistoryTasks = {}
        NextHistoryRowID (1,1) double = 0
        TransferOrder = []
        PromotedTaskID (1,1) double = NaN
        DownloadFileNames cell = cell(0, 2)
        AvatarHTMLReady (1,1) logical = false
        AvatarState struct = struct('id', {}, 'rate', {}, 'progress', {}, 'direction', {})
        OriginalWindowButtonDownFcn = []
        IsDeleting (1,1) logical = false
        IsConstructing (1,1) logical = true
        ShowWhenAvatarReady (1,1) logical = false
    end


    methods
        %-----------------------------------------------------------------%
        function obj = TransferPanel(parentContainer, options)
            % TRANSFERPANEL Construct a transfer panel attached to a UI parent.
            %
            % PARENTCONTAINER is a UI container belonging to a figure.
            % TRANSFERFACTORY creates an adapter from the normalized request.
            % Optional name-value arguments configure execution mode,
            % temporary and destination folders, and conflict policies.
            arguments
                parentContainer
                options.TransferFactory (1,1) function_handle
                options.executionMode (1,:) char = 'MATLABEnvironment'
                options.tempPath (1,:) char = tempdir
                options.targetPath (1,:) char = ''
                options.historyFile (1,:) char = ''
                options.MaxUploadBytes (1,1) double {mustBePositive} = 200 * 1024^2
                options.CollisionPolicy (1,:) char = 'askInRow'
                options.PartialConflictPolicy (1,:) char = 'askInRow'
                options.DestinationResolver = []
                options.SourceResolver = []
                options.IncludeSilentTasks (1,1) logical = false
            end

            obj.ParentContainer = parentContainer;
            obj.UIFigure = findFigure(parentContainer);
            if isempty(obj.UIFigure) || ~isvalid(obj.UIFigure)
                error('ui:TransferPanel:invalidParent', ...
                        'O contêiner pai deve pertencer a uma figura válida.')
            end

            obj.TransferFactory = options.TransferFactory;
            if ~isempty(options.DestinationResolver) && ...
                    ~isa(options.DestinationResolver, 'function_handle')
                error('ui:TransferPanel:invalidDestinationResolver', ...
                        'DestinationResolver deve ser um handle de função ou estar vazio.')
            end
            obj.DestinationResolver = options.DestinationResolver;
            if ~isempty(options.SourceResolver) && ...
                    ~isa(options.SourceResolver, 'function_handle')
                error('ui:TransferPanel:invalidSourceResolver', ...
                        'SourceResolver deve ser um handle de função ou estar vazio.')
            end
            obj.SourceResolver = options.SourceResolver;
            obj.executionMode = options.executionMode;
            obj.TempPath = char(options.tempPath);
            obj.TargetPath = char(options.targetPath);
            obj.MaxUploadBytes = options.MaxUploadBytes;
            obj.HistoryFile = char(options.historyFile);
            if isempty(obj.HistoryFile)
                obj.HistoryFile = fullfile(obj.TempPath, 'transfer-history.json');
            end
            obj.CollisionPolicy = options.CollisionPolicy;
            obj.PartialConflictPolicy = options.PartialConflictPolicy;
            obj.Manager = datatransfer.TransferManager(...
                'TransferFactory', obj.TransferFactory, ...
                'HistoryFile', obj.HistoryFile, ...
                'TempFolder', obj.TempPath, ...
                'CollisionPolicy', obj.CollisionPolicy, ...
                'PartialConflictPolicy', obj.PartialConflictPolicy, ...
                'IncludeSilentTasks', options.IncludeSilentTasks);
            obj.Manager.MaxUploadBytes = obj.MaxUploadBytes;
            obj.HistoryFile = obj.Manager.HistoryFile;
            obj.Manager.SnapshotFcn = @(snapshot) obj.onManagerSnapshot(snapshot);
            obj.Manager.TaskReorderedFcn = @(snapshot) obj.onManagerTaskReordered(snapshot);
            obj.Manager.CompletedFcn = @(taskID, info, snapshot) ...
                obj.onManagerCompleted(taskID, info, snapshot);
            obj.Manager.ErrorFcn = @(taskID, exception, snapshot) ...
                obj.onManagerError(taskID, exception, snapshot);

            obj.AvatarHTML = uihtml(parentContainer);
            obj.AvatarHTML.HTMLSource = avatarHTMLPath();
            obj.AvatarHTML.HTMLEventReceivedFcn = @(~, event) obj.onAvatarEvent(event);

            obj.OriginalWindowButtonDownFcn = obj.UIFigure.WindowButtonDownFcn;
            obj.UIFigure.WindowButtonDownFcn = @(source, event) obj.onFigureButtonDown(source, event);
            obj.Manager.restoreInterruptedTransfers();
            obj.IsConstructing = false;
        end

        %-----------------------------------------------------------------%
        function delete(obj)
            % DELETE Stop active transfers and release panel-owned UI handles.
            if obj.IsDeleting
                return
            end
            obj.IsDeleting = true;

            if ~isempty(obj.Manager) && isvalid(obj.Manager)
                delete(obj.Manager)
            end
            for taskID = 1:numel(obj.TransferTasks)
                task = obj.TransferTasks{taskID};
                if ~isempty(task)
                    obj.deleteTaskGraphics(task)
                end
            end
            for historyIndex = 1:numel(obj.HistoryTasks)
                task = obj.HistoryTasks{historyIndex};
                if ~isempty(task)
                    obj.deleteTaskGraphics(task)
                end
            end
            obj.TransferTasks = {};
            obj.HistoryTasks = {};
            obj.TransferOrder = [];
            obj.closeTransferContainer()

            if ~isempty(obj.AvatarHTML) && isvalid(obj.AvatarHTML)
                delete(obj.AvatarHTML)
            end
            if ~isempty(obj.UIFigure) && isvalid(obj.UIFigure)
                obj.UIFigure.WindowButtonDownFcn = obj.OriginalWindowButtonDownFcn;
            end
        end

        %-----------------------------------------------------------------%
        function taskID = addDownload(obj, url, options)
            % ADDDOWNLOAD Add and start a download for a URL.
            %
            % The file name is derived from URL. Depending on executionMode,
            % the target is resolved directly or through a file-selection
            % dialog. The method returns the numeric task identifier, or an
            % empty value when the user cancels destination selection.
            arguments
                obj
                url (1,:) char {mustBeNonempty}
                options.DisplayMode (1,:) char = 'normal'
                options.LogicalFileID (1,:) char = ''
            end

            url = char(url);
            [resolvedPath, cancelled, allowSourceFilename] = obj.resolveLocalPath(url);
            if cancelled
                taskID = [];
                return
            end

            [targetFolder, fileName, extension] = fileparts(resolvedPath);
            fileName = [fileName, extension];
            localPath = absolutePath(fullfile(targetFolder, fileName));
            request = struct('Direction', 'download', ...
                             'URL', url, ...
                             'TempFolder', obj.TempPath, ...
                             'LocalPath', localPath, ...
                             'FileName', fileName, ...
                             'DisplayMode', options.DisplayMode, ...
                             'AllowSourceFilename', allowSourceFilename);
            if ~isempty(options.LogicalFileID)
                request.LogicalFileID = options.LogicalFileID;
            end
            taskID = obj.Manager.addTransfer(request);
        end

        %-----------------------------------------------------------------%
        function taskID = addUpload(obj, url, options)
            % ADDUPLOAD Queue an upload of a local file to URL.
            %
            % LOCALPATH is required in webApp and optional in desktop modes,
            % where an empty value opens a source picker. Returns [] when the
            % user cancels selection. Raises
            % ui:TransferPanel:missingUploadSource when webApp has no path.
            % Completion and failure are reported through the configured
            % callbacks.
            arguments
                obj
                url (1,:) char {mustBeNonempty}
                options.LocalPath (1,:) char = ''
                options.FileName (1,:) char = ''
                options.Protocol (1,:) char = 'auto'
                options.Method (1,:) char = 'POST'
                options.FormFieldName (1,:) char = 'file'
                options.FormFields (1,1) struct = struct()
                options.DisplayMode (1,:) char = 'normal'
                options.LogicalFileID (1,:) char = ''
            end

            [localPath, cancelled] = obj.resolveUploadLocalPath(url, options.LocalPath);
            if cancelled
                taskID = [];
                return
            end
            [~, localName, extension] = fileparts(localPath);
            fileName = options.FileName;
            if isempty(fileName)
                fileName = [localName, extension];
            end
            request = struct('Direction', 'upload', ...
                             'URL', char(url), ...
                             'TempFolder', obj.TempPath, ...
                             'LocalPath', localPath, ...
                             'FileName', fileName, ...
                             'Protocol', options.Protocol, ...
                             'Method', options.Method, ...
                             'FormFieldName', options.FormFieldName, ...
                             'FormFields', options.FormFields, ...
                             'DisplayMode', options.DisplayMode);
            if ~isempty(options.LogicalFileID)
                request.LogicalFileID = options.LogicalFileID;
            end
            taskID = obj.Manager.addTransfer(request);
        end

        %-----------------------------------------------------------------%
        function show(obj)
            % SHOW Make the transfer popup visible and bring it to the front.
            obj.ShowWhenAvatarReady = false;
            if isempty(obj.TransferDialog) || ~isvalid(obj.TransferDialog)
                if isempty(obj.Manager.getHistory())
                    return
                end
                obj.ensureTransferContainer()
            end
            obj.syncHistoryRows()
            obj.refreshTransferContainer()
            obj.TransferDialog.Visible = 'on';
            drawnow
            obj.positionTransferContainer()
            uistack(obj.TransferDialog, 'top')
        end

        %-----------------------------------------------------------------%
        function hide(obj)
            % HIDE Hide the transfer popup without stopping its tasks.
            if ~isempty(obj.TransferDialog) && isvalid(obj.TransferDialog)
                obj.TransferDialog.Visible = 'off';
            end
        end

        %-----------------------------------------------------------------%
        function cancel(obj, taskID)
            % CANCEL Stop one transfer, remove temporary files, and remove its row.
            task = obj.getTask(taskID);
            if isempty(task)
                return
            end
            if taskID < 0 || ismember(task.Snapshot.LifecycleState, ...
                    {'completed', 'failed', 'interrupted'})
                obj.Manager.deleteHistoryEntry(task.HistoryEntryID)
                obj.removeTask(taskID)
            else
                obj.Manager.cancel(taskID)
            end
        end

        %-----------------------------------------------------------------%
        function cancelAll(obj)
            % CANCELALL Cancel every transfer and remove temporary files.
            obj.Manager.cancelAll()
        end

        %-----------------------------------------------------------------%
        function tf = isActive(obj, filePath)
            % ISACTIVE Return true when a task uses filePath as its LocalPath.
            tf = obj.Manager.isActive(filePath);
        end

        %-----------------------------------------------------------------%
        function setCollisionPolicy(obj, value)
            % SETCOLLISIONPOLICY Update the panel and manager policies together.
            obj.CollisionPolicy = value;
            if ~isempty(obj.Manager) && isvalid(obj.Manager)
                obj.Manager.CollisionPolicy = obj.CollisionPolicy;
            end
        end

        %-----------------------------------------------------------------%
        function set.MaxUploadBytes(obj, value)
            validateattributes(value, {'double'}, ...
                               {'scalar', 'real', 'positive', 'nonnan'}, ...
                               'TransferPanel', 'MaxUploadBytes')
            obj.MaxUploadBytes = value;
            obj.forwardMaxUploadBytes(value)
        end
    end


    % Private implementation: HTML events, task state, row controls, layout,
    % conflict handling, and per-transfer avatar updates.
    methods (Access = private)
        %-----------------------------------------------------------------%
        function onManagerSnapshot(obj, snapshot)
            if isempty(snapshot) || obj.IsDeleting
                return
            end
            taskID = snapshot.ID;
            if strcmp(snapshot.LifecycleState, 'canceled')
                obj.removeTask(taskID)
                return
            end
            if ismember(snapshot.LifecycleState, {'completed', 'failed'}) && ...
                    isfield(snapshot, 'HistoryEntry')
                obj.removeOtherHistoryRows(snapshot.HistoryEntry, taskID)
            end

            task = obj.getTask(taskID);
            if ismember(snapshot.LifecycleState, {'completed', 'failed'})
                if isempty(task)
                    task = obj.createHistoryTaskGraphics(taskID, snapshot.HistoryEntry);
                    task.RowKind = 'concluded';
                    obj.TransferOrder(end+1) = taskID;
                elseif ~strcmp(task.RowKind, 'concluded')
                    obj.deleteTaskGraphics(task)
                    task = obj.createHistoryTaskGraphics(taskID, snapshot.HistoryEntry);
                    task.RowKind = 'concluded';
                end
                task.Snapshot = snapshot;
                task.HistoryEntry = snapshot.HistoryEntry;
                obj.TransferTasks{taskID} = task;
                obj.renderHistoryRow(task, snapshot.HistoryEntry)
            else
                if isempty(task)
                    task = obj.createTaskGraphics(taskID, snapshot.FileName, snapshot.Direction);
                    obj.TransferOrder(end+1) = taskID;
                end
                task.Snapshot = snapshot;
                obj.TransferTasks{taskID} = task;
                obj.renderTask(snapshot)
            end
            obj.sortTransferOrder()
            obj.refreshTransferContainer()
            obj.updateTransferAvatar()
            if strcmp(snapshot.LifecycleState, 'awaitingConflictDecision')
                obj.requestShow()
            end
        end

        %-----------------------------------------------------------------%
        function onManagerTaskReordered(obj, snapshot)
            if isempty(snapshot) || obj.IsDeleting
                return
            end
            if isempty(obj.getTask(snapshot.ID))
                obj.onManagerSnapshot(snapshot)
            end
            obj.PromotedTaskID = snapshot.ID;
            obj.requestShow()
        end

        %-----------------------------------------------------------------%
        function requestShow(obj)
            % The caller has not placed the avatar yet during construction,
            % so anchoring the popup now would use its auto-flow grid cell.
            if obj.IsConstructing
                obj.ShowWhenAvatarReady = true;
                return
            end
            obj.show()
        end

        %-----------------------------------------------------------------%
        function onManagerCompleted(obj, taskID, info, snapshot)
            invokeCallback(obj.CompletedFcn, taskID, info, snapshot)
        end

        %-----------------------------------------------------------------%
        function onManagerError(obj, taskID, exception, snapshot)
            invokeCallback(obj.ErrorFcn, taskID, exception, snapshot)
        end

        %-----------------------------------------------------------------%
        function renderTask(obj, snapshot)
            task = obj.getTask(snapshot.ID);
            if isempty(task)
                return
            end
            task.Snapshot = snapshot;
            if strcmp(snapshot.LifecycleState, 'awaitingConflictDecision')
                obj.renderConflict(task, snapshot)
            else
                if strcmp(snapshot.LifecycleState, 'paused')
                    obj.setActionIcon(task.ActionButton, 'transfer-start.svg', ...
                                      'Iniciar ou continuar transferência');
                else
                    obj.setActionIcon(task.ActionButton, 'transfer-pause.svg', ...
                                      'Pausar transferência');
                end
                isUpload = strcmp(snapshot.Direction, 'upload');
                task.ActionButton.Visible = ternary(~isUpload || snapshot.IsResumable, 'on', 'off');
                task.RestartButton.Visible = 'on';
                task.CancelButton.Visible = 'on';
                task.ProgressFraction = snapshot.ProgressFraction;
                elapsedSeconds = snapshotElapsedSeconds(snapshot);
                task.BytesLabel.Text = ['  ', progressText(snapshot.TransferredBytes, ...
                                                              snapshot.TotalBytes, ...
                                                              elapsedSeconds, ...
                                                              snapshot.TransferRate, ...
                                                              snapshot.Direction)];
                task.StatusLabel.Text = snapshot.FileName;
            end
            obj.TransferTasks{snapshot.ID} = task;
            obj.updateProgressScale(task)
        end

        %-----------------------------------------------------------------%
        function renderConflict(obj, task, snapshot)
            isUpload = strcmp(snapshot.Direction, 'upload');
            sourceChanged = isUpload && isfield(snapshot, 'SourceChangedMessage') && ...
                            ~isempty(snapshot.SourceChangedMessage);
            if isUpload
                task.StatusLabel.Text = sprintf('Envio parcial encontrado para %s', snapshot.FileName);
                if sourceChanged
                    task.BytesLabel.Text = ['  ', snapshot.SourceChangedMessage];
                else
                    task.BytesLabel.Text = ['  ', sprintf( ...
                        '%s enviados. Continuar retoma o envio parcial.', ...
                        formatBytes(snapshot.TransferredBytes))];
                    obj.setActionIcon(task.ActionButton, 'transfer-continue.svg', ...
                                      'Continuar envio parcial');
                end
            elseif strcmp(snapshot.ConflictType, 'target')
                task.StatusLabel.Text = sprintf('%s já existe', snapshot.FileName);
                task.ProgressFraction = 1;
                task.BytesLabel.Text = ['  ', sprintf( ...
                    '%s já existe. Manter conserva o arquivo; Reiniciar baixa novamente.', ...
                    formatBytes(snapshot.TransferredBytes))];
                obj.setActionIcon(task.ActionButton, 'transfer-start.svg', ...
                                  'Manter arquivo existente');
            else
                task.StatusLabel.Text = sprintf('Arquivo parcial encontrado para %s', snapshot.FileName);
                task.BytesLabel.Text = ['  ', sprintf( ...
                    '%s baixados. Continuar retoma o arquivo parcial.', ...
                    formatBytes(snapshot.TransferredBytes))];
                obj.setActionIcon(task.ActionButton, 'transfer-continue.svg', ...
                                  'Continuar transferência parcial');
            end
            task.StatusLabel.FontColor = [0.15, 0.15, 0.15];
            task.ActionButton.Visible = ternary(~isUpload || ...
                (snapshot.IsResumable && ~sourceChanged), 'on', 'off');
            task.RestartButton.Visible = 'on';
            task.CancelButton.Visible = 'on';
            task.ProgressFraction = max(0, min(task.ProgressFraction, 1));
        end

        %-----------------------------------------------------------------%
        function renderHistoryRow(obj, task, entry)
            if isInterruptedUpload(entry)
                response = entry.Response;
                if ~isstruct(response) || ~isscalar(response)
                    response = struct();
                end
                response.OutcomeUncertain = true;
                if ~isfield(response, 'Message') || isempty(response.Message)
                    response.Message = 'Não foi possível confirmar se o servidor recebeu o arquivo.';
                end
                entry.Response = response;
            end
            task.HistoryEntry = entry;
            isUpload = strcmp(entry.Direction, 'upload');
            task.BadgeImage.ImageSource = transferIconPath(directionIcon(entry.Direction));
            task.BadgeImage.Tooltip = directionLabel(entry.Direction);
            task.StatusLabel.Text = task.FileName;
            task.StatusLabel.FontColor = [0.15, 0.15, 0.15];
            if strcmp(entry.LifecycleState, 'failed')
                task.StatusLabel.FontColor = [0.75, 0.05, 0.05];
            end
            task.BytesLabel.Text = ['  ', historyStatusText(entry)];
            if isUpload
                task.RestartButton.Visible = ternary(entry.isAvailable, 'on', 'off');
                task.RestartButton.Text = 'Reiniciar';
                task.CancelButton.Text = 'Remover';
                task.CancelButton.ButtonPushedFcn = @(~, ~) obj.cancelHistoryAction(task.ID);
                if responseOutcomeUncertain(entry)
                    task.RestartButton.Tooltip = 'Reiniciar envio requer confirmação';
                else
                    task.RestartButton.Tooltip = 'Reiniciar envio';
                end
                if task.RestartConfirmationPending
                    task.RestartButton.Text = 'Confirmar novo envio';
                    task.CancelButton.Text = 'Cancelar';
                    task.CancelButton.ButtonPushedFcn = ...
                        @(~, ~) obj.cancelRestartConfirmation(task.ID);
                end
            else
                task.RestartButton.Visible = 'on';
                task.RestartButton.Text = 'Reiniciar';
                task.CancelButton.Text = 'Remover';
                task.CancelButton.ButtonPushedFcn = @(~, ~) obj.cancel(task.ID);
            end
            task.Snapshot = struct('ID', task.ID, ...
                                   'HistoryEntryID', entry.EntryID, ...
                                   'Direction', entry.Direction, ...
                                   'LifecycleState', entry.LifecycleState, ...
                                   'HistoryEntry', entry, ...
                                   'Response', entry.Response, ...
                                   'OutcomeUncertain', responseOutcomeUncertain(entry), ...
                                   'AttemptedTimestamps', {entry.AttemptedTimestamps}, ...
                                   'TransferRate', NaN, ...
                                   'ProgressFraction', double(entry.isAvailable));
            if isfield(task, 'StrikeLine') && isgraphics(task.StrikeLine)
                task.StrikeLine.Visible = strcmp(entry.LifecycleState, 'failed');
            end
            obj.updateStrikeLine(task)
            if task.ID < 0
                obj.HistoryTasks{abs(task.ID)} = task;
            else
                obj.TransferTasks{task.ID} = task;
            end
        end

        %-----------------------------------------------------------------%
        function setActionIcon(~, button, iconName, tooltip)
            button.ImageSource = transferIconPath(iconName);
            button.Tooltip = tooltip;
        end

        %-----------------------------------------------------------------%
        function onAvatarEvent(obj, event)
            eventName = eventProperty(event, {'HTMLEventName'});
            if strcmp(eventName, 'transferAvatarReady')
                obj.AvatarHTMLReady = true;
                obj.AvatarHTML.Data = obj.AvatarState;
                if obj.ShowWhenAvatarReady && ~obj.IsConstructing
                    obj.ShowWhenAvatarReady = false;
                    obj.show()
                end
                return
            end

            if strcmp(eventName, 'transferAvatarClick')
                obj.show()
            end
        end

        %-----------------------------------------------------------------%
        function onFigureButtonDown(obj, source, event)
            if ~isempty(obj.TransferDialog) && isvalid(obj.TransferDialog) && ...
                    strcmp(obj.TransferDialog.Visible, 'on')
                point = obj.UIFigure.CurrentPoint;
                panelPosition = obj.TransferDialog.Position;
                insidePanel = point(1) >= panelPosition(1) && ...
                              point(1) <= panelPosition(1) + panelPosition(3) && ...
                              point(2) >= panelPosition(2) && ...
                              point(2) <= panelPosition(2) + panelPosition(4);
                if ~insidePanel
                    obj.hide()
                end
            end
            invokeCallback(obj.OriginalWindowButtonDownFcn, source, event)
        end

        %-----------------------------------------------------------------%
        function task = createTaskGraphics(obj, taskID, fileName, direction)
            obj.ensureTransferContainer()
            taskBackgroundColor = max(0, obj.UIFigure.Color - 0.04);
            progressTrackColor = max(0, taskBackgroundColor - 0.03);

            task = struct('ID', taskID, ...
                          'FileName', fileName, ...
                          'RowKind', 'active', ...
                          'HistoryEntryID', '', ...
                          'HistoryEntry', struct(), ...
                          'Direction', direction, ...
                          'RestartConfirmationPending', false, ...
                          'ProgressFraction', 0, ...
                          'Dialog', [], ...
                          'GridLayout', [], ...
                          'StatusLabel', [], ...
                          'BadgeImage', [], ...
                          'BytesLabel', [], ...
                          'ProgressTrack', [], ...
                          'ProgressFill', [], ...
                          'ActionButton', [], ...
                          'RestartButton', [], ...
                          'CancelButton', [], ...
                          'StrikeLine', [], ...
                          'RowHeight', 90, ...
                          'Snapshot', struct());

            task.Dialog = uipanel(obj.TransferStack, ...
                                  'BorderType', 'none', ...
                                  'BackgroundColor', taskBackgroundColor);
            task.GridLayout = uigridlayout(task.Dialog, [3, 5]);
            task.GridLayout.BackgroundColor = taskBackgroundColor;
            task.GridLayout.Padding = [12, 8, 12, 8];
            task.GridLayout.RowSpacing = 4;
            task.GridLayout.RowHeight = {22, 22, 22};
            task.GridLayout.ColumnWidth = {20, '1x', 32, 102, 72};

            task.BadgeImage = uiimage(task.GridLayout, ...
                                      'ImageSource', transferIconPath(directionIcon(direction)), ...
                                      'ScaleMethod', 'fit', ...
                                      'Tooltip', directionLabel(direction));
            task.BadgeImage.Layout.Row = 1;
            task.BadgeImage.Layout.Column = 1;

            task.StatusLabel = uilabel(task.GridLayout, ...
                                       'Text', fileName, ...
                                       'FontWeight', 'bold', ...
                                       'HorizontalAlignment', 'left', ...
                                       'VerticalAlignment', 'bottom', ...
                                       'WordWrap', 'on');
            task.StatusLabel.Layout.Row = 1;
            task.StatusLabel.Layout.Column = [2, 5];

            task.ProgressTrack = uipanel(task.GridLayout, ...
                                         'BorderType', 'none', ...
                                         'BackgroundColor', progressTrackColor, ...
                                         'Tooltip', 'Progresso da transferência');
            task.ProgressTrack.Layout.Row = 2;
            task.ProgressTrack.Layout.Column = [1, 2];

            task.ProgressFill = uipanel(task.ProgressTrack, ...
                                        'BorderType', 'none', ...
                                        'BackgroundColor', [0, 0.447, 0.741], ...
                                        'Units', 'pixels', ...
                                        'Position', [0, 0, 0, 1]);

            task.BytesLabel = uilabel(task.GridLayout, 'Text', '', 'WordWrap', 'on');
            task.BytesLabel.Layout.Row = 3;
            task.BytesLabel.Layout.Column = [1, 5];

            task.ActionButton = uiimage(task.GridLayout, ...
                                         'ImageSource', transferIconPath('transfer-pause.svg'), ...
                                         'ScaleMethod', 'fit', ...
                                         'Tooltip', 'Pausar transferência', ...
                                         'ImageClickedFcn', @(~, ~) obj.activateTask(taskID));
            task.ActionButton.Layout.Row = 2;
            task.ActionButton.Layout.Column = 3;

            task.RestartButton = uibutton(task.GridLayout, ...
                                          'Text', 'Reiniciar', ...
                                          'Tooltip', 'Reiniciar transferência', ...
                                          'ButtonPushedFcn', @(~, ~) obj.restartRow(taskID));
            task.RestartButton.Layout.Row = 2;
            task.RestartButton.Layout.Column = 4;

            task.CancelButton = uibutton(task.GridLayout, ...
                                         'Text', 'Cancelar', ...
                                         'Tooltip', 'Cancelar transferência', ...
                                         'ButtonPushedFcn', @(~, ~) obj.cancel(taskID));
            task.CancelButton.Layout.Row = 2;
            task.CancelButton.Layout.Column = 5;
            task.StrikeLine = uipanel(task.Dialog, ...
                                      'BorderType', 'none', ...
                                      'BackgroundColor', [0.75, 0.05, 0.05], ...
                                      'Visible', 'off', ...
                                      'Units', 'pixels', ...
                                      'Position', [0, 0, 0, 1]);
            obj.updateProgressScale(task)
        end

        %-----------------------------------------------------------------%
        function task = createHistoryTaskGraphics(obj, rowID, entry)
            obj.ensureTransferContainer()
            [~, baseName, extension] = fileparts(entry.LocalPath);
            fileName = [baseName, extension];
            if strcmp(entry.Direction, 'upload') && isstruct(entry.Response) && ...
                    isfield(entry.Response, 'FileName') && ...
                    ischar(entry.Response.FileName) && ~isempty(entry.Response.FileName)
                fileName = entry.Response.FileName;
            end
            task = struct('ID', rowID, ...
                          'FileName', fileName, ...
                          'RowKind', 'history', ...
                          'HistoryEntryID', entry.EntryID, ...
                          'HistoryEntry', entry, ...
                          'Direction', entry.Direction, ...
                          'RestartConfirmationPending', false, ...
                          'ProgressFraction', double(entry.isAvailable), ...
                          'Dialog', [], ...
                          'GridLayout', [], ...
                          'StatusLabel', [], ...
                          'BadgeImage', [], ...
                          'BytesLabel', [], ...
                          'ProgressTrack', [], ...
                          'ProgressFill', [], ...
                          'ActionButton', [], ...
                          'RestartButton', [], ...
                          'CancelButton', [], ...
                          'StrikeLine', [], ...
                          'RowHeight', 59, ...
                          'Snapshot', struct());

            task.Dialog = uipanel(obj.TransferStack, ...
                                  'BorderType', 'none', ...
                                  'BackgroundColor', max(0, obj.UIFigure.Color - 0.04));
            task.GridLayout = uigridlayout(task.Dialog, [2, 4]);
            task.GridLayout.Padding = [12, 6, 12, 6];
            task.GridLayout.RowSpacing = 3;
            task.GridLayout.RowHeight = {22, 22};
            task.GridLayout.ColumnWidth = {20, '1x', 140, 72};
            task.BadgeImage = uiimage(task.GridLayout, ...
                                      'ImageSource', transferIconPath(directionIcon(entry.Direction)), ...
                                      'ScaleMethod', 'fit', ...
                                      'Tooltip', directionLabel(entry.Direction));
            task.BadgeImage.Layout.Row = 1;
            task.BadgeImage.Layout.Column = 1;
            task.StatusLabel = uilabel(task.GridLayout, ...
                                       'Text', fileName, ...
                                       'FontWeight', 'bold', ...
                                       'HorizontalAlignment', 'left', ...
                                       'VerticalAlignment', 'center', ...
                                       'WordWrap', 'on');
            task.StatusLabel.Layout.Row = 1;
            task.StatusLabel.Layout.Column = 2;
            task.RestartButton = uibutton(task.GridLayout, ...
                                          'Text', 'Reiniciar', ...
                                          'Tooltip', 'Reiniciar transferência', ...
                                          'ButtonPushedFcn', @(~, ~) obj.restartRow(rowID));
            task.RestartButton.Layout.Row = 1;
            task.RestartButton.Layout.Column = 3;
            task.CancelButton = uibutton(task.GridLayout, ...
                                         'Text', 'Remover', ...
                                         'Tooltip', 'Remover registro do histórico', ...
                                         'ButtonPushedFcn', @(~, ~) obj.cancel(rowID));
            task.CancelButton.Layout.Row = 1;
            task.CancelButton.Layout.Column = 4;
            task.BytesLabel = uilabel(task.GridLayout, ...
                                      'Text', '', ...
                                      'HorizontalAlignment', 'left', ...
                                      'VerticalAlignment', 'center', ...
                                      'WordWrap', 'on');
            task.BytesLabel.Layout.Row = 2;
            task.BytesLabel.Layout.Column = [1, 4];
            task.StrikeLine = uipanel(task.Dialog, ...
                                      'BorderType', 'none', ...
                                      'BackgroundColor', [0.75, 0.05, 0.05], ...
                                      'Visible', 'off', ...
                                      'Units', 'pixels', ...
                                      'Position', [0, 0, 0, 1]);
            task.Snapshot = struct('ID', rowID, ...
                                   'HistoryEntryID', entry.EntryID, ...
                                   'LifecycleState', entry.LifecycleState, ...
                                   'HistoryEntry', entry, ...
                                   'AttemptedTimestamps', {entry.AttemptedTimestamps}, ...
                                   'TransferRate', NaN, ...
                                   'ProgressFraction', task.ProgressFraction);
            obj.renderHistoryRow(task, entry)
        end

        %-----------------------------------------------------------------%
        %-----------------------------------------------------------------%
        function activateTask(obj, taskID)
            task = obj.getTask(taskID);
            if isempty(task) || ~isfield(task, 'Snapshot') || isempty(fieldnames(task.Snapshot))
                return
            end
            if strcmp(task.Snapshot.Direction, 'upload') && ...
                    isfield(task.Snapshot, 'SourceChangedMessage') && ...
                    ~isempty(task.Snapshot.SourceChangedMessage)
                return
            end

            if strcmp(task.Snapshot.LifecycleState, 'awaitingConflictDecision')
                if strcmp(task.Snapshot.ConflictType, 'target')
                    obj.Manager.resolveConflict(taskID, 'keep')
                else
                    obj.Manager.resolveConflict(taskID, 'resume')
                end
            elseif strcmp(task.Snapshot.LifecycleState, 'paused')
                obj.Manager.resume(taskID)
            elseif strcmp(task.Snapshot.LifecycleState, 'active')
                obj.Manager.pause(taskID)
            end
        end

        %-----------------------------------------------------------------%
        function updateStrikeLine(~, task)
            if isempty(task.StrikeLine) || ~isgraphics(task.StrikeLine) || ...
                    ~isgraphics(task.StatusLabel) || ~isgraphics(task.Dialog)
                return
            end
            labelPosition = getpixelposition(task.StatusLabel, true);
            dialogPosition = getpixelposition(task.Dialog, true);
            estimatedTextWidth = min(labelPosition(3), ...
                                     numel(task.FileName) * task.StatusLabel.FontSize * 0.56);
            lineX = max(0, labelPosition(1) - dialogPosition(1) + 8);
            lineY = labelPosition(2) - dialogPosition(2) + round(labelPosition(4) * 0.55);
            task.StrikeLine.Position = [lineX, lineY, estimatedTextWidth, 2];
        end

        %-----------------------------------------------------------------%
        function restartRow(obj, taskID)
            task = obj.getTask(taskID);
            if isempty(task)
                return
            end
            if ismember(task.RowKind, {'history', 'concluded'}) && ...
                    strcmp(task.Direction, 'upload') && ...
                    responseOutcomeUncertain(task.HistoryEntry) && ...
                    ~task.RestartConfirmationPending
                task.RestartConfirmationPending = true;
                task.RestartButton.Text = 'Confirmar novo envio';
                task.RestartButton.Tooltip = 'Confirmar envio manual do arquivo';
                task.CancelButton.Text = 'Cancelar';
                task.CancelButton.ButtonPushedFcn = ...
                    @(~, ~) obj.cancelRestartConfirmation(taskID);
                obj.storeTask(task)
                return
            elseif taskID > 0 && strcmp(task.Snapshot.LifecycleState, 'awaitingConflictDecision')
                obj.Manager.resolveConflict(taskID, 'restart')
            elseif taskID < 0 || strcmp(task.RowKind, 'concluded') || ...
                    ismember(task.Snapshot.LifecycleState, {'completed', 'failed', 'interrupted'})
                if strcmp(task.Direction, 'upload') && ~task.HistoryEntry.isAvailable
                    return
                end
                obj.Manager.restartHistoryEntry(task.HistoryEntryID)
            else
                obj.Manager.restart(taskID)
            end
        end

        %-----------------------------------------------------------------%
        function syncHistoryRows(obj)
            entries = obj.Manager.getHistory();
            displayEntries = entries([]);
            for entryIndex = 1:numel(entries)
                entry = entries(entryIndex);
                if ~ismember(entry.LifecycleState, {'completed', 'failed', 'interrupted'})
                    continue
                end
                identityIndex = [];
                for displayIndex = 1:numel(displayEntries)
                    if sameHistoryRow(displayEntries(displayIndex), entry)
                        identityIndex = displayIndex;
                        break
                    end
                end
                if isempty(identityIndex)
                    displayEntries(end+1) = entry; %#ok<AGROW>
                else
                    displayEntries(identityIndex) = entry;
                end
            end

            for entryIndex = 1:numel(displayEntries)
                entry = displayEntries(entryIndex);
                if obj.hasHistoryRow(entry)
                    continue
                end
                obj.NextHistoryRowID = obj.NextHistoryRowID - 1;
                rowID = obj.NextHistoryRowID;
                task = obj.createHistoryTaskGraphics(rowID, entry);
                obj.HistoryTasks{abs(rowID)} = task;
                obj.TransferOrder(end+1) = rowID;
            end
            obj.sortTransferOrder()
        end

        %-----------------------------------------------------------------%
        function tf = hasHistoryRow(obj, entry)
            tf = false;
            taskLists = {obj.TransferTasks, obj.HistoryTasks};
            for listIndex = 1:numel(taskLists)
                tasks = taskLists{listIndex};
                for taskIndex = 1:numel(tasks)
                    task = tasks{taskIndex};
                    if isempty(task) || ~isfield(task, 'RowKind') || ...
                            ~ismember(task.RowKind, {'concluded', 'history'}) || ...
                            ~isfield(task, 'Snapshot') || ...
                            ~isfield(task.Snapshot, 'HistoryEntry')
                        continue
                    end
                    if sameHistoryRow(task.Snapshot.HistoryEntry, entry)
                        tf = true;
                        return
                    end
                end
            end
        end

        %-----------------------------------------------------------------%
        function removeOtherHistoryRows(obj, entry, keepTaskID)
            for taskID = 1:numel(obj.TransferTasks)
                task = obj.TransferTasks{taskID};
                if isempty(task) || task.ID == keepTaskID || ...
                        strcmp(task.RowKind, 'active') || ...
                        ~isfield(task, 'Snapshot') || ...
                        ~isfield(task.Snapshot, 'HistoryEntry') || ...
                        ~sameHistoryRow(task.Snapshot.HistoryEntry, entry)
                    continue
                end
                obj.deleteTaskGraphics(task)
                obj.TransferTasks{taskID} = [];
                obj.TransferOrder(obj.TransferOrder == task.ID) = [];
            end

            for historyIndex = 1:numel(obj.HistoryTasks)
                task = obj.HistoryTasks{historyIndex};
                if isempty(task) || task.ID == keepTaskID || ...
                        ~isfield(task, 'Snapshot') || ...
                        ~isfield(task.Snapshot, 'HistoryEntry') || ...
                        ~sameHistoryRow(task.Snapshot.HistoryEntry, entry)
                    continue
                end
                obj.deleteTaskGraphics(task)
                obj.HistoryTasks{historyIndex} = [];
                obj.TransferOrder(obj.TransferOrder == task.ID) = [];
            end
        end

        %-----------------------------------------------------------------%
        function sortTransferOrder(obj)
            rowIDs = obj.TransferOrder;
            if numel(rowIDs) < 2
                return
            end
            sortKeys = zeros(numel(rowIDs), 2);
            for rowIndex = 1:numel(rowIDs)
                task = obj.getTask(rowIDs(rowIndex));
                state = task.Snapshot.LifecycleState;
                if task.ID == obj.PromotedTaskID
                    group = 0;
                elseif ismember(state, {'paused', 'awaitingConflictDecision'})
                    group = 1;
                elseif ismember(state, {'created', 'active'})
                    group = 2;
                else
                    group = 3;
                end
                sortKeys(rowIndex, :) = [group, rowIndex];
            end
            [~, sortedIndices] = sortrows(sortKeys, [1, 2]);
            obj.TransferOrder = rowIDs(sortedIndices);
        end

        %-----------------------------------------------------------------%
        function removeTask(obj, taskID)
            task = obj.getTask(taskID);
            if isempty(task)
                return
            end
            obj.deleteTaskGraphics(task)
            if taskID < 0
                obj.HistoryTasks{abs(taskID)} = [];
            else
                obj.TransferTasks{taskID} = [];
            end
            obj.TransferOrder(obj.TransferOrder == taskID) = [];
            obj.refreshTransferContainer()
            obj.updateTransferAvatar()
        end

        %-----------------------------------------------------------------%
        function task = getTask(obj, taskID)
            task = [];
            if ~isscalar(taskID) || ~isnumeric(taskID) || taskID == 0
                return
            end
            if taskID > 0
                if taskID > numel(obj.TransferTasks)
                    return
                end
                task = obj.TransferTasks{taskID};
            else
                historyIndex = abs(taskID);
                if historyIndex > numel(obj.HistoryTasks)
                    return
                end
                task = obj.HistoryTasks{historyIndex};
            end
            if isempty(task)
                task = [];
            end
        end

        %-----------------------------------------------------------------%
        function cancelHistoryAction(obj, taskID)
            task = obj.getTask(taskID);
            if isempty(task)
                return
            end
            if task.RestartConfirmationPending
                obj.cancelRestartConfirmation(taskID)
            else
                obj.cancel(taskID)
            end
        end

        %-----------------------------------------------------------------%
        function cancelRestartConfirmation(obj, taskID)
            task = obj.getTask(taskID);
            if isempty(task) || ~task.RestartConfirmationPending
                return
            end
            task.RestartConfirmationPending = false;
            obj.renderHistoryRow(task, task.HistoryEntry)
        end

        %-----------------------------------------------------------------%
        function storeTask(obj, task)
            if task.ID < 0
                obj.HistoryTasks{abs(task.ID)} = task;
            else
                obj.TransferTasks{task.ID} = task;
            end
        end

        %-----------------------------------------------------------------%
        function deleteTaskGraphics(~, task)
            handles = {task.Dialog};
            for handleIndex = 1:numel(handles)
                handle = handles{handleIndex};
                try
                    if ~isempty(handle) && isvalid(handle)
                        delete(handle)
                    end
                catch
                end
            end
        end

        %-----------------------------------------------------------------%
        function ensureTransferContainer(obj)
            if ~isempty(obj.TransferDialog) && isvalid(obj.TransferDialog)
                return
            end

            obj.TransferDialog = uipanel(obj.UIFigure, ...
                                         'Title', '', ...
                                         'Visible', 'off', ...
                                         'Scrollable', 'off', ...
                                         'Units', 'pixels', ...
                                         'BorderType', 'line', ...
                                         'BackgroundColor', obj.UIFigure.Color);
            obj.TransferHeader = uipanel(obj.TransferDialog, ...
                                         'BorderType', 'none', ...
                                         'BackgroundColor', obj.UIFigure.Color);
            obj.TransferTitleLabel = uilabel(obj.TransferHeader, ...
                                             'Text', 'Transferências', ...
                                             'FontWeight', 'bold', ...
                                             'HorizontalAlignment', 'left', ...
                                             'VerticalAlignment', 'center');
            obj.CloseImage = uiimage(obj.TransferHeader, ...
                                     'ImageSource', closeIconPath(), ...
                                     'ImageClickedFcn', @(~, ~) obj.hide());
            obj.TransferContent = uipanel(obj.TransferDialog, ...
                                          'BorderType', 'none', ...
                                          'Units', 'pixels', ...
                                          'BackgroundColor', obj.UIFigure.Color);
            obj.TransferStack = uigridlayout(obj.TransferContent, [1, 1]);
            obj.TransferStack.Padding = [5, 5, 5, 5];
            obj.TransferStack.RowSpacing = 5;
            obj.TransferStack.ColumnWidth = {'1x'};
            obj.TransferStack.RowHeight = {96};
            obj.positionTransferContainer()
        end

        %-----------------------------------------------------------------%
        function closeTransferContainer(obj)
            if ~isempty(obj.TransferDialog) && isvalid(obj.TransferDialog)
                delete(obj.TransferDialog)
            end
            obj.TransferDialog = [];
            obj.TransferContent = [];
            obj.TransferStack = [];
        end

        %-----------------------------------------------------------------%
        function refreshTransferContainer(obj)
            if isempty(obj.TransferDialog) || ~isvalid(obj.TransferDialog)
                return
            end

            rowIDs = obj.TransferOrder;
            isValidTask = false(size(rowIDs));
            for taskIndex = 1:numel(rowIDs)
                task = obj.getTask(rowIDs(taskIndex));
                isValidTask(taskIndex) = ~isempty(task) && ...
                    ~isempty(task.Dialog) && isvalid(task.Dialog);
            end
            rowIDs = rowIDs(isValidTask);
            obj.TransferOrder = rowIDs;

            if isempty(rowIDs)
                obj.closeTransferContainer()
                return
            end

            rowHeights = repmat({1}, 1, numel(rowIDs));
            for row = 1:numel(rowIDs)
                task = obj.getTask(rowIDs(row));
                rowHeights{row} = task.RowHeight;
                task.Dialog.Layout.Row = row;
                task.Dialog.Layout.Column = 1;
            end
            obj.TransferStack.RowHeight = rowHeights;
            obj.positionTransferContainer()
            obj.resizeTransferProgressBars()
        end

        %-----------------------------------------------------------------%
        function positionTransferContainer(obj)
            if isempty(obj.TransferDialog) || ~isvalid(obj.TransferDialog) || ...
                    isempty(obj.AvatarHTML) || ~isvalid(obj.AvatarHTML)
                return
            end

            drawnow limitrate
            avatarPosition = getpixelposition(obj.AvatarHTML, true);
            figurePosition = obj.UIFigure.Position;
            figureWidth = figurePosition(3);
            figureHeight = figurePosition(4);
            panelWidth = min(560, max(220, figureWidth - 16));
            headerHeight = 24;
            borderInset = 2;
            panelGap = 12;
            activeHeight = 0;
            activeTaskCount = 0;
            for orderIndex = 1:numel(obj.TransferOrder)
                task = obj.getTask(obj.TransferOrder(orderIndex));
                if ~isempty(task)
                    activeHeight = activeHeight + task.RowHeight;
                    activeTaskCount = activeTaskCount + 1;
                end
            end
            if activeTaskCount > 0
                activeHeight = activeHeight + 2 * 5 + (activeTaskCount - 1) * 5;
            end
            contentHeight = max(1, activeHeight);
            requiredPanelHeight = contentHeight + headerHeight + 2 * borderInset;
            availablePanelHeight = min(avatarPosition(2) - panelGap - 8, figureHeight - 16);
            panelHeight = min(max(64, requiredPanelHeight), max(64, availablePanelHeight));
            panelX = min(max(8, avatarPosition(1)), max(8, figureWidth - panelWidth - 8));
            panelY = avatarPosition(2) - panelHeight - panelGap;
            panelY = min(max(8, panelY), max(8, figureHeight - panelHeight - 8));

            obj.TransferDialog.Position = [panelX, panelY, panelWidth, panelHeight];
            innerPosition = obj.TransferDialog.InnerPosition;
            needsVerticalScroll = contentHeight > innerPosition(4);
            obj.TransferDialog.Scrollable = ternary(needsVerticalScroll, 'on', 'off');
            drawnow limitrate
            innerPosition = obj.TransferDialog.InnerPosition;
            contentWidth = max(1, floor(innerPosition(3)) - 16 - 2 * borderInset);
            obj.TransferContent.Position = [borderInset, borderInset, contentWidth, contentHeight];
            obj.TransferHeader.Position = [borderInset, contentHeight + borderInset, contentWidth, headerHeight];
            obj.TransferTitleLabel.Position = [8, 0, max(1, contentWidth - 32), headerHeight];
            closeIconSize = 16;
            closeIconMargin = 4;
            obj.CloseImage.Position = [max(0, contentWidth - closeIconSize), ...
                                       max(closeIconMargin, (headerHeight - closeIconSize) / 2), ...
                                       closeIconSize, closeIconSize];
        end

        %-----------------------------------------------------------------%
        function resizeTransferProgressBars(obj)
            for taskID = 1:numel(obj.TransferTasks)
                task = obj.TransferTasks{taskID};
                if isempty(task) || isempty(task.ProgressTrack) || ~isvalid(task.ProgressTrack)
                    continue
                end
                obj.updateProgressScale(task)
            end
        end

        %-----------------------------------------------------------------%
        function updateProgressScale(~, task)
            if isempty(task.ProgressTrack) || ~isvalid(task.ProgressTrack)
                return
            end
            trackSize = task.ProgressTrack.InnerPosition;
            trackWidth = max(0, trackSize(3));
            trackHeight = max(1, trackSize(4));
            task.ProgressFill.Position = [0, 0, task.ProgressFraction * trackWidth, trackHeight];
        end

        %-----------------------------------------------------------------%
        function updateTransferAvatar(obj)
            state = struct('id', {}, 'rate', {}, 'progress', {}, 'direction', {});

            for taskID = 1:numel(obj.TransferTasks)
                task = obj.TransferTasks{taskID};
                if isempty(task) || ~isfield(task, 'Snapshot') || ...
                        isempty(fieldnames(task.Snapshot))
                    continue
                end
                snapshot = task.Snapshot;
                isPaused = strcmp(snapshot.LifecycleState, 'paused');
                isWaitingForPartial = strcmp(snapshot.LifecycleState, ...
                                             'awaitingConflictDecision') && ...
                                      strcmp(snapshot.ConflictType, 'partial');
                if ~ismember(snapshot.LifecycleState, {'active', 'paused'}) && ...
                        ~isWaitingForPartial
                    continue
                end
                rate = double(snapshot.TransferRate);
                isNonResumableActiveUpload = strcmp(snapshot.Direction, 'upload') && ...
                    strcmp(snapshot.LifecycleState, 'active') && ~snapshot.IsResumable;
                if isPaused || isWaitingForPartial
                    rate = 0;
                elseif ~isfinite(rate) || (rate ~= 0 && rate < 100000)
                    rate = 100000;
                end
                if isNonResumableActiveUpload && (~isfinite(rate) || rate == 0)
                    rate = 100000;
                end
                progress = double(snapshot.ProgressFraction);
                if ~isfinite(progress)
                    progress = 0;
                end
                progress = min(1, max(0, progress)) * 100;
                state(end+1) = struct('id', double(snapshot.ID), ...
                                      'rate', rate, ...
                                      'progress', progress, ...
                                      'direction', snapshot.Direction); %#ok<AGROW>
            end

            if isequal(state, obj.AvatarState)
                return
            end
            obj.AvatarState = state;
            if obj.AvatarHTMLReady && ~isempty(obj.AvatarHTML) && isvalid(obj.AvatarHTML)
                obj.AvatarHTML.Data = state;
            end
        end
    end


    methods (Access = private)
        %-----------------------------------------------------------------%
        function [localPath, cancelled, allowSourceFilename] = resolveLocalPath(obj, url)
            cancelled = false;
            [fileName, isUsefulURLName] = obj.resolveTransferFileName(url);
            allowSourceFilename = ~isUsefulURLName;
            if strcmp(obj.executionMode, 'webApp')
                if isempty(strtrim(obj.TargetPath)) || ~isfolder(obj.TargetPath)
                    error('ui:TransferPanel:missingTargetPath', ...
                          'TargetPath deve apontar para uma pasta existente no modo webApp.')
                end
                localPath = fullfile(obj.TargetPath, fileName);
                return
            end

            defaultName = fileName;
            if ~isempty(strtrim(obj.TargetPath))
                defaultName = fullfile(obj.TargetPath, fileName);
            end
            if isempty(obj.DestinationResolver)
                [selectedName, selectedFolder] = uiputfile('*.*', '', defaultName);
                resolution = struct('Cancelled', isequal(selectedName, 0), ...
                                    'TargetFolder', selectedFolder, ...
                                    'FileName', selectedName);
            else
                context = struct('ExecutionMode', obj.executionMode, ...
                                 'URL', url, ...
                                 'SuggestedFileName', fileName, ...
                                 'InitialFolder', obj.TargetPath, ...
                                 'UIFigure', obj.UIFigure);
                resolution = obj.DestinationResolver(context);
            end
            resolution = normalizeDestinationResolution(resolution);
            if resolution.Cancelled
                localPath = '';
                cancelled = true;
                allowSourceFilename = false;
                return
            end
            resolution.FileName = appendSourceExtension(resolution.FileName, ...
                                                         fileName, isUsefulURLName);
            if isempty(obj.DestinationResolver)
                figure(obj.UIFigure)
            end
            localPath = fullfile(resolution.TargetFolder, resolution.FileName);
            allowSourceFilename = false;
        end

        %-----------------------------------------------------------------%
        function [fileName, isUseful] = resolveTransferFileName(obj, url)
            [fileName, isUseful] = datatransfer.transferFileName(url, shortTaskID());
            if isUseful
                return
            end

            matchingURL = strcmp(obj.DownloadFileNames(:, 1), url);
            matchingIndex = find(matchingURL, 1, 'last');
            if ~isempty(matchingIndex)
                fileName = obj.DownloadFileNames{matchingIndex, 2};
                return
            end

            obj.DownloadFileNames(end+1, :) = {url, fileName};
        end

        %-----------------------------------------------------------------%
        function [localPath, cancelled] = resolveUploadLocalPath(obj, url, requestedPath)
            cancelled = false;
            localPath = requestedPath;
            if isempty(strtrim(localPath))
                if strcmp(obj.executionMode, 'webApp')
                    error('ui:TransferPanel:missingUploadSource', ...
                          'LocalPath deve ser informado explicitamente no modo webApp.')
                end
                [suggestedName, ~] = datatransfer.transferFileName(url, shortTaskID());
                context = struct('ExecutionMode', obj.executionMode, ...
                                 'URL', url, ...
                                 'SuggestedFileName', suggestedName, ...
                                 'InitialFolder', obj.TargetPath, ...
                                 'UIFigure', obj.UIFigure);
                if isempty(obj.SourceResolver)
                    defaultName = suggestedName;
                    if ~isempty(strtrim(obj.TargetPath)) && isfolder(obj.TargetPath)
                        defaultName = fullfile(obj.TargetPath, suggestedName);
                    end
                    [selectedName, selectedFolder] = uigetfile('*.*', '', defaultName);
                    if isequal(selectedName, 0)
                        localPath = '';
                        cancelled = true;
                        return
                    end
                    figure(obj.UIFigure)
                    localPath = fullfile(selectedFolder, selectedName);
                else
                    resolution = obj.SourceResolver(context);
                    if ~isstruct(resolution) || ~isscalar(resolution)
                        error('ui:TransferPanel:invalidSourceResolution', ...
                              'SourceResolver deve retornar uma struct escalar.')
                    end
                    if ~isfield(resolution, 'Cancelled') || isempty(resolution.Cancelled)
                        resolution.Cancelled = false;
                    end
                    if ~isscalar(resolution.Cancelled) || ...
                            ~(islogical(resolution.Cancelled) || isnumeric(resolution.Cancelled))
                        error('ui:TransferPanel:invalidSourceResolution', ...
                              'Cancelled deve ser um escalar lógico.')
                    end
                    if logical(resolution.Cancelled)
                        localPath = '';
                        cancelled = true;
                        return
                    end
                    if ~isfield(resolution, 'LocalPath') || ...
                            ~(ischar(resolution.LocalPath) || isStringScalar(resolution.LocalPath))
                        error('ui:TransferPanel:invalidSourceResolution', ...
                              'SourceResolver deve retornar LocalPath.')
                    end
                    localPath = char(resolution.LocalPath);
                end
            end
            if ~isfile(localPath)
                error('ui:TransferPanel:invalidUploadSource', ...
                      'LocalPath deve apontar para um arquivo existente.')
            end
            localPath = absolutePath(localPath);
        end

        %-----------------------------------------------------------------%
        function forwardMaxUploadBytes(obj, value)
            if ~isempty(obj.Manager) && isvalid(obj.Manager)
                obj.Manager.MaxUploadBytes = value;
            end
        end
    end


    % Static helpers used for validation and execution-mode-independent paths.
    methods (Static, Access = private)
        %-----------------------------------------------------------------%
        function setExecutionModeValue(obj, value)
            obj.executionMode = value;
        end
    end


    % Public property validation.
    methods
        %-----------------------------------------------------------------%
        function set.executionMode(obj, value)
            % SET.EXECUTIONMODE Validate and assign the execution mode.
            value = char(value);
            allowedValues = {'webApp', 'desktopStandaloneApp', 'MATLABEnvironment'};
            if ~ismember(value, allowedValues)
                error('ui:TransferPanel:invalidExecutionMode', ...
                        'executionMode deve ser webApp, desktopStandaloneApp ou MATLABEnvironment.')
            end
            obj.executionMode = value;
        end

        %-----------------------------------------------------------------%
        function set.CollisionPolicy(obj, value)
            % SET.COLLISIONPOLICY Validate the target-conflict policy.
            value = char(value);
            allowedValues = {'askInRow', 'reject'};
            if ~ismember(value, allowedValues)
                error('ui:TransferPanel:invalidCollisionPolicy', ...
                        'CollisionPolicy não é compatível.')
            end
            obj.CollisionPolicy = value;
        end

        %-----------------------------------------------------------------%
        function set.PartialConflictPolicy(obj, value)
            % SET.PARTIALCONFLICTPOLICY Validate the partial-file policy.
            value = char(value);
            allowedValues = {'askInRow', 'resume', 'restart', 'cancel'};
            if ~ismember(value, allowedValues)
                error('ui:TransferPanel:invalidPartialConflictPolicy', ...
                        'PartialConflictPolicy não é compatível.')
            end
            obj.PartialConflictPolicy = value;
        end
    end
end

%-----------------------------------------------------------------%
function figureHandle = findFigure(parentContainer)
if isa(parentContainer, 'matlab.ui.Figure')
    figureHandle = parentContainer;
else
    figureHandle = ancestor(parentContainer, 'figure');
end
end

%-----------------------------------------------------------------%
function sourcePath = avatarHTMLPath()
sourcePath = fullfile(fileparts(mfilename('fullpath')), 'html', 'pingTransferAvatar.html');
end

%-----------------------------------------------------------------%
function sourcePath = closeIconPath()
sourcePath = generalIconPath('close-16px-red.svg');
end

%-----------------------------------------------------------------%
function sourcePath = transferIconPath(iconName)
sourcePath = generalIconPath(iconName);
end

%-----------------------------------------------------------------%
function iconName = directionIcon(direction)
if strcmp(direction, 'upload')
    iconName = 'transfer-upload.svg';
else
    iconName = 'transfer-download.svg';
end
end

%-----------------------------------------------------------------%
function label = directionLabel(direction)
if strcmp(direction, 'upload')
    label = 'Envio';
else
    label = 'Recebimento';
end
end

%-----------------------------------------------------------------%
function sourcePath = generalIconPath(iconName)
classPath = which('ui.TransferPanel');
if isempty(classPath)
    error('ui:TransferPanel:classPathUnavailable', ...
          'Não foi possível resolver o caminho da classe ui.TransferPanel.')
end
generalFolder = fileparts(fileparts(classPath));
sourcePath = fullfile(generalFolder, 'icons', iconName);
if ~isfile(sourcePath)
    error('ui:TransferPanel:iconNotFound', ...
          'Não foi possível localizar o ícone de transferência em "%s".', sourcePath)
end
end

%-----------------------------------------------------------------%
function value = eventProperty(event, propertyNames)
value = '';
for propertyIndex = 1:numel(propertyNames)
    if isprop(event, propertyNames{propertyIndex})
        propertyValue = event.(propertyNames{propertyIndex});
        if ischar(propertyValue) || (isstring(propertyValue) && isscalar(propertyValue))
            value = char(propertyValue);
        else
            value = propertyValue;
        end
        return
    end
end
end

%-----------------------------------------------------------------%
function value = shortTaskID()
value = char(matlab.lang.internal.uuid());
value = regexprep(value, '-', '');
value = value(1:min(8, numel(value)));
end

%-----------------------------------------------------------------%
function resolution = normalizeDestinationResolution(resolution)
if ~isstruct(resolution) || ~isscalar(resolution)
    error('ui:TransferPanel:invalidDestinationResolution', ...
            'DestinationResolver deve retornar uma struct escalar.')
end
if ~isfield(resolution, 'Cancelled') || isempty(resolution.Cancelled)
    resolution.Cancelled = false;
end
if ~isscalar(resolution.Cancelled) || ...
        ~(islogical(resolution.Cancelled) || isnumeric(resolution.Cancelled))
    error('ui:TransferPanel:invalidDestinationResolution', ...
            'Cancelled de DestinationResolver deve ser um escalar lógico.')
end
resolution.Cancelled = logical(resolution.Cancelled);
if resolution.Cancelled
    resolution.TargetFolder = '';
    resolution.FileName = '';
    return
end
requiredFields = {'TargetFolder', 'FileName'};
for fieldIndex = 1:numel(requiredFields)
    fieldName = requiredFields{fieldIndex};
    if ~isfield(resolution, fieldName) || ...
            ~(ischar(resolution.(fieldName)) || isStringScalar(resolution.(fieldName))) || ...
            isempty(strtrim(char(resolution.(fieldName))))
        error('ui:TransferPanel:invalidDestinationResolution', ...
              'DestinationResolver deve retornar %s preenchido.', fieldName)
    end
    resolution.(fieldName) = char(resolution.(fieldName));
end
if ~isfolder(resolution.TargetFolder)
    error('ui:TransferPanel:invalidDestinationResolution', ...
            'TargetFolder de DestinationResolver deve ser uma pasta existente.')
end
if ~strcmp(resolution.FileName, datatransfer.transferFileName(resolution.FileName, 'download')) || ...
        contains(resolution.FileName, {'/', '\\'})
    error('ui:TransferPanel:invalidDestinationResolution', ...
            'FileName de DestinationResolver deve ser um nome válido, sem caminho de pasta.')
end
end

%-----------------------------------------------------------------%
function fileName = appendSourceExtension(fileName, sourceFileName, isUsefulSourceName)
if ~isUsefulSourceName
    return
end
[~, ~, selectedExtension] = fileparts(fileName);
if ~isempty(selectedExtension)
    return
end
[~, ~, sourceExtension] = fileparts(sourceFileName);
if ~isempty(sourceExtension)
    fileName = [fileName, sourceExtension];
end
end

%-----------------------------------------------------------------%
%-----------------------------------------------------------------%
function value = snapshotElapsedSeconds(snapshot)
if isempty(snapshot.StartedAt) || isempty(snapshot.UpdatedAt)
    value = 0;
    return
end
value = max(0, seconds(snapshot.UpdatedAt - snapshot.StartedAt));
end

%-----------------------------------------------------------------%
function text = progressText(transferredBytes, totalBytes, elapsedSeconds, transferRate, direction)
receivedText = formatBytes(transferredBytes);
totalText = '-';
totalSizeText = '-';
if ~isempty(totalBytes) && totalBytes > 0
    totalText = formatBytes(totalBytes);
    totalSizeText = formatTotalBytes(totalBytes);
end
if elapsedSeconds < 10
    elapsedText = '- s';
    remainingText = '- s';
else
    elapsedText = formatDuration(elapsedSeconds);
    remainingText = '- s';
    if ~isempty(totalBytes) && totalBytes > 0 && isfinite(transferRate) && transferRate > 0
        remainingText = formatDuration(max(0, double(totalBytes) - double(transferredBytes)) / transferRate);
    end
end
if strcmp(direction, 'upload')
    directionText = 'enviados';
else
    directionText = 'baixados';
end
text = sprintf('%s %s / %s (%s) | Decorrido: %s | Restante: %s', ...
               receivedText, directionText, totalText, totalSizeText, elapsedText, remainingText);
end

%-----------------------------------------------------------------%
function text = formatBytes(value)
if isempty(value) || ~isscalar(value) || ~isfinite(value)
    text = 'desconhecido';
    return
end
value = double(value);
digits = sprintf('%.0f', max(0, value));
firstGroupLength = mod(numel(digits), 3);
if firstGroupLength == 0
    firstGroupLength = 3;
end
groupCount = 1 + floor((numel(digits) - firstGroupLength) / 3);
groups = cell(1, groupCount);
groups{1} = digits(1:firstGroupLength);
for groupIndex = 2:groupCount
    startIndex = firstGroupLength + (groupIndex - 2) * 3 + 1;
    groups{groupIndex} = digits(startIndex:startIndex + 2);
end
text = strjoin(groups, ' ');
end

%-----------------------------------------------------------------%
function text = historyStatusText(entry)
timestamp = entry.CompletedAt;
if isempty(timestamp)
    timestamp = entry.UpdatedAt;
end
if isempty(timestamp)
    timestampText = '-';
else
    try
        completedAt = datetime(timestamp, ...
                               'InputFormat', "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", ...
                               'TimeZone', 'UTC');
        completedAt.Format = 'dd/MM/yy HH:mm';
        timestampText = char(completedAt);
    catch
        timestampText = timestamp;
    end
end
if entry.TransferredBytes > 0
    if strcmp(entry.Direction, 'upload')
        directionText = 'enviados';
    else
        directionText = 'baixados';
    end
    sizeText = sprintf('%s bytes (%s)', ...
                       formatBytes(entry.TransferredBytes), ...
                       formatTotalBytes(entry.TransferredBytes));
    sizeText = [sizeText, ' ', directionText];
else
    sizeText = '0 bytes';
end
text = sprintf('%s | %s', timestampText, sizeText);
if strcmp(entry.LifecycleState, 'failed')
    text = ['Falha | ', text];
    if ~isempty(entry.ErrorMessages)
        text = [text, ' | ', entry.ErrorMessages{end}];
    end
elseif strcmp(entry.LifecycleState, 'interrupted')
    text = ['Interrompida | ', text];
end
if strcmp(entry.LifecycleState, 'completed') && ~entry.isAvailable
    text = ['Indisponível | ', text];
end
if strcmp(entry.Direction, 'upload') && responseOutcomeUncertain(entry)
    text = ['Resultado do envio incerto | ', text];
    if isfield(entry.Response, 'Message') && ~isempty(entry.Response.Message)
        text = [text, ' | ', char(entry.Response.Message)];
    end
elseif strcmp(entry.Direction, 'upload') && ...
        strcmp(entry.LifecycleState, 'completed') && ...
        isstruct(entry.Response) && isfield(entry.Response, 'Success') && ...
        entry.Response.Success && isfield(entry.Response, 'Message')
    statusText = char(entry.Response.Message);
    if isfield(entry.Response, 'StatusCode') && ...
            isnumeric(entry.Response.StatusCode) && ...
            isscalar(entry.Response.StatusCode) && isfinite(entry.Response.StatusCode)
        statusText = sprintf('%s (HTTP %g)', statusText, entry.Response.StatusCode);
    end
    text = [statusText, ' | ', text];
end
end

%-----------------------------------------------------------------%
function tf = responseOutcomeUncertain(entry)
tf = false;
if ~isstruct(entry) || ~isscalar(entry)
    return
end
hasUncertainResponse = isfield(entry, 'Response') && ...
    isstruct(entry.Response) && isscalar(entry.Response) && ...
    isfield(entry.Response, 'OutcomeUncertain') && ...
    islogical(entry.Response.OutcomeUncertain) && ...
    isscalar(entry.Response.OutcomeUncertain) && entry.Response.OutcomeUncertain;
tf = hasUncertainResponse || isInterruptedUpload(entry);
end

%-----------------------------------------------------------------%
function tf = isInterruptedUpload(entry)
tf = isstruct(entry) && isscalar(entry) && ...
    isfield(entry, 'Direction') && ischar(entry.Direction) && ...
    strcmp(entry.Direction, 'upload') && ...
    isfield(entry, 'LifecycleState') && ischar(entry.LifecycleState) && ...
    strcmp(entry.LifecycleState, 'interrupted');
end

%-----------------------------------------------------------------%
function text = formatTotalBytes(value)
value = double(value);
scales = [1024^3, 1024^2, 1024];
names = {'GBytes', 'MBytes', 'kBytes'};
unitIndex = find(value >= scales, 1, 'first');
if isempty(unitIndex)
    unitIndex = numel(scales);
end
text = sprintf('%.0f %s', max(1, round(value / scales(unitIndex))), names{unitIndex});
end

%-----------------------------------------------------------------%
function text = formatDuration(seconds)
seconds = max(0, round(double(seconds)));
if seconds < 60
    text = sprintf('%.0f s', seconds);
    return
end
minutes = floor(seconds / 60);
remainingSeconds = mod(seconds, 60);
if minutes < 60
    if remainingSeconds == 0
        text = sprintf('%.0f min', minutes);
    else
        text = sprintf('%.0f min %.0f s', minutes, remainingSeconds);
    end
    return
end
hours = floor(minutes / 60);
remainingMinutes = mod(minutes, 60);
if remainingMinutes == 0
    text = sprintf('%.0f h', hours);
else
    text = sprintf('%.0f h %.0f min', hours, remainingMinutes);
end
end

%-----------------------------------------------------------------%
function invokeCallback(callback, varargin)
if isempty(callback)
    return
end
try
    callback(varargin{:})
catch
end
end

%-----------------------------------------------------------------%
function value = ternary(condition, trueValue, falseValue)
if condition
    value = trueValue;
else
    value = falseValue;
end
end

%-----------------------------------------------------------------%
function tf = sameHistoryRow(firstEntry, secondEntry)
tf = isstruct(firstEntry) && isscalar(firstEntry) && ...
     isstruct(secondEntry) && isscalar(secondEntry) && ...
     isfield(firstEntry, 'Direction') && isfield(secondEntry, 'Direction') && ...
     isfield(firstEntry, 'URL') && isfield(secondEntry, 'URL') && ...
     isfield(firstEntry, 'LocalPath') && isfield(secondEntry, 'LocalPath') && ...
     strcmp(firstEntry.Direction, secondEntry.Direction) && ...
     strcmp(firstEntry.URL, secondEntry.URL) && ...
     samePath(firstEntry.LocalPath, secondEntry.LocalPath);
end

%-----------------------------------------------------------------%
function tf = samePath(firstPath, secondPath)
if ispc
    tf = strcmpi(firstPath, secondPath);
else
    tf = strcmp(firstPath, secondPath);
end
end

%-----------------------------------------------------------------%
function value = absolutePath(pathValue)
try
    fileObject = java.io.File(pathValue);
    value = char(fileObject.getCanonicalPath());
catch
    if startsWith(pathValue, filesep) || startsWith(pathValue, '\\') || ...
            (numel(pathValue) >= 2 && pathValue(2) == ':')
        value = pathValue;
    else
        value = fullfile(pwd, pathValue);
    end
end
end
