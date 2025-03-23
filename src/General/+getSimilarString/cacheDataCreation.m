function [rawTable, cacheData] = cacheDataCreation(rawTable, cacheColumns)

    cacheData = repmat(struct('Column', '', 'uniqueValues', {{}}, 'uniqueTokens', {{}}), numel(cacheColumns), 1);

    for ii = 1:numel(cacheColumns)
        listOfColumns = strsplit(cacheColumns{ii}, ' | ');

        uniqueValues  = {};
        uniqueTokens  = {};

        for jj = 1:numel(listOfColumns)
            cacheColumn        = listOfColumns{jj};
            [uniqueTempValues, ...
                referenceData] = textAnalysis.preProcessedData(rawTable.(cacheColumn));
            tokenizedDoc       = tokenizedDocument(uniqueTempValues);

            uniqueValues       = [uniqueValues; uniqueTempValues];
            uniqueTokens       = [uniqueTokens; cellstr(tokenizedDoc.tokenDetails.Token)];
    
            rawTable.(sprintf('_%s', cacheColumn)) = referenceData;
        end
        uniqueValues  = unique(uniqueValues);

        cacheData(ii) = struct('Column',       cacheColumns{ii},  ...
                               'uniqueValues', {uniqueValues},    ...
                               'uniqueTokens', {unique([uniqueValues; uniqueTokens])});
    end

end