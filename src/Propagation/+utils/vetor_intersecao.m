function pontos_intersecao = vetor_intersecao(TX, RX, R)
% Retorna a matriz com os pontos geográficos onde o o segmento de reta 
% imaginario entre TX e RX intersecciona com os lados das celulas que
% compoem o raster
% pontos de intersecçao: matriz de pontos geograficos (lat/lon) em graus
%                        decimais
% TX: coordenada do transmissor
% RX: coordenada do receptor
%--------------------------------------------------------------------------

    %---------utils.intersecao_segmentos------------------------------------------------------------
    % Levanta as posições das células da matriz do raster que representam 
    % o TX e RX

    [TX_row, TX_col] = utils.get_raster_idx(TX.Latitude, TX.Longitude, R);

    [RX_row, RX_col] = utils.get_raster_idx(RX.Latitude, RX.Longitude, R);

    %---------------------------------------------------------------------
    % Cria vetores das colulas e linhas que compreende a região entre o TX
    % e o RX

    cols = TX_col:sign(RX_col - TX_col):RX_col;
    rows = TX_row:sign(RX_row - TX_row):RX_row;
    
    %---------------------------------------------------------------------
    % Incialixa a matriz de pontos que conterá os pontos de intersecção e 
    % o idx que representa o número de pontos de intersecção encontrados

    pts = zeros(numel(cols) + numel(rows), 2);
    idx = 0;

    %---------------------------------------------------------------------
    % Varre o vetor de colunas na região entre os pontos TX e RX
    % verificando se há intersecção com o segmento de reta imaginário TX-RX

    for n = cols
        %------------------------------------------------------------------
        % Carrega os pontos dos segmentos de reta TX-RX e o segmento que
        % representa o meridiano que limita a célula em análise

        longit = R.LongitudeLimits(1) + n * R.CellExtentInLongitude;
        P1Lon = longit;
        P2Lon = longit;
        P1Lat = R.LatitudeLimits(1);
        P2Lat = R.LatitudeLimits(2);
        %------------------------------------------------------------------
        % Analiza se há ou não intersecção

        ponto_intersecao = utils.intersecao_segmentos(...
            [TX.Longitude, TX.Latitude], [RX.Longitude, RX.Latitude],...
            [P1Lon, P1Lat], [P2Lon, P2Lat]);
        
        if ~isempty(ponto_intersecao)
            %--------------------------------------------------------------
            % havendo intersecção atualiza a matriz pts

            idx = idx + 1;
            pts(idx, :) = ponto_intersecao;

            %--------------------------------------------------------------
        end
        %------------------------------------------------------------------
       
    end
    %---------------------------------------------------------------------
    % Varre o vetor de linhas na região entre os pontos TX e RX
    % verificando se há intersecção com o segmento de reta imaginário TX-RX

    for m = rows
        %------------------------------------------------------------------
        % Carrega os pontos dos segmentos de reta TX-RX e o segmento que
        % representa o paralelo que limita a célula em análise

        latitu = R.LatitudeLimits(2) - m*R.CellExtentInLatitude;
        P1Lat = latitu;
        P2Lat = latitu;
        P1Lon = R.LongitudeLimits(1);
        P2Lon = R.LongitudeLimits(2);
        
        %------------------------------------------------------------------
        % Analiza se há ou não intersecção
        ponto_intersecao = utils.intersecao_segmentos...
            ([TX.Longitude, TX.Latitude],[RX.Longitude, RX.Latitude],...
            [P1Lon, P1Lat], [P2Lon, P2Lat]);

        if ~isempty(ponto_intersecao)
            %--------------------------------------------------------------
            % havendo intersecção atualiza a matriz pts
            idx = idx + 1;
            pts(idx, :) = ponto_intersecao;

        end
        %--------------------------------------------------------------

    end
    
    %------------------------------------------------------------------
    % Atualiza o vetor pontos_intersecao para retorno

    if idx == 0

        pontos_intersecao = [];

    else

        pontos_intersecao = pts(1:idx, :);

    end
    %------------------------------------------------------------------

end