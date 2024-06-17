function CNPJ = checkCNPJ(entityID)

    entityID = regexprep(entityID, '\D', '');
    if numel(entityID) == 14
        CNPJ = webread(sprintf('https://www.receitaws.com.br/v1/cnpj/%s', entityID), weboptions('ContentType', 'json'));
        if strcmp(CNPJ.status, 'ERROR')
            error(CNPJ.message)
        end
        
    else
        error('Consulta limitada ao número do CNPJ.')
    end

end