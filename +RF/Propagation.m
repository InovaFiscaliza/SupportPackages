classdef (Abstract) Propagation

    methods (Static = true)
        %-----------------------------------------------------------------%
        function [pathLoss, distKm, Azimuth] = PathLoss(txSite, rxSite, propModel)
            arguments
                txSite
                rxSite
                propModel char {mustBeMember(propModel, {'Free space'})} = 'Free space'
            end

             [distKm, Azimuth] = RF.Propagation.Distance(txSite, rxSite);
             switch propModel
                 case 'Free space'
                     pathLoss = fspl(distKm*1000, physconst('LightSpeed')/txSite.TransmitterFrequency);
                 otherwise
                     % Pendente!
             end
        end

        %-----------------------------------------------------------------%
        function [Rn, Dm, d1] = FresnelZone(txSite, rxSite, nPoints)
            arguments
                txSite
                rxSite
                nPoints = 256
            end

            Dm = RF.Propagation.Distance(txSite, rxSite, 'm');
            d1 = linspace(0, Dm, nPoints)';
            d2 = Dm-d1;
        
            lambda = physconst('LightSpeed')/txSite.TransmitterFrequency;
            Rn = sqrt(((d1.*d2)/Dm) * lambda);
        end

        %-----------------------------------------------------------------%
        function [Distance, Azimuth] = Distance(txSite, rxSite, Unit)
            [distArc, Azimuth] = distance(txSite.Latitude, txSite.Longitude, ...
                                          rxSite.Latitude, rxSite.Longitude);
            Distance = deg2km(distArc);
            if strcmp(Unit, 'm')
                Distance = Distance * 1000;
            end
        end

        %-----------------------------------------------------------------%
        function [Status, idxFirstObstruction] = LOS(yTerrain, yLOS, yFresnel)
            % Não usada a função do MATLAB LOS porque ela usa o modelo de elevação 
            % "USGS GMTED2010", que pode diferir daquele que é apresentado em tela, 
            % o que seria esquisito.

            yFresnelUp = yLOS + yFresnel;
            totalObstructionPerBin = yTerrain > yFresnelUp;

            if any(totalObstructionPerBin)
                Status = false;
                idxFirstObstruction = find(totalObstructionPerBin, 1);
            else
                Status = true;
                idxFirstObstruction = [];
            end
        end
    end
end