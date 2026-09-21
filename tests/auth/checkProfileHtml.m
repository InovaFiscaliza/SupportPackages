function uiFigure = checkProfileHtml
% checkProfileHtml Testa o componente profileAvatar.html sem autenticar.
%
% O harness envia ao uihtml os estados desconectado, conectado com inicial e
% conectado com foto. O nome fornece a primeira letra exibida no avatar.

mFilePath = fileparts(mfilename('fullpath'));
projectFolder = fileparts(fileparts(mFilePath));
profileHtmlPath = fullfile(projectFolder, 'src', 'Anatel', '+ws', '+auth', 'profileAvatar.html');

isConnected = false;
useProfilePicture = false;
profileName = 'Fabio Santos Lobao';
profilePictureBase64 = loadProfilePictureBase64();
blinkTimer = [];

uiFigure = uifigure('Name', 'Teste do profileAvatar.html', ...
                    'Position', [100, 100, 620, 220]);
uiFigure.CloseRequestFcn = @closeFigure;

mainLayout = uigridlayout(uiFigure, [4, 2]);
mainLayout.Padding = [12, 12, 12, 12];
mainLayout.RowSpacing = 8;
mainLayout.ColumnSpacing = 8;
mainLayout.RowHeight = {30, 30, 30, 30};
mainLayout.ColumnWidth = {'1x', 22};

connectionButton = uibutton(mainLayout, ...
                            'Text', 'conectar', ...
                            'ButtonPushedFcn', @toggleConnection);
connectionButton.Layout.Row = 1;
connectionButton.Layout.Column = 1;

avatarHTML = uihtml(mainLayout);
avatarHTML.HTMLEventReceivedFcn = @avatarEventReceived;
avatarHTML.HTMLSource = profileHtmlPath;
avatarHTML.Layout.Row = 1;
avatarHTML.Layout.Column = 2;

pictureButton = uibutton(mainLayout, ...
                         'Text', 'usar imagem', ...
                         'ButtonPushedFcn', @togglePicture);
pictureButton.Layout.Row = 2;
pictureButton.Layout.Column = 1;

nameField = uieditfield(mainLayout, 'text', ...
                          'Value', profileName, ...
                          'ValueChangedFcn', @nameChanged);
nameField.Layout.Row = 3;
nameField.Layout.Column = 1;

clickIndicator = uilabel(mainLayout, ...
                         'Text', 'Avatar Pressionado', ...
                         'HorizontalAlignment', 'left');
clickIndicator.Layout.Row = 4;
clickIndicator.Layout.Column = 1;
indicatorBackgroundColor = clickIndicator.BackgroundColor;

sendAvatarState()

    function nameChanged(source, ~)
        profileName = source.Value;
        sendAvatarState()
    end

    function toggleConnection(~, ~)
        isConnected = ~isConnected;
        if isConnected
            connectionButton.Text = 'desconectar';
        else
            connectionButton.Text = 'conectar';
        end
        sendAvatarState()
    end

    function togglePicture(~, ~)
        useProfilePicture = ~useProfilePicture;
        if useProfilePicture
            pictureButton.Text = 'usar Nome';
        else
            pictureButton.Text = 'usar imagem';
        end
        sendAvatarState()
    end

    function avatarEventReceived(~, event)
        eventName = "";
        if isprop(event, 'HTMLEventName')
            eventName = string(event.HTMLEventName);
        elseif isprop(event, 'EventName')
            eventName = string(event.EventName);
        end

        payload = [];
        if isprop(event, 'HTMLEventData')
            payload = event.HTMLEventData;
        elseif isprop(event, 'Data')
            payload = event.Data;
        end
        if ischar(payload) || (isstring(payload) && isscalar(payload))
            try
                payload = jsondecode(char(payload));
            catch
                payload = struct();
            end
        end
        if eventName == "profileAvatarClick"
            blinkIndicator()
            return
        end
        if ~isstruct(payload) || ~isfield(payload, 'type')
            return
        end

        eventType = "";
        if isstruct(payload) && isfield(payload, 'type')
            eventType = string(payload.type);
        end

        if eventType == "click"
            blinkIndicator()
            return
        end

        switch eventType
            case "ready"
                sendAvatarState()

            case "click"
                blinkIndicator()
        end
    end

    function blinkIndicator()
        if ~isempty(blinkTimer) && isvalid(blinkTimer)
            stop(blinkTimer)
            delete(blinkTimer)
        end

        clickIndicator.BackgroundColor = [0, 1, 0];
        drawnow limitrate
        blinkTimer = timer('ExecutionMode', 'singleShot', ...
                           'StartDelay', 1, ...
                           'TimerFcn', @restoreIndicator);
        start(blinkTimer)
    end

    function restoreIndicator(~, ~)
        if ~isempty(clickIndicator) && isvalid(clickIndicator)
            clickIndicator.BackgroundColor = indicatorBackgroundColor;
        end
        if ~isempty(blinkTimer) && isvalid(blinkTimer)
            delete(blinkTimer)
            blinkTimer = [];
        end
    end

    function closeFigure(source, ~)
        if ~isempty(blinkTimer) && isvalid(blinkTimer)
            stop(blinkTimer)
            delete(blinkTimer)
            blinkTimer = [];
        end
        if ~isempty(source) && isvalid(source)
            delete(source)
        end
    end

    function sendAvatarState()
        if isempty(avatarHTML) || ~isvalid(avatarHTML)
            return
        end

        initial = '?';
        if ischar(profileName) || isstring(profileName)
            trimmedName = strtrim(char(profileName));
            if ~isempty(trimmedName)
                initial = upper(trimmedName(1));
            end
        end

        state = struct('action', 'render', ...
                       'connected', isConnected, ...
                       'initial', initial, ...
                       'photoPngBase64', '');
        if isConnected && useProfilePicture
            state.photoPngBase64 = profilePictureBase64;
        end
        avatarHTML.Data = state;
    end

    function base64 = loadProfilePictureBase64()
        picturePath = fullfile(mFilePath, 'Profile-Picture.png');
        base64 = '';
        if ~isfile(picturePath)
            return
        end

        fileID = fopen(picturePath, 'rb');
        if fileID == -1
            return
        end
        fileCleanup = onCleanup(@() fclose(fileID));
        imageBytes = fread(fileID, [1, inf], '*uint8');
        base64 = char(matlab.net.base64encode(imageBytes));
    end
end
