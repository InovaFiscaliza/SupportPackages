function mustBeAppContainer(x)
%MUSTBEAPPCONTAINER

% Author.: Eric Magalhães Delgado
% Date...: July 27, 2023
% Version: 1.00

    AppContainerList = {'matlab.ui.container.internal.AppContainer', ...
                        'matlab.ui.Figure'};
    mustBeMember(class(x), AppContainerList)
end