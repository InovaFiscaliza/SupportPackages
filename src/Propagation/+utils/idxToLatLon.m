function [lat, lon] = idxToLatLon(idx, sz, R)
    [row, col] = ind2sub(sz, idx);
    [lat, lon] = R.intrinsicToGeographic(col, row);  % col = x, row = y
end

