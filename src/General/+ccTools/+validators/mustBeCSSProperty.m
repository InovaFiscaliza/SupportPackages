function mustBeCSSProperty(x, PropertyName)
%MUSTBECSSPROPERTY
% MUSTBECSSPROPERTY(x) throws an error if an invalid CSS property
% value is passed.
%
% (A) BORDER-RADIUS
%     border-radius: 30px;
%     border-radius: 50%;
% (B) ...

% Author.: Eric Magalhães Delgado
% Date...: May 12, 2023
% Version: 1.00

    arguments
        x
        PropertyName char {mustBeMember(PropertyName, {'border-radius', 'border-width', 'font-family', 'font-weight', 'font-size', 'font-style', 'text-align', 'width', 'height', 'rotate', 'size', 'paddingTop'})} = 'border-radius'
    end

    try
        switch PropertyName
            case 'border-radius'
                if ischar(x) || (isstring(x) && isscalar(x))
                    y = char(regexpi(x, '\d+px|\d+%', 'match'));
                    if contains(y, '%')
                        z = str2double(extractBefore(y, '%'));
                        if (z < 0) || (z > 100)
                            error(errorMessage(PropertyName))
                        end
                    end        
                    if ~strcmpi(x, y)
                        error(errorMessage(PropertyName))
                    end
                else
                    error(errorMessage(PropertyName))
                end

            case 'border-width'
                if ischar(x) || (isstring(x) && isscalar(x))
                    if isempty(regexpi(x, '^(\d+px\s+){3}\d+px$|^(\d+px)$', 'once'))
                        error(errorMessage(PropertyName))
                    end
                else
                    error(errorMessage(PropertyName))
                end

            case {'font-size', 'width', 'height', 'size', 'paddingTop'}
                if ischar(x) || (isstring(x) && isscalar(x))
                    y = char(regexpi(x, '\d+px', 'match'));
                    if ~strcmpi(x, y)
                        error(errorMessage(PropertyName))
                    end
                else
                    error(errorMessage(PropertyName))
                end

            case 'rotate'
                if ~(ischar(x) || (isstring(x) && isscalar(x))) || isempty(regexpi(x, '^\d{1,3}deg$', 'match'))
                    error(errorMessage(PropertyName))
                end

            case 'font-family'
                if ~(ischar(x) || (isstring(x) && isscalar(x))) || ~ismember(x, listfonts)
                    error(errorMessage(PropertyName))
                end

            case 'font-weight'
                if ~(ischar(x) || (isstring(x) && isscalar(x))) || ~ismember(x, {'normal', 'bold'})
                    error(errorMessage(PropertyName))
                end

            case 'font-style'
                if ~(ischar(x) || (isstring(x) && isscalar(x))) || ~ismember(x, {'normal', 'italic'})
                    error(errorMessage(PropertyName))
                end

            case 'text-align'
                if ~(ischar(x) || (isstring(x) && isscalar(x))) || ~ismember(x, {'left', 'center', 'right', 'justify'})
                    error(errorMessage(PropertyName))
                end
            
            otherwise
                % others properties...
        end

    catch ME
        throwAsCaller(ME)
    end
end


function msg = errorMessage(PropertyName)
    switch PropertyName
        case 'border-radius'
            msg = sprintf('Property "%s" is not valid! Input must be textual - char or scalar string - such as: "50px" | "50%%".', PropertyName);
        case {'border-width', 'font-size', 'width', 'height', 'size', 'paddingTop'}
            msg = sprintf('Property "%s" is not valid! Input must be textual - char or scalar string - such as: "0px" | "1px".', PropertyName);
        case 'font-family'
            msg = sprintf('Property "%s" is not valid! Input must be textual - char or scalar string - such as: "Helvetica" | "Times New Roman".', PropertyName);
        case 'font-weight'
            msg = sprintf('Property "%s" is not valid! Input must be textual - char or scalar string - such as: "normal" | "bold".', PropertyName);
        case 'font-style'
            msg = sprintf('Property "%s" is not valid! Input must be textual - char or scalar string - such as: "normal" | "italic".', PropertyName);
        case 'text-align'
            msg = sprintf('Property "%s" is not valid! Input must be textual - char or scalar string - such as: "left" | "center" | "right" | "justify".', PropertyName);
        otherwise
            % others properties...
    end
end