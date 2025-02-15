function mustBeUnsignedNumber(x, zeroFlag)
%MUSTBEUNSIGNEDNUMBER
% MUSTBEUNSIGNEDNUMBER(x, zeroFlag) throws an error if an invalid numeric
% value is passed.

% Author.: Eric Magalhães Delgado
% Date...: May 12, 2023
% Version: 1.00

    arguments
        x
        zeroFlag char {mustBeMember(zeroFlag, {'includingZero', 'nonZero'})} = 'includingZero'
    end

    switch zeroFlag
        case 'includingZero'; Fcn = @(x) isnumeric(x) & isreal(x) & isscalar(x) & isfinite(x) & (x >= 0);
        case 'nonZero';       Fcn = @(x) isnumeric(x) & isreal(x) & isscalar(x) & isfinite(x) & (x >  0);
    end
    
    if ~Fcn(x)
        error('Input must be scalar unsigned numeric ("uint8", "single", "double" and so on), such as: unit8(10) | single(.5) | .5');
    end    
end