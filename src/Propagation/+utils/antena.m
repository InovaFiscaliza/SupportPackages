classdef antena < handle
    % Classe definida para receber dados das antenas
    % Nome: definição da antena, p.ex.: modelo
    % Tipo: classificação se trata-se de uma antena usada para transmissão
    %       ou recepção
    % Azimute: azimute da antena (GMS)
    % Tilt_mec: valor da inclinação mecânica (+90° a -90°) GMS
    % Tilt_ele: valor da inclinação elétrica (+90° a -90°) GMS
    % Ganho: ganho máximo da antena (dBi)
    % V_ganho: matrix 2 colunas ganho vertical. Coluna 1: ângulo, 
    %          coluna 2: ganho
    % H_ganho: matrix 2 colunas ganho horizontal. Coluna 1: ângulo, 
    %          coluna 2: ganho
    %----------------------------------------------------------------------

    properties
        Nome char
        Tipo char {mustBeMember(Tipo, {'TX', 'RX'})} = 'TX'
        Azimute double {mustBeInRange(Azimute,0,360,"exclude-upper")} = 0.0
        Tilt_mec double {mustBeInRange(Tilt_mec,-90, 90)} = 0.0
        Tilt_ele double {mustBeInRange(Tilt_ele,-180, 180)} = 0.0
        Ganho double = 0.0
        V_ganho (:,2) double
        H_ganho (:,2) double
    end

    methods

        function obj = antena(Nome, Tipo, Azimute, Tilt_mec)
            obj.Nome = Nome;
            obj.Tipo = Tipo;
            obj.Azimute = Azimute;
            obj.Tilt_mec = Tilt_mec;
        end

        %---------------------------------------------------------------------------------
        function [gDirecaoH, gDirecaoV] = ganhoDirecao(obj, azimutePonto, inclinacaoPonto)
            %------------------------------------------------------------------
            % Retorna os ganhos da antena nas direões horizontais e verticais
            % gDirecaoH: ganho horizonal (dBi)
            % gDirecaoV: ganho vertical (dBi)
            % azimutePonto: azimute do ponto de interesse em relação ao eixo 
            %   ao eixo principal da antena da estação (GMS).
            % inclinacaoPonto: ângulo de inclinação do ponto de interesse em
            %   relação ao segmento perpendicular a normal do ponto da estação,
            %   i.e. em relação a linha do horizonte.
            %------------------------------------------------------------------
    
            arguments
                
                obj
                azimutePonto double {mustBeInRange(azimutePonto, -360, 360, "exclusive")}
                inclinacaoPonto double {mustBeInRange(inclinacaoPonto, -180, 180, "exclusive")}
            
            end

            %------------------------------------------------------------------
            % extração do ganho horizontal
            
            % calculo da posição relativa do ponto em relação ao azimute da
            % antena
            azimutePontoAjustado = wrapTo360(azimutePonto - obj.Azimute);
            
            % ganho horizontal da antena na direção do ponto 
            gDirecaoH = interp1([obj.H_ganho(:, 1); 360], [obj.H_ganho(:, 2); obj.H_ganho(1,2)], azimutePontoAjustado);
    
            %------------------------------------------------------------------
            % extração do ganho vertical
    
            % calculo da inclinação relativa do ponto em realcao a antena
            if inclinacaoPonto <=  (obj.Tilt_mec + obj.Tilt_ele)
                inclinacaoPontoAjustada = wrapTo360(inclinacaoPonto + obj.Tilt_ele + obj.Tilt_mec);
            else
                inclinacaoPontoAjustada = wrapTo360( -inclinacaoPonto - obj.Tilt_ele - obj.Tilt_mec);
            end
            % ganho vertical da antena da direção do ponto
            gDirecaoV = interp1([obj.V_ganho(:, 1); 360], [obj.V_ganho(:, 2); obj.V_ganho(1,2)], inclinacaoPontoAjustada);

        end
        %------------------------------------------------------------------
        
        function plotDiagramas(obj)
            %--------------------------------------------------------------
            % plota os diagramas horizontais e verticais da antena
            %--------------------------------------------------------------
            figure;
            subplot(1,2,1);
            ganhoH = obj.Ganho - obj.H_ganho(:, 2);
            polarplot(deg2rad(obj.H_ganho(:, 1)), ganhoH);
            rlim([ceil(min(ganhoH)) ceil(max(ganhoH))]);
            title("Diagrama Horizontal");

            subplot(1,2,2);
            ganhoV = obj.Ganho - obj.V_ganho(:, 2);
            polarplot(deg2rad(obj.V_ganho(:, 1)), ganhoV);
            rlim([ceil(min(ganhoV)) ceil(max(ganhoV))]);
            title("Diagrama Vertical");
        end
    
    end

end

