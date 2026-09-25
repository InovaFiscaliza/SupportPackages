classdef (Abstract) Propagation

    methods (Static = true)
        %-----------------------------------------------------------------%
        function [pathLoss, distKm, az] = PathLoss(txSite, rxSite, propModel)
            arguments
                txSite
                rxSite
                propModel char {mustBeMember(propModel, {'Free space'})} = 'Free space'
            end

             [distKm, az] = RF.Propagation.Distance(txSite, rxSite, 'km');
             switch propModel
                 case 'Free space'
                     pathLoss = fspl(distKm*1000, physconst('LightSpeed')/txSite.TransmitterFrequency);
                 otherwise
                     % Pendente!
             end
        end

        %-----------------------------------------------------------------%
        function [rn, distMeters, d1, az] = FresnelZone(txSite, rxSite, numPoints)
            arguments
                txSite
                rxSite
                numPoints = 256
            end

            [distMeters, az] = RF.Propagation.Distance(txSite, rxSite, 'm');
            d1 = linspace(0, distMeters, numPoints)';
            d2 = distMeters-d1;
        
            lambda = physconst('LightSpeed')/txSite.TransmitterFrequency;
            rn = sqrt(((d1.*d2)/distMeters) * lambda);
        end

        %-----------------------------------------------------------------%
        function [dist, az] = Distance(txSite, rxSite, unit)
            arguments
                txSite
                rxSite
                unit char {mustBeMember(unit, {'m', 'km'})} = 'km'
            end
            
            [distArc, az] = distance(txSite.Latitude, txSite.Longitude, rxSite.Latitude, rxSite.Longitude);
            dist = deg2km(distArc);
            if strcmp(unit, 'm')
                dist = dist * 1000;
            end
        end

        %-----------------------------------------------------------------%
        function [status, firstObstructionIdx] = LOS(yTerrain, yLOS, yFresnel)
            % Não usada a função do MATLAB LOS porque ela usa o modelo de elevação 
            % "USGS GMTED2010", que pode diferir daquele que é apresentado em tela, 
            % o que seria esquisito.

            yFresnelUp = yLOS + yFresnel;
            totalObstructionPerBin = yTerrain > yFresnelUp;

            if any(totalObstructionPerBin)
                status = false;
                firstObstructionIdx = find(totalObstructionPerBin, 1);
            else
                status = true;
                firstObstructionIdx = [];
            end
        end
    end
end