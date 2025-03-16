function [chPower, chPowerUnit, PowerSpectralDensity] = ChannelPower(specData, idxThread, chLimits)

    FreqStart  = specData(idxThread).MetaData.FreqStart;
    FreStop    = specData(idxThread).MetaData.FreqStop;
    DataPoints = specData(idxThread).MetaData.DataPoints;
    RBW        = specData(idxThread).MetaData.Resolution;
    
    if (chLimits(1) > FreStop) || (chLimits(2) < FreqStart)
        error('RF:ChannelPower:OutOfRange', 'Out of range')
    end
    
    % Freq_Hz = aCoef*idx + bCoef;
    aCoef  = (FreStop - FreqStart) ./ (DataPoints - 1);
    bCoef  = FreqStart - aCoef;    
    xData  = linspace(FreqStart, FreStop, DataPoints)';

    % Channel Limits (idx)
    chLimits(1) = max(chLimits(1), FreqStart);
    chLimits(2) = min(chLimits(2), FreStop);

    idx1 = round((chLimits(1) - bCoef)/aCoef);
    idx2 = round((chLimits(2) - bCoef)/aCoef);

    switch specData(idxThread).MetaData.LevelUnit
        case {'dBm', 'dBµV', 'dBµV/m'}
            chPowerUnit = specData(idxThread).MetaData.LevelUnit;
            yData = specData(idxThread).Data{2};
        % case 'dBµV'
        %     chPowerUnit = 'dBm';
        %     yData = specData(idxThread).Data{2} - 107; % 'dBµV' >> 'dBm' (50 Ohm system)
        otherwise
            error('RF:ChannelPower:UnexpectedLevelUnit', 'Unexpected level unit')
    end

    xData_ch = xData(idx1:idx2);
    yData_ch = double(yData(idx1:idx2,:));

    if idx1 ~= idx2
        switch chPowerUnit
            case 'dBm'
                chPower = pow2db((trapz(xData_ch, db2pow(yData_ch), 1)/RBW))';
            case {'dBµV', 'dBµV/m'}
                chPower = mag2db((trapz(xData_ch, db2mag(yData_ch), 1)/RBW))';
        end
    else
        chPower = yData_ch';
    end

    chBandWidth = range(chLimits);
    PowerSpectralDensity = chPower - 10*log10(chBandWidth);
end