%% ws.auth.F5Session
% Spike de autenticação interativa (SAML 2.0 + MFA) através do proxy reverso
% F5 BIG-IP APM, e validação de que os cookies de sessão extraídos do
% navegador embarcado funcionam no cliente HTTP do próprio MATLAB.
%
% Execute célula a célula (Ctrl+Enter).

targetURL = 'https://fiscalizacao.anatel.gov.br/rffusion/debug/headers';

mFilePath = fileparts(which('checkF5Auth'));
addpath(fullfile(fileparts(fileparts(mFilePath)), 'src', 'Anatel'))

%% Test1: Login interativo
% Abre a janela embarcada, aguarda o fluxo SAML + aprovação do push no
% Microsoft Authenticator e captura os cookies de sessão.

session = ws.auth.F5Session(targetURL);
login(session)

disp(debugInfo(session))

%% Test2: Round-trip fora do navegador embarcado
% Confirma que o cookie é portável para o cliente HTTP do MATLAB, isto é,
% que o F5 não o vincula a fingerprint de navegador (User-Agent, TLS etc.).
% read() usa MaxRedirects=0, tornando visível o 302 do APM para /my.policy.

data = read(session, targetURL);

disp(data)
assert(isstruct(data), 'Resposta não é JSON - provável redirecionamento para a página de login.')

%% Test3: Requisição sem cookie (controle negativo)
% Simula a sessão expirada e valida que isSessionExpired() reconhece a
% resposta - seja um 302 do APM, seja a própria página de login em HTTP 200.

request  = matlab.net.http.RequestMessage('GET');
response = request.send(targetURL, matlab.net.http.HTTPOptions('MaxRedirects', 0));

fprintf('HTTP %d (%s)\n', double(response.StatusCode), char(response.StatusCode));
fprintf('Location: %s\n', strjoin(string({getFields(response, 'Location').Value}), ''));
fprintf('Detectado como sessão inválida: %d\n', ws.auth.F5Session.isSessionExpired(response));

payload = response.Body.Data;
if ischar(payload) || isStringScalar(payload)
    disp(extractBefore(string(payload), min(600, strlength(payload)+1)))
end

%% Cleanup
% Descarta a sessão em memória (nada foi gravado em disco).

delete(session)
