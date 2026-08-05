function Pwr_rx_csv = compara_HTZ(fileData, HTZData)
%--------------------------------------------------------------------------
% Compara resultados de predição obtidos pelo software HTZ da ATDI com os
% resultados da implementação no Matlab
%
% fileData: arquivo que contém a estrutura com parâmetros da predição
% HTZData: arquivo csv com a medidas exportadas do HTZ
%--------------------------------------------------------------------------
    
    run(fileData);

    modelo = dadosPredicao.modeloPredicao;

    % Dados da estação base
    base = txsite("Name", dadosPredicao.Base.Nome,...
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
    % Carrega CSV
    csv = readmatrix(HTZData);
    csv2 = csv( (csv(:, 1) > R.LongitudeLimits(1) & ...
        csv(:, 1) < R.LongitudeLimits(2) & ...
        csv(:, 2) > R.LatitudeLimits(1) & ...
        csv(:, 2) < R.LatitudeLimits(2)), :);

    %--------------------------------------------------------------------------
    % Cria variáveis de saída
    Pwr_rx_csv =  zeros(size(csv2, 1), 2);
    csv2 = csv( (csv(:, 1) > R.LongitudeLimits(1) & ...
        csv(:, 1) < R.LongitudeLimits(2) & ...
        csv(:, 2) > R.LatitudeLimits(1) & ...
        csv(:, 2) < R.LatitudeLimits(2)), :);
    
    %--------------------------------------------------------------------------
    % elevação da TX
    [n, m] = utils.get_raster_idx(base.Latitude, base.Longitude, R);
    elevBase = A(n, m);

    %--------------------------------------------------------------------------
    % Dados da estaçao RX
    RX = rxsite("Latitude",csv2(1, 2), ...
               "Longitude", csv2(1, 1), ...
               "AntennaHeight", dadosPredicao.Movel.Antena.Altura);
    %--------------------------------------------------------------------------
    % Inicializas a classe de predição conforme o modelo a ser utilizado
    switch modelo
        case 'Hata'
            predicao = model.Hata(base, RX, A, R, C, S);

        case 'P.1812'
           predicao = model.P1812(base, RX, A, R, C, S);

        otherwise
            error("Modelo não implementado");
    end

    %--------------------------------------------------------------------------
    % Cria barra de progresso
    d = uiprogressdlg(uifigure);
    
    %--------------------------------------------------------------------------
    % Loop de execução
    idx = numel(csv2(:, 1));

    for n = 1:idx
        percent_exec = n / idx;
        d.Message = sprintf('Executado: %.1f %%', (percent_exec * 100));
        d.Value = percent_exec;
        
        %----------------------------------------------------------------------
        % Carrega as coordenadas da ponto de comparação
        RX.Latitude = csv2(n, 2);
        RX.Longitude = csv2(n, 1);

        %------------------------------------------------------------------
        % encontra distancia, azimute e inclinação do ponto em relação a
        % estação TX
        [distanciaPonto, azimutePonto] = utils.Propagation.Distance(base, RX, "m");
        [x, y] = utils.get_raster_idx(RX.Latitude, RX.Longitude, R);
        inclinacaoPonto = rad2deg(atan(((RX.AntennaHeight + A(x, y)) - (base.AntennaHeight + elevBase)) / distanciaPonto));
        
        %------------------------------------------------------------------
        % extrai os dados de ganho na direção do ponto
        [gH, gV] = antenaBase.ganhoDirecao(azimutePonto, inclinacaoPonto);
        gAnt = antenaBase.Ganho - gH - gV;
        
        %------------------------------------------------------------------
        % calcula a atenuação e nível de sinal recebido
        predicao.siteRX = RX;
        predicao.calculo(gAnt);
        Pwr_rx_csv(n,1) = predicao.PRX;
        Pwr_rx_csv(n,2) = csv2(n, 4);
        %----------------------------------------------------------------------

    end

    %--------------------------------------------------------------------------
    % Cálculo do erro
    erro = sqrt((Pwr_rx_csv(:,2) - Pwr_rx_csv(:,1)).^2);
    erro_medio = sum(erro) / numel(erro);
    desvio = std(erro);
    
    fprintf("Erro médio quadrado:\t%1.f dB\n", erro_medio);
    fprintf("Desvio padrão do erro:\t%1.f dB\n", desvio);
    
    %--------------------------------------------------------------------------
    % Grafico predição comparada
    figure(1)
    title('Valores de E RX  - HTZ vs Matlab');
    plot(Pwr_rx_csv(:,2), 'b')
    hold on
    plot(Pwr_rx_csv(:,1), 'r')
    legend('HTZ', 'Matlab')
    hold off
    
    %--------------------------------------------------------------------------
    % Gráfico distribuição do erro
    figure(2)
    title('Distribuição do Erro - HTZ vs Matlab');
    histogram(erro)  

end

