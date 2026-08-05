function [AA, RR] = resizeGeotiff(A, R, n)
%UNTITLED2 Summary of this function goes here
%   Detailed explanation goes here
arguments
    A 
    R 
    n int16 = 3
end

    s = R.RasterSize;
    rows = s(1);
    cols = s(2);
    newRows = ceil(rows / n);
    newCols = ceil(cols / n);
    AA = zeros(newRows, newCols);

    AA(1, 1) = mean(A(1: n, 1 : n), "all");    
    for r = 1 : newRows - 1
        for c = 1 : newCols - 1
            uR = n * r + n;
            uC = n * c + n;
            if uR > rows
                uR = rows;
            end

            if uC > cols
                uC = cols;
            end

            AA(r, c) = mean(A(n * r + 1 : uR, n * c + 1 : uC), "all");

        end
    end

    RR = R;
    RR.RasterSize= [newRows, newCols];

end