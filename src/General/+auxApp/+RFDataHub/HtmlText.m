classdef (Abstract) HtmlText

    % Textos HTML do módulo RFDataHub (auxApp.winRFDataHub).
    %
    % O interpretador HTML do uilabel não aceita <img>, <svg> nem "class". Os 
    % ícones dos links são, então, SVGs mantidos nesta classe, registrados no
    % navegador por "ui.TextView.registerLinkIcon" e desenhados por CSS nos 
    % links criados por "createIconLink".

    properties (Constant)
        %-----------------------------------------------------------------%
        ICON_LOCATION_SVG    = '<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path d="M8 1C11.3137 1 14 3.68629 14 7C14 9.87377 10.9031 13.016 9.15918 14.5576C8.49082 15.1484 7.50918 15.1484 6.84082 14.5576C5.09688 13.016 2 9.87377 2 7C2 3.68629 4.68629 1 8 1ZM8 2C5.23858 2 3 4.23858 3 7C3 8.10839 3.61436 9.39536 4.56934 10.6826C5.50328 11.9415 6.65741 13.0603 7.50391 13.8086C7.79391 14.0647 8.20609 14.0647 8.49609 13.8086C9.34259 13.0603 10.4967 11.9415 11.4307 10.6826C12.3856 9.39536 13 8.10839 13 7C13 4.23858 10.7614 2 8 2ZM8 4.75C9.24264 4.75 10.25 5.75736 10.25 7C10.25 8.24264 9.24264 9.25 8 9.25C6.75736 9.25 5.75 8.24264 5.75 7C5.75 5.75736 6.75736 4.75 8 4.75ZM8 5.75C7.30964 5.75 6.75 6.30964 6.75 7C6.75 7.69036 7.30964 8.25 8 8.25C8.69036 8.25 9.25 7.69036 9.25 7C9.25 6.30964 8.69036 5.75 8 5.75Z"/></svg>'

        ICON_FILE_PDF_SVG    = '<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path d="M13.5 7H13V5.414C13 5.016 12.842 4.635 12.561 4.353L9.647 1.439C9.366 1.158 8.984 1 8.586 1H5C3.895 1 3 1.895 3 3V7H2.5C1.673 7 1 7.673 1 8.5V13.5C1 14.327 1.673 15 2.5 15H13.5C14.327 15 15 14.327 15 13.5V8.5C15 7.673 14.327 7 13.5 7ZM9 2.207L11.793 5H9.5C9.224 5 9 4.776 9 4.5V2.207ZM4 3C4 2.448 4.448 2 5 2H8V4.5C8 5.328 8.672 6 9.5 6H12V7H4V3ZM14 13.5C14 13.775 13.775 14 13.5 14H2.5C2.224 14 2 13.775 2 13.5V8.5C2 8.225 2.224 8 2.5 8H13.5C13.775 8 14 8.225 14 8.5V13.5Z"/><path d="M4.5 9H3.5C3.224 9 3 9.224 3 9.5V12.5C3 12.776 3.224 13 3.5 13C3.776 13 4 12.776 4 12.5V12H4.5C5.327 12 6 11.327 6 10.5C6 9.673 5.327 9 4.5 9ZM4.5 11H4V10H4.5C4.776 10 5 10.225 5 10.5C5 10.775 4.776 11 4.5 11Z"/><path d="M8 9H7.5C7.224 9 7 9.224 7 9.5V12.5C7 12.776 7.224 13 7.5 13H8C9.103 13 10 12.103 10 11C10 9.897 9.103 9 8 9ZM8 12V10C8.552 10 9 10.448 9 11C9 11.552 8.552 12 8 12Z"/><path d="M13 9H11.5C11.224 9 11 9.224 11 9.5V12.5C11 12.776 11.224 13 11.5 13C11.776 13 12 12.776 12 12.5V12H12.5C12.776 12 13 11.776 13 11.5C13 11.224 12.776 11 12.5 11H12V10H13C13.276 10 13.5 9.776 13.5 9.5C13.5 9.224 13.276 9 13 9Z"/></svg>'

        ICON_EYE_SVG         = '<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path d="M2.98444 8.62471L2.98346 8.62815C2.91251 8.8948 2.63879 9.05404 2.37202 8.9833C1.94098 8.86907 2.01687 8.37186 2.01687 8.37186L2.03453 8.31047C2.03453 8.31047 2.06063 8.22636 2.08166 8.1653C2.12369 8.04329 2.18795 7.87274 2.27931 7.66977C2.46154 7.26493 2.75443 6.72477 3.19877 6.18295C4.09629 5.08851 5.60509 4 8.00017 4C10.3952 4 11.904 5.08851 12.8016 6.18295C13.2459 6.72477 13.5388 7.26493 13.721 7.66977C13.8124 7.87274 13.8766 8.04329 13.9187 8.1653C13.9397 8.22636 13.9552 8.27541 13.9658 8.31047C13.9711 8.328 13.9752 8.34204 13.9781 8.35236L13.9816 8.365L13.9827 8.36916L13.9832 8.37069L13.9835 8.37186C14.0542 8.63878 13.8952 8.91253 13.6283 8.9833C13.3618 9.05397 13.0885 8.89556 13.0172 8.62937L13.0169 8.62815L13.0159 8.62471L13.0085 8.5997C13.0014 8.57616 12.9898 8.53927 12.9732 8.49095C12.9399 8.39422 12.8866 8.25227 12.8091 8.08023C12.6538 7.73508 12.4041 7.27523 12.0283 6.81706C11.2857 5.9115 10.0445 5 8.00017 5C5.95584 5 4.71464 5.9115 3.97201 6.81706C3.59627 7.27523 3.34655 7.73508 3.19119 8.08023C3.11375 8.25227 3.06047 8.39422 3.02715 8.49095C3.01051 8.53927 2.9989 8.57616 2.99179 8.5997L2.98444 8.62471ZM8.00024 7C6.61953 7 5.50024 8.11929 5.50024 9.5C5.50024 10.8807 6.61953 12 8.00024 12C9.38096 12 10.5002 10.8807 10.5002 9.5C10.5002 8.11929 9.38096 7 8.00024 7ZM6.50024 9.5C6.50024 8.67157 7.17182 8 8.00024 8C8.82867 8 9.50024 8.67157 9.50024 9.5C9.50024 10.3284 8.82867 11 8.00024 11C7.17182 11 6.50024 10.3284 6.50024 9.5Z"/></svg>'

        ICON_EYE_CLOSED_SVG  = '<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path d="M10.1196 10.8267L14.1464 14.8536C14.3417 15.0488 14.6583 15.0488 14.8536 14.8536C15.0488 14.6583 15.0488 14.3417 14.8536 14.1464L1.85355 1.14645C1.65829 0.951184 1.34171 0.951184 1.14645 1.14645C0.951184 1.34171 0.951184 1.65829 1.14645 1.85355L4.37624 5.08334C3.90117 5.4183 3.5126 5.80026 3.19877 6.18295C2.75443 6.72477 2.46154 7.26493 2.27931 7.66977C2.18795 7.87274 2.12369 8.04329 2.08166 8.1653C2.06063 8.22636 2.03453 8.31047 2.03453 8.31047L2.01687 8.37186C2.01687 8.37186 1.94098 8.86907 2.37202 8.9833C2.63879 9.05404 2.91251 8.8948 2.98346 8.62815L2.98444 8.62471L2.99179 8.5997C2.9989 8.57616 3.01051 8.53927 3.02715 8.49095C3.06047 8.39421 3.11375 8.25227 3.19119 8.08023C3.34655 7.73507 3.59627 7.27523 3.97201 6.81706C4.26363 6.46146 4.63213 6.10494 5.09595 5.80306L6.67356 7.38067C5.9688 7.82277 5.50024 8.60667 5.50024 9.5C5.50024 10.8807 6.61953 12 8.00024 12C8.89358 12 9.67747 11.5314 10.1196 10.8267ZM9.3807 10.0878C9.15205 10.6241 8.62005 11 8.00024 11C7.17182 11 6.50024 10.3284 6.50024 9.5C6.50024 8.88019 6.87616 8.34819 7.41244 8.11955L9.3807 10.0878ZM6.31962 4.19853L7.174 5.05291C7.43366 5.01852 7.70875 5 8.00017 5C10.0445 5 11.2857 5.9115 12.0283 6.81706C12.4041 7.27523 12.6538 7.73507 12.8091 8.08023C12.8866 8.25227 12.9399 8.39421 12.9732 8.49095C12.9898 8.53927 13.0014 8.57616 13.0085 8.5997L13.0159 8.62471L13.0169 8.62815L13.0172 8.62937C13.0885 8.89555 13.3618 9.05397 13.6283 8.9833C13.8952 8.91253 14.0542 8.63878 13.9835 8.37186L13.9832 8.37069L13.9827 8.36916L13.9816 8.365L13.9781 8.35236C13.9752 8.34204 13.9711 8.328 13.9658 8.31047C13.9552 8.27541 13.9397 8.22636 13.9187 8.1653C13.8766 8.04329 13.8124 7.87274 13.721 7.66977C13.5388 7.26493 13.2459 6.72477 12.8016 6.18295C11.904 5.0885 10.3952 4 8.00017 4C7.38264 4 6.82403 4.07236 6.31962 4.19853Z"/></svg>'

        ICON_CLOSE_SVG       = '<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path d="M8.70701 8.00001L12.353 4.35401C12.548 4.15901 12.548 3.84201 12.353 3.64701C12.158 3.45201 11.841 3.45201 11.646 3.64701L8.00001 7.29301L4.35401 3.64701C4.15901 3.45201 3.84201 3.45201 3.64701 3.64701C3.45201 3.84201 3.45201 4.15901 3.64701 4.35401L7.29301 8.00001L3.64701 11.646C3.45201 11.841 3.45201 12.158 3.64701 12.353C3.74501 12.451 3.87301 12.499 4.00101 12.499C4.12901 12.499 4.25701 12.45 4.35501 12.353L8.00101 8.70701L11.647 12.353C11.745 12.451 11.873 12.499 12.001 12.499C12.129 12.499 12.257 12.45 12.355 12.353C12.55 12.158 12.55 11.841 12.355 11.646L8.70901 8.00001H8.70701Z"/></svg>'

        EVENT_TX_LOCATION    = 'onRFDataHubTXLocationEditRequested'
        EVENT_RX_LOCATION    = 'onRFDataHubRXLocationEditRequested'
        EVENT_CHANNEL_REPORT = 'onRFDataHubChannelReportOpenRequested'
        EVENT_RFLINK_TOGGLE  = 'onRFLinkToggleViewRequested'
        EVENT_RULE_DELETE    = 'onFilterRuleDeleteRequested'
    end


    methods (Static = true)
        %-----------------------------------------------------------------%
        function registerIcons(jsBackDoor)
            % Ícones dos links dos painéis HTML (exceto o de visualização do 
            % enlace, que depende do estado: "registerRFLinkToggleIcon").
            ui.TextView.registerLinkIcon(jsBackDoor, auxApp.RFDataHub.HtmlText.EVENT_TX_LOCATION,    auxApp.RFDataHub.HtmlText.ICON_LOCATION_SVG)
            ui.TextView.registerLinkIcon(jsBackDoor, auxApp.RFDataHub.HtmlText.EVENT_RX_LOCATION,    auxApp.RFDataHub.HtmlText.ICON_LOCATION_SVG)
            ui.TextView.registerLinkIcon(jsBackDoor, auxApp.RFDataHub.HtmlText.EVENT_CHANNEL_REPORT, auxApp.RFDataHub.HtmlText.ICON_FILE_PDF_SVG)
            ui.TextView.registerLinkIcon(jsBackDoor, auxApp.RFDataHub.HtmlText.EVENT_RULE_DELETE,    auxApp.RFDataHub.HtmlText.ICON_CLOSE_SVG, 16, '#ff0000')
        end

        %-----------------------------------------------------------------%
        function registerRFLinkToggleIcon(jsBackDoor, isRFLinkVisible)
            if isRFLinkVisible
                iconSVG = auxApp.RFDataHub.HtmlText.ICON_EYE_SVG;
            else
                iconSVG = auxApp.RFDataHub.HtmlText.ICON_EYE_CLOSED_SVG;
            end

            ui.TextView.registerLinkIcon(jsBackDoor, auxApp.RFDataHub.HtmlText.EVENT_RFLINK_TOGGLE, iconSVG)
        end

        %-----------------------------------------------------------------%
        function htmlLink = createIconLink(appHandleNameInBase, eventName, eventData)
            arguments
                appHandleNameInBase
                eventName
                eventData = ''
            end

            htmlLink = '';

            try
                if ~isempty(appHandleNameInBase)
                    htmlLink = ui.TextView.createHTMLLink('customIcon', appHandleNameInBase, eventName, eventData);
                end
            catch
            end
        end

        %-----------------------------------------------------------------%
        function htmlContent = getStationInfo(rfDataHub, idxRFDataHub, rfDataHubLOG, generalSettings, rfDataHubAnnotation, rxSite, appHandleNameInBase, markerColor)
            % Gera o HTML com as informações da estação TX selecionada, da 
            % estação RX de referência e do enlace TX-RX (distância, azimute 
            % e atenuação no espaço livre). rxSite é uma estrutura com os 
            % campos Latitude, Longitude e AntennaHeight (vazio omite RX e 
            % enlace). markerColor (hexadecimal) é a cor dos marcadores TX 
            % e RX no plot geográfico, replicada nos selos. O ícone do selo
            % do enlace (olho aberto/fechado) é definido por 
            % "registerRFLinkToggleIcon".
            arguments
                rfDataHub
                idxRFDataHub
                rfDataHubLOG
                generalSettings
                rfDataHubAnnotation = []
                rxSite = []
                appHandleNameInBase = ''
                markerColor {mustBeTextScalar} = '#ff365e'
            end

            % idxRFDataHub vazio (nenhum registro selecionado): apenas a estação
            % RX, sem TX e sem enlace.
            if isempty(idxRFDataHub)
                htmlContent = '';
                if ~isempty(rxSite)
                    rxSection   = auxApp.RFDataHub.HtmlText.rxStationSection(rxSite, appHandleNameInBase, markerColor);
                    htmlContent = sprintf('<section style="padding: 10px;">%s</section>', auxApp.RFDataHub.HtmlText.htmlSection(rxSection{1}, rxSection{2}, '', 0));
                end
                return
            end

            % stationTag
            stationInfo    = table2struct(rfDataHub(idxRFDataHub,:));
            if stationInfo.BW <= 0
                stationTag = sprintf('%.3f MHz',            stationInfo.Frequency);
            else
                stationTag = sprintf('%.3f MHz ⌂ %.1f kHz', stationInfo.Frequency, stationInfo.BW);
            end

            % SERVIÇO
            global id2nameTable
            if isempty(id2nameTable)
                serviceOptions = generalSettings.eFiscaliza.defaultValues.servicos_da_inspecao.options;
                serviceIDs     = int16(str2double(extractBefore(serviceOptions, '-')));
                id2nameTable   = table(serviceIDs, serviceOptions, 'VariableNames', {'ID', 'Serviço'});
            end
            stationService = ws.eFiscaliza.serviceMapping(stationInfo.Service);

            [~, idxService] = ismember(stationInfo.Service, id2nameTable.ID);
            if idxService
                stationService = id2nameTable.("Serviço"){idxService};
            else
                stationService = num2str(stationService);
            end

            if strcmp(stationService, '-1')
                stationService = '<font style="color: red;">-1</font>';
            end

            % NÚMERO
            mergeCount = str2double(string(stationInfo.MergeCount));
            if stationInfo.Station == -1
                stationNumber = sprintf('<font style="color: red;">%d</font>', stationInfo.Station);
            else
                stationNumber = num2str(stationInfo.Station);
                if mergeCount > 1
                    stationNumber = sprintf('%s*', stationNumber);
                end
            end

            % LOCAL DE INSTALAÇÃO
            % Valores editados pelo usuário (rfDataHubAnnotation) são 
            % evidenciados com o valor original tachado seguido do novo valor.
            txLatitude       = double(stationInfo.Latitude);
            txLongitude      = double(stationInfo.Longitude);
            stationLatitude  = sprintf('%.6fº', txLatitude);
            stationLongitude = sprintf('%.6fº', txLongitude);
            stationHeight    = str2double(char(stationInfo.AntennaHeight));
            if stationHeight <= 0
                stationHeight = '<font style="color: red;">-1</font>';
            else
                stationHeight = sprintf('%.1f metros', stationHeight);
            end

            if ~isempty(rfDataHubAnnotation)
                [~, annotationIdx] = ismember(string(stationInfo.ID), rfDataHubAnnotation.ID);

                if annotationIdx
                    txSite = rfDataHubAnnotation.TXSite(annotationIdx);

                    if txSite.Latitude.Status
                        txLatitude = txSite.Latitude.EditedValue;
                        stationLatitude = auxApp.RFDataHub.HtmlText.markEditedValue(stationLatitude, sprintf('%.6fº', txLatitude));
                    end

                    if txSite.Longitude.Status
                        txLongitude = txSite.Longitude.EditedValue;
                        stationLongitude = auxApp.RFDataHub.HtmlText.markEditedValue(stationLongitude, sprintf('%.6fº', txLongitude));
                    end

                    if txSite.AntennaHeight.Status
                        stationHeight = auxApp.RFDataHub.HtmlText.markEditedValue(stationHeight, sprintf('%.1f metros', txSite.AntennaHeight.EditedValue));
                    end
                end
            end

            % TX
            % Outros aspectos técnicos: apenas os campos preenchidos, em 
            % formato JSON (compacto) para economizar espaço.
            editedStationInfo = rmfield(stationInfo, { ...
                'AntennaPattern', 'BW', 'Description', 'Distance', 'Fistel', 'Frequency',     ...
                'ID', 'Latitude', 'LocationID', 'Location', 'Log', 'Longitude', 'MergeCount', ...
                'Name', 'Station', 'StationClass', 'Status', 'Service', 'Source', 'State', 'URL' ...
            });

            otherAspects = struct();
            editedFieldNames = fieldnames(editedStationInfo);
            for ii = 1:numel(editedFieldNames)
                fieldValue = editedStationInfo.(editedFieldNames{ii});

                if ~isequal(fieldValue, categorical(-1))
                    if iscategorical(fieldValue) || isstring(fieldValue)
                        fieldValue = char(fieldValue);
                    end
                    otherAspects.(editedFieldNames{ii}) = fieldValue;
                end
            end

            % LOG
            stationLOG = model.RFDataHub.queryLog(rfDataHubLOG, stationInfo.Log);
            if isempty(stationLOG)
                stationLOG = 'Registro não editado';
            end

            txEditLink = auxApp.RFDataHub.HtmlText.createIconLink(appHandleNameInBase, auxApp.RFDataHub.HtmlText.EVENT_TX_LOCATION);

            % Documento (PDF) gerado pelo Mosaico, disponível apenas para 
            % registros do "MOSAICO-SRD" que possuem URL. O link fica ao lado 
            % do selo do TX.
            channelReportLink = '';
            if string(stationInfo.Source) == "MOSAICO-SRD" && ~strcmp(char(stationInfo.URL), '-1')
                channelReportLink = auxApp.RFDataHub.HtmlText.createIconLink(appHandleNameInBase, auxApp.RFDataHub.HtmlText.EVENT_CHANNEL_REPORT);
            end

            % Conteúdo da seção gerado por struct2PrettyPrintList.
            displayEntry = [ ...
                auxApp.RFDataHub.HtmlText.makeDisplayEntry('Service', stationService), ...
                auxApp.RFDataHub.HtmlText.makeDisplayEntry('Station', sprintf('%s (ID %s)', stationNumber, stationInfo.ID)), ...
                auxApp.RFDataHub.HtmlText.makeDisplayEntry('LOCAL DE INSTALAÇÃO', struct('Latitude', stationLatitude, 'Longitude', stationLongitude, 'Altura', stationHeight)) ...
            ];

            if ~isempty(fieldnames(otherAspects))
                otherAspectsJSON = replace(matlab.jsonencode(otherAspects), {'&', '<', '>'}, {'&amp;', '&lt;', '&gt;'});
                displayEntry(end+1) = auxApp.RFDataHub.HtmlText.makeDisplayEntry('OUTROS ASPECTOS TÉCNICOS', otherAspectsJSON);
            end

            if mergeCount > 1
                displayEntry(end+1) = auxApp.RFDataHub.HtmlText.makeDisplayEntry('REGISTROS AGRUPADOS', string(mergeCount));
            end

            try
                if isstruct(stationLOG) || ischar(stationLOG)
                    displayEntry(end+1) = auxApp.RFDataHub.HtmlText.makeDisplayEntry('LOG', stationLOG);

                elseif iscell(stationLOG)
                    for ii = 1:numel(stationLOG)
                        displayEntry(end+1) = auxApp.RFDataHub.HtmlText.makeDisplayEntry(sprintf('LOG #%d', ii), stationLOG{ii}); %#ok<AGROW>
                    end
                end
            catch
            end

            htmlIntro = [ ...
                sprintf('<font style="font-size: 13px;"><b>%s</b></font><br>', stationTag) ...
                sprintf('<font style="font-size: 10px; color: gray;">%s</font><br><br>', stationInfo.Description) ...
            ];

            txContent = textFormatGUI.struct2PrettyPrintList(displayEntry, 'delete', htmlIntro, 'html');

            % As seções são renderizadas ao final, pois a última não tem 
            % margem inferior.
            % Os selos replicam os marcadores do plot geográfico: ● (U+25CF) 
            % para o TX e ▲ (U+25B2) para o RX. O seletor U+FE0E força a 
            % renderização como texto (e não como emoji).
            sections = {auxApp.RFDataHub.HtmlText.stationBadge('&#x25CF;', 'TX', markerColor, 17, sprintf('%s&emsp;%s', txEditLink, channelReportLink)), txContent};

            % RX e ENLACE TX-RX
            if ~isempty(rxSite)
                sections(end+1, :) = auxApp.RFDataHub.HtmlText.rxStationSection(rxSite, appHandleNameInBase, markerColor);

                try
                    txSiteLink = struct( ...
                        'Latitude', txLatitude, ...
                        'Longitude', txLongitude, ...
                        'TransmitterFrequency', double(stationInfo.Frequency) * 1e+6 ...
                    );
                    [pathLoss, distanceKm, azimuth] = RF.Propagation.PathLoss(txSiteLink, rxSite);

                    linkEntry = [ ...
                        auxApp.RFDataHub.HtmlText.makeDisplayEntry('DISTÂNCIA', sprintf('%.1f km', distanceKm)), ...
                        auxApp.RFDataHub.HtmlText.makeDisplayEntry('AZIMUTE', sprintf('%.1fº', azimuth)), ...
                        auxApp.RFDataHub.HtmlText.makeDisplayEntry('ATENUAÇÃO NO ESPAÇO LIVRE', sprintf('%.1f dB', pathLoss(end))) ...
                    ];
                    linkContent = textFormatGUI.struct2PrettyPrintList(linkEntry, 'delete', '', 'html');
                    rfLinkToggleLink = auxApp.RFDataHub.HtmlText.createIconLink(appHandleNameInBase, auxApp.RFDataHub.HtmlText.EVENT_RFLINK_TOGGLE);

                    sections(end+1, :) = {auxApp.RFDataHub.HtmlText.stationBadge('', 'TX –. RX', markerColor, 17, rfLinkToggleLink), linkContent};
                catch
                end
            end

            sectionsHTML = cell(1, height(sections));
            for ii = 1:height(sections)
                bottomMargin = 30;
                if ii == height(sections)
                    bottomMargin = 0;
                end

                sectionsHTML{ii} = auxApp.RFDataHub.HtmlText.htmlSection(sections{ii, 1}, sections{ii, 2}, '', bottomMargin);
            end

            htmlContent = sprintf('<section style="padding: 10px;">%s</section>', strjoin(sectionsHTML, ''));
        end
    end


    methods (Static = true, Access = private)
        %-----------------------------------------------------------------%
        function rxSection = rxStationSection(rxSite, appHandleNameInBase, markerColor)
            % Seção {título, conteúdo} com os dados da estação RX de referência.
            rxEditLink = auxApp.RFDataHub.HtmlText.createIconLink(appHandleNameInBase, auxApp.RFDataHub.HtmlText.EVENT_RX_LOCATION);
            rxEntry = auxApp.RFDataHub.HtmlText.makeDisplayEntry('LOCAL DE INSTALAÇÃO', struct('Latitude', sprintf('%.6fº', rxSite.Latitude), 'Longitude', sprintf('%.6fº', rxSite.Longitude), 'Altura', sprintf('%.1f metros', rxSite.AntennaHeight)));
            rxContent = textFormatGUI.struct2PrettyPrintList(rxEntry, 'delete', '', 'html');
            rxSection = {auxApp.RFDataHub.HtmlText.stationBadge('&#x25B2;', 'RX', markerColor, 13, rxEditLink), rxContent};
        end

        %-----------------------------------------------------------------%
        function entry = makeDisplayEntry(group, value, link)
            arguments
                group
                value
                link = ''
            end

            entry = struct('group', group, 'value', value, 'link', link);
        end

        %-----------------------------------------------------------------%
        function html = markEditedValue(oldValue, newValue)
            html = sprintf('<del>%s</del> → <font style="color: red;">%s</font>', oldValue, newValue);
        end

        %-----------------------------------------------------------------%
        function html = htmlSection(title, content, link, bottomMargin)
            arguments
                title
                content
                link = ''
                bottomMargin (1,1) double = 30 % pixels
            end

            if ~isempty(link)
                link = ['&emsp;' link];
            end

            % O título fica fora da tabela. O efeito de borda lateral é obtido 
            % com uma coluna de 3px de largura, e não com "border-left".
            html = sprintf([ ...
                '<section style="margin: 0px 0px %dpx 0px;">' ...
                    '<p style="margin: 0px 0px 10px 0px;"><font style="font-size: 12px; color: black;"><b>%s</b></font>%s</p>' ...
                    '<table style="width: 100%%;">' ...
                        '<tr>' ...
                            '<td style="width: 3px; background: #7a7a7a;"></td>' ...
                            '<td style="padding-left: 7px;">%s</td>' ...
                        '</tr>' ...
                    '</table>' ...
                '</section>' ...
            ], bottomMargin, title, link, content);
        end

        %-----------------------------------------------------------------%
        function html = stationBadge(symbolEntity, label, color, symbolFontSize, clickableIcon)
            % color: cor hexadecimal (#RRGGBB) do marcador no plot, usada no 
            % texto do selo e (com transparência) no fundo.
            % symbolFontSize: tamanho (pixels) da fonte do símbolo; o texto 
            % do selo mantém 11px.
            arguments
                symbolEntity
                label
                color {mustBeTextScalar}
                symbolFontSize (1,1) double = 13
                clickableIcon = ''
            end

            hex = char(color);
            rgb = [hex2dec(hex(2:3)), hex2dec(hex(4:5)), hex2dec(hex(6:7))];
            backgroundColor = sprintf('rgba(%d, %d, %d, 0.12)', rgb);

            if ~isempty(clickableIcon)
                clickableIcon = sprintf('&emsp;%s', clickableIcon);
            end

            html = sprintf([ ...
                '<font style="color: %s; background-color: %s; font-size: 11px; font-weight: normal; ' ...
                'display: inline-block; vertical-align: middle; padding: 5px; border-radius: 5px;">' ...
                '<font style="font-size: %dpx;">%s&#xFE0E;</font> %s</font>%s' ...
            ], color, backgroundColor, symbolFontSize, symbolEntity, label, clickableIcon);
        end
    end
end