function mustBeColor(x, Format)
%MUSTBECOLOR
% MUSTBECOLOR(x) throws an error if an invalid color is passed. In the 
% context of this function, a valid color is a numeric vector with three 
% elements of types "uint8" (ranges from 0 to 255), "single" or "double" 
% (ranges from 0 to 1), or a textual value ("char", scalar "string", or 
% scalar "categorical") that represents the color's hexadecimal code or 
% its name, such as "white" or "black".

% See also VALIDATECOLOR

% Author.: Eric Magalhães Delgado
% Date...: June 06, 2023
% Version: 1.00

    arguments
        x
        Format {mustBeMember(Format, {'hex', 'rgb', 'css', 'all'})} = 'all'
    end        

    try
        switch Format
            case 'hex'
                if ischar(x) || (ismember(class(x), ["string", "categorical"]) && isscalar(x))
                    x = char(x);
                    Fcn = @(x) numel(x) == 7 & ~isempty(regexpi(x, '#[a-f0-9]{6}', 'once'));

                    if ~Fcn(x)
                        error('Input must be char, string, or categorical, such as: "#FF0000"');
                    end            
                else
                    error('Input must be char, string, or categorical, such as: "#FF0000"');
                end

            case 'rgb'
                if ismember(class(x), ["uint8", "single", "double"])
                    Fcn = @(x) (numel(x) == 3) & (isa(x, 'uint8') | (isfloat(x) & all(x >= 0 & x <= 1)));

                    if ~Fcn(x)
                        error('Input must be numeric array ("uint8", "single" or "double"), such as: uint8([255,0,0]) | single([1,0,0]) | [1,0,0]');
                    end
                else
                    error('Input must be numeric array ("uint8", "single" or "double"), such as: uint8([255,0,0]) | single([1,0,0]) | [1,0,0]');
                end

            case 'css'
                if ischar(x) || (ismember(class(x), ["string", "categorical"]) && isscalar(x))
                    x = char(x);
                    Fcn = @(x) ismember(lower(x), cssColorList);

                    if ~Fcn(x)
                        error('Input must be a CSS font name, such as: "blue" | "gray" | "white" | "transparent"');
                    end            
                else
                    error('Input must be a CSS font name, such as: "blue" | "gray" | "white" | "transparent"');
                end

            case 'all'        
                if ismember(class(x), ["uint8", "single", "double", "char"]) || (ismember(class(x), ["string", "categorical"]) && isscalar(x))
                    if isnumeric(x)
                        Fcn = @(x) (numel(x) == 3) & (isa(x, 'uint8') | (isfloat(x) & all(x >= 0 & x <= 1)));
                    else
                        x = char(x);
                        Fcn = @(x) (numel(x) == 7 & ~isempty(regexpi(x, '#[a-f0-9]{6}', 'once'))) | ismember(lower(x), cssColorList);
                    end
                    
                    if ~Fcn(x)
                        error('Input is not a valid color, such as: "red" | "transparent" | "#FF0000" | uint8([255,0,0]) | [.5,.5,.5]');
                    end            
                else
                    error('Input is not a valid color, such as: "red" | "transparent" | "#FF0000" | uint8([255,0,0]) | [.5,.5,.5]');
                end
        end

    catch ME
        throwAsCaller(ME)
    end
end


function Colors = cssColorList
    Colors = ["aliceblue", "antiquewhite", "aqua", "aquamarine", "azure", "beige", "bisque", "black", "blanchedalmond",                ...
    "blue", "blueviolet", "brown", "burlywood", "cadetblue", "chartreuse", "chocolate", "coral", "cornflowerblue",                     ...
    "cornsilk", "crimson", "cyan", "darkblue", "darkcyan", "darkgoldenrod", "darkgray", "darkgreen", "darkgrey",                       ...
    "darkkhaki", "darkmagenta", "darkolivegreen", "darkorange", "darkorchid", "darkred", "darksalmon", "darkseagreen",                 ...
    "darkslateblue", "darkslategray", "darkslategrey", "darkturquoise", "darkviolet", "deeppink", "deepskyblue", "dimgray",            ...
    "dimgrey", "dodgerblue", "firebrick", "floralwhite", "forestgreen", "fuchsia", "gainsboro", "ghostwhite", "goldenrod",             ...
    "gold", "gray", "green", "greenyellow", "grey", "honeydew", "hotpink", "indianred", "indigo", "ivory", "khaki",                    ...
    "lavenderblush", "lavender", "lawngreen", "lemonchiffon", "lightblue", "lightcoral", "lightcyan", "lightgoldenrodyellow",          ...
    "lightgray", "lightgreen", "lightgrey", "lightpink", "lightsalmon", "lightseagreen", "lightskyblue", "lightslategray",             ...
    "lightslategrey", "lightsteelblue", "lightyellow", "lime", "limegreen", "linen", "magenta", "maroon", "mediumaquamarine",          ...
    "mediumblue", "mediumorchid", "mediumpurple", "mediumseagreen", "mediumslateblue", "mediumspringgreen", "mediumturquoise",         ...
    "mediumvioletred", "midnightblue", "mintcream", "mistyrose", "moccasin", "navajowhite", "navy", "oldlace", "olive", "olivedrab",   ...
    "orange", "orangered", "orchid", "palegoldenrod", "palegreen", "paleturquoise", "palevioletred", "papayawhip", "peachpuff",        ...
    "peru", "pink", "plum", "powderblue", "purple", "rebeccapurple", "red", "rosybrown", "royalblue", "saddlebrown", "salmon",         ...
    "sandybrown", "seagreen", "seashell", "sienna", "silver", "skyblue", "slateblue", "slategray", "slategrey", "snow", "springgreen", ...
    "steelblue", "tan", "teal", "thistle", "tomato", "transparent", "turquoise", "violet", "wheat", "white", "whitesmoke", "yellow", "yellowgreen"];
end