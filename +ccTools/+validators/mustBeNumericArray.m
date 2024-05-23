function mustBeNumericArray(x, Size, Type)
%MUSTBENUMERICARRAY
% MUSTBENUMERICARRAY(x, Size, Type) throws an error if an invalid numeric
% array is passed.

% Author.: Eric Magalhães Delgado
% Date...: Junho 05, 2023
% Version: 1.00

    arguments
        x {mustBeNumeric}
        Size {mustBeScalarOrEmpty, mustBeNonempty, mustBeNonnegative, mustBeInteger, mustBeFinite}
        Type {mustBeMember(Type, {'NonNegativeInteger'})}
    end

    try        
        switch Type
            case 'NonNegativeInteger'
                Fcn = @(x) (numel(x) == Size) & isreal(x) & all(isfinite(x)) & all(x>=0) & isequal(x, round(x));
        
                if ~Fcn(x)
                    error('Input must be a numeric array with %.0f elements of type "%s".', Size, Type);
                end
        end

    catch ME
        throwAsCaller(ME)
    end
end