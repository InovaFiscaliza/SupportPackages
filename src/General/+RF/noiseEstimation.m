function noiseValue = noiseEstimation(specData, xIndexDown, xIndexUp, noiseTrashSamples, noiseUsefulSamples, noiseOffset)
    arguments
        specData
        xIndexDown
        xIndexUp
        noiseTrashSamples  double {mustBeNonnegative, mustBeLessThan(noiseTrashSamples,  1)}
        noiseUsefulSamples double {mustBeNonnegative, mustBeLessThan(noiseUsefulSamples, 1)}
        noiseOffset        double {mustBeNonnegative, mustBeFinite}
    end

    DataPoints  = xIndexUp-xIndexDown+1;

    idx1        = max(1,                 ceil(noiseTrashSamples  * DataPoints));
    idx2        = min(DataPoints, idx1 + ceil(noiseUsefulSamples * DataPoints));
    
    sortedData  = sort(specData.Data{3}(xIndexDown:xIndexUp, 2));
    sortedData  = sortedData(idx1:idx2);
    
    noiseValue = median(sortedData) + noiseOffset;
end