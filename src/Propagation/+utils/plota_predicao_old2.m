function plota_predicao(dadosPredicao, Z, tipoZ, axesHandle)
%----------------------------------------------------------------------
% Plota o mapa da mancha de prediçao
%   fileData: arquivo que contém a estrutura com parâmetros da predição
%   Z: dados de atenuação ou sinal recebido
%   tipoZ: nome variável que Z representa, p.ex: Atenuação
%----------------------------------------------------------------------
arguments
    dadosPredicao struct {mustBeNonempty}
    Z (:, :) double
    tipoZ string
    axesHandle = []
end

dir_app = fileparts(mfilename('fullpath'));


%----------------------------------------------------------------------
% Carrega os parâmetros utilizados para realizar a predição

modelo = dadosPredicao.modeloPredicao;

%----------------------------------------------------------------------
% Dados da estação base
base = txsite("Name", dadosPredicao.Base.Nome,...
    "Latitude", dadosPredicao.Base.Latitude,...
    "Longitude", dadosPredicao.Base.Longitude,...
    "Antenna", dadosPredicao.Base.Antena.Tipo,...
    "AntennaHeight", dadosPredicao.Base.Antena.Altura,...
    "TransmitterFrequency", dadosPredicao.frequencia,...
    "TransmitterPower", dadosPredicao.Base.Potencia);

%----------------------------------------------------------------------
% Caracteristicas da area
% Carrega dados do relevo
arquivoRelevo = dadosPredicao.dadosRelevo;
if ~isfile(arquivoRelevo)
    arquivoRelevo = fullfile(dir_app, '..', '..', dadosPredicao.dadosRelevo);
end
[A, R] = utils.loadRaster(arquivoRelevo, true);
[A, R] = utils.resizeGeotiff(A, R);

%--------------------------------------------------------------------------
% elevação da estação Base
[n, m] = utils.get_raster_idx(base.Latitude, base.Longitude, R);
elevBase = A(n, m);

if isempty(axesHandle)
    f = uifigure('Name', 'Predição de Cobertura', 'NumberTitle', 'off');
    ax = uiaxes(f);
    util.axesm(ax, 'MapProjection','mercator','MapLatLimit',R.LatitudeLimits+[-1 1] )
    geoshow(Z, R, DisplayType="texturemap");%, Parent=axesHandle)
    geoshow(base.Latitude, base.Longitude, DisplayType="point", ZData=elevBase, MarkerEdgeColor="k", MarkerFaceColor="c", MarkerSize=10, Marker="o")
    title (sprintf('Dados de Cobertura (%s) da estação %s\nModelo: %s', tipoZ, dadosPredicao.Base.Nome, modelo));

    if tipoZ == "Nível de sinal"
        colormap('turbo')
    else

        % cria um colormap do branco->amarelo->vermelho
        cmap = zeros(256, 3);
        cmap(1:128, 1:2) = repmat([1 1], 128, 1);
        cmap(1:128, 3) = linspace(0.8, 0, 128);
        cmap(129:end, 1) = 1;
        cmap(129:end, 2) = linspace(1, 0, 128);

        colormap(cmap)
    end
    colorbar

    text1 = dadosPredicao.Base.Nome;
    delta = 0.0025;
    %textm(base.Latitude+delta,base.Longitude+delta,text1)
    cb = colorbar;
    cb.Label.String = tipoZ;

else
    Z(isinf(Z)) = nan;
    alfa = 0.4;
    [latGrid, lonGrid] = meshgrid( ...
        linspace(R.LatitudeLimits(1), R.LatitudeLimits(2), size(Z,1)), ...
        linspace(R.LongitudeLimits(1), R.LongitudeLimits(2), size(Z,2)));
    latGrid = latGrid';
    lonGrid = lonGrid';

    cla(axesHandle);
    atualBasemap = axesHandle.Basemap;
    
    if (strcmp(atualBasemap,'PredicaoPropagRF')) 
        geobasemap(axesHandle,'satellite')
    end
    
    pasta = fileparts(mfilename('fullpath'));
    pastaCache = fullfile(pasta, '..', '..', 'cache');
    arquivosCache = dir (fullfile(pastaCache, '*.mbtiles'));

    if (size({arquivosCache.name}, 2) > 0)
        [~,ultimoArquivo, ~] = fileparts(fullfile(pastaCache, arquivosCache(end).name));
        ultimoArquivo = str2double(ultimoArquivo);
        if ultimoArquivo < 9
            string1 = '0';
        else
            string1 = '';
        end

        arquivoTile = strcat(string1, num2str(ultimoArquivo + 1));
    else
        arquivoTile = '01';
    end
    arquivoTile = fullfile(pastaCache, strcat(arquivoTile, '.mbtiles'));


    margin = -0.01;
    lat_span = max(latGrid(:)) - min(latGrid(:));
    lon_span = max(lonGrid(:)) - min(lonGrid(:));
    geolimits(axesHandle, ...
        [min(latGrid(:)) - margin * lat_span, max(latGrid(:)) + margin * lat_span], ...
        [min(lonGrid(:)) - margin * lon_span, max(lonGrid(:)) + margin * lon_span]);
    pause(2);
    exportgraphics(axesHandle, fullfile(pastaCache, 'mapa_satelite.tif'));

    geoData = Z;
    geoData(isnan(geoData)) = -999999;
    mask = geoData ~= -999999;
    vmin = min(min(geoData(mask)));
    vmax = max(max(geoData(mask)));
    geoDataClamped = min(max(geoData, vmin), vmax);
    geoDataNorm = (geoDataClamped - vmin) / (vmax - vmin);
    nColors = 256;
    cmap = turbo(nColors);
    idx = round(geoDataNorm * (nColors - 1)) + 1;
    idx(~mask) = 1;
    geoDataRGB = ind2rgb(idx, cmap);
    geotiffwrite(fullfile(pastaCache, 'ultimapredicao.tif'), geoDataRGB, R);


    imgBase = imread(fullfile(pastaCache, 'mapa_satelite.tif'));
    geoResized = imresize(geoDataRGB, [size(imgBase,1), size(imgBase,2)]);
    imgBase = im2double(imgBase);
    fused_img = (1 - alfa) * imgBase + alfa * geoResized;
    R_fused = R;
    R_fused.RasterSize = [size(imgBase, 1), size(imgBase, 2)];
    geotiffwrite(fullfile(pastaCache, 'fused_basemap.tif'), im2uint8(fused_img), R_fused);
    
    switch version('-release')
        case ["2024b", "2025b"]
                writeRasterMBTiles(arquivoTile, im2uint8(fused_img), R_fused);

       otherwise
            % comandos no gdal
            path_gdal = fullfile('\', 'OSGeo4W', 'bin');
            gdal_translate = fullfile(path_gdal, 'gdal_translate');
            cmd = sprintf('"%s" "%s" "%s" -of MBTILES', gdal_translate, (fullfile(pastaCache, 'fused_basemap.tif')),  arquivoTile);
            system(cmd);
            gdaladdo = fullfile(path_gdal, 'gdaladdo');
            cmd = sprintf('"%s" -r average "%s"', gdaladdo, arquivoTile);
            system(cmd);
    end
    
    removeCustomBasemap PredicaoPropagRF
    addCustomBasemap('PredicaoPropagRF', arquivoTile, 'Attribution', 'Anatel')
    geobasemap(axesHandle, 'PredicaoPropagRF')
    txPlot = geoscatter(axesHandle, base.Latitude, base.Longitude, 80, 'w^', 'filled');
    dtt = txPlot.DataTipTemplate;
    linha_nome = dataTipTextRow('Nome:', {base.Name});
    linha_lat = dataTipTextRow('Lat:', {round(base.Latitude, 4)});
    linha_lon = dataTipTextRow('Lon:', {round(base.Longitude, 4)});
    dtt.DataTipRows = [linha_nome, linha_lat, linha_lon];

    %geoplot3(axesHandle, base.Latitude, base.Longitude, elevBase, 'co', 'MarkerSize', 5);
end

end

