function varargout = checkCNPJOrCPF(entityID, searchType)

    arguments
        entityID   (1,:) char
        searchType       char {mustBeMember(searchType, {'NumberValidation', 'PublicAPI'})} = 'NumberValidation'
    end
    
    entityIDNumber = regexprep(entityID, '\D', '');
    switch numel(entityIDNumber)
        case 11
            digitType = 'CPF';
        case 14
            digitType = 'CNPJ';
        otherwise
            error('Consulta limitada ao CNPJ ou CPF')
    end
    
    [isValid, entityID] = isValidCNPJOrCPF(entityIDNumber, digitType);
    
    if ~isValid
        error('CNPJ ou CPF inválido')
    end
    
    switch searchType
        case 'NumberValidation'
            varargout  = {entityID};
            
        case 'PublicAPI'
            if strcmp(digitType, 'CPF')
                error('Consulta limitada ao CNPJ')
            end
    
            entityInfo = webread(sprintf('https://www.receitaws.com.br/v1/cnpj/%s', entityIDNumber), weboptions('ContentType', 'json'));
            if strcmp(entityInfo.status, 'ERROR')
                error(entityInfo.message)
            end
    
            varargout  = {entityInfo};
    end
end

%-------------------------------------------------------------------------%
function [isValid, entityID] = isValidCNPJOrCPF(entityIDNumber, digitType)
    arrayCNPJOrCPF = arrayfun(@(x) str2double(x), entityIDNumber);
    
    digit1Value    = CheckDigit(arrayCNPJOrCPF(1:end-2), ArrayWeights(digitType, 1));
    digit2Value    = CheckDigit(arrayCNPJOrCPF(1:end-1), ArrayWeights(digitType, 2));
    
    if isequal(arrayCNPJOrCPF(end-1:end), [digit1Value, digit2Value])
        isValid  = true;
        switch digitType
            case 'CNPJ'
                entityID = sprintf('%s.%s.%s/%s-%s', entityIDNumber(1:2), entityIDNumber(3:5), entityIDNumber(6:8), entityIDNumber(9:12), entityIDNumber(13:14));
            case 'CPF'
                entityID = sprintf('%s.%s.%s-%s',    entityIDNumber(1:3), entityIDNumber(4:6), entityIDNumber(7:9), entityIDNumber(10:11));
        end
    else
        isValid  = false;
        entityID = '';
    end
end

%-------------------------------------------------------------------------%
function arrayWeights = ArrayWeights(digitType, digitPosition)
    arguments
        digitType     char   {mustBeMember(digitType, {'CNPJ', 'CPF'})}
        digitPosition double {mustBeMember(digitPosition, [1, 2])}
    end

    switch digitType
        case 'CNPJ'
            arrayWeights = [4+digitPosition:-1:2, 9:-1:2];
        case 'CPF'
            arrayWeights = 9+digitPosition:-1:2;
    end
end

%-------------------------------------------------------------------------%
function checkDigit = CheckDigit(arrayCNPJOrCPF, arrayWeights)
    sumOfElements = sum(arrayCNPJOrCPF .* arrayWeights);
    remainderDiv  = mod(sumOfElements, 11);

    if remainderDiv < 2
        checkDigit = 0;
    else
        checkDigit = 11 - remainderDiv;
    end
end