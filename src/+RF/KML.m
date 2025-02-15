classdef KML < handle

    properties
        %-----------------------------------------------------------------%
        File
        TempFile
        LayerNames = {}
        GeoTable
    end


    methods
        %-----------------------------------------------------------------%
        function obj = KML(fileName)
            [~, ~, fileExt] = fileparts(fileName);
            switch lower(fileExt)
                case '.kml'
                    kmlFile = fileName;

                case '.kmz'                    
                    tempDir = tempname;
                    if ~isfolder(tempDir)
                        mkdir(tempDir)
                    end
                    
                    tempFile = unzip(fileName, tempDir);
                    tempFile = tempFile(endsWith(tempFile, '.kml', 'IgnoreCase', true));
                    if isempty(tempFile)
                        error('auxApp:drivetest:KML:read:KMLFileNotFound', 'KML file not found')
                    end

                    kmlFile = tempFile{1};

                otherwise
                    error('auxApp:drivetest:KML:read:UnexpectedFileFormat', 'Unexpected file format')
            end

            obj.File = fileName;
            obj.TempFile = kmlFile;

            getLayerNames(obj, kmlFile)
        end

        %-----------------------------------------------------------------%
        function readgeotable(obj, LayerName)
            arguments
                obj
                LayerName char {mustBeTextScalar} = ''
            end

            if isempty(LayerName)
                LayerName = obj.LayerNames{1};
            end
            obj.GeoTable = readgeotable(obj.TempFile, 'CoordinateSystemType', 'geographic', 'Layer', LayerName);
        end
    end


    methods (Access = private)
        %-----------------------------------------------------------------%
        function getLayerNames(obj, kmlFile)
            obj.LayerNames = map.internal.io.getLayerNames(kmlFile)';
        end
    end
end