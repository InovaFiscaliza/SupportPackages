function [Lb, E] = calcPredicaoEnlace(preditionData, rxSite, txAntenna, rxAntenna, distM, Azimuth, d1, wayPoints3D)
%calcPredicaoEnlace Instancia e executa o modelo de predição para um enlace
%   [Lb, E] = calcPredicaoEnlace(preditionData, rxSite, txAntenna, rxAntenna, distM, Azimuth, d1, wayPoints3D)
%
%   Parâmetros de entrada:
%   preditionData  - struct com campos Base, Movel, frequencia e modeloPredicao
%   rxSite         - objeto rxsite (fornece Latitude e Longitude do móvel)
%   txAntenna      - altura da antena TX acima do nível do mar (m)
%   rxAntenna      - altura da antena RX acima do nível do mar (m)
%   distM          - distância TX-RX em metros
%   Azimuth        - azimute de TX para RX (graus)
%   d1             - vetor de distâncias cumulativas do perfil (m), coluna ou linha
%   wayPoints3D    - matriz Nx3 [lat, lon, elevação(m)]
%
%   Parâmetros de saída:
%   Lb             - atenuação básica de transmissão (dB)
%   E              - intensidade de campo elétrico em relação a Ptx (dBuV/m)

TX = txsite("Name",                 preditionData.Base.Nome, ...
            "Latitude",             preditionData.Base.Latitude, ...
            "Longitude",            preditionData.Base.Longitude, ...
            "Antenna",              preditionData.Base.Antena.Tipo, ...
            "AntennaHeight",        preditionData.Base.Antena.Altura, ...
            "TransmitterFrequency", preditionData.frequencia, ...   % Hz
            "TransmitterPower",     preditionData.Base.Potencia);   % W

RX = rxsite("Latitude",      rxSite.Latitude, ...
            "Longitude",     rxSite.Longitude, ...
            "AntennaHeight", preditionData.Movel.Antena.Altura);

A = ones(2,2);
C = A;
R = [];
S = R;

% Leitura do padrão de antena e cálculo do ganho na direção do enlace
antenaBase = utils.readAntennaData(preditionData.Base.Antena.ArquivoDados, ...
                                   preditionData.Base.Antena.Modelo, ...
                                   preditionData.Base.Antena.Funcao, ...
                                   preditionData.Base.Antena.Azimute, ...
                                   preditionData.Base.Antena.tiltMecanico);

elevAngle = atand((rxAntenna - txAntenna) / distM);
[gDirecaoH, gDirecaoV] = antenaBase.ganhoDirecao(Azimuth, elevAngle);
gAnt = antenaBase.Ganho - gDirecaoH - gDirecaoV;

% Perfil de propagação (compartilhado entre os modelos)
perfilDist    = d1(:)' ./ 1000;                                 % m → km, garante vetor linha
perfilElev    = wayPoints3D(:, end)';
perfilClutter = zeros(1, numel(perfilElev));

switch preditionData.modeloPredicao

    case 'P.526'
        predicao = model.P526(TX, RX, A, R, C, S);
        predicao.calculo(gAnt, ...
            'perfil_distancia', perfilDist, ...
            'perfil_elevacao',  perfilElev, ...
            'perfil_clutter',   perfilClutter);

    case 'P.1812'
        espacamento_m = distM / (numel(d1) - 1);
        sigmaL = ((24e-3 * (preditionData.frequencia / 1e9) + 0.52) * espacamento_m) ^ 0.28;

        predicao = model.P1812(TX, RX, A, R, C, S);
        predicao.calculo(gAnt, ...
            'perfil_distancia', perfilDist, ...
            'perfil_elevacao',  perfilElev, ...
            'perfil_clutter',   perfilClutter, ...
            'sigmaL',           sigmaL);

    otherwise
        warning('utils.calcPredicaoEnlace: modelo "%s" não suportado.', preditionData.modeloPredicao);
        Lb = NaN;
        E  = NaN;
        return
end

Lb = predicao.Lb;
E  = predicao.PRX;
end
