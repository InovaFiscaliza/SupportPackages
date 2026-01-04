function [entityId, status, details] = checkCNPJOrCPF(entityId, searchType)
    arguments
        entityId   (1,:) char
        searchType char {mustBeMember(searchType, {'NumberValidation', 'PublicAPI'})} = 'NumberValidation'
    end

    status  = false;
    details = '';

    try    
        entityIDNumber = regexprep(entityId, '\D', '');
        switch numel(entityIDNumber)
            case 11
                digitType = 'CPF';
            case 14
                digitType = 'CNPJ';
            otherwise
                error('UnexpectedNumberOfElements')
        end
        
        entityId = isValidCNPJOrCPF(entityIDNumber, digitType);
        status   = ~isempty(entityId);
    
        if strcmp(searchType, 'PublicAPI') && strcmp(digitType, 'CNPJ') && status
            rawDetails = webread(sprintf('https://www.receitaws.com.br/v1/cnpj/%s', entityIDNumber), weboptions('ContentType', 'json'));
            if isfield(rawDetails, 'status') && ~strcmp(rawDetails.status, 'ERROR')
                details = rawDetails;
            end
        end
    catch
    end
end

%-------------------------------------------------------------------------%
function entityId = isValidCNPJOrCPF(entityIDNumber, digitType)
    arrayCNPJOrCPF = arrayfun(@(x) str2double(x), entityIDNumber);
    
    digit1Value    = CheckDigit(arrayCNPJOrCPF(1:end-2), ArrayWeights(digitType, 1));
    digit2Value    = CheckDigit(arrayCNPJOrCPF(1:end-1), ArrayWeights(digitType, 2));

    if ~isequal(arrayCNPJOrCPF(end-1:end), [digit1Value, digit2Value])
        error('UnexpectedDigitValues')
    end

    switch digitType
        case 'CPF'
            entityId = sprintf('%s.%s.%s-%s',    entityIDNumber(1:3), entityIDNumber(4:6), entityIDNumber(7:9), entityIDNumber(10:11));
        case 'CNPJ'
            entityId = sprintf('%s.%s.%s/%s-%s', entityIDNumber(1:2), entityIDNumber(3:5), entityIDNumber(6:8), entityIDNumber(9:12), entityIDNumber(13:14));
    end
end

%-------------------------------------------------------------------------%
function arrayWeights = ArrayWeights(digitType, digitPosition)
    arguments
        digitType     char   {mustBeMember(digitType, {'CNPJ', 'CPF'})}
        digitPosition double {mustBeMember(digitPosition, [1, 2])}
    end

    switch digitType
        case 'CPF'
            arrayWeights = 9+digitPosition:-1:2;
        case 'CNPJ'
            arrayWeights = [4+digitPosition:-1:2, 9:-1:2];
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