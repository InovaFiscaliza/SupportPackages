classdef PropagationBase < handle
    % base para os modelos de propagação
    % Lb: atenuação resultante (dB)
    % PRX: intensidade de campo elétrico (dBuV/m)
    % gAnt: ganho da antena
    % siteTX: classe TX
    % siteRX: classe RX
    % A, R: geoTiff [A, R] dados de elevação
    % C, S: geoTiff [A, R] dados de clutter
    %----------------------------------------------------------------------
    
    properties
        Lb double
        PRX double
        siteTX txsite
        siteRX rxsite
        A (:, :) double
        R
        C (:, :) double
        S
    end
    
    methods
        function obj = PropagationBase(siteTX, siteRX, A, R, C, S)
            obj.siteTX = siteTX;
            obj.siteRX = siteRX;
            obj.A = A;
            obj.R = R;
            obj.C = C;
            obj.S = S;
        end
    end
end

