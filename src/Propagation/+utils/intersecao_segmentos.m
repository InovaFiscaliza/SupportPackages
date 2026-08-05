function [ponto_intersecao] = intersecao_segmentos(p1, p2, p3, p4)
    
    % Parâmetros:
    % p1, p2: Pontos iniciais e finais do segmento 1 (x1, y1), (x2, y2)
    % p3, p4: Pontos iniciais e finais do segmento 2 (x3, y3), (x4, y4)
    
    %----------------------------------------------------------------------
    % Calcula coeficientes da equação linear
    denom = (p1(1) - p2(1)) * (p3(2) - p4(2)) - (p1(2) - p2(2)) * (p3(1) - p4(1));
    
    %----------------------------------------------------------------------
    % Se os segmentos são paralelos
    if denom == 0

        ponto_intersecao = [];

        return; 

    end
    %----------------------------------------------------------------------
    % Calcula os coeficientes da forma paramétrica do segmento
    
    t = ((p1(1) - p3(1)) * (p3(2) - p4(2)) - (p1(2) - p3(2)) * (p3(1) - p4(1))) / denom;
    u = -((p1(1) - p2(1)) * (p1(2) - p3(2)) - (p1(2) - p2(2)) * (p1(1) - p3(1))) / denom;


    %----------------------------------------------------------------------
    % Verifica se o ponto de intersecção está dentro dos segmentos
    if t >= 0 && t <= 1 && u >= 0 && u <= 1

        ponto_intersecao = [p1(1) + t * (p2(1) - p1(1)), p1(2) + t * (p2(2) - p1(2))];

    else

        ponto_intersecao = []; % Não há intersecção dentro dos segmentos

    end
    %----------------------------------------------------------------------
    
end