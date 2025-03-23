function hslImg = rgb2hsl(rgbImg)
%RGB2HSL
% General info:
% - Algorithm: https://www.rapidtables.com/convert/color/hsl-to-rgb.html
% - RGB (Reg, Green, Blue)
% - HSL (Hue, Saturation, Lightness)

% Author.: Eric Magalhães Delgado
% Date...: May 12, 2023
% Version: 1.00

    arguments
        rgbImg {ccTools.validators.mustBeColor(rgbImg, 'rgb')}
    end

    rgbImg = double(rgbImg)/255;    
    R = rgbImg(1);
    G = rgbImg(2);
    B = rgbImg(3);
    
    [Cmax, idx] = max(rgbImg);
    Cmin  = min(rgbImg);
    Cdiff = Cmax-Cmin;

    L = (Cmax+Cmin)/2;

    if Cdiff == 0
        H = 0;
        S = 0;
    else
        S = Cdiff/(1-abs(2*L-1));
        switch idx
            case 1; H = 60 * mod((G-B)/Cdiff, 6);
            case 2; H = 60 *    ((B-R)/Cdiff + 2);
            case 3; H = 60 *    ((R-G)/Cdiff + 4);
        end
    end
    hslImg = [H, S, L];
end