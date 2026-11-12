function numCanvas = countCanvasElements(container)
    % Retorna o número de elementos <canvas> HTML que o MATLAB cria dentro do
    % "container" (usado em "numCanvasElements" do evento "dockContainer").
    %
    % Regra: apenas "tiledlayout" cria canvas próprio no container. Ao ser
    % inserido, ele apaga tudo o que havia no container, ficando sozinho.
    % Eixos diretos (uiaxes, geoaxes) compartilham um único canvas, criado no
    % uifigure ao inserir o primeiro eixo, fora do container do popup.
    %
    % Cenário testado:
    % • uifigure com uiaxes, geoaxes e uipanel.
    % • No uipanel, um tiledlayout com uiaxes e geoaxes.
    % • Resultado: 2 canvas. Um do uifigure (criado com o primeiro eixo) e outro
    %   do uipanel (criado ao inserir o tiledlayout).
    %
    % Observações:
    % • Um uipanel recém-criado não possui canvas.
    % • Canvas e eixos não possuem DataTag de elemento HTML; o DataTag está no
    %   uipanel, o que permite buscar os canvas dentro dele.
    % • Um tiledlayout pode ter n eixos, mas cria apenas 1 canvas.
    % • Cada tiledlayout exige um container próprio.

    numCanvas = numel(findobj(container, 'Type', 'tiledlayout'));
end