function varName = nameOfVariable(varargin)
    varName = {};
    for ii = 1:numel(varargin)
        varName{end+1} = inputname(ii);
    end
end