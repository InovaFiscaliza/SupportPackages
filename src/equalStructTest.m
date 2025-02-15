function [isEqual, changedFields] = equalStructTest(oldData, newData)

    arguments
        oldData struct
        newData struct
    end

    isEqual       = isequal(oldData, newData);
    changedFields = struct('fieldName', {}, 'oldValue', {}, 'newValue', {});

    if isequal(fields(oldData), fields(newData))
        listOfFields  = fields(oldData);    
        for ii =1:numel(listOfFields)
            fieldName = listOfFields{ii};
            oldValue  = oldData.(fieldName);
            newValue  = newData.(fieldName);
    
            if ~isequal(oldValue, newValue)
                if ~isempty(oldValue) || ~isempty(newValue)
                    changedFields(end+1).fieldName = fieldName;
                    changedFields(end).oldValue    = oldValue;
                    changedFields(end).newValue    = newValue;
                end
            end
        end
    end
    changedFields = struct2table(changedFields);

end