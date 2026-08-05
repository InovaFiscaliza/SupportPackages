function [lb, pwrRx, ganhosAnt] = predicao_area(raio_m, dadosPredicao, A , R, C, S, lb , ganhosAnt)
    %----------------------------------------------------------------------
    % Calcula a predição e cobertura de uma área
    %
    % fileData: arquivo que contém a estrutura com parâmetros da predição
    %       dadosPredicao: nome da struct
    %               modelo de predição: ['Hata', 'P.1812']
    %               frequencia: frequência da análise (Hz)
    %               dadosRelevo: arquivo geotif com dados de elevação em metros da
    %                   área de análise 
    %               dadosClutter: arquivo geotif com dados de classificação
    %                   da cobertura do terreno na área de análise
    %               Movel:
    %                   Antena:
    %                       Altura: altura da antena (m)
    %               Base:
    %                   Nome: nome da estação
    %                   Latitude: latitude da estação (graus decimais)
    %                   Longitude: longitude da estação (graus decimais)
    %                   Potencia: potência do transmissor (W)
    %                   Antena:
    %                       Altura: altura da antena (m)
    %                       ArquivoDados: arquivo de informações e diagrama
    %                       de irradiação da antena
    %                       Modelo: nome do modelo da antena
    %                       Funcao: ['TX', 'RX']
    %                       Azimute: azimute a antena
    %                       tiltMecanico: inclinação da antena
    %                       Tipo: ['isotropic', 'array']
    %
    %   Lb: matriz de valores de atenuação calculada para cada célula do
    %       geotif da área de análise (dB)
    %   Pwr_rx: matriz de valores de nível de sinal recebido calculado para
    %           cada célula do geotif da área de análise
    %----------------------------------------------------------------------
   
    arguments
        raio_m  
        dadosPredicao struct {mustBeNonempty}
        A = []
        R = []
        C = []
        S = []
        lb = []
        ganhosAnt = []
    end
    
    %----------------------------------------------------------------------
    % Carrega os parâmetros utilizados para realizar a predição


    modelo = dadosPredicao.modeloPredicao;

    %----------------------------------------------------------------------
    % Dados da estação base
    base = txsite("Name", dadosPredicao.Base.Nome,...
        "Latitude", dadosPredicao.Base.Latitude,...
        "Longitude", dadosPredicao.Base.Longitude,...
        "Antenna", dadosPredicao.Base.Antena.Tipo,...
        "AntennaHeight", dadosPredicao.Base.Antena.Altura,...
        "TransmitterFrequency", dadosPredicao.frequencia,...
        "TransmitterPower", dadosPredicao.Base.Potencia);
    
    % Carrega os dados da antena
    
    antenaBase = utils.readAntennaData(dadosPredicao.Base.Antena.ArquivoDados, dadosPredicao.Base.Antena.Modelo,...
        dadosPredicao.Base.Antena.Funcao, dadosPredicao.Base.Antena.Azimute, dadosPredicao.Base.Antena.tiltMecanico);

    %----------------------------------------------------------------------
    % Caracteristicas da area
    % Carrega dados do relevo
    if isempty(A) || isempty(R)
        [A, R] = utils.loadRaster(dadosPredicao.dadosRelevo, true);
        [A, R] = utils.resizeGeotiff(A, R);
    end
    sizeA = size(A);
    %--------------------------------------------------------------------------
    % Carrega dados do clutter, se não houver arqivo de clutter uma matriz
    % default com representação área aberta/rural
    if  isempty(C) || isempty(S)
        if ~isempty(dadosPredicao.dadosClutter)

            [C, S] = utils.read_clutter(dadosPredicao.dadosClutter);
            [C, S] = utils.resizeGeotiff(C, S);

        else

            C = 2 * ones(sizeA);
            S = R;

        end
    end
    
    C = double(C);
    
    %--------------------------------------------------------------------------
    % Cria variáveis de saída

    lb = -Inf(sizeA);
    ganhosAnt = -Inf(sizeA);
    
    %--------------------------------------------------------------------------
    % elevação da estação Base
    [n, m] = utils.get_raster_idx(base.Latitude, base.Longitude, R);
    elevBase = A(n, m);

    %--------------------------------------------------------------------------
    % clutter da estação Base
    clutBase = C(n,m);


    %----------------------------------------------------------------------
    % Calcula as células que compõem a borda da area de predição 
    % raio em número de células
    raioC = round(raio_m/((R.CellExtentInLatitude * 111320)));
    
    % indices da celula que abriga a estação base
    txN = n;
    txM = m;

    %----------------------------------------------------------------------
    % Cria uma máscara para todas células que compõem a mancha
    [M, N] = meshgrid(1:size(A, 2), 1:size(A, 1));
    mascaraDentro = ((M + 2) - txM).^2 + ((N + 2) - txN).^2 <= raioC^2;
    idxmascara = find(mascaraDentro);

    
    %--------------------------------------------------------------------------
    % Prepara loop de execução para carregar as coordenadas do centro de todas 
    % as células
    % centro_i =  -R.CellExtentInLatitude / 2;
    % centro_j =  R.CellExtentInLongitude / 2;
    % 
    % latitudes = R.LatitudeLimits(2):...
    %     -R.CellExtentInLatitude:...
    %     R.LatitudeLimits(1);
    % latitudes = latitudes + centro_i;
    % longitudes = R.LongitudeLimits(1):...
    %     R.CellExtentInLongitude:...
    %     R.LongitudeLimits(2);
    % longitudes = longitudes + centro_j;
    
    [latitudes, longitudes] = arrayfun(@(idx) utils.idxToLatLon(idx, sizeA, R), idxmascara);

    %--------------------------------------------------------------------------
    % Inicializa o loop com dados da primeira célula 
    RX = rxsite("AntennaHeight",dadosPredicao.Movel.Antena.Altura);

    %--------------------------------------------------------------------------
    % Inicializas a classe de predição conforme o modelo a ser utilizado
    switch modelo
        case 'Hata'
            predicao = model.Hata(base, RX, A, R, C, S);

        case 'P.1812'
           predicao = model.P1812(base, RX, A, R, C, S);

        case 'P.526'
           predicao = model.P526(base, RX, A, R, C, S);
    end
    %--------------------------------------------------------------------------
    % Cria barra de progresso
    %d = uiprogressdlg(uifigure);
    
    %--------------------------------------------------------------------------
    % Loop de execução
    

    %for n = 1:Llat
 
        % percent_exec = ((n - 1) * Llon + m)/(Llat * Llon);
        % d.Message = sprintf('Executado: %.1f %%', (percent_exec * 100));
        % d.Value = percent_exec;
        
        %for m = 1:Llon

   for ii = 1:numel(idxmascara)
            
            [n, m] = ind2sub(sizeA, idxmascara(ii));
            
            RX.Latitude = latitudes(ii);
            RX.Longitude = longitudes(ii);
            
            %------------------------------------------------------------------
            % encontra distancia, azimute e inclinação do ponto em relação a
            % estação TX
            [distanciaPonto, azimutePonto] = utils.Propagation.Distance(base, RX, "m");
            inclinacaoPonto = rad2deg(atan(((RX.AntennaHeight + A(n, m)) - (base.AntennaHeight + elevBase)) / distanciaPonto));
            
            %------------------------------------------------------------------
            % extrai os dados de ganho na direção do ponto
            [gH, gV] = antenaBase.ganhoDirecao(azimutePonto, inclinacaoPonto);
            gAnt = antenaBase.Ganho - gH - gV;
            
            %------------------------------------------------------------------
            % calcula a atenuação e nível de sinal recebido
            predicao.siteRX = RX;
            calculo(predicao, gAnt);
            lb(n, m) = predicao.Lb;
            ganhosAnt(n, m) = gAnt;
 
    end
    %close(d)
    %lb(~mascaraDentro) = -Inf;
    %EpPtx = 199.36 + 20*log10(base.TransmitterFrequency) + 10*log10(base.TransmitterPower / 1e3);
    pwrRx =  10*log10(base.TransmitterPower/1e-3) - lb;

end