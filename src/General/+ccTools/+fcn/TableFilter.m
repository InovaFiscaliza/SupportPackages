function [fTable, fIndex, fTableParser, fSentence, fValid] = TableFilter(hTable, fRawSentence)
%CCTABLEFILTER
% Allowed filter operations (n-th column, case insensitive validation):
% (a) NUMERIC COLUMNS:
%     Cn <  numericValue 
%     Cn <= numericValue
%     Cn == numericValue
%     Cn != numericValue
%     Cn >= numericValue
%     Cn >  numericValue
%     Cn sorted
%     Cn sorted up
%     Cn sorted down
%     Cn precision "%.1f"
% (c) TEXTUAL COLUMNS:
%     Cn contains  "stringValue"
%     Cn !contains "stringValue"
%     Cn  isequal  "stringValue"
%     Cn !isequal  "stringValue"
%     Cn sorted
%     Cn sorted up
%     Cn sorted down
% (c) LOGICAL OPERATORS:
%     && 
%     ||
% (d) SENTENCES SEPARATORS:
%     ;
% (e) EXAMPLES:
%     C1 >= 100 && C1 <= 1000; C2 contains "Some text"; C3 sorted
%     C1 == 87.9 || C1 == 104.9; C2 !isequal "Some text"
%     C1 PRECISION "%.0F"; C2 PRECISION "%.3F"

% Author.: Eric Magalhães Delgado
% Date...: June 03, 2023
% Version: 1.00

    [fTableParser, fSentence, fValid] = Fcn1_InputParser(hTable, fRawSentence);
    [fTable, fIndex] = Fcn2_FilterData(hTable, fTableParser);
end


function [fTableParser, fSentence, fValid] = Fcn1_InputParser(hTable, fRawSentence)
    fTableParser = table('Size', [0, 5],                                                ...
                         'VariableTypes', {'double', 'cell', 'double', 'cell', 'cell'}, ...
                         'VariableNames', {'ID', 'Combinator', 'Column', 'Operation', 'Value'});

    sRawSentence = upper(strsplit(fRawSentence, ';'));
    for ii = 1:numel(sRawSentence)
        Combinator = '-';

        if contains(sRawSentence{ii}, 'SORTED')
            temp = sRawSentence(ii);
            regE = 'C(?<Column>\d+)\s*(?<Operation>SORTED\s*(UP|DOWN)*)';

        elseif contains(sRawSentence{ii}, 'PRECISION')
            temp = sRawSentence(ii);
            regE = 'C(?<Column>\d+)\s*(?<Operation>PRECISION)\s*(?<Value>"%.\d{1,2}F")';
        
        else
            % Logical operators accepts: || or &&
            x1 = sRawSentence{ii} == '|';
            x2 = sRawSentence{ii} == '&';

            if any(~ismember((find(diff([0, x1, 0]) == -1) - find(diff([0, x1, 0]) == 1)), [0, 2])) || ...
               any(~ismember((find(diff([0, x2, 0]) == -1) - find(diff([0, x2, 0]) == 1)), [0, 2])) || ...
               (any(x1) && any(x2))
                continue

            elseif any(x1)
                Combinator = 'OR';
                temp = strsplit(sRawSentence{ii}, '||');

            elseif any(x2)
                Combinator = 'AND';
                temp = strsplit(sRawSentence{ii}, '&&');

            else
                temp = sRawSentence(ii);
            end
            regE = 'C(?<Column>\d+)\s*(?<Operation>(CONTAINS|!CONTAINS|ISEQUAL|!ISEQUAL|<=|==|!=|>=|<|>))\s*(?<Value>(".+"|[-]?\d*[.]?\d*))';
        end
    
        for jj = 1:numel(temp)
            tempStruct = regexpi(temp{jj}, regE, 'names');

            if ~isempty(tempStruct)
                if strcmp(Combinator, '-')
                    tempStruct = tempStruct(1);
                end
        
                for kk = 1:numel(tempStruct)
                    COLUMN = str2double(tempStruct(kk).Column);

                    if COLUMN > width(hTable)
                        continue
                        
                    elseif contains(tempStruct(kk).Operation, 'SORTED')
                        tempStruct(kk).Value = '-';

                    elseif strcmp(tempStruct(kk).Operation, 'PRECISION')
                        quotation = sum(tempStruct(kk).Value == '"');
                        keywords  = extractBetween(tempStruct(kk).Value, '"', '"');
                        if (quotation ~= 2) || (numel(keywords) == 1 && isempty(char(keywords))) || (numel(keywords) > 1) || ~isnumeric(hTable{:,COLUMN})
                            continue
                        end
        
                    elseif ismember(tempStruct(kk).Operation, {'CONTAINS', '!CONTAINS', 'ISEQUAL', '!ISEQUAL'})
                        quotation = sum(tempStruct(kk).Value == '"');
                        keywords  = extractBetween(tempStruct(kk).Value, '"', '"');
                        if (quotation ~= 2) || (numel(keywords) == 1 && isempty(char(keywords))) || (numel(keywords) > 1) || isnumeric(hTable{:,COLUMN})
                            continue
                        end
        
                    else
                        if ~ismember(tempStruct(kk).Operation, {'<', '<=', '==', '!=', '>=', '>'}) || isnan(str2double(tempStruct(kk).Value)) || ~isnumeric(hTable{:,COLUMN})
                            continue
                        end
                    end
        
                    fTableParser(end+1,:) = {ii, Combinator, str2double(tempStruct(kk).Column), tempStruct(kk).Operation, tempStruct(kk).Value};
                end
            end
        end
    end

    fSentence = {};
    for ii = unique(fTableParser.ID)'
        idx = find(fTableParser.ID == ii);
        if ~isempty(idx)
            if numel(idx) == 1
                if contains(fTableParser.Operation{idx}, 'SORTED')
                    fSentence{end+1} = sprintf('C%d %s', fTableParser.Column(idx), fTableParser.Operation{idx});
                else
                    fSentence{end+1} = sprintf('C%d %s %s', fTableParser.Column(idx), fTableParser.Operation{idx}, fTableParser.Value{idx});
                end
            
            else
                if numel(unique(fTableParser.Column(idx))) > 1
                    fTableParser(idx,:) = [];
                    continue
                end

                tempSentence = {};
                for jj = idx'
                    tempSentence{end+1} = sprintf('C%d %s %s', fTableParser.Column(jj), fTableParser.Operation{jj}, fTableParser.Value{jj});
                end

                if strcmp(fTableParser.Combinator{idx(1)}, 'AND')
                    fSentence{end+1} = strjoin(tempSentence, ' && ');
                else
                    fSentence{end+1} = strjoin(tempSentence, ' || ');
                end
            end
        end
    end
    fSentence = strjoin(fSentence, '; ');
    fValid    = isequal(upper(replace(fRawSentence, ' ', '')), replace(fSentence, ' ', ''));
end


function [fTable, fIndex] = Fcn2_FilterData(hTable, fTableParser)
    % FILTER TABLE
    fNonSorted = fTableParser(~contains(fTableParser.Operation, {'SORTED', 'PRECISION'}), :);
    SentenceID = unique(fNonSorted.ID)';

    fLogical   = true(height(hTable), numel(SentenceID));
    fTolerance = 1e-5;                                           % Math operation (related to float datatypes)

    for ii = 1:numel(SentenceID)             
        idx = find(fNonSorted.ID == SentenceID(ii))';

        tempLogical = true(height(hTable), numel(idx));
        for jj = 1:numel(idx)
            Fcn = FilterFcn(fNonSorted(idx(jj), :), fTolerance);
            tempLogical(:,jj) = Fcn(hTable{:, fNonSorted.Column(idx(jj))});
        end

        if strcmp(fNonSorted.Combinator{idx(1)}, 'AND')
            fLogical(:, ii) = all(tempLogical, 2);
        else
            fLogical(:, ii) = any(tempLogical, 2);
        end        
    end
    fLogical = all(fLogical, 2);
    fTable   = hTable(fLogical, :);
    fIndex   = find(fLogical);

    % SORT TABLE
    fSorted = fTableParser(contains(fTableParser.Operation, 'SORTED'), :);
    if ~isempty(fSorted)
        if contains(fSorted.Operation{1}, 'DOWN'); Direction = 'descend';
        else;                                      Direction = 'ascend';
        end

        [fTable, idx] = sortrows(fTable, unique(fSorted.Column, 'stable'), Direction);
        fIndex = fIndex(idx);
    end
end


function Fcn = FilterFcn(fNonSorted, tol)
    switch fNonSorted.Operation{1}
        case 'CONTAINS';  Fcn = @(x)  contains(x, extractBetween(fNonSorted.Value{1}, '"', '"'), 'IgnoreCase', true);
        case '!CONTAINS'; Fcn = @(x) ~contains(x, extractBetween(fNonSorted.Value{1}, '"', '"'), 'IgnoreCase', true);
        case 'ISEQUAL';   Fcn = @(x)  strcmpi( x, extractBetween(fNonSorted.Value{1}, '"', '"'));
        case '!ISEQUAL';  Fcn = @(x) ~strcmpi( x, extractBetween(fNonSorted.Value{1}, '"', '"'));
        case '==';        Fcn = @(x) abs(x - str2double(fNonSorted.Value{1})) < tol;
        case '!=';        Fcn = @(x) abs(x - str2double(fNonSorted.Value{1})) > tol;
        case '<';         Fcn = @(x) x <  str2double(fNonSorted.Value{1});
        case '<=';        Fcn = @(x) x <= str2double(fNonSorted.Value{1});
        case '>=';        Fcn = @(x) x >= str2double(fNonSorted.Value{1});
        case '>';         Fcn = @(x) x >  str2double(fNonSorted.Value{1});
    end
end