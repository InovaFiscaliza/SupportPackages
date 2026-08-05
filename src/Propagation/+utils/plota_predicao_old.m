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
%run(fileData);

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
    figure('Name', 'Predição de Cobertura', 'NumberTitle', 'off');
    axesm('MapProjection','mercator','MapLatLimit',R.LatitudeLimits+[-1 1])
    geoshow(Z, R, DisplayType="texturemap", Parent=axesHandle)
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
    % % [latGrid, lonGrid] = geographicGrid(R);
    % % lat = latGrid(:);
    % % lon = lonGrid(:);
    % % val = Z(:);
    % %
    % % geoscatter(axesHandle, lat, lon, 20, val, 'filled');
    % % geoplot3(axesHandle, base.Latitude, base.Longitude, elevBase, 'ko', 'MarkerFaceColor', 'c', 'MarkerSize', 15);
    % %georastershow(axesHandle, Z, R);
    Z(isinf(Z)) = nan;
    alfa = 0.4;
    [latGrid, lonGrid] = meshgrid( ...
        linspace(R.LatitudeLimits(1), R.LatitudeLimits(2), size(Z,1)), ...
        linspace(R.LongitudeLimits(1), R.LongitudeLimits(2), size(Z,2)));
    latGrid = latGrid';
    lonGrid = lonGrid';
    %
    % %------------------------------------------------------------------
    % % Definição dos intervalos de agrupamento das medidas
    % limiares = min(min(Z)) : 7 : max(max(Z));
    % nn = length(limiares);
    %
    % %------------------------------------------------------------------
    % % Definição do colormap
    % coresRGB = turbo(nn);
    % coresCell = mat2cell(coresRGB, ones(1, nn), 3);
    %
    % %------------------------------------------------------------------
    % % Apaga os plots existente
    % cla(axesHandle);
    %
    % %------------------------------------------------------------------
    % % Criação das formas dos contornos das medidas
    %
    % for i = 1:nn
    %     limiar = limiares(i);
    %
    %     %--------------------------------------------------------------
    %     % Máscara da área com sinal maior ou igual ao limiar
    %     mascara = Z >= limiar;
    %
    %     %--------------------------------------------------------------
    %     % Remover áreas já plotadas por limiares mais altos
    %     if i < nn - 1
    %         mascara = mascara & Z < limiares(i+2);
    %     end
    %
    %     %--------------------------------------------------------------
    %     % Encontrar contornos das regiões conectadas
    %     B = bwboundaries(mascara);
    %
    %     for k = 1:length(B)
    %         contorno = B{k};
    %         row = contorno(:,1);
    %         col = contorno(:,2);
    %
    %         %----------------------------------------------------------
    %         % Coordenadas geográficas
    %         lat = latGrid(sub2ind(size(latGrid), row, col));
    %         lon = lonGrid(sub2ind(size(lonGrid), row, col));
    %
    %         %----------------------------------------------------------
    %         % Criar e plotar polígono
    %         try
    %             shp = geopolyshape(lat, lon);
    %             geoplot(axesHandle, shp, ...
    %                 'FaceColor', coresCell{i}, ...
    %                 'FaceAlpha', alfa, ...
    %                 'EdgeColor', 'none', ...
    %                 'LineWidth', 0.01);
    %         catch
    %             continue
    %         end
    %
    %     end
    % end
    %
    % %----------------------------------------------------------------------
    % % Centralizar o mapa
    %
    % lat_span = max(latGrid(:)) - min(latGrid(:));
    % lon_span = max(lonGrid(:)) - min(lonGrid(:));
    % margin = 0.05;
    % geolimits(axesHandle, ...
    %     [min(latGrid(:)) - margin * lat_span, max(latGrid(:)) + margin * lat_span], ...
    %     [min(lonGrid(:)) - margin * lon_span, max(lonGrid(:)) + margin * lon_span]);
    %
    % %----------------------------------------------------------------------
    % % Criar legenda
    % legendas = strings(1, nn -2);
    % patchHandles = gobjects(1, nn -2);
    % for i = 1:nn -2
    %     patchHandles(i) = geoplot(axesHandle, NaN, NaN, ...
    %         'square', 'MarkerFaceColor', coresCell{i}, ...
    %         'MarkerEdgeColor', 'none');
    %     legendas(i) = sprintf('%.0f a %.0f dBm', limiares(i), limiares(i+2));
    % end
    %
    % legend(axesHandle, patchHandles, legendas, ...
    %     'Location', 'northeast', 'Orientation', 'vertical', 'Box', 'on', ...
    %     'TextColor', 'w', 'FontSize', 8, 'Color', [0.25,0.25,0.25], 'NumColumns', 1);

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
end

end

