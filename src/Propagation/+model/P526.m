classdef P526 < model.PropagationBase
    %----------------------------------------------------------------------
    % Cálculo de predição de cobertura conforme modelo ITU-R P.526-15
    %----------------------------------------------------------------------

    methods
        
        function calculo(obj, gAnt, varargin)
            %--------------------------------------------------------------
            % Calcula o nivel de sinal recebido e a atenuação até a estação
            % de recepção
            % gAnt: ganho da antena
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
            addParameter(ip, 'perfil_distancia', [], @isnumeric);
            addParameter(ip, 'perfil_elevacao', [], @isnumeric);
            addParameter(ip, 'perfil_clutter', [], @isnumeric);

            parse(ip, varargin{:});
            
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

            idx = size(perfil_distancia, 2);

            if idx > 2
                [obj.Lb, obj.PRX] = model.p526.tl_p526(obj.siteTX.TransmitterFrequency/1e9, ...  % GHz
                            perfil_distancia, ... %(1:idx)./1000, ...
                            perfil_elevacao, ... %(1:idx), ...
                            alturas_clutter, ...
                            obj.siteTX.AntennaHeight, ...
                            obj.siteRX.AntennaHeight, ...
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