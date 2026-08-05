function antenaObj = readAntennaData(filename, Nome, Tipo, Azimute, Tilt_mec, Ganho)
    %----------------------------------------------------------
    % Carrega a função parse para cada extensão de arquivo de 
    % definição de características de antena e retorna um objeto
    % da classe utils/antena
    %
    % filename: arquivo de dados da antena
    % Nome: nome ou modelo da antena
    % Tipo: uso como 'TX' ou 'RX'
    % Azimute: azimute da antena (GMS)
    % Tilt_mec: valor da inclinação mecânica (+90° a -90°) GMS
    %
    %-----------------------------------------------------------

    arguments

        filename
        Nome char
        Tipo char {mustBeMember(Tipo, {'TX', 'RX'})} = 'TX'
        Azimute double {mustBeInRange(Azimute,0,360,"exclude-upper")} = 0.0
        Tilt_mec double {mustBeInRange(Tilt_mec,-90, 90)} = 0.0
        Ganho double = 0.0;
   
    end

    %-------------------------------------------------------------
    % instancia um objeto utils.antena e carrega as propriedades
    % informadas pelos argumentos da função
    
    antenaObj = utils.antena(Nome, Tipo, Azimute, Tilt_mec);

    if isfile(filename)
        %--------------------------------------------------------------
        % verfica se o arquivo de dados da antena é do tipo .msi
    
        if endsWith(upper(filename), '.MSI')
            %----------------------------------------------------------
            % carrega o arquivo
        
            antenaData = utils.getMsiData(filename);
            
            %----------------------------------------------------------
            % parse dos dados
            antenaObj.Ganho = antenaData.Data(2);
    
            % Verifica o número de amostra de ganho horizontal
            nAmostrasH = antenaData.Data(5);
    
            % carrega o array de ganhos horizontais
            ganhoH = zeros(nAmostrasH ,2);
            ganhoH(:, 1) = antenaData.NAME(6: nAmostrasH + 5);
    
            ganhoH(:, 2) = antenaData.Data(6: nAmostrasH + 5);
            antenaObj.H_ganho = double(ganhoH);
    
            % carrega o array de ganhos vertiais
            nAmostrasV = antenaData.Data(nAmostrasH + 6);
            ganhoV = zeros(nAmostrasV, 2);
            
            ganhoV(:, 1) = antenaData.NAME(nAmostrasH + 7 : nAmostrasV + nAmostrasH + 6);
            
            ganhoV(:, 2) = antenaData.Data(nAmostrasH + 7 : nAmostrasV + nAmostrasH + 6);
            antenaObj.V_ganho = double(ganhoV);
    
        else
            error("Pendente de implementação")
    
        end
    
    else
        % Valor padrão para o caso de não carregar o arquivo da antena
        antenaObj.Ganho = Ganho;
        antenaObj.V_ganho = [(0:359)', zeros(360,1)];

        if ~isempty(filename)
            antenaObj.H_ganho = utils.categoricalPatternToArray(filename);
        else
            antenaObj.H_ganho = antenaObj.V_ganho;
        end

    end
    
end