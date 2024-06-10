function disablingWarningMessages()

    warning('off', 'MATLAB:ui:javaframe:PropertyToBeRemoved')
    warning('off', 'MATLAB:subscripting:noSubscriptsSpecified')
    warning('off', 'MATLAB:structOnObject')
    warning('off', 'MATLAB:class:DestructorError')
    warning('off', 'MATLAB:modes:mode:InvalidPropertySet')
    warning('off', 'MATLAB:table:RowsAddedExistingVars')
    warning('off', 'MATLAB:colon:operandsNotRealScalar')
    
end