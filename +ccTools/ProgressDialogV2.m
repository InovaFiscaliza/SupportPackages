classdef ProgressDialogV2 < handle

    properties
        %-----------------------------------------------------------------%
        jsBackDoor
        Size    = '40px'
        Color   = '#d95319' % '#d95319' (appColeta)
        Visible = 'hidden'
    end


    properties (Constant)
        %-----------------------------------------------------------------%
        UUID    = char(matlab.lang.internal.uuid())
    end


    methods
        %-----------------------------------------------------------------%
        function obj = ProgressDialogV2(jsBackDoor)
            obj.jsBackDoor = jsBackDoor;
            
            sendEventToHTMLSource(obj.jsBackDoor, "progressDialog", struct("Type",  "Creation", ...
                                                                           "UUID",  obj.UUID,   ...
                                                                           "Size",  obj.Size,   ...
                                                                           "Color", obj.Color));
        end


        %-----------------------------------------------------------------%
        function set.Size(obj, value)
            obj.Size = value;
            changeSize(obj)
        end


        %-----------------------------------------------------------------%
        function set.Color(obj, value)
            obj.Color = value;
            changeColor(obj)
        end


        %-----------------------------------------------------------------%
        function set.Visible(obj, value)
            obj.Visible = value;
            changeVisibility(obj)
        end
    end


    methods (Access = private)
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