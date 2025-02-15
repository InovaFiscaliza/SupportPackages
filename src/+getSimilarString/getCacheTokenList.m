function cacheTokenList = getCacheTokenList(cacheData, listOfColumns)

    cacheIndex     = find(strcmp(listOfColumns, {cacheData.Column}), 1);
    cacheTokenList = cacheData(cacheIndex).uniqueTokens;

end