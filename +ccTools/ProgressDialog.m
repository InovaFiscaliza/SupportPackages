classdef ProgressDialog < handle

    properties (Access = private)
        %-----------------------------------------------------------------%
        hFigure
        jsBackDoor
    end


    properties
        %-----------------------------------------------------------------%
        Size    = '40px'
        Color   = '#d95319'
        Visible = 'hidden'
    end


    properties (Constant)
        %-----------------------------------------------------------------%
        UUID    = char(matlab.lang.internal.uuid())
        Type    = 'ccTools.ProgressDialog'
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
            if ~strcmp(obj.Size, value)
                obj.Size = value;
                changeSize(obj)
            end
        end


        %-----------------------------------------------------------------%
        function set.Color(obj, value)
            if ~strcmp(obj.Color, value)
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