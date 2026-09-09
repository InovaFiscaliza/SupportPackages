function reexibe_predicao(axesHandle, nomeBasemap)
%----------------------------------------------------------------------
% Plota novamente o mapa da mancha de prediçao
%----------------------------------------------------------------------
arguments
    axesHandle
    nomeBasemap string
end

cla(axesHandle);
alfa = 0.4;
geobasemap(axesHandle,nomeBasemap)

pasta = fileparts(mfilename('fullpath'));
pastaCache = fullfile(pasta, '..', '..', 'cache');

%----------------------------------------------------------------------
% Recupera a última predição realizada
[geoDataRGB, R]  = readgeoraster(fullfile(pastaCache, 'ultimapredicao.tif'));

%----------------------------------------------------------------------
% Calclula os limites da área de exibição
margin = -0.01;
lat_span = max(R.LatitudeLimits) - min(R.LatitudeLimits);
lon_span = max(R.LongitudeLimits) - min(R.LongitudeLimits);


%----------------------------------------------------------------------
% define o nome do arquivo mbtile como o próximo arquivo sequencial do
% diretório  cache
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

%----------------------------------------------------------------------
% centraliza o mapa na tela
geolimits(axesHandle, ...
    [min(R.LatitudeLimits) - margin * lat_span,  max(R.LatitudeLimits) + margin * lat_span], ...
    [min(R.LongitudeLimits) - margin * lon_span, max(R.LongitudeLimits) + margin * lon_span]);
pause(2);

%----------------------------------------------------------------------
% exporta o basemap para um arquivo na pasta cache
exportgraphics(axesHandle, fullfile(pastaCache, 'mapa_satelite.tif'));


%----------------------------------------------------------------------
% funde o basemap com a figura da predição
imgBase = imread(fullfile(pastaCache, 'mapa_satelite.tif'));
geoResized = imresize(geoDataRGB, [size(imgBase,1), size(imgBase,2)]);
imgBase = im2double(imgBase);
fused_img = (1 - alfa) * imgBase + alfa * geoResized;
R_fused = R;
R_fused.RasterSize = [size(imgBase, 1), size(imgBase, 2)];
geotiffwrite(fullfile(pastaCache, 'fused_basemap.tif'), im2uint8(fused_img), R_fused);

% comandos no gdal
path_gdal = fullfile('\', 'OSGeo4W', 'bin');
gdal_translate = fullfile(path_gdal, 'gdal_translate');
cmd = sprintf('"%s" "%s" "%s" -of MBTILES', gdal_translate, (fullfile(pastaCache, 'fused_basemap.tif')),  arquivoTile);
system(cmd);
gdaladdo = fullfile(path_gdal, 'gdaladdo');
cmd = sprintf('"%s" -r average "%s"', gdaladdo, arquivoTile);
system(cmd);

removeCustomBasemap PredicaoPropagRF
addCustomBasemap('PredicaoPropagRF', arquivoTile, 'Attribution', 'Anatel')
geobasemap(axesHandle, 'PredicaoPropagRF')

end

