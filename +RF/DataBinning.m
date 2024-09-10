classdef (Abstract) DataBinning
    
    methods (Static = true)
        %-----------------------------------------------------------------%
        function specRawTable = RawTableCreation(specData, idxThread, idxEmission)
            Timestamp = specData(idxThread).Data{1}';
            
            Latitude  = [];
            Longitude = [];
            for ii = 1:height(specData(idxThread).RelatedFiles)
                Latitude  = [Latitude;  specData(idxThread).RelatedFiles.GPS{ii}.Matrix(:,1)];
                Longitude = [Longitude; specData(idxThread).RelatedFiles.GPS{ii}.Matrix(:,2)];
            end
            
            emissionFrequency = specData(idxThread).UserData.Emissions.Frequency(idxEmission) * 1e+6;
            emissionBW        = specData(idxThread).UserData.Emissions.BW(idxEmission)        * 1e+3;
            emissionPower     = RF.ChannelPower(specData(idxThread), [emissionFrequency-emissionBW/2, emissionFrequency+emissionBW/2]);

            specRawTable      = table(Timestamp, Latitude, Longitude, emissionPower);
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
        
            [specRawTable, specFilteredTable, filterSpec] = RF.DataBinning.Filtering(specRawTable, filterSpec);
        
            [binLat,   ...
             binLong,  ...
             binCount]  = hista(specFilteredTable.Latitude, specFilteredTable.Longitude, (binningLength/1000)^2);            
            
            [binLatEq, ...
             binLongEq] = grn2eqa(binLat, binLong);
        
            dist = pdist2([specFilteredTable.LongEq, specFilteredTable.LatEq], [binLongEq, binLatEq]);            
            [~, specFilteredTable.FK2] = min(dist, [], 2);
            
            switch binningFcn
                case 'min';    binFcn = @min;
                case 'mean';   binFcn = @(x) pow2db(  mean(db2pow(x)));
                case 'median'; binFcn = @(x) pow2db(median(db2pow(x)));
                case 'rms';    binFcn = @(x) pow2db(   rms(db2pow(x)));
                case 'max';    binFcn = @max;
            end
            binPower = splitapply(binFcn, specFilteredTable.emissionPower, specFilteredTable.FK2);
        
            % Mapeamento entre a tabela com os dados filtrados - specFilteredTable - e a
            % tabela com os dados sumarizados no processo de DataBinning - binTable.
            PK2 = int32(1:numel(binLat))';        
            specBinTable = table(binLat, binLong, binPower, binCount, PK2);

            % Sumário do processo:
            binningSummary = RF.DataBinning.About(specRawTable, specFilteredTable, specBinTable, binningLength, binningFcn);
        end
  
        %-------------------------------------------------------------------------%
        function [specRawTable, specFilteredTable, filterSpec] = Filtering(specRawTable, filterSpec)
            arguments
                % Tabela com colunas "Timestamp", "Latitude", "Longitude" e 
                % "emissionPower".
                specRawTable  table
        
                % Tabela com colunas "type", "subtype", "roi" e "enable".
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
                    idy1 = specRawTable.emissionPower >= filterSpec.roi(ii).handle.Position(3);
                end
        
                idy2 = zeros(height(specRawTable), 1, 'logical');
                for ii = idx2'
                    idy2 = or(idy2, inROI(filterSpec.roi(ii).handle, specRawTable.Latitude, specRawTable.Longitude));
                end
        
                idy = and(idy1, idy2);
        
            elseif ~isempty(idx1)
                for ii = idx1'
                    idy1 = specRawTable.emissionPower >= filterSpec.roi(ii).handle.Position(3);
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
        
            specRawTable.filtered      = idy;
            specRawTable.PK1           = int32(1:height(specRawTable))';
        
            % A tabela com os dados filtrados - specFilteredTable - não copia apenas
            % a coluna "Timestamp".
            specFilteredTable          = specRawTable(idy,2:4);
            [specFilteredTable.LatEq, ...
             specFilteredTable.LongEq] = grn2eqa(specFilteredTable.Latitude, specFilteredTable.Longitude);
        
            % Mapeamento entre a tabela com os dados filtrados - specFilteredTable - e as
            % outras tabelas...
            specFilteredTable.FK1      = find(idy);
            specFilteredTable.FK2      = -1*ones(height(specFilteredTable), 1, 'int32');
        
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
            locIndex = specFilteredTable.FK2(1);
            for ii = 1:height(specFilteredTable)
                if locIndex(end) ~= specFilteredTable.FK2(ii)
                    locIndex(end+1,1) = specFilteredTable.FK2(ii);
                end
            end

            nRaw      = height(specRawTable);
            nFiltered = height(specFilteredTable);
            nBin      = height(specBinTable);
            nLocIndex = numel(locIndex);

            % Identifica os limites do quantitativo de medições por quadrícula.
            [binCount_min, binCount_max] = bounds(specBinTable.binCount);

            if nLocIndex >= 2
                % Identifica as distâncias entre medições subsequentes que
                % estão relacionadas a quadrículas diferentes.
                ptDist = deg2km(distance('gc', [specBinTable.binLat(locIndex(1:end-1)), specBinTable.binLong(locIndex(1:end-1))], ...
                                               [specBinTable.binLat(locIndex(2:end)),   specBinTable.binLong(locIndex(2:end))]));
                [ptDist_min, ptDist_max] = bounds(ptDist*1000);
                ptDist_mean = mean(ptDist)*1000; 
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
                            '•&thinsp;Quadrícula menos visitada agrupou %d medições\n'                             ...
                            '•&thinsp;Quadrícula mais visitada agrupou %d medições\n\n'], binningLength, nBin, binningFcn, binCount_min, binCount_max);
            
            if (nLocIndex >= 2) && (nLocIndex ~= nBin)
                msg4 = sprintf(['Ao longo da rota, foram identificadas %d medições subsequentes que estão relacionadas '                 ...
                                'a quadrículas diferentes, apesar das medições terem sido agrupadas em apenas %d quadrículas.\n'         ...
                                '•&thinsp;Medições subsequentes mais próximas registradas a %.0f metros de distância uma da outra\n'    ...
                                '•&thinsp;Medições subsequentes mais distantes registradas a %.0f metros de distância uma da outra\n\n' ...
                                'Na média, entretanto, <b>as medições subsequentes foram registradas a %.0f metros de distância umas das outras</b>.'], nLocIndex, nBin, ptDist_min, ptDist_max, ptDist_mean);
            else
                msg4 = '';
            end
    
            binningSummary = [msg1, msg2, msg3, msg4];
        end
    end
end