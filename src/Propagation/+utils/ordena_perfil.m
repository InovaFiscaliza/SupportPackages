function [perfilOrdenado] = ordena_perfil(distancia, elevacao, clutter)
% Recebe arrays de distancia, elevação e clutter com n elementos e devolve 
% uma matriz (3,n) com os perfis ordenados

    perfil = [distancia; elevacao; clutter];
    [~, indice] = sort(perfil(1,:));
    perfilOrdenado = perfil(:, indice);
end

