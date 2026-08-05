function plot_perfil(fileData, latRX, lonRX, axesHandle)
%----------------------------------------------------------------------
% Traça o grafico do perfil do terreno, posiçao das estaçoes, linha de
% visada e primeira zona de Fresnel
%
% TX: classe TX
% RX: classe RX
% A, R: geotiff elevação
% C, S: geotiff clutter
%----------------------------------------------------------------------
% validação dos argumentos

arguments
    fileData
    latRX double
    lonRX double
    axesHandle = []
end

if ~isstruct(fileData)
    if isfile(fileData)
        %----------------------------------------------------------------------
        %Carrega os parâmetros utilizados para realizar a predição
        run(fileData)
    else
        return
    end
else
    dadosPredicao = fileData;
end

if isempty(dadosPredicao)
    return
else

    %----------------------------------------------------------------------
    % Carrega o modelo de predição a ser empregado
    modelo = dadosPredicao.modeloPredicao;

    %----------------------------------------------------------------------
    % Dados da estação TX
    TX = txsite("Name", dadosPredicao.Base.Nome,...
        "Latitude", dadosPredicao.Base.Latitude,...
        "Longitude", dadosPredicao.Base.Longitude,...
        "Antenna", dadosPredicao.Base.Antena.Tipo,...
        "AntennaHeight", dadosPredicao.Base.Antena.Altura,...
        "TransmitterFrequency", dadosPredicao.frequencia,...
        "TransmitterPower", dadosPredicao.Base.Potencia);


    % Carrega os dados da antena
    antenaBase = utils.readAntennaData(dadosPredicao.Base.Antena.ArquivoDados, dadosPredicao.Base.Antena.Modelo,...
        dadosPredicao.Base.Antena.Funcao, dadosPredicao.Base.Antena.Azimute, dadosPredicao.Base.Antena.tiltMecanico);

    %----------------------------------------------------------------------
    % Caracteristicas da area
    % Carrega dados do relevo
    [A, R] = utils.loadRaster(dadosPredicao.dadosRelevo, true);

    %--------------------------------------------------------------------------
    % Carrega dados do clutter, se não houver arqivo de clutter uma matriz
    % default com representação área aberta/rural
    if ~isempty(dadosPredicao.dadosClutter)

        [C, S] = utils.read_clutter(dadosPredicao.dadosClutter);

    else

        C = 2 * ones(size(A));
        S = R;

    end


    %--------------------------------------------------------------------------
    % Dados da estaçao RX
    RX = rxsite("Latitude",latRX, ...
        "Longitude", lonRX, ...
        "AntennaHeight", dadosPredicao.Movel.Antena.Altura);


    %---------------------------------------------------------------------
    %levanta o perfil das elevações e clutter do terreno
    [distancias, elevacoes, clutter ] = utils.levanta_perfil(TX, RX, A, R, C, S);
    elevTX = elevacoes(1);
    elevRX = elevacoes(end);

    %----------------------------------------------------------------------
    % utiliza apenas região limitada pela mínima e máxima elevações
    min_elevacao = min(elevacoes);
    distancias_km = distancias * 1000;

    %-----------------------------------------------------------------------b
    % cálculo do elipsoide da primeira zona de Fresnel
    % F: vetor raio do elipsoide
    % Fl: limite inferior do elipsoide em relação a linha de visada
    % Fu: limite superior do elipsoide em relação a linha de visada

    lambda = physconst("LightSpeed") / TX.TransmitterFrequency;
    alt_visada = linspace(TX.AntennaHeight, RX.AntennaHeight, numel(distancias_km));
    F = sqrt(lambda * distancias_km.* ...
        (distancias_km(end) - distancias_km) / (distancias_km(end)));

    Fl = ((elevacoes(end) + RX.AntennaHeight - elevTX)/...
        distancias_km(end)) * distancias_km + (elevTX + alt_visada) - F;

    Fu = ((elevacoes(end) + RX.AntennaHeight - elevTX)/...
        distancias_km(end)) * distancias_km + (elevTX + alt_visada) + F;

    alturas_clutter = clutter;

    %----------------------------------------------------------------------
    % cálculo da intensidade campo recebida ao longo dos enlace
    num_pts = 500;
    distancias_enlace = linspace(0, distancias(end), num_pts);
    latitudes_enlace = linspace(TX.Latitude, RX.Latitude, num_pts);
    longitudes_enlace = linspace(TX.Longitude, RX.Longitude, num_pts);
    E_enlace = zeros(1, num_pts);
    RX_enlace = RX;

    %--------------------------------------------------------------------------

    switch modelo
        case 'Hata'
            predicao = model.Hata(TX, RX_enlace, A, R, C, S);

        case 'P.1812'
            predicao = model.P1812(TX, RX_enlace, A, R, C, S);

            %--------------------------------------------------------------
            % calcula o array de alturas adicional conforme a classificação
            % de clutter REC P1812.7 seção 3.2.1, tabela 2
            alturas_clutter(ismember(alturas_clutter, [1 2])) = 0;
            alturas_clutter(alturas_clutter == 3) = 10;
            alturas_clutter(alturas_clutter == 4) = 15;
            alturas_clutter(alturas_clutter == 5) = 20;


        case 'P.526'
            predicao = model.P526(TX, RX_enlace, A, R, C, S);

        otherwise
            error("Modelo não implementado");
    end

    %----------------------------------------------------------------------
    % loop de varredura no pontos do enlace
    for idx = 2:num_ptsantenaBase.Ganho

        %----------------------------------------------------------------------
        % Carrega as coordenadas da ponto de comparação
        RX_enlace.Latitude = latitudes_enlace(idx);
        RX_enlace.Longitude = longitudes_enlace(idx);

        %------------------------------------------------------------------
        % encontra distancia, azimute e inclinação do ponto em relação a
        % estação TX
        [distanciaPonto, azimutePonto] = utils.Propagation.Distance(TX, RX_enlace, "m");
        [x, y] = utils.get_raster_idx(RX_enlace.Latitude, RX_enlace.Longitude, R);
        inclinacaoPonto = rad2deg(atan(((RX_enlace.AntennaHeight + A(x, y)) - (TX.AntennaHeight + elevTX)) / distanciaPonto));

        %------------------------------------------------------------------
        % extrai os dados de ganho na direção do ponto
        [gH, gV] = ganhoDirecao(antenaBase, azimutePonto, inclinacaoPonto);
        gAnt = antenaBase.Ganho - gH - gV;

        %----------------------------------------------------------------------
        % Executa o modelo de predição
        predicao.siteRX = RX_enlace;
        calculo(predicao, gAnt);
        E_enlace(idx) = predicao.PRX;

    end

    %----------------------------------------------------------------------
    % Calculo da antenuação no espaço livre TX-RX
    FSL = utils.Propagation.PathLoss(TX, RX, "Free space");

    %----------------------------------------------------------------------
    % Cálculo da antenuação total do enlace
    Atn = predicao.Lb;

    %----------------------------------------------------------------------
    % Definições da área do gráfico

    if isempty(axesHandle)
        figure('Units', 'centimeters', 'Position', [1 1 60 7])
        ax = axes();
        hold on;
    else
        ax = axesHandle;
    end
     yyaxis(ax, "right")
     cla(ax);
     yyaxis(ax, "left")
     cla(ax)


    ax.View = [0,90];
    ylabel(ax, 'Elevações (m)');
    xlabel(ax, 'distância (Km)');
    ylim(ax, [min(min_elevacao, min(Fl)) inf])
    xlim(ax,[distancias(1) distancias(end)])

    %----------------------------------------------------------------------
    % mapeia os valores de clutter com cores representativas

    cores = [hex2rgb('#007cff'); hex2rgb('#0bdc0b'); hex2rgb('#ff7f7f'); hex2rgb('#4fae00'); hex2rgb('#b3263e')];


    %----------------------------------------------------------------------
    % Plot do clutter

    for n = 1:(numel(distancias) - 1)
        cor = ceil(clutter(n));
        if cor > size(cores, 1)
            cor = size(cores, 1);
        end
        if cor == 0
            cor = 1;
        end

        fill(ax, [distancias(n) distancias(n) distancias(n+1) distancias(n+1)],...
            [elevacoes(n)  (elevacoes(n) + alturas_clutter(n)) ...
            (elevacoes(n) + alturas_clutter(n)) elevacoes(n)], ...
            cores(cor,:), 'EdgeColor', 'none');
    end

    %----------------------------------------------------------------------
    % Plot do perfil de elevações
    area(ax, distancias, elevacoes, 'FaceColor', '#90a2b5', 'EdgeColor', '#101010', 'basevalue', min(min_elevacao, min(Fl)));



    %----------------------------------------------------------------------
    % desenha a linha de visada
    plot(ax, [distancias(1) distancias(end)], [(elevTX + TX.AntennaHeight) ...
        (elevRX + RX.AntennaHeight)], 'Color', '#00f9ff');

    %----------------------------------------------------------------------
    % desenha os limites da primeira zona de Fresnel
    plot(ax, distancias, Fl,'-.', 'Color', '#007cff');
    plot(ax, distancias, Fu,'-.', 'Color', '#007cff');

    yyaxis(ax, "right")

    %----------------------------------------------------------------------
    % desenha o grafico de campo E recebido
 
    ylim(ax, [0 (1.5 * max(E_enlace))]);
    %plot(ax, distancias_enlace, E_enlace, 'Color', '#00ff88');
    plot(ax, distancias_enlace, E_enlace, 'Color', [0.8510, 0.3255, 0.0980]);

    hold off;

    %----------------------------------------------------------------------
    % Informações da simulação
    footNotePosition = 0;
    footNoteAlign = 'left';
    Footnote = sprintf([ ...
        "\n\n\n\\bfDados da simulação: modelo %s\n" + ...
        "\\bfTX:\nAltitude: %.1f m\nCoord: %.5f %.5f\n" + ...
        "Frequência: %.1f MHz\n" + ...
        "Potência: %.1f W\n" + ...
        "Antena: %.1f m\n" + ...
        "\tGanho: %.1f dBi\n" + ...
        "\tMáxima potência irradiada: %.1f dBW\n" + ...
        "\tAzimute: %.1f°\t/ tilt: %.1f°\n\n" + ...
        "\\bfRX:\nAltitude: %.1f m\nCoor: %.5f %.5f\n" + ...
        "Antena: %.1f m\n" + ...
        "Nível de sinal recebido: %.1f dBm\n\n" + ...
        "\\bfEnlace:\nDistância: %.1f Km\n" + ...
        "Ângulos: V: %.2f° H: %.2f°\n" + ...
        "Padrão de atenuação da antena: V: %.2f dB H: %.2f dB\n" + ...
        "Atenuação no espaço livre: %.1f dB - Atenuação total: %.1f dB\n" + ...
        "Atenuação do modelo: %.1f dB\n" ...
        ], ...
        modelo, ...
        elevTX, TX.Longitude, TX.Latitude, ...
        TX.TransmitterFrequency/1e6, ...
        TX.TransmitterPower, ...
        TX.AntennaHeight, ...
        antenaBase.Ganho, ...
        (10*log10(TX.TransmitterPower) + antenaBase.Ganho), ...
        dadosPredicao.Base.Antena.Azimute, dadosPredicao.Base.Antena.tiltMecanico, ...
        elevRX, RX.Latitude, RX.Longitude, ...
        RX.AntennaHeight, ...
        E_enlace(end), ...
        distancias(end), ...
        inclinacaoPonto, azimutePonto, ...
        gV, gH, ...
        FSL, Atn, ...
        (Atn - FSL + gAnt) ...
        );
    text(ax, footNotePosition,2, Footnote, Units='normalized', FontSize=12, Interpreter='tex', HorizontalAlignment=footNoteAlign, VerticalAlignment='top', PickableParts='none', Tag='Footnote');


end

