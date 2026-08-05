function exporta_prx2csv(arquivo, matriz)
% Salva dados de predição para compação com o HTZ no formato CSV
% arquivo: nome do arquivo csv de saída
% matriz: matriz de dados estimados recepção no formato compativel com HTZ
%--------------------------------------------------------------------------

    fid = fopen(arquivo, 'w');

    %----------------------------------------------------------------------
    % varre a matriz e salva em formato ponto decimal com 6 casas de
    % precisão

    for i = 1:size(matriz, 1)
    
        fprintf(fid, '%.6f,%.6f,%.4f\n', matriz(i,:));
    
    end
    %----------------------------------------------------------------------

    fclose(fid);
    
end