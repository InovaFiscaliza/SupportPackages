function [RX_comparar] = csv_compara_resultado (R, Pwr_rx, fator)
% Seleciona pontos da predição do matlab para serem comparados com o HTZ
% 
% R: Coleção de atributos do geotiff do relevo que foi processado
% Pwr_rx: Matriz de dados de potência recebida estimada em dBm
% fator: denominador da taxa de amostragem de pontos
%
%--------------------------------------------------------------------------
    % inicializa as variaáveis

    RX_comparar = [];

    %----------------------------------------------------------------------
    % Seleciona os pontos de comparação de acordo com a taxa de amostragem

    for n = 1 : size(Pwr_rx, 1)
    
        for m = 1 : size(Pwr_rx , 2)
        
            if ~(mod(n, fator) || mod(m, fator))
                lat = R.LatitudeLimits(1) + (n + .5) * R.CellExtentInLatitude;
                lon = R.LongitudeLimits(1) + (m + .5) * R.CellExtentInLongitude;
                RX_comparar = [RX_comparar; lat lon Pwr_rx(n, m)];
            end
        
        end
    
    end
    %----------------------------------------------------------------------
    
end
    