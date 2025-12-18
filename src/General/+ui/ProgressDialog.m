classdef ProgressDialog < handle

    properties (Access = private)
        %-----------------------------------------------------------------%
        hFigure
        jsBackDoor
    end


    properties
        %-----------------------------------------------------------------%
        Size           {mustBeA(Size,  {'char', 'string', 'double'})}                    = '40px'
        Color          {mustBeA(Color, {'char', 'string', 'double', 'single', 'uint8'})} = '#d95319'
        Visible        {mustBeMember(Visible, {'hidden', 'visible'})}                    = 'hidden'
        VisibilityLock {mustBeMember(VisibilityLock, {'locked', 'unlocked'})}            = 'unlocked'
    end


    properties (Constant)
        %-----------------------------------------------------------------%
        UUID = char(matlab.lang.internal.uuid())
        Type = 'ui.ProgressDialog'
    end


    methods
        %-----------------------------------------------------------------%
        function obj = ProgressDialog(jsBackDoor)
            arguments
                jsBackDoor (1,1) matlab.ui.control.HTML
            end

            if ~isvalid(jsBackDoor)
                error('HTML component is not valid!')
            end
            
            obj.hFigure    = ancestor(jsBackDoor, 'figure');
            obj.jsBackDoor = jsBackDoor;
            sendEventToHTMLSource(obj.jsBackDoor, "progressDialog", struct("Type",  'Creation', ...
                                                                           "UUID",  obj.UUID,   ...
                                                                           "Size",  obj.Size,   ...
                                                                           "Color", obj.Color));
        end

        %-----------------------------------------------------------------%
        function set.Size(obj, value)
            if ~isequal(obj.Size, value)
                if isnumeric(value)
                    value = sprintf('%dpx', value);
                end

                obj.Size = value;
                changeSize(obj)
            end
        end

        %-----------------------------------------------------------------%
        function set.Color(obj, value)
            if ~isequal(obj.Color, value)
                if isnumeric(value)
                    value = rgb2hex(value);
                end

                obj.Color = value;
                changeColor(obj)
            end
        end

        %-----------------------------------------------------------------%
        function set.Visible(obj, value)
            if ~strcmp(obj.Visible, value)
                obj.Visible = value;
                changeVisibility(obj)
            end
        end

        %-----------------------------------------------------------------%
        function requestVisibilityChange(obj, visibilityValue, visibilityCallerRole)
            if strcmp(obj.VisibilityLock, 'locked') && strcmp(visibilityCallerRole, 'unlocked')
                return
            elseif ~strcmp(obj.VisibilityLock, visibilityCallerRole)
                obj.VisibilityLock = visibilityCallerRole;
            end
            
            obj.Visible = visibilityValue;            
        end
    end


    methods (Access = private)
        %-----------------------------------------------------------------%
        function changeSize(obj)
            sendEventToHTMLSource(obj.jsBackDoor, "progressDialog", struct("Type",  'changeSize', ...
                                                                           "UUID",  obj.UUID,     ...
                                                                           "Size",  obj.Size));
        end

        %-----------------------------------------------------------------%
        function changeColor(obj)
            sendEventToHTMLSource(obj.jsBackDoor, "progressDialog", struct("Type",  'changeColor', ...
                                                                           "UUID",  obj.UUID,      ...
                                                                           "Color", obj.Color));
        end

        %-----------------------------------------------------------------%
        function changeVisibility(obj)
            if strcmp(obj.VisibilityLock, 'locked') && strcmp(obj.Visible, 'hidden')
                obj.VisibilityLock = 'unlocked';
            end

            sendEventToHTMLSource(obj.jsBackDoor, "progressDialog", struct("Type",       'changeVisibility', ...
                                                                           "UUID",       obj.UUID,           ...
                                                                           "Visibility", obj.Visible));
            drawnow
        end
    end
end