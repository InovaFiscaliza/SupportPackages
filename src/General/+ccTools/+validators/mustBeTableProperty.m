function mustBeTableProperty(x, PropertyName)
%MUSTBETABLEPROPERTY
% MUSTBETABLEPROPERTY(x) throws an error if an invalid value is passed.

% Author.: Eric Magalhães Delgado
% Date...: May 12, 2023
% Version: 1.00

    switch PropertyName
        case 'Selection';        Fcn = @(x) ~isempty(x) && isnumeric(x) && isreal(x) && isscalar(x) && isfinite(x) && (x>=0);
        case 'Cell';             Fcn = @(x) isstruct(x) & all(isfield(x, {'Row', 'Column', 'Value'}));
        case 'ColumnName';       Fcn = @(x) iscell(x) & all(cellfun(@(y) ~isempty(deblank(y)), x));
        case 'ColumnEditable',   Fcn = @(x) islogical(x) | all(isnumeric(x) & ismember(x, [0,1]));
        case 'ColumnWidth',      Fcn = @(x) iscell(x) & all(cellfun(@(y) ~isempty(regexp(y, 'auto|\dpx', 'once')), x));
        case 'ColumnAlign',      Fcn = @(x) iscell(x) & all(cellfun(@(y) ismember(y, {'auto', 'left', 'center', 'right'}), x));
        case 'ColumnPrecision',  Fcn = @(x) iscell(x) & all(cellfun(@(y) ~isempty(regexp(y, '(auto|(%s|%d|%i|%.\d{1,2}f))', 'once')), x));
        case 'ColumnMultiplier'; Fcn = @(x) isnumeric(x) & isreal(x) & all(isfinite(x));
    end    
    
    if ~Fcn(x)
        error('Property "%s" is not valid. Check documentation!', PropertyName);
    end
end