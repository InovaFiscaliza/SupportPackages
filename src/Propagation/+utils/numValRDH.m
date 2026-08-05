function numVal = numValRDH(catVal)
% Verifica se o argumento do tipo categorical é diferente de -1. Se for retorna o valor double, senão retorna 0. 
%   numVal: catVal convertido para double
%   catVal: variável a ser convertida

    numVal = str2double(string(catVal));
    if numVal == -1
        numVal = 0;
    end
  
end

