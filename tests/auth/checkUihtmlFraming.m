function uiFigure = checkUihtmlFraming
% checkUihtmlFraming Probe uihtml framing and cross-origin cookie access.
%
% This is a feasibility test only. It does not authenticate, collect cookie
% values, or attempt MFA. Type checkUihtmlFraming in MATLAB, then use the
% buttons below the frame. Use Next URL to run the two configured cases in
% order.

mFilePath = fileparts(mfilename('fullpath'));
addpath(fullfile(fileparts(fileparts(mFilePath)), 'src', 'General'))

%% Test URLs
protectedURL = 'https://fiscalizacao.anatel.gov.br/rffusion';
loginURL = 'https://fiscalizacao.anatel.gov.br/rffusion/api/users/login';

testURLs = {protectedURL, loginURL};
testNames = {'Protected Anatel URL', 'API login URL'};
testCount = numel(testURLs);

currentURLIndex = 1;
requestID = 0;
lastFramingStatus = "unknown";

%% User interface
uiFigure = uifigure('Name', 'uihtml framing feasibility probe', ...
                    'Position', [100, 100, 1100, 760]);
uiFigure.CloseRequestFcn = @(source, ~) delete(source);

layout = uigridlayout(uiFigure, [3, 1]);
layout.RowHeight = {'1x', 105, 42};
layout.ColumnWidth = {'1x'};
layout.Padding = [8, 8, 8, 8];
layout.RowSpacing = 8;

htmlView = uihtml(layout);
htmlView.Layout.Row = 1;
htmlView.Layout.Column = 1;
htmlView.HTMLEventReceivedFcn = @onHtmlEvent;

statusArea = uitextarea(layout, ...
                        'Editable', 'off', ...
                        'Value', {'Starting uihtml test.'});
statusArea.Layout.Row = 2;
statusArea.Layout.Column = 1;

controlLayout = uigridlayout(layout, [1, 6]);
controlLayout.Layout.Row = 3;
controlLayout.Layout.Column = 1;
controlLayout.ColumnWidth = {'1x', 110, 140, 160, 120, 160};
controlLayout.ColumnSpacing = 8;

urlLabel = uilabel(controlLayout, 'Text', '');
urlLabel.Layout.Column = 1;
urlLabel.HorizontalAlignment = 'left';

nextURLButton = uibutton(controlLayout, 'Text', 'Next URL', ...
                          'ButtonPushedFcn', @selectNextURL);
nextURLButton.Layout.Column = 2;

checkFramingButton = uibutton(controlLayout, 'Text', 'Check framing', ...
                              'ButtonPushedFcn', @checkFraming);
checkFramingButton.Layout.Column = 3;

checkCookiesButton = uibutton(controlLayout, 'Text', 'Attempt cookie read', ...
                              'ButtonPushedFcn', @attemptCookieRead);
checkCookiesButton.Layout.Column = 4;

ErikButton = uibutton(controlLayout, 'Text', 'Erik Button', ...
                              'ButtonPushedFcn', @erikButtonCallback);
ErikButton.Layout.Column = 5;

sharedBridgeButton = uibutton(controlLayout, 'Text', 'Use shared bridge', ...
                              'ButtonPushedFcn', @useSharedBridge);
sharedBridgeButton.Layout.Column = 6;

loadCurrentURL()

%% Button callbacks
    function selectNextURL(~, ~)
        currentURLIndex = mod(currentURLIndex, numel(testURLs)) + 1;
        loadCurrentURL()
    end

    function checkFraming(~, ~)
        requestID = requestID + 1;
        appendStatus(sprintf('Checking framing for URL %d.', currentURLIndex))
        htmlView.Data = struct('source', 'uihtmlFramingProbe', ...
                       'action', 'checkFraming', 'requestId', requestID);
    end

    function attemptCookieRead(~, ~)
        requestID = requestID + 1;
        appendStatus(sprintf('Attempting parent-context document.cookie access for URL %d.', currentURLIndex))
        htmlView.Data = struct('source', 'uihtmlFramingProbe', ...
                       'action', 'attemptCookieRead', 'requestId', requestID);
    end

    function erikButtonCallback(~, ~)
        webWin = struct(struct(struct(uiFigure).Controller).PlatformHost).CEF;
        webWin.openDevTools();
    end

    function useSharedBridge(~, ~)
        appendStatus('Loading appEngine.util.jsBackDoorHTMLSource().')
        htmlView.Data = struct('source', 'uihtmlFramingProbe', ...
                               'action', 'loadURL', ...
                               'url', testURLs{currentURLIndex});
        htmlView.HTMLSource = appEngine.util.jsBackDoorHTMLSource();
    end

    function loadCurrentURL()
        currentURL = testURLs{currentURLIndex};
        lastFramingStatus = "unknown";  

        if isempty(currentURL)
            urlLabel.Text = sprintf('URL %d/%d: %s (not configured)', ...
                                    currentURLIndex, testCount, testNames{currentURLIndex});
            appendStatus(sprintf('URL %d/%d (%s) is empty.', ...
                                  currentURLIndex, testCount, testNames{currentURLIndex}))
        else
            urlLabel.Text = sprintf('URL %d/%d: %s', ...
                                    currentURLIndex, testCount, testNames{currentURLIndex});
            appendStatus(sprintf('Loaded URL %d/%d (%s): %s', ...
                                  currentURLIndex, testCount, testNames{currentURLIndex}, currentURL))
        end

        htmlView.HTMLSource = makeHTML(currentURL);
    end

    function onHtmlEvent(~, event)
        % All browser-to-MATLAB traffic uses one event name and a structured
        % payload, so this callback does not depend on event-property names
        % that vary between MATLAB releases.
        payload = event.Data;
        if ~isstruct(payload) || ~isfield(payload, 'type')
            appendStatus('Received an unexpected uihtml event payload.')
            return
        end

        eventType = string(payload.type);
        switch eventType
            case "ready"
                appendStatus('uihtml data-binding event bridge is ready.')

            case "bridge-ready"
                appendStatus('Shared matlabJSBridge.html is ready.')

            case "framing"
                lastFramingStatus = string(payload.status);
                appendFramingResult(payload)

            case "cookies"
                appendCookieResult(payload)

            otherwise
                appendStatus(sprintf('Received unknown uihtml event type: %s.', eventType))
        end
    end

    function appendFramingResult(payload)
        detail = char(string(payload.detail));
        switch string(payload.status)
            case "blocked"
                appendStatus(sprintf('Framing result: blocked. %s', detail))
                appendStatus('Summary: Framing blocked - X-Frame-Options/CSP in effect.')

            case "cross-origin"
                appendStatus(sprintf('Framing result: loaded but cross-origin. %s', detail))
                appendStatus('Summary: Framing succeeded, but parent JavaScript cannot inspect the cross-origin frame.')

            case "same-origin"
                appendStatus(sprintf('Framing result: loaded same-origin. %s', detail))
                appendStatus('Summary: Framing and cookie read both succeeded - re-evaluate assumptions.')

            otherwise
                appendStatus(sprintf('Framing result was inconclusive: %s', detail))
        end
    end

    function appendCookieResult(payload)
        detail = char(string(payload.detail));
        switch string(payload.status)
            case "blocked"
                appendStatus(sprintf('Cookie result: blocked. %s', detail))
                if lastFramingStatus == "cross-origin"
                    appendStatus('Summary: Framing succeeded, cookie read blocked by Same-Origin Policy.')
                else
                    appendStatus('Summary: Cookie read blocked; run Check framing to classify the frame.')
                end

            case "readable"
                appendStatus(sprintf('Cookie result: readable. %s', detail))
                if lastFramingStatus == "same-origin"
                    appendStatus('Summary: Framing and cookie read both succeeded - re-evaluate assumptions.')
                else
                    appendStatus('Summary: document.cookie was readable, but the frame may be blank or blocked; check framing.')
                end

            otherwise
                appendStatus(sprintf('Cookie result was inconclusive: %s', detail))
        end
    end

    function appendStatus(message)
        statusArea.Value = [string(statusArea.Value); string(message)];
        drawnow limitrate
    end
end

function html = makeHTML(frameURL)
% makeHTML Return the inline page hosted by uihtml.

if isempty(frameURL)
    frameURL = 'about:blank';
end

frameURL = escapeHTMLAttribute(frameURL);
html = sprintf([ ...
    '<!doctype html><html><head><meta charset="utf-8">', ...
    '<style>', ...
    'html,body{height:100%%;margin:0;overflow:hidden;background:#f4f4f4;}', ...
    'iframe{width:100%%;height:100%%;box-sizing:border-box;', ...
    'border:3px solid #d9534f;background:white;display:block;}', ...
    '</style></head><body>', ...
    '<iframe id="targetFrame" src="%s" title="Framed test target"></iframe>', ...
    '<script>', ...
    'var frameHasLoaded = false;', ...
    'function sendResult(type, status, detail, requestId) {', ...
    '  sendEventToMATLAB("uihtmlProbe", {type:type,status:status,detail:detail,requestId:requestId});', ...
    '}', ...
    'function setup(htmlComponent) {', ...
    '  var frame = document.getElementById("targetFrame");', ...
    '  frame.addEventListener("load", function() { frameHasLoaded = true; });', ...
    '  htmlComponent.addEventListener("DataChanged", function() {', ...
    '    var command = htmlComponent.Data;', ...
    '    if (!command || !command.action) return;', ...
    '    if (command.action === "checkFraming") {', ...
    '      inspectFraming(frame, command.requestId);', ...
    '    } else if (command.action === "attemptCookieRead") {', ...
    '      inspectCookies(frame, command.requestId);', ...
    '    }', ...
    '  });', ...
    '  sendEventToMATLAB("uihtmlProbe", {type:"ready"});', ...
    '}', ...
    'function inspectFraming(frame, requestId) {', ...
    '  try {', ...
    '    var frameDocument = frame.contentDocument;', ...
    '    if (frameDocument !== null) {', ...
    '      var frameDocumentURL = frameDocument.URL || "";', ...
    '      if (frameDocumentURL && frameDocumentURL !== "about:blank" && frameHasLoaded) {', ...
    '        sendResult("framing", "same-origin", "contentDocument was accessible.", requestId);', ...
    '      } else {', ...
    '        sendResult("framing", "blocked", "The frame is empty or remained at about:blank.", requestId);', ...
    '      }', ...
    '      return;', ...
    '    }', ...
    '    try {', ...
    '      var accessibleDocument = frame.contentWindow.document;', ...
    '      var accessibleURL = accessibleDocument.URL || "";', ...
    '      if (accessibleURL && accessibleURL !== "about:blank" && frameHasLoaded) {', ...
    '        sendResult("framing", "same-origin", "contentWindow.document was accessible.", requestId);', ...
    '      } else {', ...
    '        sendResult("framing", "blocked", "contentDocument was null and the accessible frame was blank.", requestId);', ...
    '      }', ...
    '    } catch (error) {', ...
    '      sendResult("framing", "cross-origin", "contentDocument was unavailable and contentWindow.document raised " + error.name + ".", requestId);', ...
    '    }', ...
    '  } catch (error) {', ...
    '    sendResult("framing", "cross-origin", "Reading contentDocument raised " + error.name + ".", requestId);', ...
    '  }', ...
    '}', ...
    'function inspectCookies(frame, requestId) {', ...
    '  try {', ...
    '    var cookieDocument = frame.contentWindow.document;', ...
    '    var ignoredCookieValue = cookieDocument.cookie;', ...
    '    void ignoredCookieValue;', ...
    '    sendResult("cookies", "readable", "document.cookie was readable; its value was intentionally discarded.", requestId);', ...
    '  } catch (error) {', ...
    '    sendResult("cookies", "blocked", "document.cookie raised " + error.name + " (expected for a cross-origin frame).", requestId);', ...
    '  }', ...
    '}', ...
    '</script></body></html>'], frameURL);
end

function escapedValue = escapeHTMLAttribute(value)
% escapeHTMLAttribute Keep the configured URL in a valid src attribute.

escapedValue = strrep(value, '&', '&amp;');
escapedValue = strrep(escapedValue, '"', '&quot;');
escapedValue = strrep(escapedValue, '<', '&lt;');
escapedValue = strrep(escapedValue, '>', '&gt;');
end