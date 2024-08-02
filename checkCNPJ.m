function [CNPJ, nCNPJ] = checkCNPJ(entityID, apiFlag)

arguments
    entityID (1,:) char
    apiFlag  (1,1) logical = true
end

    nCNPJ = regexprep(entityID, '\D', '');
    if numel(nCNPJ) == 14
        % Verifica se os digitos verificadores estão corretos.
        if ~isValidCNPJ(nCNPJ)
            error('CNPJ inválido.')
        end

        % Consulta em base disponibilizada na internet.
        if apiFlag
            CNPJ = webread(sprintf('https://www.receitaws.com.br/v1/cnpj/%s', nCNPJ), weboptions('ContentType', 'json'));
            if strcmp(CNPJ.status, 'ERROR')
                error(CNPJ.message)
            end
        else
            CNPJ = struct('cnpj', sprintf('%s.%s.%s/%s-%s', nCNPJ(1:2), nCNPJ(3:5), nCNPJ(6:8), nCNPJ(9:12), nCNPJ(13:14)));
        end
        
    else
        error('Consulta limitada ao número do CNPJ.')
    end
end


%-------------------------------------------------------------------------%
function isValid = isValidCNPJ(entityID)
    arrayCNPJ   = arrayfun(@(x) str2double(x), entityID);
    
    checkDigit1 = CheckDigit(arrayCNPJ(1:12), [5 4 3 2 9 8 7 6 5 4 3 2]);
    checkDigit2 = CheckDigit(arrayCNPJ(1:13), [6 5 4 3 2 9 8 7 6 5 4 3 2]);
    
    if isequal(arrayCNPJ(13:14), [checkDigit1, checkDigit2])
        isValid = true;
    else
        isValid = false;
    end
end


%-------------------------------------------------------------------------%
function checkDigit = CheckDigit(arrayCNPJ, arrayWeights)
    sumOfElements = sum(arrayCNPJ .* arrayWeights);
    remainderDiv  = mod(sumOfElements, 11);

    if remainderDiv < 2
        checkDigit = 0;
    else
        checkDigit = 11 - remainderDiv;
    end
end