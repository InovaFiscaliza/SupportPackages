classdef ReceitaFederal < ws.WebServiceBase

    % Referências das APIs:
    % - http://www.sped.fazenda.gov.br/wsconsultasituacao/wsconsultasituacao.asmx
    % - http://www.sped.fazenda.gov.br/SPEDPISCofins/WSConsulta/WSConsulta.asmx
    % - http://www.sped.fazenda.gov.br/SpedFiscalServer/WSConsultasPVA/WSConsultasPVA.asmx

    properties (Access = private, Constant)
        %-----------------------------------------------------------------%
        url = struct('ECD',  'http://www.sped.fazenda.gov.br/wsconsultasituacao/wsconsultasituacao.asmx', ...
                     'EFDC', 'http://www.sped.fazenda.gov.br/SPEDPISCofins/WSConsulta/WSConsulta.asmx', ...
                     'EFDI', 'http://www.sped.fazenda.gov.br/SpedFiscalServer/WSConsultasPVA/WSConsultasPVA.asmx')
    end


    methods
        %-----------------------------------------------------------------%
        function obj = ReceitaFederal()
            % ... construtor só precisa se tiver alguma propriedade ...
        end

        %-----------------------------------------------------------------%
        function msg = run(obj, operation, varargin)
            % Referências:
            % - consultar_situacao_efdi(CNPJ, IE, file_id) (!! PENDENTE !!)
            % - consultar_situacao_efdc(CNPJ, file_id)     (!! PENDENTE !!)
            % - consultar_situacao_ecd(NIRE, sha1_hash)
            arguments
                obj
                operation char {mustBeMember(operation, {'ECD', 'EFDC', 'EFDI'})}
            end

            arguments (Repeating)
                varargin
            end

            endPoint = obj.url.(operation);

            try
                switch operation
                    case 'ECD'
                        NIRE = varargin{1};
                        sha1_hash = varargin{2};

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
                                        '<ns1:NIRE xsi:type="xsd:string">%s</ns1:NIRE>' ...
                                        '<ns1:identificacaoArquivo xsi:type="xsd:string">%s</ns1:identificacaoArquivo>' ...
                                        '<ns1:versaoPVA xsi:type="xsd:string"></ns1:versaoPVA>' ...
                                    '</ns1:SituacaoEscrituracao>' ...
                                '</soapenv:Body>' ...
                            '</soapenv:Envelope>'], NIRE, sha1_hash);

                        response = ws.WebServiceBase.request(endPoint, 'POST', header, body);
        
                        switch response.StatusCode
                            case 'OK'
                                % Precisa parsear a resposta. Talvez precise gerar uma estrutura a partir do
                                % KML. MATLAB tem essa função.
                                % response.Body.show
                                
                                msg  = 'Documento consta na base da Receita Federal';
                            otherwise
                                msg  = 'Erro na requisição... ';
                        end

                    case 'EFDC'
                        % ...

                    case 'EFDI'
                        % ...
    
                    otherwise
                        error('UnexpectedCall')
                end

            catch ME
                msg  = ME.message;
            end
        end

        %-----------------------------------------------------------------%
        function sha1_hash = calculate_sha1(fileNamePath)
            % Referência:
            % calculate_sha1(file_path)

            % def calculate_sha1(file_path):
            %     sha1 = hashlib.sha1()
            %     try:
            %         with open(file_path, 'rb') as f:
            %             while True:
            %                 data = f.read(65536)  # Lê o arquivo em blocos de 64KB
            %                 if not data:
            %                     break
            %                 sha1.update(data)
            %     except Exception as e:
            %         debug(f"Erro ao calcular o hash SHA-1: {e}")
            %     return sha1.hexdigest()
        end

        %-----------------------------------------------------------------%
        function NIRE = str_field_from_left(fileNamePath)
            % Referência:
            % NIRE = str_field_from_left(first_line,field_position=8)

            % def str_field_from_left(line, field_position=10):
            %     """ Extrai um campo específico de uma string delimitada por | """
            %     fields = line.strip().split("|")
            %     if len(fields) >= field_position:
            %         return fields[field_position - 1]  # -1 porque índices são baseados em 0
            %     else:
            %         return f"*** Erro: Menos de {field_position} campos na linha."
        end
    end

end