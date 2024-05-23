function mustBeNumberInRange(x, A, B, numClass)
%MUSTBENUMBERINRANGE
% MUSTBENUMBERINRANGE(x, A, B, numClass) throws an error if an invalid 
% value is passed. % In the context of this function, a valid value is a 
% scalar numeric value range between A and B.

% Author.: Eric Magalhães Delgado
% Date...: May 12, 2023
% Version: 1.00

    arguments
        x {mustBeNumeric}
        A {mustBeNumeric} = 0
        B {mustBeNumeric} = 1
        numClass {mustBeMember(numClass, {'int8', 'int16', 'int32', 'int64', 'uint8', 'uint16', 'uint32', 'uint64', 'single', 'double', 'all'})} = 'all'
    end

    try
        if (A>B)
            initialA = A;
            initialB = B;

            A = initialB;
            B = initialA;
        end

        if ~strcmp(numClass, 'all') && ~isa(x, numClass)
            error('Input must be a scalar numeric value of class "%s".', numClass);
        end

        Fcn = @(x) isscalar(x) & isreal(x) & (x >= A) & (x <= B);
        
        if ~Fcn(x)
            error('Input must be a scalar numeric value between %f and %f, such as: %f', A, B, mean([A,B]));
        end    

    catch ME
        throwAsCaller(ME)
    end
end