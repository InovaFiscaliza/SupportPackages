classdef (Abstract) Axes

    % Criação, interatividade e ordenação (stacking order) dos eixos do módulo
    % RFDataHub (auxApp.winRFDataHub), de forma que o módulo não dependa de 
    % classes do projeto hospedeiro (como "plot.axes.Creation" e 
    % "plot.axes.Interactivity").
    %
    % Os eixos são:
    % (1) Geográfico: mapa com estações, TX, RX e enlace TX-RX.
    % (2) Cartesiano: perfil de relevo do enlace TX-RX.
    % (3) Polar: diagrama de radiação da antena e azimute.

    properties (Constant)
        %-----------------------------------------------------------------%
        STACKING_ORDER = struct( ...
            'RFDataHub', {{'FilterROI', 'RFLink', 'TX', 'RX', 'Stations'}}, ... % GeographicAxes
            'RFLink',    {{'StationLabel', 'Station', 'Link', 'Fresnel', 'FirstObstruction', 'Footnote', 'Terrain', 'BackgroundLayer'}} ... % CartesianAxes
        )
    end


    methods (Static = true)
        %-----------------------------------------------------------------%
        function [hGeographicAxes, hProfileAxes, hPatternAxes] = create(hMapContainer, hPatternContainer, basemap)
            arguments
                hMapContainer
                hPatternContainer
                basemap char
            end

            hParent = tiledlayout(hMapContainer, 3, 5, "Padding", "none", "TileSpacing", "none");

            % Eixo geográfico: MAPA
            hGeographicAxes = geoaxes(hParent, FontSize=6, Basemap='none', AxisColor='white',      ...
                                               Grid='off', TickDir='none', Box='off', LineWidth=1, ...
                                               Interactions=[], Toolbar=[]);
            hGeographicAxes.LatitudeLabel.String  = '';
            hGeographicAxes.LongitudeLabel.String = '';
            hGeographicAxes.Scalebar.Visible = 0;
            set(hGeographicAxes, 'Basemap', basemap, 'Color', [.2, .2, .2], 'GridColor', [.5, .5, .5])
            hold(hGeographicAxes, 'on')

            hGeographicAxes.Layout.Tile = 1;
            hGeographicAxes.Layout.TileSpan = [3, 5];

            set(hGeographicAxes.LatitudeAxis,  'TickLabels', {}, 'Color', 'none')
            set(hGeographicAxes.LongitudeAxis, 'TickLabels', {}, 'Color', 'none')

            geolimits(hGeographicAxes, 'auto')

            if ismember(basemap, {'darkwater', 'none'})
                hGeographicAxes.Grid = 'on';
            end

            % Eixo cartesiano: PERFIL DE RELEVO
            hProfileAxes = uiaxes(hParent, Color=[.07,0,0], ColorScale='log', FontName='Helvetica', FontSize=10,                    ...
                                           XColor=[.8,.8,.8], YColor=[.8,.8,.8],                                                    ...
                                           XGrid='on', XMinorGrid='on', YGrid='on', YMinorGrid='on', TickDir='in',                  ...
                                           GridAlpha=.25, GridColor=[.94,.94,.94], MinorGridAlpha=.2, MinorGridColor=[.94,.94,.94], ...
                                           Interactions=[], Toolbar=[]);
            set(hProfileAxes, 'XGrid', 'off', 'XMinorGrid', 'off', 'XTick', [], 'XColor', [.8,.8,.8], ...
                              'YGrid', 'off', 'YMinorGrid', 'off', 'YTick', [], 'YColor', 'none',     ...
                              'Color', 'none', 'Clipping', 'on', 'LineWidth', 2, 'Layer', 'top', 'HitTest', 'off', 'Visible', 'off')
            hold(hProfileAxes, 'on')

            hProfileAxes.Layout.Tile = 11;
            hProfileAxes.Layout.TileSpan = [1 2];
            hProfileAxes.XAxis.TickLabelFormat = '%.1f';

            % Eixo polar: DIAGRAMA DE RADIAÇÃO DA ANTENA
            hPatternAxes = polaraxes(hPatternContainer, 'Units',             'normalized',      ...
                                                        'Position',          [.08, 0, .9, .85], ...
                                                        'ThetaZeroLocation', 'top',             ...
                                                        'Toolbar',           [],                ...
                                                        'FontSize',          8,                 ...
                                                        'Color',             'yellow',          ...
                                                        'ThetaTick',         0,                 ...
                                                        'ThetaDir',          'clockwise',       ...
                                                        'RTickLabel',        {});
            hold(hPatternAxes, 'on')

            % Interações com o mouse e teclado
            hGeographicAxes.Interactions = [dataTipInteraction, zoomInteraction, panInteraction];
            enableDefaultInteractivity(hGeographicAxes)

            hProfileAxes.Interactions = dataTipInteraction;
            enableDefaultInteractivity(hProfileAxes)
        end

        %-----------------------------------------------------------------%
        function regionZoom(hGeographicAxes, hToolbarButton)
            % Zoom de região no eixo geográfico (não disponível como interação 
            % nativa em geoaxes). O ícone do botão indica que a interação está
            % ativa. As interações padrão são desabilitadas enquanto o usuário
            % desenha o retângulo.
            iconFolder = fullfile(fileparts(mfilename('fullpath')), 'icons');

            hToolbarButton.ImageSource = fullfile(iconFolder, 'zoom-region-20px-filled.png');
            axesInteractions = hGeographicAxes.Interactions;
            hGeographicAxes.Interactions = [];
            disableDefaultInteractivity(hGeographicAxes)

            restoreState = onCleanup(@() restoreInteractions(hGeographicAxes, hToolbarButton, axesInteractions, fullfile(iconFolder, 'zoom-region-20px.png')));

            r = drawrectangle(hGeographicAxes, 'FaceSelectable', 0, 'InteractionsAllowed', 'none', 'LineWidth', 1, 'FaceAlpha', 0, 'Tag', 'RegionZoom');
            if ~isempty(r.Position) && all(r.Position(3:4) > 0)         && ...
                    r.Position(1) >= hGeographicAxes.LatitudeLimits(1)  && ...
                    r.Position(1) <  hGeographicAxes.LatitudeLimits(2)  && ...
                    r.Position(2) >= hGeographicAxes.LongitudeLimits(1) && ...
                    r.Position(2) <  hGeographicAxes.LongitudeLimits(2)

                newLatitudeLimits  = [r.Position(1), sum(r.Position([1,3]))];
                newLongitudeLimits = [r.Position(2), sum(r.Position([2,4]))];

                geolimits(hGeographicAxes, newLatitudeLimits, newLongitudeLimits)
            end
            delete(r)
        end

        %-----------------------------------------------------------------%
        function stackingOrder(hAxes, clientID)
            arguments
                hAxes
                clientID char {mustBeMember(clientID, {'RFDataHub', 'RFLink'})}
            end

            refStackingOrder = auxApp.RFDataHub.Axes.STACKING_ORDER.(clientID);
            stackingOrderTag = arrayfun(@(x) x.Tag, hAxes.Children, 'UniformOutput', false)';

            [~, newOrderMemberIndex] = ismember(stackingOrderTag, refStackingOrder);
            [~, newOrderIndex]       = sort(newOrderMemberIndex);

            hAxes.Children = hAxes.Children(newOrderIndex);
        end
    end
end

%-------------------------------------------------------------------------%
function restoreInteractions(hAxes, hToolbarButton, axesInteractions, normalIcon)
    if isvalid(hAxes)
        hAxes.Interactions = axesInteractions;
        enableDefaultInteractivity(hAxes)
    end

    if isvalid(hToolbarButton)
        hToolbarButton.ImageSource = normalIcon;
    end
end