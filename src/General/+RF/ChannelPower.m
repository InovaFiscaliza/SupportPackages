function [chPower, chPowerUnit, chDensity, chAzimuth] = ChannelPower(specData, flowIdx, chLimits)

    freqStart  = specData(flowIdx).MetaData.FreqStart;
    freqStop   = specData(flowIdx).MetaData.FreqStop;
    dataPoints = specData(flowIdx).MetaData.DataPoints;
    resolution = specData(flowIdx).MetaData.Resolution;
    
    if (chLimits(1) > freqStop) || (chLimits(2) < freqStart)
        error('RF:ChannelPower:OutOfRange', 'Out of range')
    end
    
    % Freq_Hz = aCoef*idx + bCoef;
    aCoef  = (freqStop - freqStart) ./ (dataPoints - 1);
    bCoef  = freqStart - aCoef;    
    xData  = linspace(freqStart, freqStop, dataPoints)';

    % Channel Limits (idx)
    chLimits(1) = max(chLimits(1), freqStart);
    chLimits(2) = min(chLimits(2), freqStop);

    chLim1Idx = round((chLimits(1) - bCoef)/aCoef);
    chLim2Idx = round((chLimits(2) - bCoef)/aCoef);

    switch specData(flowIdx).MetaData.LevelUnit
        case {'dBm', 'dBµV', 'dBµV/m'}
            chPowerUnit = specData(flowIdx).MetaData.LevelUnit;
            yData = specData(flowIdx).Data{2};

        % case 'dBµV'
        %     chPowerUnit = 'dBm';
        %     yData = specData(idxThread).Data{2} - 107; % 'dBµV' >> 'dBm' (50 Ohm system)

        otherwise
            error('RF:ChannelPower:UnexpectedLevelUnit', 'Unexpected level unit')
    end

    xData_ch = xData(chLim1Idx:chLim2Idx);
    yData_ch = double(yData(chLim1Idx:chLim2Idx, :));

    if chLim1Idx ~= chLim2Idx
        switch chPowerUnit
            case 'dBm'
                chPower = pow2db((trapz(xData_ch, db2pow(yData_ch), 1)/resolution))';

            case {'dBµV', 'dBµV/m'}
                chPower = mag2db((trapz(xData_ch, db2mag(yData_ch), 1)/resolution))';
        end
    else
        chPower = yData_ch';
    end

    chBandWidth = range(chLimits);
    chDensity = chPower - 10*log10(chBandWidth);

    chAzimuth = [];
    if numel(specData(flowIdx).Data) > 3
        chFreqCenterIdx = round(mean([chLim1Idx, chLim2Idx]));
        chAzimuth = double(specData(flowIdx).Data{4}(chFreqCenterIdx, :))';
    end
end