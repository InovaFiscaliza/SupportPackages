function [M, O] = loadRaster(filename, convertToDouble)
% Carrega um arquivo raster GeoTiff e retorna a matriz de dados M e a
% GeographicCellsReference M

    arguments
        filename {mustBeFile}
        convertToDouble logical = false
    end

    [M, O] = readgeoraster(filename, "CoordinateSystemType", 'geographic');
    if isa(O, 'map.rasterref.GeographicPostingsReference')
        O = georefcells(O.LatitudeLimits, O.LongitudeLimits, O.RasterSize);
    end

    if convertToDouble
        M = double(M);
    end
    
end

