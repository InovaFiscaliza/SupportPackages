classdef (Abstract) Datatips

    % Templates de datatip dos plots do módulo RFDataHub.

    methods (Static = true)
        %-----------------------------------------------------------------%
        function apply(dtParent, dtType, varargin)
            arguments
                dtParent
                dtType char {mustBeMember(dtType, {'Coordinates', 'Stations', 'AntennaPattern', 'LOS', 'Terrain'})}
            end

            arguments (Repeating)
                varargin
            end

            if isempty(dtParent)
                return
            elseif ~isprop(dtParent, 'DataTipTemplate')
                % 'images.roi.line' e 'images.roi.Rectangle' não suportam DataTip
                try
                    dt = datatip(dtParent, Visible = 'off');
                catch
                    return
                end
            end

            set(dtParent.DataTipTemplate, FontName='Calibri', FontSize=10)

            switch dtType
                case 'Coordinates'
                    dtParent.DataTipTemplate.DataTipRows(1).Label = 'Lat:';
                    dtParent.DataTipTemplate.DataTipRows(2).Label = 'Lon:';
                    if numel(dtParent.DataTipTemplate.DataTipRows) > 2
                        dtParent.DataTipTemplate.DataTipRows(3:end) = [];
                    end

                case 'Stations'
                    hTable = varargin{1};

                    dtParent.DataTipTemplate.DataTipRows(1) = dataTipTextRow('', hTable.ID);
                    dtParent.DataTipTemplate.DataTipRows(2) = dataTipTextRow('', hTable.Frequency, '%.3f MHz');
                    dtParent.DataTipTemplate.DataTipRows(3) = dataTipTextRow('', hTable.Distance,  '%.1f km');

                    if numel(dtParent.DataTipTemplate.DataTipRows) > 3
                        dtParent.DataTipTemplate.DataTipRows(4:end) = [];
                    end

                case 'AntennaPattern'
                    dtParent.DataTipTemplate.DataTipRows(1) = dataTipTextRow('', 'ThetaData', '%.0fº');
                    dtParent.DataTipTemplate.DataTipRows(2) = dataTipTextRow('', 'RData',     '%.1fdBd');

                case 'LOS'
                    hTable = varargin{1};

                    dtParent.DataTipTemplate.DataTipRows(1) = dataTipTextRow('Distância:',    hTable.Distance, '%.1f km');
                    dtParent.DataTipTemplate.DataTipRows(2) = dataTipTextRow('Altura:',       hTable.Height,   '%.1f m');
                    dtParent.DataTipTemplate.DataTipRows(3) = dataTipTextRow('Espaço livre:', hTable.PathLoss, '%.1f dB');

                case 'Terrain'
                    hTable = varargin{1};

                    dtParent.DataTipTemplate.DataTipRows(1) = dataTipTextRow('Lat:', hTable.Latitude,  '%.6f');
                    dtParent.DataTipTemplate.DataTipRows(2) = dataTipTextRow('Lon:', hTable.Longitude, '%.6f');
                    dtParent.DataTipTemplate.DataTipRows(3) = dataTipTextRow('',     hTable.Elevation, '%.1f m');
            end

            if exist('dt', 'var')
                delete(dt)
            end
        end
    end
end