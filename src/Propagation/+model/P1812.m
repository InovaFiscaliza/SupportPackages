classdef P1812 < model.PropagationBase
    %----------------------------------------------------------------------
    % Cálculo de predição de cobertura conforme modelo ITU-R P.1812-6
    %----------------------------------------------------------------------

    methods
        
        function calculo(obj, gAnt, varargin)
            %--------------------------------------------------------------
            % Calcula o nivel de sinal recebido e a atenuação até a estação
            % de recepção
            % gAnt: ganho da antena
            % p:                Nível de disponibilidade requerido para transmissão          
            % pL:               Percentagem de tempo em que a perda de transmissão 
            %                   não ultrapassa o valor calculado (entre 1% e 99%)
            % sigmal:           Desvios padrão da variabilidade espacial calculados
            %                   utilizando o método stdDev.m, conforme descrito nos
            %                   itens 4.8 e 4.10 da recomendação 1812
            % perfil_distancia: array (1,n) distancias dos obstaculos até o TX
            % perfil_elevacao: array (1,n) elevações dos obstáculos
            % perfil_clutter: array (1, n) classificação das feições do terreno
            %--------------------------------------------------------------
            
            arguments
                obj 
                gAnt double {mustBeNumeric, mustBeNonNan, mustBeNonempty}
            end

            arguments (Repeating)
                varargin
            end


            ip = inputParser;
            addParameter(ip, 'p', 1, @isnumeric);
            addParameter(ip, 'pL', 50, @isnumeric);
            addParameter(ip, 'sigmaL', [], @isnumeric);
            addParameter(ip, 'perfil_distancia', [], @isnumeric);
            addParameter(ip, 'perfil_elevacao', [], @isnumeric);
            addParameter(ip, 'perfil_clutter', [], @isnumeric);

            parse(ip, varargin{:});
            
            p = ip.Results.p;
            pL = ip.Results.pL;
            sigmaL = ip.Results.sigmaL;
            % Calcula sigmaL padrão apenas quando não fornecido e o raster está disponível
            if isempty(sigmaL)
                if isobject(obj.R) && isprop(obj.R, 'CellExtentInLatitude')
                    sigmaL = ((24e-3 * (obj.siteTX.TransmitterFrequency/1e9) + 0.52) ...
                             * (obj.R.CellExtentInLatitude * 111320))^(0.28);
                else
                    sigmaL = 0;
                end
            end
            perfil_distancia = ip.Results.perfil_distancia;
            perfil_elevacao = ip.Results.perfil_elevacao;
            perfil_clutter = ip.Results.perfil_clutter;

            PTX = obj.siteTX.TransmitterPower / 1e3;
            
            if (isempty(perfil_distancia))
                [perfil_distancia, perfil_elevacao, perfil_clutter] = utils.levanta_perfil(obj.siteTX, obj.siteRX, obj.A, obj.R, obj.C, obj.S);
            end
            
            
            %--------------------------------------------------------------
            % calcula o array de alturas adicional conforme a classificação
            % de clutter REC P1812.7 seção 3.2.1, tabela 2
            alturas_clutter = perfil_clutter;
            alturas_clutter(ismember(alturas_clutter, [1 2])) = 0;
            alturas_clutter(alturas_clutter == 3) = 10;
            alturas_clutter(alturas_clutter == 4) = 15;
            alturas_clutter(alturas_clutter == 5) = 20;

            idx = size(perfil_distancia, 2);

            if idx > 2
                [obj.Lb, obj.PRX] = model.p1812.tl_p1812(obj.siteTX.TransmitterFrequency/1e9, ...  % GHz
                            p, ...
                            perfil_distancia, ... %(1:idx)./1000, ...
                            perfil_elevacao, ... %(1:idx), ...
                            alturas_clutter, ...
                            perfil_clutter, ...
                            4 * ones(1, idx),... 
                            obj.siteTX.AntennaHeight, ...
                            obj.siteRX.AntennaHeight, ...
                            1, ...
                            'phi_t', obj.siteTX.Latitude, ...
                            'phi_r', obj.siteRX.Latitude, ...
                            'lam_t', obj.siteTX.Longitude, ...
                            'lam_r', obj.siteRX.Longitude, ...
                            'pL', pL, ...
                            'sigmaL', sigmaL, ...
                            'Ptx', PTX);
            else
                obj.PRX = PTX;
                obj.Lb = 0;
            end
            obj.PRX = obj.PRX + gAnt;
            obj.Lb = obj.Lb - gAnt;
        end
    end
end