function numVal = numValRDH(catVal)
% Verifica se o argumento do tipo categorical é diferente de -1 (inválido). 
% Se for retorna o valor double, senão retorna 0. 

    strVal = replace(string(catVal), ',', '.');
    strVal = regexprep(strVal, '[^0-9.-]', '');
    numVal = str2double(strVal);
    if numVal == -1
        numVal = 0;
    end
  
end