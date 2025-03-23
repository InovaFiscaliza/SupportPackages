classdef (Abstract) Object

    methods (Static = true)
        %-----------------------------------------------------------------%
        function addRegister(hFig, hObj)
           global ccToolsObjects

            if ~isa(ccToolsObjects, 'dictionary')
                ccToolsObjects = dictionary;
            end
            ccToolsObjects = ccToolsObjects.insert(hFig, hObj);
        end


        %-----------------------------------------------------------------%
        function delRegister(hFig)
            global ccToolsObjects

            if isa(ccToolsObjects, 'dictionary') && isKey(ccToolsObjects, hFig)
                ccToolsObjects = ccToolsObjects.remove(hFig);
            end
        end


        %-----------------------------------------------------------------%
        function hObj = findobj(hFig)
            global ccToolsObjects

            hObj = [];
            if isa(ccToolsObjects, 'dictionary') && isKey(ccToolsObjects, hFig) && isvalid(ccToolsObjects(hFig))
                hObj = ccToolsObjects(hFig);
            end
        end
    end
end