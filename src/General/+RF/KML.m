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
        function obj = KML(fileFullName)
            [~, ~, fileExt] = fileparts(fileFullName);
            switch lower(fileExt)
                case '.kml'
                    kmlFile = fileFullName;

                case '.kmz'                    
                    tempDir = tempname;
                    if ~isfolder(tempDir)
                        mkdir(tempDir)
                    end
                    
                    tempFile = unzip(fileFullName, tempDir);
                    tempFile = tempFile(endsWith(tempFile, '.kml', 'IgnoreCase', true));
                    if isempty(tempFile)
                        error('RF:KML:FileNotFound', 'KML file not found')
                    end

                    kmlFile = tempFile{1};

                otherwise
                    error('RF:KML:UnexpectedFileFormat', 'Unexpected file format "%s"', fileExt)
            end

            obj.File = fileFullName;
            obj.TempFile = kmlFile;

            getLayerNames(obj, kmlFile)
        end

        %-----------------------------------------------------------------%
        function readgeotable(obj, layerName)
            arguments
                obj
                layerName char {mustBeTextScalar} = ''
            end

            if isempty(layerName)
                layerName = obj.LayerNames{1};
            end
            obj.GeoTable = readgeotable(obj.TempFile, 'CoordinateSystemType', 'geographic', 'Layer', layerName);
        end
    end


    methods (Access = private)
        %-----------------------------------------------------------------%
        function getLayerNames(obj, kmlFile)
            obj.LayerNames = map.internal.io.getLayerNames(kmlFile)';
        end
    end


    methods (Static = true)
        %-----------------------------------------------------------------%
        function [status, errorMsg] = generateKML(fileName, fileType, measTable, varargin)
            arguments
                fileName
                fileType {mustBeMember(fileType, {'measures', 'route'})}
                measTable
            end

            arguments (Repeating)
                varargin
            end
        
            status = true;
            errorMsg = '';
            
            try    
                switch fileType
                    case 'measures'
                        measValueColumnName = varargin{1};
                        measPlotHandle = varargin{2};

                        description  = arrayfun(@(x,y) sprintf('%s\n%.1f V/m', x, y), measTable.Timestamp, measTable.(measValueColumnName), 'UniformOutput', false);
                        geoTableMeas = table2geotable(measTable);
                        rgbMapping   = imageUtil.getRGB(measPlotHandle);
                        kmlwrite(fileName, geoTableMeas, 'Name', string(1:height(geoTableMeas))', 'Description', description, 'Color', rgbMapping)
            
                    case 'route'
                        description  = sprintf('%s - %s', char(measTable.Timestamp(1)), char(measTable.Timestamp(end)));
                        kmlwriteline(fileName, measTable.Latitude, measTable.Longitude, 'Name', 'Route', 'Description', description', 'Color', 'red', 'LineWidth', 3)
                end
        
            catch ME
                status = false;
                errorMsg = ME.message;
            end
        end
    end
end