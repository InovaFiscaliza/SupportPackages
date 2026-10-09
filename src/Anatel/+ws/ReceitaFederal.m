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
        function [APIResponse, status] = Get(obj, operationType, fileType, varargin)
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

                if ~isempty(APIResponse) && isstruct(APIResponse) && isfield(APIResponse, 'situacao')
                    switch APIResponse.situacao
                        case {'A', 'R'}
                            status = 1;
                        otherwise % 'S'
                            status = -1;
                    end
                else
                    status = -2;
                end

            catch ME
                status = -2;
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


            if any(strcmp(fileType, {'EFDI', 'EFDC'}))
                % consultar_situacao_efdc(CNPJ, file_id) | consultar_situacao_efdi(CNPJ, IE, file_id)
                % varargin = {CNPJ, IE, file_id}; para EFDC, varargin{2} é ignorado.
                isEFDI = strcmp(fileType, 'EFDI');

                CNPJ = '';
                IE = '';
                file_id = '';

                if numel(varargin) >= 3
                    CNPJ = char(string(varargin{1}));
                    if isEFDI
                        IE = char(string(varargin{2}));
                    end
                    file_id = char(string(varargin{3}));

                elseif ~isempty(varargin)
                    sourceObj = varargin{1};

                    if (isstruct(sourceObj) && isfield(sourceObj, 'CompanyInfo')) || (isobject(sourceObj) && isprop(sourceObj, 'CompanyInfo'))
                        companyInfo = sourceObj.CompanyInfo;
                        if ~isempty(companyInfo)
                            companyInfo = companyInfo(end);
                            if isfield(companyInfo, 'CNPJ')
                                CNPJ = char(string(companyInfo.CNPJ));
                            end
                            if isEFDI && isfield(companyInfo, 'IE')
                                IE = char(string(companyInfo.IE));
                            end
                        end
                    end

                    if (isstruct(sourceObj) && isfield(sourceObj, 'Hash')) || (isobject(sourceObj) && isprop(sourceObj, 'Hash'))
                        file_id = char(string(sourceObj.Hash));
                    end
                end

                CNPJ = strtrim(CNPJ);
                IE = strtrim(IE);
                file_id = strtrim(file_id);

                if isempty(CNPJ)
                    error(['ReceitaFederal:' fileType ':MissingCNPJ'], 'Não foi possível obter o CNPJ para consulta %s.', fileType);
                end
                if isEFDI && isempty(IE)
                    error('ReceitaFederal:EFDI:MissingIE', 'Não foi possível obter a IE para consulta EFDI.');
                end
                if isempty(file_id)
                    error(['ReceitaFederal:' fileType ':MissingHash'], 'Não foi possível obter a identificação do arquivo (hash) para consulta %s.', fileType);
                end
            end

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

                    header = { ...
                        'Content-Type',  'text/xml; charset=utf-8', ...
                        'Accept',        'application/soap+xml, application/dime, multipart/related, text/*', ...
                        'User-Agent',    'Axis/1.4', ...
                        'Host',          'www.sped.fazenda.gov.br', ...
                        'Cache-Control', 'no-cache', ...
                        'Pragma',        'no-cache', ...
                        'SOAPAction',    '"http://br.gov.serpro.spedpiscofinsserver/consulta/consultarSituacaoEscrituracao"' ...
                    };

                    body = sprintf([...
                        '<?xml version="1.0" encoding="UTF-8"?>' ...
                        '<soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">' ...
                            '<soap:Body>' ...
                                '<consultarSituacaoEscrituracao xmlns="http://br.gov.serpro.spedpiscofinsserver/consulta">' ...
                                    '<niContribuinte>%s</niContribuinte>' ...
                                    '<identificacaoArquivo>%s</identificacaoArquivo>' ...
                                '</consultarSituacaoEscrituracao>' ...
                            '</soap:Body>' ...
                        '</soap:Envelope>'], CNPJ, file_id);

                    response = ws.WebServiceBase.request(endPoint, 'POST', header, body);

                    switch response.StatusCode
                        case 'OK'
                            APIResponse = parseResponse(obj, response.Body.char, fileType);

                        otherwise
                            error(response.StatusCode)
                    end

                case 'EFDI'
                    % Migrar Python>>MATLAB
                    % consultar_situacao_efdi(CNPJ, IE, file_id)

                    header = { ...
                        'Content-Type',  'text/xml; charset=utf-8', ...
                        'Accept',        'application/soap+xml, application/dime, multipart/related, text/*', ...
                        'User-Agent',    'Axis/1.4', ...
                        'Host',          'www.sped.fazenda.gov.br', ...
                        'Cache-Control', 'no-cache', ...
                        'Pragma',        'no-cache', ...
                        'SOAPAction',    'http://br.gov.serpro.spedfiscalserver/consulta/consultarSituacaoEscrituracao' ...
                    };

                    body = sprintf([...
                        '<?xml version="1.0" encoding="UTF-8"?>' ...
                        '<soap12:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap12="http://www.w3.org/2003/05/soap-envelope">' ...
                            '<soap12:Body>' ...
                                '<consultarSituacaoEscrituracao xmlns="http://br.gov.serpro.spedfiscalserver/consulta">' ...
                                    '<niContribuinte>%s</niContribuinte>' ...
                                    '<ieContribuinte>%s</ieContribuinte>' ...
                                    '<identificacaoArquivo>%s</identificacaoArquivo>' ...
                                '</consultarSituacaoEscrituracao>' ...
                            '</soap12:Body>' ...
                        '</soap12:Envelope>'], CNPJ, IE, file_id);

                    response = ws.WebServiceBase.request(endPoint, 'POST', header, body);

                    switch response.StatusCode
                        case 'OK'
                            APIResponse = parseResponse(obj, response.Body.char, fileType);

                        otherwise
                            error(response.StatusCode)
                    end
            end
        end

        %-----------------------------------------------------------------%
        function resultStruct = parseResponse(~, xmlString, fileType, xmlTag)
            arguments
                ~
                xmlString
                fileType (1,:) char {mustBeMember(fileType, {'ECD', 'EFDC', 'EFDI'})} = 'ECD'
                xmlTag   (1,:) char = 'SituacaoEscrituracaoResult'
            end

            % Resposta da Receita Federal à pergunta "este arquivo (CNPJ + hash) é o que foi transmitido?".
            % Campos usados: situacao (resultado da consulta), dataEnvio/dtEnvio (transmissão do arquivo),
            % dataConsulta/dtCons (momento da consulta) e idArquivo/hashEsc (identificação do arquivo).
            % O WSCorIDSOAPHeader é cabeçalho técnico de rastreio do servidor e é ignorado.
            % situacao "se encontra na base" -> status 1 (coincide); "não se encontra" -> -1 (diverge); sem situacao -> -2 (erro).
            % Arquivo não localizado: niContribuinte = 0 e dataEnvio = 0001-01-01, também quando o tipo de hash enviado está errado.

            %%%%%%%%%%%%%%%%%%%%%%%%%%% ECD  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            %
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
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            % ECD: SOAP 1.1; o resultado é um XML escapado, com os campos em atributos
            % (situacao, hashEsc, dtEnvio, dtCons, retVerif). O hash consultado é o SHA-1.
        
            %%%%%%%%%%%%%%%%%%%%%%%%%  EFDC  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            %
            %        '<?xml version="1.0" encoding="utf-8"?>
            % <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
            %                xmlns:xsd="http://www.w3.org/2001/XMLSchema"
            %                xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            %    <soap:Header>
            %       <WSCorIDSOAPHeader xmlns="http://www.wilytech.com/"
            %                          CorID="16A55663C8C6EF1803E3FDFD7D69FA55,1:1,0,0,,,AgAAAj9IQgAAAAFGAAAAAQAAABFqYXZhLnV0aWwuSGFzaE1hcAAAAAhIQgAAAAJGAAAAAgAAABBqYXZhLmxhbmcuU3RyaW5nABBBcHBNYXBDYWxsZXJIb3N0SEIAAAADRQAAAAIADHNwY2RzcnZ2MTY3NkhCAAAABEUAAAACAA5BcHBNYXBBcHBOYW1lc0hCAAAABUYAAAADAAAAE2phdmEudXRpbC5BcnJheUxpc3QAAAACSEIAAAAGRQAAAAIADi9TcGVkUGlzQ29maW5zSEIAAAAHRQAAAAIADi9TcGVkUGlzQ29maW5zSEIAAAAIRQAAAAIAD0NhbGxlclRpbWVzdGFtcEhCAAAACUUAAAACAA0xNzkxMzgxMjk2NzM5SEIAAAAKRQAAAAIAFkFwcE1hcENhbGxlck1ldGhvZE5hbWVIQgAAAAtFAAAAAgAlU3luY1Nlc3Npb25sZXNzSGFuZGxlcnxQcm9jZXNzUmVxdWVzdEhCAAAADEUAAAACABFBcHBNYXBDYWxsZXJBZ2VudEhDSEIAAAANRQAAAAIAEEFwcE1hcENhbGxlclR5cGVIQgAAAA5FAAAAAgAHU2VydmxldEhCAAAAD0UAAAACABNBcHBNYXBDYWxsZXJQcm9jZXNzSEIAAAAQRQAAAAIADC5ORVQgUHJvY2Vzc0hCAAAAEUUAAAACAApUeG5UcmFjZUlkSEIAAAASRQAAAAIAITE2QTU1NjQ5QzhDNkVGMTgwM0UzRkRGRDYyMDJFNzlCMA=="/>
            %    </soap:Header>
            %    <soap:Body>
            %       <consultarSituacaoEscrituracaoResponse xmlns="http://br.gov.serpro.spedpiscofinsserver/consulta">
            %          <consultarSituacaoEscrituracaoResult>
            %             <niContribuinte>63356042</niContribuinte>
            %             <idArquivo>D79301E0250E399D615DBA10CB25ABEE</idArquivo>
            %             <dataConsulta>2026-10-07T13:54:56.7295177Z</dataConsulta>
            %             <dataEnvio>2020-08-20T17:29:31Z</dataEnvio>
            %             <situacao>A escrituração visualizada se encontra na base de dados do SPED.</situacao>
            %          </consultarSituacaoEscrituracaoResult>
            %       </consultarSituacaoEscrituracaoResponse>
            %    </soap:Body>
            % </soap:Envelope>'
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            % EFDC: SOAP 1.1, namespace "spedpiscofinsserver"; campos em elementos filhos iniciados em minúscula.
            % idArquivo é o MD5 do arquivo (SHA-1 não é localizado). Arquivo não localizado: niContribuinte = 0,
            % dataEnvio = 0001-01-01T00:00:00 e situacao = "A escrituração visualizada não se encontra na base de dados do SPED."


            %%%%%%%%%%%%%%%%%%%%%%%%%  EFDI  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            % '<?xml version="1.0" encoding="utf-8"?>
            % <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" 
            %                xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' ...
            %                xmlns:xsd="http://www.w3.org/2001/XMLSchema">
            %       <soap:Header>
            %           <WSCorIDSOAPHeader CorID="17685633C8C6EF1800FD727F7F00900F,1:1,0,0,,,AgAAAkVIQgAAAAFGAAAAAQAAABFqYXZhLnV0aWwuSGFzaE1hcAAAAAhIQgAAAAJGAAAAAgAAABBqYXZhLmxhbmcuU3RyaW5nABBBcHBNYXBDYWxsZXJIb3N0SEIAAAADRQAAAAIADHNwY2RzcnZ2MTY3NEhCAAAABEUAAAACAA5BcHBNYXBBcHBOYW1lc0hCAAAABUYAAAADAAAAE2phdmEudXRpbC5BcnJheUxpc3QAAAACSEIAAAAGRQAAAAIAES9TcGVkRmlzY2FsU2VydmVySEIAAAAHRQAAAAIAES9TcGVkRmlzY2FsU2VydmVySEIAAAAIRQAAAAIAD0NhbGxlclRpbWVzdGFtcEhCAAAACUUAAAACAA0xNzkxMzk0MDc2MjExSEIAAAAKRQAAAAIAFkFwcE1hcENhbGxlck1ldGhvZE5hbWVIQgAAAAtFAAAAAgAlU3luY1Nlc3Npb25sZXNzSGFuZGxlcnxQcm9jZXNzUmVxdWVzdEhCAAAADEUAAAACABFBcHBNYXBDYWxsZXJBZ2VudEhDSEIAAAANRQAAAAIAEEFwcE1hcENhbGxlclR5cGVIQgAAAA5FAAAAAgAHU2VydmxldEhCAAAAD0UAAAACABNBcHBNYXBDYWxsZXJQcm9jZXNzSEIAAAAQRQAAAAIADC5ORVQgUHJvY2Vzc0hCAAAAEUUAAAACAApUeG5UcmFjZUlkSEIAAAASRQAAAAIAITE3Njg1NjE0QzhDNkVGMTgwMEZENzI3RjFCQTJGNTE3MA==" xmlns="http://www.wilytech.com/" />
            %       </soap:Header>
            %       <soap:Body>
            %           <consultarSituacaoEscrituracaoResponse xmlns="http://br.gov.serpro.spedfiscalserver/consulta">
            %               <consultarSituacaoEscrituracaoResult dataHora="2026-10-07T14:27:56.2114005-03:00" codRetorno="101" codOperacao="4" id="RT134358676762114005-SPCDSRVV1674">
            %                   <NiContribuinte>125941477</NiContribuinte>
            %                   <IeContribuinte>206603117119</IeContribuinte>
            %                   <IdArquivo>730E3FAD1DF83BE7C5FE8BD79ACD4E44</IdArquivo>
            %                   <DataConsulta>2026-10-07T17:27:56.2114005Z</DataConsulta>
            %                   <DataEnvio>2023-02-15T21:39:36Z</DataEnvio>
            %                   <Situacao>A escrituração visualizada encontra-se na base de dados do Sped e corresponde à última escrituração fiscal enviada.</Situacao>
            %               </consultarSituacaoEscrituracaoResult>
            %           </consultarSituacaoEscrituracaoResponse>
            %       </soap:Body>
            %   </soap:Envelope>'
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            % EFDI: SOAP 1.2, namespace "spedfiscalserver"; campos em elementos iniciados em maiúscula e atributos
            % no Result (dataHora, codRetorno, codOperacao, id). IdArquivo é o MD5 do arquivo.

            switch fileType
                case 'ECD'
                    xmlString = extractBetween(xmlString, ['<' xmlTag '>'], ['</' xmlTag '>'], "Boundaries", "inclusive");

                    expr = '(\w+)="([^"]*)"';
                    tokens = regexp(xmlString, expr, 'tokens');
                    if ~isempty(tokens)
                        tokens = tokens{1};
                    end

                    resultStruct = struct();
                    for ii = 1:numel(tokens)
                        resultStruct.(tokens{ii}{1}) = strtrim(tokens{ii}{2});
                    end

                case {'EFDC', 'EFDI'}
                    resultStruct = struct();

                    xmlResult = regexp(xmlString, '<consultarSituacaoEscrituracaoResult[^>]*>.*?</consultarSituacaoEscrituracaoResult>', 'match', 'once');
                    tokens    = regexp(xmlResult, '<(\w+)>([^<]*)</\1>', 'tokens');
                    for ii = 1:numel(tokens)
                        fieldName = [lower(tokens{ii}{1}(1)), tokens{ii}{1}(2:end)];
                        resultStruct.(fieldName) = strtrim(tokens{ii}{2});
                    end

                    if isfield(resultStruct, 'situacao')
                        message = resultStruct.situacao;

                        isFound = ~isempty(regexpi(message, '(?<!n[ãa]o )(se encontra|encontra-se) na base de dados', 'once')) && ...
                                  ~contains(message, 'não corresponde', 'IgnoreCase', true);

                        % Mesmos campos do retorno ECD, p/ compatibilidade com o restante do app.
                        resultStruct.retVerif = message;
                        if isfield(resultStruct, 'dataEnvio')
                            resultStruct.dtEnvio = resultStruct.dataEnvio;
                        end
                        if isfield(resultStruct, 'dataConsulta')
                            resultStruct.dtCons = resultStruct.dataConsulta;
                        end

                        if isFound
                            resultStruct.situacao = 'A';
                        else
                            resultStruct.situacao = 'S';
                        end
                    end
            end
        end
    end
end