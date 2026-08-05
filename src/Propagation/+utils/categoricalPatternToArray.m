function dataArray = categoricalPatternToArray(catInput)
% categoricalPatternToArray - Converte um categorical do tipo {'key': value, ...}
%                            para um array numérico Nx2
%
% USO:
%   dataArray = categoricalPatternToArray(mln.AntennaPattern);
%
% ENTRADA:
%   catInput - variável do tipo categorical contendo string única no formato
%              {'chave1': valor1, 'chave2': valor2, ...}
%
% SAÍDA:
%   dataArray - matriz Nx2 com [chave valor] como números

    % Garantir que é string
    str = string(catInput);
    
    % Extrair o conteúdo entre { e }
    str = extractBetween(str, '{', '}');
    if isempty(str)
        error('Formato inválido: não contém colchetes {}');
    end
    str = str{1};

    % Separar os pares 'key': value
    pairs = split(str, ',');
    n = numel(pairs);
    dataArray = zeros(n, 2);

    % Extrair chave e valor
    for i = 1:n
        kv = split(pairs{i}, ':');
        key = str2double(strrep(strtrim(kv{1}), '''', ''));
        val = str2double(strtrim(kv{2}));
        dataArray(i, :) = [key, val];
    end

    % Ordenar pelas chaves (opcional)
    dataArray = sortrows(dataArray, 1);
end