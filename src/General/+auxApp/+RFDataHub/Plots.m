classdef (Abstract) Plots

    % Plots do módulo RFDataHub (auxApp.winRFDataHub): estações, TX, RX, 
    % enlace TX-RX (mapa e perfil de relevo), azimute e diagrama de radiação 
    % da antena. O perfil do enlace ("rfLinkProfile") é usado também por outros 
    % módulos.
    %
    % Os métodos recebem o eixo e os dados, sem acessar o app. Os eixos são
    % criados por "auxApp.RFDataHub.Axes.create".
    %
    % Estruturas "txSite" e "rxSite": campos Latitude, Longitude e AntennaHeight
    % (e TransmitterFrequency, em Hz, para "rfLinkProfile").

    properties (Constant)
        %-----------------------------------------------------------------%
        STATIONS_COLOR = '#00ffff'
        LINK_COLOR     = '#ff365e'  % RX, TX, enlace TX-RX e azimute
    end


    methods (Static = true)
        %-----------------------------------------------------------------%
        % MAPA (eixo geográfico)
        %-----------------------------------------------------------------%
        function stations(hAxes, stationsTable, latitudes, longitudes)
            % Substitui as estações plotadas, preservando TX. Com tabela vazia, 
            % apenas limpa o eixo.
            delete(findobj(hAxes.Children, '-not', 'Tag', 'TX'))

            if ~isempty(stationsTable)
                geolimits(hAxes, 'auto')

                color = auxApp.RFDataHub.Plots.STATIONS_COLOR;
                hStations = geoscatter(hAxes, latitudes, longitudes, ...
                    'MarkerEdgeColor', color, ...
                    'MarkerFaceColor', color, ...
                    'SizeData', 5, ...
                    'DisplayName', 'RFDataHub', ...
                    'Tag', 'Stations' ...
                );
                auxApp.RFDataHub.Datatips.apply(hStations, 'Stations', stationsTable)
            end
        end

        %-----------------------------------------------------------------%
        function rx(hAxes, rxSite)
            delete(findobj(hAxes.Children, 'Tag', 'RX'))

            color = auxApp.RFDataHub.Plots.LINK_COLOR;
            hRX = geoscatter(hAxes, rxSite.Latitude, rxSite.Longitude, ...
                'Marker', '^', ...
                'MarkerEdgeColor', color, ...
                'MarkerFaceColor', color, ...
                'SizeData', 92, ...
                'DisplayName', 'RX', ...
                'Tag', 'RX' ...
            );
            auxApp.RFDataHub.Datatips.apply(hRX, 'Coordinates')
        end

        %-----------------------------------------------------------------%
        function tx(hAxes, txSite, rxSite)
            % Plota o TX e a linha do enlace TX-RX. Com "txSite" vazio, 
            % apenas remove o TX e a linha do enlace.
            delete(findobj(hAxes.Children, 'Tag', 'TX'))
            delete(findobj(hAxes.Children, 'Tag', 'RFLink'))

            if ~isempty(txSite)
                color = auxApp.RFDataHub.Plots.LINK_COLOR;

                % Linha tracejada entre TX e RX (apenas os extremos). É criada 
                % antes do marcador TX para que este fique sobreposto.
                geoplot(hAxes, [txSite.Latitude, rxSite.Latitude], [txSite.Longitude, rxSite.Longitude], Color=color, LineStyle='-.', PickableParts='none', DisplayName='Enlace', Tag='RFLink');

                hTX = geoscatter(hAxes, txSite.Latitude, txSite.Longitude, ...
                    'LineWidth', 2, ...
                    'Marker', 'o', ...
                    'MarkerEdgeColor', color, ...
                    'MarkerFaceColor', color, ...
                    'SizeData', 48, ...
                    'PickableParts', 'none', ...
                    'DisplayName', 'TX', ...
                    'Tag', 'TX' ...
                );
                auxApp.RFDataHub.Datatips.apply(hTX, 'Coordinates')
            end
        end

        %-----------------------------------------------------------------%
        % DIAGRAMA DE RADIAÇÃO DA ANTENA E AZIMUTE (eixo polar)
        %-----------------------------------------------------------------%
        function antennaPattern(hAxes, antennaPattern)
            % "antennaPattern" é o texto do campo "AntennaPattern" do RFDataHub 
            % ("-1" quando ausente). O bloco try/catch protege possível erro no 
            % parser da informação do Mosaico. Como exposto em 
            % model.RFDataHub.parsingAntennaPattern foram identificados quatro 
            % formas de armazenar a informação.
            % "cla" (e não apenas a exclusão do diagrama) reinicializa os limites 
            % do eixo, usados na plotagem do azimute.
            cla(hAxes)

            if antennaPattern ~= "-1"
                try
                    [angle, gain] = model.RFDataHub.parsingAntennaPattern(antennaPattern, 360);
                    hAntennaPattern = polarplot(hAxes, angle, gain, 'Tag', 'AntennaPattern');
                    auxApp.RFDataHub.Datatips.apply(hAntennaPattern, 'AntennaPattern')
                catch
                end
            end
        end

        %-----------------------------------------------------------------%
        function azimuth(hAxes, txSite, rxSite)
            % O azimute independe do perfil de elevação, pois depende apenas 
            % das coordenadas de TX e RX. Com "txSite" vazio, apenas remove o 
            % azimute.
            delete(findobj(hAxes.Children, 'Tag', 'Azimuth'))

            if isempty(txSite)
                return
            end

            try
                color = auxApp.RFDataHub.Plots.LINK_COLOR;
                [~, azimuthDeg] = RF.Propagation.Distance(txSite, rxSite);

                az = deg2rad(azimuthDeg);
                polarplot(hAxes, az, hAxes.RLim(1), 'MarkerEdgeColor', color, 'MarkerFaceColor', color, 'Marker', 'o', 'PickableParts', 'none', 'Tag', 'Azimuth');
                polarplot(hAxes, az, hAxes.RLim(2), 'MarkerEdgeColor', color, 'MarkerFaceColor', color, 'Marker', '^', 'PickableParts', 'none', 'Tag', 'Azimuth');
                polarplot(hAxes, [az, az], hAxes.RLim, 'Color', color, 'LineStyle', '-.', 'PickableParts', 'none', 'Tag', 'Azimuth');
            catch
            end
        end

        %-----------------------------------------------------------------%
        % PERFIL DE RELEVO DO ENLACE (eixo cartesiano)
        %-----------------------------------------------------------------%
        function resetRFLinkProfile(hAxes)
            % O retângulo de fundo ("BackgroundLayer") é criado na primeira 
            % chamada e reaproveitado nas demais. Fica invisível e minimizado 
            % em torno de (0,0) enquanto o link não é plotado, para não 
            % interferir nos limites automáticos do eixo.
            delete(findobj(hAxes.Children, '-not', 'Tag', 'BackgroundLayer'))

            hBackground = findobj(hAxes, 'Tag', 'BackgroundLayer');
            if isempty(hBackground)
                rectangle(hAxes, 'Visible', 'off', 'Position', [0 0 .001 .001], 'Curvature', [.05 .15], 'FaceColor', [.07,0,0], 'FaceAlpha', 0.65, 'EdgeColor', 'none', 'PickableParts', 'none', 'HitTest', 'off', 'Tag', 'BackgroundLayer');
            else
                set(hBackground, 'Visible', 'off', 'Position', [0 0 .001 .001])
            end
        end

        %-----------------------------------------------------------------%
        function fitRFLinkBackground(hAxes)
            % O fundo ocupa todos os limites x e y do eixo.
            xLim = hAxes.XLim;
            yLim = hAxes.YLim;

            set(findobj(hAxes, 'Tag', 'BackgroundLayer'), 'Position', [xLim(1), yLim(1), diff(xLim), diff(yLim)], 'Visible', 'on')
        end

        %-----------------------------------------------------------------%
        function rfLinkProfile(hAxes, txSite, rxSite, wayPoints3D)
            arguments
                hAxes
                txSite
                rxSite
                wayPoints3D
            end

            % ## prePlot
            % (a) Altura das estações TX-RX.
            txAntennaElevation = wayPoints3D(1,3);
            if txSite.AntennaHeight > 0
                txAntennaElevation = txAntennaElevation + txSite.AntennaHeight;
            end

            rxAntennaElevation = wayPoints3D(end,3);
            if rxSite.AntennaHeight > 0
                rxAntennaElevation = rxAntennaElevation + rxSite.AntennaHeight;
            end

            % (b) 1ª Zona de Fresnel, atenuação no espaço livre, análise de visada 
            %     entre TX e RX, distância e azimute.
            [fresnelRadius, linkDistanceMeters, profileDistance, az] = RF.Propagation.FresnelZone(txSite, rxSite, height(wayPoints3D));
            profileDistance   = double(profileDistance); % força double porque fspl só aceita double
            profileDistanceKm = profileDistance/1000;
            linkDistanceKm    = linkDistanceMeters/1000;
            losHeight         = interp1([0, linkDistanceMeters], [txAntennaElevation, rxAntennaElevation], profileDistance, 'linear');
            pathLoss          = fspl(profileDistance, physconst('LightSpeed')/txSite.TransmitterFrequency);
            [~, firstObstructionIdx] = RF.Propagation.LOS(wayPoints3D(:,3), losHeight, fresnelRadius);

            % (c) Cores
            [terrainFaceColor, terrainEdgeColor] = getPlotColor('Terrain');
            terrainFaceAlpha   = 0.75;
            colorObstruction   = getPlotColor('FirstObstruction');
            colorStation       = getPlotColor('Station');
            colorLink          = getPlotColor('Link');
            colorFresnel       = getPlotColor('Fresnel');

            % ## Plot
            % Preserva o plot de fundo ("BackgroundLayer"), caso exista.
            delete(findobj(hAxes.Children, '-not', 'Tag', 'BackgroundLayer'))
            hAxes.XLimMode = 'auto';
            hAxes.YLimMode = 'auto';

            % (a) Perfil de terreno e primeira obstrução (caso aplicável)
            hTerrain = area(hAxes, profileDistanceKm, wayPoints3D(:,3), BaseValue=0, FaceColor=terrainFaceColor, FaceAlpha=terrainFaceAlpha, EdgeColor=terrainEdgeColor, LineWidth=1, Tag='Terrain');
            terrainTable = table(wayPoints3D(:,1), wayPoints3D(:,2), wayPoints3D(:,3), 'VariableNames', {'Latitude', 'Longitude', 'Elevation'});
            auxApp.RFDataHub.Datatips.apply(hTerrain, 'Terrain', terrainTable)

            if ~isempty(firstObstructionIdx)
                stem(hAxes, profileDistanceKm(firstObstructionIdx), wayPoints3D(firstObstructionIdx,3), 'filled', 'Marker', 'square', 'MarkerSize', 8, 'MarkerFaceColor', colorObstruction, 'LineStyle', '-.', 'Color', colorObstruction, 'PickableParts', 'none', 'Tag', 'FirstObstruction');
            end

            % (b) Estações TX e RX
            stem(hAxes, 0,              txAntennaElevation, 'filled', 'MarkerFaceColor', colorStation, 'Color', colorStation,                'PickableParts', 'none', 'Tag', 'Station');
            stem(hAxes, linkDistanceKm, rxAntennaElevation, 'filled', 'MarkerFaceColor', colorStation, 'Color', colorStation, 'Marker', '^', 'PickableParts', 'none', 'Tag', 'Station');

            % (c) Linha de visada entre TX e RX
            hLOS = plot(hAxes, profileDistanceKm, losHeight, 'Color', colorLink, 'LineStyle', '-.', 'LineWidth', .5,  'Tag', 'Link');
            losTable = table(profileDistanceKm, losHeight, pathLoss, 'VariableNames', {'Distance', 'Height', 'PathLoss'});
            auxApp.RFDataHub.Datatips.apply(hLOS, 'LOS', losTable)

            % (d) 1ª Zona de Fresnel
            images.roi.Polygon( ...
                hAxes, ...
                Position=[profileDistanceKm, losHeight+fresnelRadius; flip(profileDistanceKm), flip(losHeight-fresnelRadius)],  ...
                Color=colorFresnel, ...
                Deletable=0, ...
                EdgeAlpha=.35, ...
                FaceAlpha=.15, ...
                FaceSelectable=0, ...
                InteractionsAllowed='none', ...
                LineWidth=.5, ...
                Tag='Fresnel' ...
            );

            yLimMin = max(hAxes.YLim(1), min(wayPoints3D(:,3))-10);
            if ~wayPoints3D(1,3) || ~wayPoints3D(end,3)
                yLimMin = -10;
            end

            hAxes.YLim = [yLimMin, max(hAxes.YLim(2), max(wayPoints3D(:,3))+10)];
            hTerrain.BaseValue = hAxes.YLim(1);

            xLim = [profileDistanceKm(1), profileDistanceKm(end)];
            xDiff = diff(xLim);
            hAxes.XLim = [xLim(1)-xDiff*0.05, xLim(2)+xDiff*0.05];

            % (e) Visualização do eixo (OPCIONAL) e labels das estações TX e RX
            txLabel      = 'TX   ';
            rxLabel      = '  RX';
            txLabelAlign = 'right';
            rxLabelAlign = 'left';

            text(hAxes, 0,              txAntennaElevation, txLabel, 'Color', colorStation, 'HorizontalAlignment', txLabelAlign, 'VerticalAlignment', 'bottom', 'FontSize', 10, 'PickableParts', 'none', 'Tag', 'StationLabel');
            text(hAxes, linkDistanceKm, rxAntennaElevation, rxLabel, 'Color', colorStation, 'HorizontalAlignment', rxLabelAlign, 'VerticalAlignment', 'bottom', 'FontSize', 10, 'PickableParts', 'none', 'Tag', 'StationLabel');

            % ## post-Plot
            hAxes.UserData = struct('TX', txSite, 'RX', rxSite, 'Distance', linkDistanceKm, 'Azimuth', az, 'TXAntennaElevation', txAntennaElevation, 'RXAntennaElevation', rxAntennaElevation);
            auxApp.RFDataHub.Axes.stackingOrder(hAxes, 'RFLink')
        end
    end
end

%-------------------------------------------------------------------------%
function varargout = getPlotColor(plotTag)
    switch plotTag
        case 'Terrain'
            varargout = {'#333333', '#777777'};

        case 'FirstObstruction'
            varargout = {[.94,.94,.94]};

        case {'Station', 'Link', 'Fresnel'}
            varargout = {'cyan'};
    end
end