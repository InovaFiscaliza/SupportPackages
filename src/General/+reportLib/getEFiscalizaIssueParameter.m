function fieldValue = getEFiscalizaIssueParameter(reportInfo, fieldName, varargin)
    arguments
        reportInfo
        fieldName {mustBeMember(fieldName, {'Informação Bruta', ...
                                            'Solicitação de Inspeção', ...
                                            'Ação de Inspeção', ...
                                            'Atividade de Inspeção', ...
                                            'Nome do Demandante', ...
                                            'Nome da Unidade Executante', ...
                                            'Sede da Unidade Executante', ...
                                            'Período Previsto da Fiscalização', ...
                                            'Lista de Entidades', ...
                                            'Lista de Serviços', ...
                                            'Lista de Fiscais'})}
    end

    arguments (Repeating)
        varargin
    end

    fieldValue = '';
    
    projectData = reportInfo.Project;
    context = reportInfo.Context;
    generalSettings = reportInfo.Settings;

    issueDetails = getOrFetchIssueDetails(projectData, projectData.modules.(context).ui.system, projectData.modules.(context).ui.issue, reportInfo.App.eFiscalizaObj);

    if ~isempty(issueDetails)
        fieldSubName = {};
        if ~isempty(varargin)
            fieldSubName = varargin{1};
        end

        switch fieldName
            case 'Informação Bruta'
                fieldValue = jsonencode(issueDetails);

            case 'Solicitação de Inspeção'
                switch fieldSubName
                    case {'id', 'codigo', 'descricao', 'status', 'entidades', 'servicos'}
                        fieldValue = issueDetails.issueContext.solicitacao.(fieldSubName);
                    case {'inicio', 'fim'}
                        fieldValue = issueDetails.issueContext.solicitacao.periodo.(fieldSubName);
                    case {'demandante', 'paaf'}
                        fieldValue = issueDetails.issueContext.solicitacao.origem.(fieldSubName);
                    case {'tipo', 'tema', 'subtema', 'tematica', 'macrotema', 'classe'}
                        fieldValue = issueDetails.issueContext.solicitacao.classificacao.(fieldSubName);
                    case 'processo'
                        fieldValue = issueDetails.issueContext.solicitacao.sei.(fieldSubName);
                end

            case 'Ação de Inspeção'
                switch fieldSubName
                    case {'id', 'codigo', 'descricao', 'status'}
                        fieldValue = issueDetails.issueContext.acao.(fieldSubName);
                    case {'inicio', 'fim'}
                        fieldValue = issueDetails.issueContext.acao.periodo.(fieldSubName);
                    case {'unidade', 'responsavel'}
                        fieldValue = issueDetails.issueContext.acao.execucao.(fieldSubName);
                    case {'processo', 'relatorio', 'despacho', 'pado'}
                        fieldValue = issueDetails.issueContext.acao.sei.(fieldSubName);
                end

            case 'Atividade de Inspeção'
                switch fieldSubName
                    case {'id', 'codigo', 'descricao', 'status'}
                        fieldValue = issueDetails.issueContext.atividade.(fieldSubName);
                    case {'inicio', 'fim'}
                        fieldValue = issueDetails.issueContext.atividade.periodo.(fieldSubName);
                    case {'principal', 'equipe'}
                        fieldValue = issueDetails.issueContext.atividade.responsaveis.(fieldSubName);
                end

            case {'Nome do Demandante', 'Nome da Unidade Executante'}
                switch fieldName
                    case 'Nome do Demandante'
                        unit = reportLib.getEFiscalizaIssueParameter(reportInfo, 'Solicitação de Inspeção', 'demandante');
                    case 'Nome da Unidade Executante'
                        unit = reportLib.getEFiscalizaIssueParameter(reportInfo, 'Ação de Inspeção', 'unidade');
                end

                unitIndex = find(strcmpi({generalSettings.eFiscaliza.defaultValues.unitNameMapping.unit}, unit), 1);
                if ~isempty(unitIndex)
                    fieldValue = sprintf('%s (%s)', generalSettings.eFiscaliza.defaultValues.unitNameMapping(unitIndex).name, unit);
                else
                    fieldValue = unit;
                end

            case 'Sede da Unidade Executante'
                unit = reportLib.getEFiscalizaIssueParameter(reportInfo, 'Ação de Inspeção', 'unidade');
                unitIndex = find(strcmpi({generalSettings.eFiscaliza.defaultValues.unitCityMapping.unit}, unit), 1);
                if ~isempty(unitIndex)
                    fieldValue = generalSettings.eFiscaliza.defaultValues.unitCityMapping(unitIndex).city;
                end

            case 'Período Previsto da Fiscalização'
                fieldValue = sprintf('%s a %s', ...
                    datetime(reportLib.getEFiscalizaIssueParameter(reportInfo, 'Ação de Inspeção', 'inicio'), 'InputFormat', 'yyyy-MM-dd', 'Format', 'dd/MM/yyyy'), ...
                    datetime(reportLib.getEFiscalizaIssueParameter(reportInfo, 'Ação de Inspeção', 'fim'),    'InputFormat', 'yyyy-MM-dd', 'Format', 'dd/MM/yyyy') ...
                );

            case 'Lista de Entidades'
                entidades = reportLib.getEFiscalizaIssueParameter(reportInfo, 'Solicitação de Inspeção', 'entidades');
                entidades = arrayfun(@(x) sprintf('%s (%s)', x.nome, x.id), entidades, 'UniformOutput', false);
                if isscalar(entidades)
                    fieldValue = char(entidades);
                else
                    fieldValue = strjoin([{strjoin(entidades(1:end-1), ', ')}, entidades(end)], ' e ');
                end

            case 'Lista de Serviços'
                servicos = reportLib.getEFiscalizaIssueParameter(reportInfo, 'Solicitação de Inspeção', 'servicos');
                if isscalar(servicos)
                    fieldValue = char(servicos);
                else
                    fieldValue = strjoin([{strjoin(servicos(1:end-1), ', ')}, servicos(end)], ' e ');
                end

            case 'Lista de Fiscais'
                fiscais = reportLib.getEFiscalizaIssueParameter(reportInfo, 'Atividade de Inspeção', 'equipe');
                if isscalar(fiscais)
                    fieldValue = char(fiscais);
                else
                    fieldValue = strjoin([{strjoin(fiscais(1:end-1), ', ')}, fiscais(end)], ' e ');
                end
        end

        if isnumeric(fieldValue)
            fieldValue = num2str(fieldValue);
        end

        if isempty(fieldSubName) || ~ismember(fieldSubName, {'inicio', 'fim', 'demandante', 'unidade', 'entidades', 'servicos', 'equipe'})
            fieldValue = highlightIssueParameterInDev(fieldValue);
        end
    end
end

%-------------------------------------------------------------------------%
function fieldValue = highlightIssueParameterInDev(fieldValue)
    if ~isdeployed()
        fieldValue = sprintf('<font style="color: red;">%s</font>', fieldValue);
    end
end