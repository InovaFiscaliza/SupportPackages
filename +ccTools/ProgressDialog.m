classdef ProgressDialog < handle

    properties (Access = private)
        %-----------------------------------------------------------------%
        hFigure
        jsBackDoor
    end


    properties
        %-----------------------------------------------------------------%
        Size         {mustBeA(Size,  {'char', 'string', 'double'})}                    = '40px'
        Color        {mustBeA(Color, {'char', 'string', 'double', 'single', 'uint8'})} = '#d95319'
        Visible char {mustBeMember(Visible, {'hidden', 'visible'})}                    = 'hidden'
    end


    properties (Constant)
        %-----------------------------------------------------------------%
        UUID = char(matlab.lang.internal.uuid())
        Type = 'ccTools.ProgressDialog'
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
            sendEventToHTMLSource(obj.jsBackDoor, "progressDialog", struct("Type",  "Creation", ...
                                                                           "UUID",  obj.UUID,   ...
                                                                           "Size",  obj.Size,   ...
                                                                           "Color", obj.Color));
            registerInstance(obj, 'onCreation')
        end


        %-----------------------------------------------------------------%
        function delete(obj)
            registerInstance(obj, 'onCleanup')
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
    end


    methods (Access = private)
        %-----------------------------------------------------------------%
        function registerInstance(obj, registerType)
            switch registerType
                case 'onCreation'
                    ccTools.Object.addRegister(obj.hFigure, obj)

                case 'onCleanup'
                    ccTools.Object.delRegister(obj.hFigure)
            end
        end


        %-----------------------------------------------------------------%
        function changeSize(obj)
            sendEventToHTMLSource(obj.jsBackDoor, "progressDialog", struct("Type",  "changeSize", ...
                                                                           "UUID",  obj.UUID,     ...
                                                                           "Size",  obj.Size));
        end


        %-----------------------------------------------------------------%
        function changeColor(obj)
            sendEventToHTMLSource(obj.jsBackDoor, "progressDialog", struct("Type",  "changeColor", ...
                                                                           "UUID",  obj.UUID,      ...
                                                                           "Color", obj.Color));
        end


        %-----------------------------------------------------------------%
        function changeVisibility(obj)
            sendEventToHTMLSource(obj.jsBackDoor, "progressDialog", struct("Type",       "changeVisibility", ...
                                                                           "UUID",       obj.UUID,           ...
                                                                           "Visibility", obj.Visible));
            drawnow
        end
    end
end