classdef projectLib < dynamicprops

    properties
        %-----------------------------------------------------------------%
        name  (1,:) char   = ''
        file  (1,:) char   = ''
        issue (1,1) double = -1

        documentType {mustBeMember(documentType, {'Relatório de Atividades', 'Relatório de Fiscalização', 'Informe'})} = 'Relatório de Atividades'
        documentModel      = ''
        documentScript     = []
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
                    obj.customProperties   = {'peaksTable', 'exceptionList', 'externalFiles'};

                    addprop(obj, 'peaksTable');
                    addprop(obj, 'exceptionList');
                    addprop(obj, 'externalFiles');                    

                    obj.peaksTable    = table('Size', [0, 23],                                                                                                                                                                                                         ...
                                              'VariableTypes', {'cell', 'single', 'single', 'uint16', 'double', 'single', 'double', 'cell', 'cell', 'cell', 'cell', 'cell', 'cell', 'cell', 'int16', 'int32', 'cell', 'cell', 'cell', 'cell', 'cell', 'cell', 'cell'}, ...
                                              'VariableNames', {'Tag', 'Latitude', 'Longitude', 'Index', 'Frequency', 'Truncated', 'BW', 'minLevel', 'meanLevel', 'maxLevel', 'meanOCC', 'maxOCC', 'Type', 'Regulatory', 'Service', 'Station', 'Description', 'Distance', 'Irregular', 'RiskLevel', 'occMethod', 'Detection', 'Classification'});

                    obj.exceptionList = table('Size', [0, 10],                                                                                       ...
                                              'VariableTypes', {'cell', 'double', 'cell', 'cell', 'int16', 'int32', 'cell', 'cell', 'cell', 'cell'}, ...
                                              'VariableNames', {'Tag', 'Frequency', 'Type', 'Regulatory', 'Service', 'Station', 'Description', 'Distance', 'Irregular', 'RiskLevel'});

                    obj.externalFiles = table('Size', [0, 3],                             ...
                                              'VariableTypes', {'uint8', 'cell', 'cell'}, ...
                                              'VariableNames', {'ID', 'Tag', 'Filename'});

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
                    
                    obj.listOfProducts = table('Size', [0, 16],                                                                                                                                                               ...
                                               'VariableTypes', {'cell', 'categorical', 'cell', 'cell', 'logical', 'logical', 'logical', 'double', 'uint32', 'uint32', 'uint32', 'uint32', 'uint32', 'cell', 'cell', 'cell'}, ...
                                               'VariableNames', {'Homologação', 'Tipo', 'Fabricante', 'Modelo', 'RF?', 'Em uso?', 'Interferência?', 'Valor Unit. (R$)', 'Qtd. uso/vendida', 'Qtd. estoque', 'Qtd. lacradas', 'Qtd. apreendidas', 'Qtd. retidas (RFB)', 'Situação', 'Infração', 'Informações adicionais'});
                    obj.listOfProducts.("Tipo") = categorical(listOfProducts.("Tipo"), varargin{1});
            end
        end


        %-----------------------------------------------------------------%
        function Restart(obj)
            obj.name           = '';
            obj.file           = '';
            obj.issue          = -1;
            obj.documentType   = 'Relatório de Atividades';
            obj.documentModel  = '';
            obj.documentScript = [];

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

            report_ProjectDataGUI(obj.callingApp)

            if isprop(obj.callingApp, 'fiscalizaObj') && ~isempty(obj.callingApp.fiscalizaObj)
                fiscalizaLibConnection.ResetGUI(obj.callingApp)
            end
        end
    end
end