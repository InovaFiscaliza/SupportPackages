function Measures(specData, idxThread, idxEmission, orientation, varargin)

    arguments
        specData    model.SpecData
        idxThread   {mustBeInteger, mustBeNonnegative, mustBeFinite} =  1
        idxEmission {mustBeInteger, mustBeFinite} = -1
        orientation {mustBeMember(orientation, {'Band', 'Channel', 'Emission'})} = 'Band'
    end

    arguments (Repeating)
        varargin
    end

    switch orientation
        case 'Band'
            % BAND
            % (a) "Level"
            %      Mínimo, médio e máximo por bin, armazenando a informação em 
            %      specData(idxThread).Data{3}.
            % (b) "Occupancy"
            %     FCO por bin, armazenando a informaçãoem specData(idxThread).UserData.occCache 
            %     e specData(idxThread).UserData.occoccMethod.CacheIndex.
            %     FBO da banda.
            % (c) "BandWidth"
            %     Não aplicável.

        case 'Channel'
            channelObj = varargin{1};

            % CHANNEL: itera em todos os canais
            % (a) "Level"
            %      Potência do canal.         reportChannelTable    = []
                reportChannelAnalysis = []
            % (b) "Occupancy"
            %     Aferida ocupação por ponto de frequência, armazenando a informação
            %     em specData(idxThread).UserData.occCache e
            %     specData(idxThread).UserData.occoccMethod.CacheIndex
            % (c) "BandWidth"
            %     Não aplicável.
            chTable  = specData(idxThread).UserData.reportChannelTable;
            if isempty(chTable)
                chTable = ChannelTable2Plot(channelObj, specData(idxThread));
                specData(idxThread).UserData.reportChannelTable = chTable;
            end

        case 'Emission'
            % EMISSION: emissão específica
            specData(idxThread).UserData.Emissions(idxEmission, :);

    end
end