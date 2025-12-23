classdef ReceitaFederal < ws.WebServiceBase

    % Referências das APIs:
    % - http://www.sped.fazenda.gov.br/wsconsultasituacao/wsconsultasituacao.asmx
    % - http://www.sped.fazenda.gov.br/SPEDPISCofins/WSConsulta/WSConsulta.asmx
    % - http://www.sped.fazenda.gov.br/SpedFiscalServer/WSConsultasPVA/WSConsultasPVA.asmx

    properties
        %-----------------------------------------------------------------%
        cacheFolder
        cacheMapping = table('Size',          [0, 4],                           ...
                             'VariableTypes', {'cell', 'cell', 'cell', 'cell'}, ...
                             'VariableNames', {'Type', 'Hash', 'APIResponse', 'Timestamp'});
    end

    properties (Access = private, Constant)
        %-----------------------------------------------------------------%
        cacheFile = 'cacheMapping.xlsx'
        url = struct('ECD',  'http://www.sped.fazenda.gov.br/wsconsultasituacao/wsconsultasituacao.asmx', ...
                     'EFDC', 'http://www.sped.fazenda.gov.br/SPEDPISCofins/WSConsulta/WSConsulta.asmx', ...
                     'EFDI', 'http://www.sped.fazenda.gov.br/SpedFiscalServer/WSConsultasPVA/WSConsultasPVA.asmx')
    end


    methods
        %-----------------------------------------------------------------%
        function [obj, msgWarning] = ReceitaFederal()
            obj.cacheFolder = fullfile(appEngine.util.OperationSystem('programData'), 'ANATEL', 'ReceitaFederal');
            
            try
                obj.cacheMapping = readtable(fullfile(obj.cacheFolder, obj.cacheFile));
                msgWarning = '';
            catch ME
                msgWarning = ME.message;
            end
        end

        %-----------------------------------------------------------------%
        function [APIResponse, Status] = Get(obj, operationType, fileType, varargin)
            arguments
                obj
                operationType char {mustBeMember(operationType, {'OnlyCache', 'Cache+RealTime', 'RealTime'})}
                fileType      char {mustBeMember(fileType,      {'ECD', 'EFDC', 'EFDI'})}
            end

            arguments (Repeating)
                varargin
            end

            APIResponse = [];

            try
                switch operationType
                    case 'OnlyCache'
                        APIResponse = CheckCache(obj, fileType, varargin{:});
    
                    case 'Cache+RealTime'
                        APIResponse = CheckCache(obj, fileType, varargin{:});
                        if isempty(APIResponse)
                            APIResponse = WebRequest(obj, fileType, varargin{:});
                        end
    
                    case 'RealTime'
                        APIResponse = WebRequest(obj, fileType, varargin{:});
                end

                % Códigos de status (p/ controle no monitorSPED):
                % -2 (Erro) | -1 (Diverge) | 0 (Pendente) | 1 (Coincide)

                if ~isempty(APIResponse) && isstruct(APIResponse) && isfield(APIResponse, 'retVerif')
                    if contains(APIResponse.retVerif, 'mesma', 'IgnoreCase', true)
                        Status = 1;
                    elseif contains(APIResponse.retVerif, 'não', 'IgnoreCase', true)
                        Status = -1;
                    else
                        Status = -2;
                    end
                else
                    Status = -2;
                end

            catch ME
                Status = -2;
                APIResponse = struct('identifier', ME.identifier, 'message', ME.message);
            end
        end
    end

    methods (Access = private)
        %-----------------------------------------------------------------%
        function APIResponse = CheckCache(obj, fileType, varargin)
            APIResponse = [];

            switch fileType
                case 'ECD'
                    Hash = varargin{1};
                    idxCache = find(strcmp(obj.cacheMapping.Type, fileType) & strcmp(obj.cacheMapping.Hash, Hash));
                    
                    if ~isempty(idxCache)
                        idxCache = idxCache(end);
                        APIResponse = jsondecode(obj.cacheMapping.APIResponse{idxCache});                
                    end

                case 'EFDC'
                    % Migrar Python>>MATLAB
                    % consultar_situacao_efdc(CNPJ, file_id)

                case 'EFDI'
                    % Migrar Python>>MATLAB
                    % consultar_situacao_efdi(CNPJ, IE, file_id)
            end
        end

        %-----------------------------------------------------------------%
        function APIResponse = WebRequest(obj, fileType, varargin)
            arguments
                obj
                fileType
            end

            arguments (Repeating)
                varargin
            end

            APIResponse = [];
            endPoint    = obj.url.(fileType);

            switch fileType
                case 'ECD'
                    Hash = varargin{1};

                    header = { ...
                        'Content-Type',  'text/xml; charset=utf-8', ...
                        'Accept',        'application/soap+xml, application/dime, multipart/related, text/*', ...
                        'User-Agent',    'Axis/1.4', ...
                        'Host',          'www.sped.fazenda.gov.br', ...
                        'Cache-Control', 'no-cache', ...
                        'Pragma',        'no-cache', ...
                        'SOAPAction',    'http://tempuri.org/SituacaoEscrituracao' ...
                    };

                    body = sprintf([...
                        '<?xml version="1.0" encoding="UTF-8"?>' ...
                        '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' ...
                            '<soapenv:Body>' ...
                                '<ns1:SituacaoEscrituracao soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:ns1="http://tempuri.org/">' ...
                                    '<ns1:identificacaoArquivo xsi:type="xsd:string">%s</ns1:identificacaoArquivo>' ...
                                    '<ns1:versaoPVA xsi:type="xsd:string"></ns1:versaoPVA>' ...
                                '</ns1:SituacaoEscrituracao>' ...
                            '</soapenv:Body>' ...
                        '</soapenv:Envelope>'], Hash);

                    response = ws.WebServiceBase.request(endPoint, 'POST', header, body);
    
                    switch response.StatusCode
                        case 'OK'
                            APIResponse = parseResponse(obj, response.Body.char);

                            idxCache = height(obj.cacheMapping)+1;
                            obj.cacheMapping(idxCache, :) = {fileType, Hash, jsonencode(APIResponse), datestr(now)};

                            if ~isfolder(obj.cacheFolder)
                                mkdir(obj.cacheFolder)
                            end
                            writetable(obj.cacheMapping(end,:), fullfile(obj.cacheFolder, obj.cacheFile), 'WriteMode', 'append', 'AutoFitWidth', false);

                        otherwise
                            error(response.StatusCode)
                    end

                case 'EFDC'
                    % Migrar Python>>MATLAB
                    % consultar_situacao_efdc(CNPJ, file_id)

                case 'EFDI'
                    % Migrar Python>>MATLAB
                    % consultar_situacao_efdi(CNPJ, IE, file_id)
            end
        end

        %-----------------------------------------------------------------%
        function resultStruct = parseResponse(obj, xmlString, xmlTag)
            arguments
                obj
                xmlString
                xmlTag (1,:) char = 'SituacaoEscrituracaoResult'
            end

            % <?xml version="1.0" encoding="utf-8"?>
            % <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
            %                xmlns:xsd="http://www.w3.org/2001/XMLSchema"
            %                xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            %    <soap:Header>
            %       <WSCorIDSOAPHeader xmlns="http://www.wilytech.com/"
            %                          CorID="C5C585A4C8C6EF1801F609182D519186,1:1,0,0,,,AgAAAkdIQgAAAAFGAAAAAQAAABFqYXZhLnV0aWwuSGFzaE1hcAAAAAhIQgAAAAJGAAAAAgAAABBqYXZhLmxhbmcuU3RyaW5nABBBcHBNYXBDYWxsZXJIb3N0SEIAAAADRQAAAAIADHNwY2RzcnZ2MTY3NUhCAAAABEUAAAACABBBcHBNYXBDYWxsZXJUeXBlSEIAAAAFRQAAAAIAB1NlcnZsZXRIQgAAAAZFAAAAAgAKVHhuVHJhY2VJZEhCAAAAB0UAAAACACFDNUM1ODU3NUM4QzZFRjE4MDFGNjA5MTg0NjJGOEE0NjBIQgAAAAhFAAAAAgARQXBwTWFwQ2FsbGVyQWdlbnRIQ0hCAAAACUUAAAACAA5BcHBNYXBBcHBOYW1lc0hCAAAACkYAAAADAAAAE2phdmEudXRpbC5BcnJheUxpc3QAAAACSEIAAAALRQAAAAIAEndzQ29uc3VsdGFTaXR1YWNhb0hCAAAADEUAAAACABJ3c0NvbnN1bHRhU2l0dWFjYW9IQgAAAA1FAAAAAgAWQXBwTWFwQ2FsbGVyTWV0aG9kTmFtZUhCAAAADkUAAAACACVTeW5jU2Vzc2lvbmxlc3NIYW5kbGVyfFByb2Nlc3NSZXF1ZXN0SEIAAAAPRQAAAAIAE0FwcE1hcENhbGxlclByb2Nlc3NIQgAAABBFAAAAAgAMLk5FVCBQcm9jZXNzSEIAAAARRQAAAAIAD0NhbGxlclRpbWVzdGFtcEhCAAAAEkUAAAACAA0xNzU1NjY0NzEzMTI0"/>
            %    </soap:Header>
            %    <soap:Body>
            %       <SituacaoEscrituracaoResponse xmlns="http://tempuri.org/">
            %          <SituacaoEscrituracaoResult>&lt;docSPEDContabil xmlns="http://www.sped.fazenda.gov.br/SPEDContabil/RetornoConsultaSituacao"&gt;&lt;consSituacaoResult versao="1.0" nire="35212923462   " hashEsc="CAB2051CB96BB920AF24744EBF11536A8EFA2A6F" dtEnvio="2020-07-30T17:29:23" retVerif="A escrituração visualizada é a mesma que se encontra na base de dados do SPED." situacao="A" dtCons="2025-08-20T01:38:33" /&gt;&lt;/docSPEDContabil&gt;</SituacaoEscrituracaoResult>
            %       </SituacaoEscrituracaoResponse>
            %    </soap:Body>
            % </soap:Envelope>

            if ~isempty(xmlTag)
                xmlString = extractBetween(xmlString, ['<' xmlTag '>'], ['</' xmlTag '>'], "Boundaries", "inclusive");
            end

            expr = '(\w+)="([^"]*)"';
            tokens = regexp(xmlString, expr, 'tokens');
            if ~isempty(tokens)
                tokens = tokens{1};
            end
            
            resultStruct = struct();
            for ii = 1:numel(tokens)
                resultStruct.(tokens{ii}{1}) = strtrim(tokens{ii}{2});
            end
        end
    end
end