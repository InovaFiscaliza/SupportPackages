function [n, m] = get_raster_idx(lat, lon, R)
% recebe a latitude ou longitude e retorna a linha ou coluna da 
% matriz do raster
% idx: linha ou coluna
% coord: latitude ou longitude em graus decimais
% limit: latitude ou longitude mínima do tile do raster
% delta: a extenção da célula do raster na dimensão em questão
% maxdim: número de colunas da matriz do raster na dimensão
%----------------------------------------------------------------------
    n = ceil((R.LatitudeLimits(2) - lat)/...
        R.CellExtentInLatitude);

    m = ceil((lon - R.LongitudeLimits(1))/...
        R.CellExtentInLongitude);

    %----------------------------------------------------------------------
    % ajusta os limites inferior e superior
    if n < 1

        n = 1;

    elseif n > R.RasterSize(1)

        n = R.RasterSize(1);
        
    end

    if m < 1

        m = 1;

    elseif m > R.RasterSize(2)

        m = R.RasterSize(2);
        
    end

    %----------------------------------------------------------------------

end