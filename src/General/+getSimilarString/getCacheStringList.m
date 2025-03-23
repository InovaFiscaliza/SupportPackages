function cacheStringList = getCacheStringList(cacheData, listOfColumns)

    cacheIndex      = find(strcmp(listOfColumns, {cacheData.Column}), 1);
    cacheStringList = cacheData(cacheIndex).uniqueValues;

end