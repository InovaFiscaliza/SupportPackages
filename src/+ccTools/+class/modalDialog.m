classdef modalDialog

    properties
        type
        webWin
        parentTag
        dataTag
        onCreation
        onCleanup
        rootPath
    end

    methods
        function obj = modalDialog(type, webWin, parentTag, dataTag, jsCodeOnCreation, jsCodeOnCleanup, rootPath)
            obj.type       = type;
            obj.webWin     = webWin;
            obj.parentTag  = parentTag;
            obj.dataTag    = dataTag;
            obj.onCreation = jsCodeOnCreation;
            obj.onCleanup  = jsCodeOnCleanup;
            obj.rootPath   = rootPath;

            creation(obj)
            backgroundColorConfig(obj)
        end

        function deleteAll(obj)
            jsCmd = sprintf(fileread(fullfile(obj.rootPath, 'css&js', 'modalDialog_DeleteAll.js')), obj.type);
            obj.webWin.executeJS(jsCmd);
        end

        function delete(obj)
            if ~isempty(obj.onCleanup)
                obj.webWin.executeJS(obj.onCleanup);
            end

            backgroundColorConfig(obj)
        end
    end

    methods (Access = protected)
        function creation(obj)
            obj.webWin.executeJS(obj.onCreation);
        end

        function backgroundColorConfig(obj)
            color = ccTools.fcn.defaultBackgroundColor();
            jsCmd = sprintf(fileread(fullfile(obj.rootPath, 'css&js', 'modalDialog_BackgroundColor.js')), obj.type, color, color, color);
            obj.webWin.executeJS(jsCmd);
        end
    end
end