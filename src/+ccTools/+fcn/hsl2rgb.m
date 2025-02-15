function rgbImg = hsl2rgb(hslImg, OuputFormat, Decimals)
%HSL2RGB
% General info:
% - Algorithm: https://www.rapidtables.com/convert/color/hsl-to-rgb.html
% - RGB (Reg, Green, Blue)
% - HSL (Hue, Saturation, Lightness)

% Author.: Eric Magalhães Delgado
% Date...: May 12, 2023
% Version: 1.00

    arguments
        hslImg
        OuputFormat {mustBeMember(OuputFormat, {'uint8', 'float'})}                = 'float'
        Decimals    {ccTools.validators.mustBeUnsignedNumber(Decimals, 'nonZero')} = 3
    end

    H = hslImg(1);
    S = hslImg(2);
    L = hslImg(3);

    C = (1-abs(2*L-1))*S;
    X = C*(1-abs(mod(H/60, 2)-1));
    m = L-C/2;

    if     H <  60; rgbImg = [C,X,0];
    elseif H < 120; rgbImg = [X,C,0];
    elseif H < 180; rgbImg = [0,C,X];
    elseif H < 240; rgbImg = [0,X,C];
    elseif H < 300; rgbImg = [X,0,C];
    else;           rgbImg = [C,0,X];
    end

    switch OuputFormat
        case 'uint8'; rgbImg = uint8((rgbImg+m)*255);
        case 'float'; rgbImg = round(rgbImg+m, Decimals);
    end
end