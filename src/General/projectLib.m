classdef projectLib < dynamicprops

    properties
        %-----------------------------------------------------------------%
        name  (1,:) char   = ''
        file  (1,:) char   = ''
        issue (1,1) double = -1
        unit  (1,:) char   = ''

        documentType {mustBeMember(documentType, {'Relatório de Atividades', 'Relatório de Fiscalização', 'Informe'})} = 'Relatório de Atividades'
        documentModel      = ''
        documentScript     = []
        generatedFiles     = []
    end

    
    properties (Access = private)
        %-----------------------------------------------------------------%
        callingApp
        defaultFilePreffix = ''
        customProperties   = {}
    end


    methods
        %-----------------------------------------------------------------%
        function obj = projectLib(callingApp, varargin)            
            obj.callingApp = callingApp;

            switch class(callingApp)
                case {'winAppAnalise', 'winAppAnalise_exported'}
                    obj.defaultFilePreffix = 'appAnalise';
                    obj.customProperties   = {'externalFiles'};

                    addprop(obj, 'externalFiles');
                    obj.externalFiles = table('Size',          [0, 4],                           ...
                                              'VariableTypes', {'cell', 'cell', 'cell', 'int8'}, ...
                                              'VariableNames', {'Type', 'Tag', 'Filename', 'ID'});

                case {'winSCH', 'winSCH_exported'}
                    obj.defaultFilePreffix = 'SCH';
                    obj.customProperties   = {'EntityType', 'EntityID', 'EntityName', 'listOfProducts'};
                    
                    addprop(obj, 'EntityType');
                    addprop(obj, 'EntityID');
                    addprop(obj, 'EntityName');
                    addprop(obj, 'listOfProducts');
                    
                    obj.EntityType     = '';
                    obj.EntityID       = '';
                    obj.EntityName     = '';
                    
                    obj.listOfProducts = table('Size',          [0, 22],                                                                                                                                                                                                                               ...
                                               'VariableTypes', {'cell', 'cell', 'cell', 'categorical', 'cell', 'cell', 'logical', 'logical', 'logical', 'double', 'cell', 'uint32', 'uint32', 'uint32', 'uint32', 'uint32', 'uint32', 'uint32', 'categorical', 'categorical', 'categorical', 'cell'}, ...
                                               'VariableNames', {'Homologação', 'Importador', 'Código aduaneiro', 'Tipo', 'Fabricante', 'Modelo', 'RF?', 'Em uso?', 'Interferência?', 'Valor Unit. (R$)', 'Fonte do valor', 'Qtd. uso', 'Qtd. vendida', 'Qtd. estoque/aduana', 'Qtd. anunciada',       ...
                                                                 'Qtd. lacradas', 'Qtd. apreendidas', 'Qtd. retidas (RFB)', 'Situação', 'Infração', 'Sanável?', 'Informações adicionais'});
                    
                    obj.listOfProducts.("Tipo")     = categorical(obj.listOfProducts.("Tipo"),     varargin{1});
                    obj.listOfProducts.("Situação") = categorical(obj.listOfProducts.("Situação"), varargin{2});
                    obj.listOfProducts.("Infração") = categorical(obj.listOfProducts.("Infração"), varargin{3});
                    obj.listOfProducts.("Sanável?") = categorical(obj.listOfProducts.("Sanável?"), {'-1', 'Sim', 'Não'});

                case {'winMonitorRNI', 'winMonitorRNI_exported'}
                    obj.defaultFilePreffix = 'monitorRNI';
                    obj.customProperties   = {'rawListOfYears', 'referenceListOfLocations', 'referenceListOfStates', 'selectedFileLocations', 'listOfLocations'};

                    % A planilha de referência do PM-RNI possui uma relação
                    % de estações de telecomunicações que deve ser avaliada.
                    % Dessa planilha, extrai-se:
                    % • "rawListOfYears": a lista com todos os anos da planilha 
                    %   bruta - Coluna "Ano".
                    
                    % • "referenceListOfLocation": a lista com todas as localidades 
                    %   relacionadas às estações da planilha filtrada (pelo ano sob 
                    %   análise).
                    
                    % • "referenceListOfStates": a lista com todas as UFs relacionadas 
                    %   às estações da planilha filtrada.

                    % O monitorRNI identifica a localidade relacionada às coordenadas 
                    % centrais de cada arquivo. Essa lista é apresentada nos modos 
                    % auxiliares auxApp.winRNI e auxApp.ExternalRequest.
                    % • "selectedFileLocations": a lista com as localidades 
                    %   selecionadas pelo usuário em um dos modos auxiliares.

                    % • "listOfLocations": a lista de localidades sob análise 
                    %   no módulo auxApp.winRNI p/ fins de geração da planilha 
                    %   que será submetida ao Centralizador do PM-RNI.

                    addprop(obj, 'rawListOfYears');
                    addprop(obj, 'referenceListOfLocations');
                    addprop(obj, 'referenceListOfStates');
                    addprop(obj, 'selectedFileLocations');
                    addprop(obj, 'listOfLocations');
                    
                    obj.selectedFileLocations = {};
                    obj.listOfLocations = struct('Manual', [], 'Automatic', []);
            end
        end


        %-----------------------------------------------------------------%
        function Restart(obj)
            obj.name           = '';
            obj.file           = '';
            obj.issue          = -1;
            obj.unit           = '';

            obj.documentType   = 'Relatório de Atividades';
            obj.documentModel  = '';
            obj.documentScript = [];
            obj.generatedFiles = [];

            customPropertiesList = obj.customProperties;
            for ii = 1:numel(customPropertiesList)
                propertyName = customPropertiesList{ii};

                switch class(obj.(propertyName))
                    case 'table'
                        obj.(propertyName)(:,:) = [];
                    case 'struct'
                        obj.(propertyName)(:)   = [];
                    case 'cell'
                        obj.(propertyName)      = {};
                    case 'char'
                        obj.(propertyName)      = '';
                    otherwise
                        obj.(propertyName)      = [];
                end
            end
        end
    end
end