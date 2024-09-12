classdef (Abstract) DataBinning
    
    methods (Static = true)
        %-----------------------------------------------------------------%
        function specRawTable = RawTableCreation(specData, idxThread, chAssigned)
            Timestamp = specData(idxThread).Data{1}';
            
            Latitude  = [];
            Longitude = [];
            for ii = 1:height(specData(idxThread).RelatedFiles)
                Latitude  = [Latitude;  specData(idxThread).RelatedFiles.GPS{ii}.Matrix(:,1)];
                Longitude = [Longitude; specData(idxThread).RelatedFiles.GPS{ii}.Matrix(:,2)];
            end
            
            Frequency    = chAssigned.Frequency * 1e+6; % MHz >> Hz
            ChannelBW    = chAssigned.ChannelBW * 1e+3; % kHz >> Hz
            ChannelPower = RF.ChannelPower(specData, idxThread, [Frequency-ChannelBW/2, Frequency+ChannelBW/2]);

            specRawTable = table(Timestamp, Latitude, Longitude, ChannelPower);
        end

        %-----------------------------------------------------------------%
        function [specRawTable, specFilteredTable, specBinTable, filterSpec, binningSummary] = execute(specRawTable, binningLength, binningFcn, filterSpec)
            arguments
                % Tabela com colunas "Timestamp", "Latitude", "Longitude" e 
                % "emissionPower".
                specRawTable  table
        
                % Distâncie entre quadrículas adjacentes, além da função de 
                % sumarização.
                binningLength double
                binningFcn    char {mustBeMember(binningFcn, {'min', 'mean', 'median', 'rms', 'max'})}
        
                % Tabela com colunas "type", "subtype", "roi" e "enable".
                filterSpec    table = table({}, {}, struct('handle', {}, 'specification', {}), true(0, 1), 'VariableNames', {'type', 'subtype', 'roi', 'enable'})
            end
        
            [specRawTable,      ...
             specFilteredTable, ...
             filterSpec]     = RF.DataBinning.Filtering(specRawTable, filterSpec);
        
            [binLatitude,  ...
             binLongitude, ...
             binMeasures]    = hista(specFilteredTable.Latitude, specFilteredTable.Longitude, (binningLength/1000)^2);            
            
            [binXYLatitude, ...
             binXYLongitude] = grn2eqa(binLatitude, binLongitude);
        
            Distance = pdist2([specFilteredTable.xyLongitude, specFilteredTable.xyLatitude], [binXYLongitude, binXYLatitude]);            
            [~, specFilteredTable.BinIndex] = min(Distance, [], 2);
            
            switch binningFcn
                case 'min';    binFcn = @min;
                case 'mean';   binFcn = @(x) pow2db(  mean(db2pow(x)));
                case 'median'; binFcn = @(x) pow2db(median(db2pow(x)));
                case 'rms';    binFcn = @(x) pow2db(   rms(db2pow(x)));
                case 'max';    binFcn = @max;
            end
            binPower = splitapply(binFcn, specFilteredTable.ChannelPower, specFilteredTable.BinIndex);
            
            specFilteredTable = removevars(specFilteredTable, {'xyLatitude', 'xyLongitude'});
            specBinTable      = table(binLatitude, binLongitude, binPower, binMeasures, 'VariableNames', {'Latitude', 'Longitude', 'ChannelPower', 'Measures'});            

            % Sumário do processo:
            binningSummary = RF.DataBinning.About(specRawTable, specFilteredTable, specBinTable, binningLength, binningFcn);
        end
  
        %-------------------------------------------------------------------------%
        function [specRawTable, specFilteredTable, filterSpec] = Filtering(specRawTable, filterSpec)
            arguments
                % Tabela com colunas "Timestamp", "Latitude", "Longitude" e 
                % "ChannelPower".
                specRawTable  table
        
                % Tabela com colunas "type", "subtype" e "roi".
                filterSpec    table
            end
        
            % O processo de filtragem é orientado às interações na GUI, inserindo
            % um FILTRO DE NÍVEL (ROI de linha) e FILTROS GEOGRÁFICOS (ROI circular, 
            % retangular ou poligonal).
        
            % (a) Coluna "type"...: "Level" | "Geographic ROI"
            % (b) Coluna "subtype": "Threshold" | "Circle" | "Rectangle" | "Polygon"
            % (c) Coluna "roi"....: estrutura com os campos "handle" e "specification"
            % (d) Coluna "enable".: true | false
        
            idy  = ones(height(specRawTable), 1, 'logical');
        
            idx1 = find(filterSpec.type == "Level");
            idx2 = find(filterSpec.type == "Geographic ROI");
        
            if ~isempty(idx1) & ~isempty(idx2)
                for ii = idx1'
                    idy1 = specRawTable.ChannelPower >= filterSpec.roi(ii).handle.Position(3);
                end
        
                idy2 = zeros(height(specRawTable), 1, 'logical');
                for ii = idx2'
                    idy2 = or(idy2, inROI(filterSpec.roi(ii).handle, specRawTable.Latitude, specRawTable.Longitude));
                end
        
                idy = and(idy1, idy2);
        
            elseif ~isempty(idx1)
                for ii = idx1'
                    idy1 = specRawTable.ChannelPower >= filterSpec.roi(ii).handle.Position(3);
                end
        
                idy = idy1;
        
            elseif ~isempty(idx2)
                idy2 = zeros(height(specRawTable), 1, 'logical');
                for ii = idx2'
                    idy2 = or(idy2, inROI(filterSpec.roi(ii).handle, specRawTable.Latitude, specRawTable.Longitude));
                end
        
                idy = idy2;                
            end
            
            if ~sum(idy)
                error('DataBinning:Filtering:NoneSamples', 'No sample was obtained when applying the set of filter. For this reason, the last added filter will be automatically removed.')
            end
        
            specRawTable.Filtered = idy;
        
            % A tabela com os dados filtrados - specFilteredTable - não copia apenas
            % a coluna "Timestamp".
            specFilteredTable     = specRawTable(idy,1:4);
            [specFilteredTable.xyLatitude, ...
             specFilteredTable.xyLongitude] = grn2eqa(specFilteredTable.Latitude, specFilteredTable.Longitude);
        
            if ~isempty(idx1)
                filterSpec.roi(idx1).handle.Position(2) = height(specFilteredTable);
            end
        end

        %-----------------------------------------------------------------%
        function binningSummary = About(specRawTable, specFilteredTable, specBinTable, binningLength, binningFcn)
            % Identifica os índices das quadrículas relacionadas a medições
            % subsequentes. O uso de UNIQUE não resolve porque pontos de 
            % medições subsequentes podem ser agrupados em quadrículas diferentes. 
            % E a mesma região pode ser passada mais de uma vez na rota, de 
            % forma que teríamos pontos de medição na quadrícula A, depois B, 
            % depois A de novo, por exemplo.
            locIndex = specFilteredTable.BinIndex(1);
            for ii = 1:height(specFilteredTable)
                if locIndex(end) ~= specFilteredTable.BinIndex(ii)
                    locIndex(end+1,1) = specFilteredTable.BinIndex(ii);
                end
            end

            nRaw      = height(specRawTable);
            nFiltered = height(specFilteredTable);
            nBin      = height(specBinTable);
            nLocIndex = numel(locIndex);

            % Identifica os limites do quantitativo de medições por quadrícula.
            [binCount_min, binCount_max] = bounds(specBinTable.Measures);

            if nLocIndex >= 2
                % Identifica as distâncias entre medições subsequentes que
                % estão relacionadas a quadrículas diferentes.
                ptDist = deg2km(distance('gc', [specBinTable.Latitude(locIndex(1:end-1)), specBinTable.Longitude(locIndex(1:end-1))], ...
                                               [specBinTable.Latitude(locIndex(2:end)),   specBinTable.Longitude(locIndex(2:end))]));
                [ptDist_min, ptDist_max] = bounds(ptDist*1000);
                ptDist_mode   = mode(ptDist)*1000;
                ptDist_median = median(ptDist)*1000;
                ptDist_mean   = mean(ptDist)*1000; 
            end
    
            % Sumário:
            msg1 = sprintf('A tarefa de monitoração sob análise registrou <b>%d medições</b>. ', nRaw);
            if nRaw == nFiltered
                msg2 = sprintf('Não foi aplicado filtro ordinário (nível, temporal, ou geográfico).\n\n');
            else
                msg2 = sprintf(['Foi aplicado ao menos um filtro ordinário (nível, temporal, ou '    ...
                                'geográfico), de forma que <b>%d medições (o que equivale a %.1f%% ' ...
                                'do total) foram excluídas</b>.\n\n'], nRaw-nFiltered, 100*(nRaw-nFiltered)/nRaw);
            end
            msg3 = sprintf(['As medições foram agrupadas em quadrículas distantes uma das outras '                  ...
                            'de aproximadamente <b>%d metros</b>. Ao final desse agrupamento, foram identificadas ' ...
                            'medições em <b>%d quadrículas</b>, as quais foram sumarizadas usando a função '        ...
                            'estatística "<b>%s</b>".\n'                                                            ...
                            '•&thinsp;A quadrícula menos visitada agrupou %d medições; e\n'                         ...
                            '•&thinsp;A quadrícula mais visitada agrupou %d medições.\n\n'], binningLength, nBin, binningFcn, binCount_min, binCount_max);
            
            if (nLocIndex >= 2) && (nLocIndex ~= nBin)
                msg4 = sprintf(['Ao longo da rota, foram identificadas %d medições subsequentes que estão relacionadas '                ...
                                'a quadrículas diferentes, apesar das medições terem sido agrupadas em %d quadrículas.\n'               ...
                                '•&thinsp;Medições subsequentes mais próximas registradas a %.0f metros de distância uma da outra; e\n' ...
                                '•&thinsp;Medições subsequentes mais longes registradas a %.0f metros de distância uma da outra.\n\n'   ...
                                'Em relação à tendência central dessas distâncias, a sua moda foi %.0f metros; a mediana, %.0f metros; e a média, %.0f metros.'], nLocIndex, nBin, ptDist_min, ptDist_max, ptDist_mode, ptDist_median, ptDist_mean);
            else
                msg4 = '';
            end
    
            binningSummary = [msg1, msg2, msg3, msg4];
        end
    end
end