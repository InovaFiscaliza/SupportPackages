classdef ProfilePanel < handle

    % PROFILEPANEL Reusable floating panel that displays a user profile.
    %
    % The panel is anchored below a caller-supplied UI component (typically
    % the profile avatar) and shows a fixed set of profile fields. It does
    % not know how authentication works: the sign-out control only invokes
    % SignOutFcn, which the caller uses to discard its session.
    %
    %   panel = ui.ProfilePanel(parentContainer, ...
    %       'Anchor', avatarComponent, ...
    %       'SignOutFcn', @() session.logout());
    %   panel.toggle(profile)

    properties
        SignOutFcn = []
    end

    properties (SetAccess = private)
        Anchor
    end

    properties (Access = private)
        UIFigure
        Dialog
        TitleLabel
        CloseImage
        SignOutImage
        ValueLabels = {}
        OriginalWindowButtonDownFcn = []
        IsDeleting (1,1) logical = false
    end

    properties (Constant, Access = private)
        % {display label, profile field}
        Fields = {'Nome',        'NA_USER_NAME';
                  'e-mail',      'NA_USER_EMAIL';
                  'Lotação',     'NA_DEPARTMENT';
                  'Cargo',       'NA_JOB_TITLE';
                  'Localização', 'NA_LOCATION';
                  'Papel',       'NA_ROLE'}
        PanelWidth = 360
        RowHeight = 22
        RowSpacing = 4
        HeaderHeight = 20
        FooterHeight = 20
        OuterSpacing = 6
        Padding = [12, 8, 12, 8]
    end


    methods
        %-----------------------------------------------------------------%
        function obj = ProfilePanel(parentContainer, options)
            arguments
                parentContainer
                options.Anchor = []
                options.SignOutFcn = []
            end

            obj.UIFigure = findFigure(parentContainer);
            if isempty(obj.UIFigure) || ~isvalid(obj.UIFigure)
                error('ui:ProfilePanel:invalidParent', ...
                      'The parent container must belong to a valid figure.')
            end
            obj.Anchor = options.Anchor;
            obj.SignOutFcn = options.SignOutFcn;

            obj.createComponents()

            obj.OriginalWindowButtonDownFcn = obj.UIFigure.WindowButtonDownFcn;
            obj.UIFigure.WindowButtonDownFcn = @(source, event) obj.onFigureButtonDown(source, event);
        end

        %-----------------------------------------------------------------%
        function delete(obj)
            if obj.IsDeleting
                return
            end
            obj.IsDeleting = true;

            if ~isempty(obj.Dialog) && isvalid(obj.Dialog)
                delete(obj.Dialog)
            end
            if ~isempty(obj.UIFigure) && isvalid(obj.UIFigure)
                obj.UIFigure.WindowButtonDownFcn = obj.OriginalWindowButtonDownFcn;
            end
        end

        %-----------------------------------------------------------------%
        function show(obj, profile)
            % SHOW Fill the fields from PROFILE and display the panel.
            if nargin > 1
                obj.update(profile)
            end
            obj.positionDialog()
            obj.Dialog.Visible = 'on';
            uistack(obj.Dialog, 'top')
        end

        %-----------------------------------------------------------------%
        function hide(obj)
            if ~isempty(obj.Dialog) && isvalid(obj.Dialog)
                obj.Dialog.Visible = 'off';
            end
        end

        %-----------------------------------------------------------------%
        function toggle(obj, profile)
            if obj.isVisible()
                obj.hide()
            else
                obj.show(profile)
            end
        end

        %-----------------------------------------------------------------%
        function tf = isVisible(obj)
            tf = ~isempty(obj.Dialog) && isvalid(obj.Dialog) && ...
                 strcmp(obj.Dialog.Visible, 'on');
        end

        %-----------------------------------------------------------------%
        function update(obj, profile)
            % UPDATE Refresh the displayed values without changing visibility.
            for fieldIndex = 1:size(obj.Fields, 1)
                value = profileField(profile, obj.Fields{fieldIndex, 2});
                if isempty(strtrim(value))
                    value = '-';
                end
                obj.ValueLabels{fieldIndex}.Text = value;
                obj.ValueLabels{fieldIndex}.Tooltip = value;
            end
        end
    end


    methods (Access = private)
        %-----------------------------------------------------------------%
        function createComponents(obj)
            backgroundColor = obj.UIFigure.Color;
            obj.Dialog = uipanel(obj.UIFigure, ...
                                 'Title', '', ...
                                 'Visible', 'off', ...
                                 'Units', 'pixels', ...
                                 'BorderType', 'line', ...
                                 'BackgroundColor', backgroundColor);

            fieldCount = size(obj.Fields, 1);
            outerLayout = uigridlayout(obj.Dialog, [3, 1]);
            outerLayout.Padding = obj.Padding;
            outerLayout.RowSpacing = obj.OuterSpacing;
            outerLayout.RowHeight = {obj.HeaderHeight, obj.bodyHeight(), obj.FooterHeight};
            outerLayout.BackgroundColor = backgroundColor;

            headerLayout = uigridlayout(outerLayout, [1, 2]);
            headerLayout.Padding = [0, 0, 0, 0];
            headerLayout.ColumnWidth = {'1x', 16};
            headerLayout.RowHeight = {'1x'};
            headerLayout.BackgroundColor = backgroundColor;
            obj.TitleLabel = uilabel(headerLayout, ...
                                     'Text', 'Perfil', ...
                                     'FontWeight', 'bold', ...
                                     'HorizontalAlignment', 'left', ...
                                     'VerticalAlignment', 'center');
            obj.CloseImage = uiimage(headerLayout, ...
                                     'ImageSource', iconPath('close-16px-red.svg'), ...
                                     'Tooltip', 'Fechar', ...
                                     'ImageClickedFcn', @(~, ~) obj.hide());

            bodyLayout = uigridlayout(outerLayout, [fieldCount, 2]);
            bodyLayout.Padding = [0, 0, 0, 0];
            bodyLayout.RowSpacing = obj.RowSpacing;
            bodyLayout.ColumnWidth = {90, '1x'};
            bodyLayout.RowHeight = repmat({obj.RowHeight}, 1, fieldCount);
            bodyLayout.BackgroundColor = backgroundColor;
            obj.ValueLabels = cell(1, fieldCount);
            for fieldIndex = 1:fieldCount
                keyLabel = uilabel(bodyLayout, ...
                                   'Text', obj.Fields{fieldIndex, 1}, ...
                                   'FontWeight', 'bold', ...
                                   'HorizontalAlignment', 'left');
                keyLabel.Layout.Row = fieldIndex;
                keyLabel.Layout.Column = 1;

                valueLabel = uilabel(bodyLayout, ...
                                     'Text', '-', ...
                                     'HorizontalAlignment', 'left');
                valueLabel.Layout.Row = fieldIndex;
                valueLabel.Layout.Column = 2;
                obj.ValueLabels{fieldIndex} = valueLabel;
            end

            footerLayout = uigridlayout(outerLayout, [1, 2]);
            footerLayout.Padding = [0, 0, 0, 0];
            footerLayout.ColumnWidth = {'1x', obj.FooterHeight};
            footerLayout.RowHeight = {'1x'};
            footerLayout.BackgroundColor = backgroundColor;
            obj.SignOutImage = uiimage(footerLayout, ...
                                       'ImageSource', iconPath('sign-out.svg'), ...
                                       'Tooltip', 'Desconectar', ...
                                       'ImageClickedFcn', @(~, ~) obj.onSignOut());
            obj.SignOutImage.Layout.Row = 1;
            obj.SignOutImage.Layout.Column = 2;
        end

        %-----------------------------------------------------------------%
        function value = bodyHeight(obj)
            fieldCount = size(obj.Fields, 1);
            value = fieldCount * obj.RowHeight + (fieldCount - 1) * obj.RowSpacing;
        end

        %-----------------------------------------------------------------%
        function positionDialog(obj)
            panelHeight = obj.Padding(2) + obj.Padding(4) + obj.HeaderHeight + ...
                          obj.bodyHeight() + obj.FooterHeight + 2 * obj.OuterSpacing;
            panelWidth = obj.PanelWidth;
            figureSize = obj.UIFigure.Position(3:4);

            if isempty(obj.Anchor) || ~isvalid(obj.Anchor)
                anchorPosition = [figureSize(1) - 8, figureSize(2) - 8, 0, 0];
            else
                drawnow limitrate
                anchorPosition = getpixelposition(obj.Anchor, true);
            end

            panelX = min(max(8, anchorPosition(1) + anchorPosition(3) - panelWidth), ...
                         max(8, figureSize(1) - panelWidth - 8));
            panelY = anchorPosition(2) - panelHeight - 4;
            if panelY < 8
                panelY = anchorPosition(2) + anchorPosition(4) + 4;
            end
            obj.Dialog.Position = [panelX, panelY, panelWidth, panelHeight];
        end

        %-----------------------------------------------------------------%
        function onSignOut(obj)
            obj.hide()
            invokeCallback(obj.SignOutFcn)
        end

        %-----------------------------------------------------------------%
        function onFigureButtonDown(obj, source, event)
            if obj.isVisible()
                point = obj.UIFigure.CurrentPoint;
                % Clicks on the anchor are left to its own toggle handler.
                if ~isInside(point, obj.Dialog.Position) && ~obj.isInsideAnchor(point)
                    obj.hide()
                end
            end
            invokeCallback(obj.OriginalWindowButtonDownFcn, source, event)
        end

        %-----------------------------------------------------------------%
        function tf = isInsideAnchor(obj, point)
            tf = ~isempty(obj.Anchor) && isvalid(obj.Anchor) && ...
                 isInside(point, getpixelposition(obj.Anchor, true));
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
function sourcePath = iconPath(iconName)
generalFolder = fileparts(fileparts(mfilename('fullpath')));
sourcePath = fullfile(generalFolder, 'icons', iconName);
if ~isfile(sourcePath)
    error('ui:ProfilePanel:iconNotFound', ...
          'Could not find the profile icon at "%s".', sourcePath)
end
end

%-----------------------------------------------------------------%
function tf = isInside(point, position)
tf = point(1) >= position(1) && point(1) <= position(1) + position(3) && ...
     point(2) >= position(2) && point(2) <= position(2) + position(4);
end

%-----------------------------------------------------------------%
function value = profileField(profile, fieldName)
value = '';
if ~isstruct(profile) || ~isscalar(profile)
    return
end
fields = fieldnames(profile);
fieldIndex = find(strcmpi(fields, fieldName), 1);
if isempty(fieldIndex)
    return
end
value = valueText(profile.(fields{fieldIndex}));
end

%-----------------------------------------------------------------%
function text = valueText(value)
if ischar(value)
    text = value;
elseif isstring(value) && isscalar(value)
    text = char(value);
elseif (isnumeric(value) || islogical(value)) && isscalar(value)
    text = char(string(value));
elseif isstruct(value) || iscell(value) || isnumeric(value) || islogical(value)
    text = char(jsonencode(value));
else
    text = char(string(value));
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
