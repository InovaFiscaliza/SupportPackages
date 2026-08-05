function [Lb, Ep] = tl_p526(f, d, h, R, htg, hrg, varargin)
%tl_p526 basic transmission loss according to P.526-15
%   [Lb Ep] = tl_p526(f, d, h, R, htg, hrg, varargin)
%
%   Esta é a FUNÇÃO PRINCIPAL que calcula a perda básica de transmissão
%   e a intensidade de campo conforme definido na recomendação ITU-R P.526-15
%
%   As demais funções chamadas por esta função estão na subpasta ./private/
%
%     Parâmetros de entrada:
%     f       -   Frequência (GHz)
%     d       -   vetor de distâncias di do i-ésimo ponto do perfil (km)
%     h       -   vetor de alturas hi do i-ésimo ponto do perfil (metros
%                 acima do nível médio do mar)
%     R       -   vetor de altura representativa de obstruções Ri do i-ésimo ponto do perfil (m)
%     htg     -   Altura do centro da antena transmissora em relação ao solo (m)
%     hrg     -   Altura do centro da antena receptora em relação ao solo (m)
%
%     Parâmetros de saída:
%     Lb      -   Perda básica de transmissão conforme P.1812-6
%     Ep      -   Intensidade de campo em relação a Ptx
%
%     Argumentos opcionais (Par Valor-Nome):
%     Ptx     -   Potência do transmissor (kW), valor padrão 1 kW
%     debug   -   Definir como 1 para gerar arquivos de log,
%                 valor padrão 0 (não gerar)
%     fid_log -   Se debug == 1, pode ser fornecido um identificador de arquivo
%                 para o log. Caso contrário, será criado um arquivo padrão
%                 com timestamp no nome
%

%
%    Numbers refer to Rec. ITU-R P.526-15

%     Rev   Date        Author                          Description
%     -------------------------------------------------------------------------------
%     v0    03ABR25     Marcelo Nunes, Anatel         Initial version for ITU-R P.526-15

%

% MATLAB Version 24.2.0.2833386 (R2024b) used in development of this code
%
% The Software is provided "AS IS" WITH NO WARRANTIES, EXPRESS OR IMPLIED, 
% INCLUDING BUT NOT LIMITED TO, THE WARRANTIES OF MERCHANTABILITY, FITNESS 
% FOR A PARTICULAR PURPOSE AND NON-INFRINGMENT OF INTELLECTUAL PROPERTY RIGHTS 
% 
% Neither the Software Copyright Holder (or its affiliates) nor the ITU 
% shall be held liable in any event for any damages whatsoever
% (including, without limitation, damages for loss of profits, business 
% interruption, loss of information, or any other pecuniary loss)
% arising out of or related to the use of or inability to use the Software.
%
% THE AUTHOR(S) AND ANATEL DO NOT PROVIDE ANY SUPPORT FOR THIS SOFTWARE
%



%% Lê os argumentos de entrada e valida

% arguments
%     f double {mustBeNumeric, mustBeNonNan, mustBeNonempty}
%     d (:, 1) double
%     h (:, 1) double
%     R (:, 1) double
%     htg double {mustBeNumeric, mustBeNonNan, mustBeNonempty}
%     hrg double {mustBeNumeric, mustBeNonNan, mustBeNonempty}
% end
% 
% arguments (Repeating)
%    varargin
% end

% Parse dos inputs opicionais

iP = inputParser;
addParameter(iP, 'Ptx', 1, @isnumeric);
addParameter(iP, 'debug', 0, @isnumeric);
addParameter(iP, 'fid_log',[], @isstring);

parse(iP, varargin{:});

% Unpack from input parser
debug = iP.Results.debug;
fid_log = iP.Results.fid_log;
Ptx = iP.Results.Ptx;


NN=numel(d);

% the number of elements in d and path need to be the same
if(numel(h) ~= NN)
    error('The number of elements in the array ''d'' and array ''h'' must be the same.')
end

if isempty(R)
    R=zeros(size(h)); % default is clutter height zero
else
    if(numel(R) ~= NN)
        error('The number of elements in the array ''d'' and array ''R'' must be the same.')
    end
end



% O identificador de arquivo (handle) fidlog é reservado aqui para gravação dos arquivos
% Se fidlog já estiver aberto fora desta função, o arquivo precisa estar
% vazio (nada escrito), caso contrário será fechado e reaberto
% Se fid não estiver aberto, então um arquivo com nome correspondente ao
% timestamp será aberto e fechado dentro desta função.

inside_file = 0;
if (debug)
    if (isempty (fid_log))
        fid_log = fopen(['P526_' num2str(floor(datetime("now")*1e10)) '_log.csv'],'w');
        inside_file = 1;
        if (fid_log == -1)
            error('The log file could not be opened.')
        end
    else
        inside_file = 0;
    end
end

floatformat= '%.10g,\n';

if (debug)
    
    fprintf(fid_log,'# Parameter,Ref,,Value,\n');
    fprintf(fid_log,['Ptx (kW),,,' floatformat],Ptx);
    fprintf(fid_log,['f (GHz),,,' floatformat],f);
    fprintf(fid_log,['htg (m),,,' floatformat],htg);
    fprintf(fid_log,['hrg (m),,,' floatformat],hrg);
    fprintf(fid_log,['R2 (m) ,,,' floatformat],R(2));
    fprintf(fid_log,['Rn-1 (m) ,,,' floatformat],R(end-1));
    
end


%--------------------------------------------------------------------------
% definições

% raio efetivo da Terra
Re = 6371;

% Alturas das antenas de Tx e Rx acima do nível do mar (m)
hts = h(1) + htg;
hrs = h(end) + hrg;


% Representação das alturas do clutter
g = h + R;
g(1) = h(1);
g(end) = h(end);


%--------------------------------------------------------------------------
% Cálculo da atenuação no espaço livre
dfs = sqrt(d(end).^2 + ((hts - hrs)/1000.0).^2);

lEl = 92.4 + 20.0*log10(f) + 20.0*log10(dfs);

%--------------------------------------------------------------------------
% Cálculo da atenuação pelo método de Bullington
lBull = dl_bull(d, g, hts, hrs, Re, f);


%--------------------------------------------------------------------------
% Cálculo da atenuação total
 Lb = lEl + lBull;

%--------------------------------------------------------------------------
% The field strength exceeded for p% time and pL% locations

Ep = 199.36 + 20*log10(f) - Lb; % eq (70)

% % Scale to the transmitter power

EpPtx = Ep + 10*log10(Ptx);


if (debug)
    fprintf(fid_log,['lEl (dB) (attenuação no espaço livre),' floatformat],lEl);
    fprintf(fid_log,['lBull (dB), (atenução por Bullington),' floatformat],lBull);
    fprintf(fid_log,['Lbulls (dB),Eq (21),,' floatformat],Lbulls50);
    fprintf(fid_log,['Lb (dB),Eq (69),,' floatformat],Lb);
    fprintf(fid_log,['Ep (dBuV/m),Eq (70),,' floatformat],Ep);
    fprintf(fid_log,['Ep (dBuV/m) w.r.t. Ptx,,,' floatformat],EpPtx);
end

Ep = EpPtx;

if (debug==1)
    
    if(inside_file)
        try
            fclose(fid_log);
        end
    end
    
end

return
end