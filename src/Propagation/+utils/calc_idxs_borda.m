function borda = calc_idxs_borda(tx_m, tx_n, raio)
% Calcula os indices das células que formam o circulo de raio r em torno da
% estação
% tx_m: linha da matriz onde se localiza a estação
% tx_n: coluna da matriz onde se localiza a estação
% raio: número de células da estação até a borda do círculo 
%
%--------------------------------------------------------------------------
    % Inicializa a matriz de pontos da borda
    
    borda = []; 
    
    %----------------------------------------------------------------------
    % Percorre os valores de x dentro do círculo
    
    for x = (tx_m - raio):(tx_m + raio) 
        %------------------------------------------------------------------
        % Calcula o termo da equação do círculo

        delta = raio^2 - (x - tx_m)^2; 
        
        %------------------------------------------------------------------
        % Calcula o deslocamento de y

        if delta >= 0
            y_offset = round(sqrt(delta)); 
           
            %--------------------------------------------------------------
            % Adiciona os pontos na borda do círculo

            borda = [borda; x, tx_n + y_offset]; % Parte superior
            borda = [borda; x, tx_n - y_offset]; % Parte inferior
            
        end
        %------------------------------------------------------------------

    end
    
    %----------------------------------------------------------------------
    %remove as linhas em duplicidade
    
    borda = unique(borda, "rows");
end

