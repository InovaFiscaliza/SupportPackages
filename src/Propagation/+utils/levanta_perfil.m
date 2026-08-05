function [distancias, elevacoes, clutter] = levanta_perfil(TX, RX, A, R, C, S)
    %----------------------------------------------------------------------
    % Funçao que levanta o perfil do enlace TX e RX
    % distancias:       array de distancias entre os pontos de alteraçao da
    % elevaçao no terreno e o TX em km
    % elevacoes:        array do perfil de elevaçoes do terreno em m
    % TX:               classe txsite
    % RX:               classe rxsite
    % A, R:             matriz de elevações A e struct de atributos do georaster
    % C, S:             matriz de clutter C e struct de atributos do georaster
    % vetor_intersec:   array de pontos de intersecção (lat, lon) entre o segmento de
    % reta definido pelas coordenadas de TX e de RX com os meridianos e
    % paralelos que limitam os tiles do geroraster
    % distancias:       array ordenado de distancias entre os pontos de
    % transição das elevações do terreno e o ponto TX em km
    % elevacoes:        perfil de elevações do terreno em m
    
    
    %----------------------------------------------------------------------
    % inicializa as variaáveis

    distancias = [];
    elevacoes = [];
    clutter = [];
    
    %----------------------------------------------------------------------
    % calcula o array de intersecções
    
    vetor_intersec = utils.vetor_intersecao(TX, RX, R);

    %----------------------------------------------------------------------
    
    if ~isempty(vetor_intersec)
        
        %------------------------------------------------------------------
        % levanta o perfil do terreno removendo as ambiguidades

        [distancias, elevacoes, clutter] = utils.analisa_perfil(TX, vetor_intersec, A, R, C, S);
        
        %------------------------------------------------------------------
        % Preenche as posições iniciais e finais dos arrays distancias,
        % elevacoes e clutter

        [n, m] = utils.get_raster_idx(RX.Latitude, RX.Longitude, R);
        elevsiteRX = A(n, m);

        distanciaRX = utils.Propagation.Distance(TX, RX, 'km');

        [n, m] = utils.get_raster_idx(RX.Latitude, RX.Longitude, S);
        clutterRX = C(n,m);

        [n, m] = utils.get_raster_idx(TX.Latitude, TX.Longitude, R);
        elevsiteTX = A(n, m);
        
        [n, m] = utils.get_raster_idx(TX.Latitude, TX.Longitude, S);
        clutterTX = C(n, m);

        distancias = [0, distancias, distanciaRX];
        elevacoes = [elevsiteTX, elevacoes, elevsiteRX];
        clutter = [clutterTX, clutter, clutterRX];
    
    end

    %----------------------------------------------------------------------
end