function DataTipTemplate(DataTipType, hAxes, varargin)

    arguments
        DataTipType
        hAxes
    end

    arguments (Repeating)
        varargin
    end

    if isempty(hAxes)
        return
    elseif ~isprop(hAxes, 'DataTipTemplate')
        dt = datatip(hAxes, 'Visible', 'off');
    end

    set(hAxes.DataTipTemplate, 'FontName', 'Calibri', 'FontSize', 10)

    switch DataTipType
        case 'Frequency+Level'
            hAxes.DataTipTemplate.DataTipRows(1).Label  = '';
            hAxes.DataTipTemplate.DataTipRows(1).Format = '%.3f MHz';                    
            hAxes.DataTipTemplate.DataTipRows(2).Label  = '';
            hAxes.DataTipTemplate.DataTipRows(2).Format = ['%.0f ' varargin{1}];

        case 'Frequency+Occupancy'
            hAxes.DataTipTemplate.DataTipRows(1).Label  = '';
            hAxes.DataTipTemplate.DataTipRows(1).Format = '%.3f MHz';                    
            hAxes.DataTipTemplate.DataTipRows(2).Label  = '';
            hAxes.DataTipTemplate.DataTipRows(2).Format = ['%.0f' varargin{1}];

        case 'Frequency+Timestamp+Level'
            switch class(hAxes)
                case 'matlab.graphics.chart.primitive.Surface'
                    hAxes.DataTipTemplate.DataTipRows(1).Label  = '';
                    hAxes.DataTipTemplate.DataTipRows(2).Label  = '';
                    hAxes.DataTipTemplate.DataTipRows(3).Label  = '';
                                    
                    hAxes.DataTipTemplate.DataTipRows(1).Format = '%.3f MHz';
                    hAxes.DataTipTemplate.DataTipRows(2).Format =  'dd/MM/yyyy HH:mm:ss';
                    hAxes.DataTipTemplate.DataTipRows(3).Format =  ['%.0f ' varargin{1}];

                case 'matlab.graphics.primitive.Image'
                    hAxes.DataTipTemplate.DataTipRows(1).Label  = '';
                    hAxes.DataTipTemplate.DataTipRows(2).Label  = '';

                    hAxes.DataTipTemplate.DataTipRows(2).Format = ['%.0f ' varargin{1}];                            
                    hAxes.DataTipTemplate.DataTipRows(3)        = [];
            end

        case 'Coordinates'
            hAxes.DataTipTemplate.DataTipRows(1).Label = 'Latitude:';
            hAxes.DataTipTemplate.DataTipRows(2).Label = 'Longitude:';
            if numel(hAxes.DataTipTemplate.DataTipRows) > 2
                hAxes.DataTipTemplate.DataTipRows(3:end) = [];
            end

        case 'Coordinates+Frequency'
            DataTable = varargin{1};

            hAxes.DataTipTemplate.DataTipRows(1).Label = 'Latitude:';
            hAxes.DataTipTemplate.DataTipRows(2).Label = 'Longitude:';
            hAxes.DataTipTemplate.DataTipRows(3)       = dataTipTextRow('Frequência:', DataTable.Frequency, '%.3f MHz');
            hAxes.DataTipTemplate.DataTipRows(4)       = dataTipTextRow('Entidade:',   DataTable.Name);

            hAxes.DataTipTemplate.DataTipRows          = hAxes.DataTipTemplate.DataTipRows([3:4,1:2]);

        case 'SweepID+ChannelPower+Coordinates'
            DataTable = table((1:numel(hAxes.LatitudeData))', 'VariableNames', {'ID'});

            hAxes.DataTipTemplate.DataTipRows(1).Label = 'Latitude:';
            hAxes.DataTipTemplate.DataTipRows(2).Label = 'Longitude:';
            hAxes.DataTipTemplate.DataTipRows(3)       = dataTipTextRow('ID:', DataTable.ID);
            hAxes.DataTipTemplate.DataTipRows(4)       = dataTipTextRow('Potência:', 'CData', '%.1f dBm');

            if numel(hAxes.DataTipTemplate.DataTipRows) > 4
                hAxes.DataTipTemplate.DataTipRows(5:end) = [];
            end

            hAxes.DataTipTemplate.DataTipRows          = hAxes.DataTipTemplate.DataTipRows([3:4,1:2]);

        case 'SweepID+ChannelPower'
            hAxes.DataTipTemplate.DataTipRows(1).Label = 'ID:';
            hAxes.DataTipTemplate.DataTipRows(2)       = dataTipTextRow('Potência:', 'YData', ['%.1f ' varargin{1}]);

        case 'winRFDataHub.Geographic'
            DataTable = varargin{1};

            hAxes.DataTipTemplate.DataTipRows(1) = dataTipTextRow('', DataTable.Frequency, '%.3f MHz');
            hAxes.DataTipTemplate.DataTipRows(2) = dataTipTextRow('', DataTable.Distance,  '%.0f km');

            ROWS = height(DataTable);
            if ROWS == 1
                hAxes.DataTipTemplate.DataTipRows(3) = dataTipTextRow('ID:', {DataTable{:,1}});
                hAxes.DataTipTemplate.DataTipRows(4) = dataTipTextRow('',    {DataTable{:,5}});

            else
                hAxes.DataTipTemplate.DataTipRows(3) = dataTipTextRow('ID:', DataTable{:,1});
                hAxes.DataTipTemplate.DataTipRows(4) = dataTipTextRow('',    DataTable{:,5});
            end

            hAxes.DataTipTemplate.DataTipRows = hAxes.DataTipTemplate.DataTipRows([3,1,4,2]);

        case 'winRFDataHub.SelectedNode'
            hAxes.DataTipTemplate.DataTipRows(1).Label = 'Latitude:';
            hAxes.DataTipTemplate.DataTipRows(2).Label = 'Longitude:';

            if numel(hAxes.DataTipTemplate.DataTipRows) > 2
                hAxes.DataTipTemplate.DataTipRows(3:end) = [];
            end

        case 'winRFDataHub.Histogram1'
            hAxes.DataTipTemplate.DataTipRows = flip(hAxes.DataTipTemplate.DataTipRows);
            
            hAxes.DataTipTemplate.DataTipRows(1).Label  = 'Banda (MHz):';
            hAxes.DataTipTemplate.DataTipRows(2).Label  = 'Registros:';

        case 'winRFDataHub.Histogram2'
            hAxes.DataTipTemplate.DataTipRows = flip(hAxes.DataTipTemplate.DataTipRows);

            hAxes.DataTipTemplate.DataTipRows(1).Label  = 'Serviço:';
            hAxes.DataTipTemplate.DataTipRows(2).Label  = 'Registros:';

        case 'winRFDataHub.SimulationLink'
            hAxes.DataTipTemplate.DataTipRows(1).Label  = 'Distância:';
            hAxes.DataTipTemplate.DataTipRows(1).Format = '%.1f km';
            hAxes.DataTipTemplate.DataTipRows(2).Label  = 'Elevação:';
            hAxes.DataTipTemplate.DataTipRows(2).Format = '%.1f m';
    end

    if exist('dt', 'var')
        delete(dt)
    end
end