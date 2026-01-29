/*
    Função executada pelo MATLAB ao renderizar o componente uihtml, possibilitando
    estabelecer comunicação entre MATLAB e HTML/JS. 

    No webapp existem três níveis de window: window.top (host), window.parent (iframe 
    do app) e window (iframe uihtml). Por outro lado, na versão desktop, top e parent 
    referenciam o mesmo objeto.

    Em geral, todas as operações agem sobre elementos em window.parent. Exceções:
    (a) window.top: remover progressdialog inicial do webapp e obter a URL real do app;
    (b) window: identificar caminho estático do servidor (em relação ao uihtml), 
        possibilitando injeção de scripts da biblioteca "D3" para wordcloud.
*/
function setup(htmlComponent) {
    const hostWindow = window.top;
    const appWindow  = window.parent;

    if (!appWindow.app) {
        appWindow.app = {
            staticBaseURL: new URL(".", window.document.baseURI).href,
            executionMode: null,
            matlabJSBridge: htmlComponent,
            ui: [], 
            modules: {
                consoleLog, 
                uuid,
                createUIBlocker,
                findComponentHandle,
                injectBaseStyles,
                injectStyle,
                injectScript,                
                isMobile,
                camelToKebab
            },
            indexedDB: null,
            wordcloud: null
        };
    }

    if (!appWindow.document._blockUIInstalled) {
        appWindow.document._blockUIInstalled = true;
        createUIBlocker(appWindow, 'matlab-js-bridge-ui-blocker', 901);
    }

    injectBaseStyles();

    /*
        Corrige o comportamento de foco do uialert, evitando que o botão receba foco 
        ao interagir com elementos de texto usando o mouse.
    */
    if (!appWindow.document._customFocusInListenerInstalled) {
        appWindow.document._customFocusInListenerInstalled = true;

        let lastInteractionWasKeyboard = false;
        appWindow.document.addEventListener('keydown',     () => { lastInteractionWasKeyboard = true;  }, true);
        appWindow.document.addEventListener('mousedown',   () => { lastInteractionWasKeyboard = false; }, true);
        appWindow.document.addEventListener('pointerdown', () => { lastInteractionWasKeyboard = false; }, true);

        appWindow.document.addEventListener('focusin', (event) => {
            const target = event.target;
            if (!lastInteractionWasKeyboard && target.matches('.mwButton, .mwCloseNode') && target.closest('.mwDialog')?.classList.contains('focused')) {
                target.blur();
            }
        }, true);
    }

    /*-----------------------------------------------------------------------------------
        ## LISTENERS ##
        No webapp, ao tentar fechar a aba, o evento "beforeunload" desconecta o websocket, 
        tornando o app inoperante, independente da resposta à confirmação de fechamento do
        webapp apresentada no navegador. 
        
        Para evitar isso, remove-se esse listener do arquivo "bundle.469.js" e usa-se um 
        substituto que não interage com o websocket. Se o usuário confirmar o fechamento, 
        o evento "unload" é disparado e aciona a função MATLAB closeFcn(app, event), que 
        realiza algumas operações, inclusive fechando a instância do MATLAB Runtime que 
        suporte o webapp
    -----------------------------------------------------------------------------------*/  
    htmlComponent.addEventListener("startup", function(customEvent) {
        const executionMode = customEvent.Data;
        appWindow.app.executionMode = executionMode;

        if (!appWindow.document._customWebAppListenersInstalled) {
            appWindow.document._customWebAppListenersInstalled = true;

            if (executionMode === "webApp") {
                appWindow.addEventListener("beforeunload", (event) => {
                    event.preventDefault();
                    event.returnValue = '';
                });

                appWindow.addEventListener("unload", () => {
                    htmlComponent.sendEventToMATLAB("unload");
                });

                if ('serviceWorker' in navigator) {
                    navigator.serviceWorker.register('/webapps/home/service-worker.js', { scope: '/webapps/home/' })
                    .then(()  => { consoleLog('Service worker registered successfully'); })
                    .catch(ME => { consoleLog(`Service worker registration failed: ${ME.message}`)});
                }
            }
        }
    });

    /*---------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("initializeComponents", function (customEvent) {
        const components = customEvent.Data;
        const maxAttempts = 100;
        let modifyAttempts = 0;
        let dataTags = '';

        appWindow.app.ui.push(...components);

        const modifyInterval = setInterval(() => {
            modifyAttempts++;

            components.forEach((el, index) => {
                let handle = findComponentHandle(el.dataTag);
                if (el.generation === 1) {
                    handle = handle?.children?.[0];
                } else if (el.generation === 2) {
                    handle = handle?.children?.[0].children?.[0];
                } else if (el.selector) {
                    handle = handle?.querySelector(`${el.selector}`);
                }

                if (handle) {
                    let modifyStatus = true;

                    if (el.style) {
                        Object.assign(handle.style, el.style);
                        handle.offsetHeight;
                    }

                    if (el.styleImportant) {
                        Object.keys(el.styleImportant).forEach(elKey => {
                            handle.style.setProperty(camelToKebab(elKey), el.styleImportant[elKey], "important");
                            handle.offsetHeight;
                        })
                    }

                    if (el.class) {
                        let classList = el.class;
                        if (!Array.isArray(classList)) {
                            classList = [classList];
                        }

                        classList.forEach(classElement => {
                            injectBaseStyles();
                            handle.classList.add(classElement);

                            modifyStatus = !!handle.classList.contains(classElement);
                            if (!modifyStatus) {
                                consoleLog(`Error: the class "${classElement}" could not be applied to the element ${el.dataTag}`);
                            }
                        })
                        handle.offsetHeight;
                    }

                    if (el.listener) {
                        const htmlEventName = el.listener.componentName;
                        const keyEvents = el.listener.keyEvents;
    
                        if (!handle.dataset.keydownListener) {
                            handle.dataset.keydownListener = keyEvents.join('-');
                            
                            handle.addEventListener('keydown', (event) => {
                                if (keyEvents.includes(event.key)) {
                                    event.preventDefault();
                                    event.stopPropagation();

                                    const htmlEventData = (handle.tagName === 'INPUT') 
                                        ? { key: event.key, value: handle.value } 
                                        : event.key;

                                    htmlComponent.sendEventToMATLAB(htmlEventName, htmlEventData);
                                }
                            });
                        }
                    }

                    if (el.tooltip) {
                        const {textContent, defaultPosition} = el.tooltip;
                        createTooltip(handle, textContent, defaultPosition);
                    }

                    if (el.stackorder && handle.parentElement) {
                        const parent = handle.parentElement;

                        if (el.stackorder === "top") {
                            const last = parent.children[parent.children.length - 1];
                            if (handle !== last) {
                                parent.appendChild(handle);
                            }

                        } else if (el.stackorder === "bottom") {
                            const first = parent.children[0];
                            if (handle !== first) {
                                parent.insertBefore(handle, first);
                            }
                        }
                    }

                    if (el.child) {
                        let child = handle.querySelector(`div[data-tag="${el.child.dataTag}"]`);
                        
                        if (child) {
                            child.innerHTML   = el.child.innerHTML;
                        } else {
                            child = appWindow.document.createElement('div');
                            child.dataset.tag = el.child.dataTag;
                            child.innerHTML   = el.child.innerHTML;
                            handle.appendChild(child);
                        }
                    }

                    if (modifyStatus) {
                        components.splice(index, 1);
                    }
                }
            });

            if (modifyAttempts >= maxAttempts) {
                dataTags = components.map(component => component.dataTag).join(', ');
                consoleLog(`Error: failed to apply class to the following components after ${maxAttempts} attempts: ${dataTags}`);
            }
    
            if (!components.length || modifyAttempts >= maxAttempts) {
                clearInterval(modifyInterval);
            }
        }, 1000);
    });

    /*---------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("getCssPropertyValue", function(customEvent) {
        const auxAppTag     = customEvent.Data.auxAppTag;
        const componentName = customEvent.Data.componentName;
        const dataTag       = customEvent.Data.dataTag
        const childClass    = customEvent.Data.childClass;
        const propertyName  = customEvent.Data.propertyName;

        let handle = findComponentHandle(dataTag);
        if (!handle) return;
        
        if (childClass) {
            const child = handle.getElementsByClassName(childClass)[0];
            if (child) {
                handle = child;
            }
        }
        
        const propertyValue = appWindow.getComputedStyle(handle).getPropertyValue(propertyName);
        htmlComponent.sendEventToMATLAB("getCssPropertyValue", { auxAppTag, componentName, propertyName, propertyValue });
    });

    /*---------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("changeTableRowHeight", function(customEvent) {
        let styleElement = appWindow.document.getElementById('matlab-js-bridge-uitable');
        if (styleElement) {
            styleElement.remove();
        }

        const rowHeight = customEvent.Data;
        if (rowHeight == "default") {
            return
        }

        const cssText = `/*
  ## Customizações gerais (MATLAB Built-in uitable) ##
*/
.mw-table-row-header-cell {
    height: ${rowHeight}px !important;
    max-height: ${rowHeight}px !important;
}

.mw-table-row {
    height: ${rowHeight}px !important;
}

.mw-table-cell {
    height: 100% !important;
    white-space: pre-line !important;
}`;
        
        styleElement = appWindow.document.createElement("style");
        styleElement.type = "text/css";
        styleElement.id = "matlab-js-bridge-uitable";
        styleElement.innerHTML = `${cssText}`;

        appWindow.document.head.appendChild(styleElement);
    });

    /*---------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("addStyle", function(customEvent) {
        let handle  = findComponentHandle(customEvent.Data.dataTag);
        const style = customEvent.Data.style;

        if (customEvent.Data.selector) {
            handle = handle?.querySelector(`${customEvent.Data.selector}`);
        }
        
        Object.assign(handle.style, style);
    });

    /*---------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("delProgressDialog", function() {
        try {
            hostWindow.document.getElementsByClassName("mw-busyIndicator")[0].remove();
        } catch (ME) {
            // console.log(ME);
        }
    });

    /*---------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("getNavigatorBasicInformation", function() {
        const htmlEventName = "getNavigatorBasicInformation";
        const htmlEventData = {
            name: "BROWSER",
            url: hostWindow.location.href,
            platform: navigator.userAgentData?.platform || navigator.platform,
            mobile: navigator.userAgentData?.mobile ?? isMobile(),
            userAgent: navigator.userAgent,
            vendor: navigator.vendor,
            screen: (screen?.width && screen?.height) ? `${screen.width} x ${screen.height} pixels` : 'unknown'
        };

        htmlComponent.sendEventToMATLAB(htmlEventName, htmlEventData);
    });

    /*---------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("setFocus", function(customEvent) {
        const dataTag = customEvent.Data.dataTag;
        const handle  = findComponentHandle(dataTag).querySelector("input");

        try {
            handle.focus();
            handle.setSelectionRange(handle.value.length, handle.value.length);
        } catch (ME) {
            // console.log(ME);
        }
    });

    /*---------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("forceReflow", function(customEvent) {
        const dataTag = customEvent.Data.dataTag;
        const handle  = findComponentHandle(dataTag)
        handle?.offsetHeight;
    });

    /*---------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("setBackgroundTransparent", function(customEvent) {
        const objDataName = customEvent.Data.componentName.toString();
        const objDataTag  = customEvent.Data.componentDataTag.toString();
        const interval_ms = customEvent.Data.interval_ms || 25;
        const handle      = findComponentHandle(objDataTag);

        try {
            let opacityValue = 1.0;
            let intervalId = setInterval(() => {
                opacityValue -= 0.02;
                handle.style.opacity = opacityValue;

                if (opacityValue <= 0.02) {
                    clearInterval(intervalId);
                    htmlComponent.sendEventToMATLAB("backgroundBecameTransparent", objDataName);
                }
            }, interval_ms);
        } catch (ME) {
            // console.log(ME);
        }
    });

    /*-----------------------------------------------------------------------------------
        ## CUSTOM FORM ##
    -----------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("customForm", function(customEvent) {
        try {
            const { UUID, Context, Varargin } = customEvent.Data;
            const labelColumnWidth  = customEvent.Data.ColumnWidth || "70px";
            let Fields    = customEvent.Data.Fields;
            Fields        = Array.isArray(Fields) ? Fields : [Fields];
            const zIndex  = 1000;

            let nFields = Fields.length;
            let Height  = nFields <= 3 ? 165 : 95+20*nFields+5*(nFields-1);

            injectBaseStyles();

            // Background layer
            var u = window.parent.document.createElement("div");
            u.style.cssText = "visibility: visible; position: absolute; left: 0%; top: 0%; width: 100%; height: 100%; background: rgba(255,255,255,0.65); z-index: " + (zIndex + 3) + ";";

            // Progress dialog
            var w = window.parent.document.createElement("div");
            w.setAttribute("data-tag", UUID);
            w.innerHTML = `
                <div class="mwDialog mwAlertDialog mwModalDialog mw-theme-light mwModalDialogFg" data-tag="${UUID}_uiCustomForm" style="width: 260px; height: ${Height}px; visibility: visible; z-index: ${zIndex + 4}; color-scheme: light; position: fixed; top: 50%; left: 50%; transform: translate(-50%, -50%);">
                    <div class="mwDialogTitleBar mwDraggableDialog" data-tag="${UUID}_PanelTitle">
                        <span class="mwTitleNode"></span>
                        <div class="mwControlNodeBar">
                            <button class="mwCloseNode" data-tag="${UUID}_Close">
                                <svg viewBox="0 0 12 12" class="mwCloseSVG">
                                    <g>
                                        <rect width="12" height="12" fill="none"></rect>
                                        <path d="M9.09,1.5L6,4.59,2.91,1.5,1.5,2.91,4.59,6,1.5,9.08,2.91,10.5,6,7.41,9.09,10.5,10.5,9.08,7.41,6,10.5,2.91,9.09,1.5h0Z" fill="var(--mw-backgroundColor-iconFill, #616161)"></path>
                                    </g>
                                </svg>
                            </button>
                        </div>
                    </div>
                    <div id="mwDialogBody" style="padding: 10px; height: ${Height-75}px;">
                    </div>
                    <div class="mwDialogButtonBar mwNoSplBtn">
                        <div class="mwActionButtonBar">
                            <button class="mwButton" data-tag="${UUID}_OK">OK</button>
                        </div>
                    </div>    
                </div>
            `;

            u.appendChild(w);
            appWindow.document.body.appendChild(u);

            // Form generation
            let formContainer = window.parent.document.createElement("form");
            formContainer.style.cssText = `display: grid; grid-template-columns: ${labelColumnWidth} auto; gap: 5px; font-size: 12px; align-items: center;`;
    
            Fields.forEach(function(field) {
                // Label
                let label = appWindow.document.createElement("label");
                label.textContent = field.label;
                formContainer.appendChild(label);
    
                // Input field
                let input = appWindow.document.createElement("input");
                input.type = field.type;
                input.value = field.defaultValue || "";
                input.className = "custom-form-entry";
                input.style.cssText = "height: 18px;";
                input.setAttribute("data-tag", UUID + "_" + field.id);
                
                input.addEventListener("keydown", event => {
                    if (event.key === "Enter") {
                        event.preventDefault();
                    }
                });

                formContainer.appendChild(input);
            });
    
            // Append form to the dialog body
            let dialogBody = appWindow.document.getElementById("mwDialogBody");
            dialogBody.appendChild(formContainer);

            // Handles
            let dialogBox  = appWindow.document.querySelector(`div[data-tag="${UUID}_uiCustomForm"]`);            
            let panelTitle = appWindow.document.querySelector(`div[data-tag="${UUID}_PanelTitle"]`);            
            let btnClose   = appWindow.document.querySelector(`button[data-tag="${UUID}_Close"]`);
            let btnOK      = appWindow.document.querySelector(`button[data-tag="${UUID}_OK"]`);

            // Callbacks
            let mousePosX, mousePosY;
            let objNormLeft, objNormTop;
            panelTitle.addEventListener("mousedown", function(event) {
                event.preventDefault();

                mousePosX    = event.clientX;
                mousePosY    = event.clientY;

                objNormLeft  = dialogBox.offsetLeft;
                objNormTop   = dialogBox.offsetTop;
                
                dialogBox.style.cursor = "move";
                appWindow.document.addEventListener("mousemove", mouseMoveCallback);
                appWindow.document.addEventListener("mouseup", mouseUpCallback);
            });

            function mouseMoveCallback(event) {
                mouseDiffX   = event.clientX - mousePosX;
                mouseDiffY   = event.clientY - mousePosY;

                objNormLeft += mouseDiffX;
                objNormTop  += mouseDiffY;

                let minLeft  = dialogBox.offsetWidth/2;
                let maxLeft  = appWindow.innerWidth  - dialogBox.offsetWidth/2;
                let minTop   = dialogBox.offsetHeight/2;
                let maxTop   = appWindow.innerHeight - dialogBox.offsetHeight/2;

                if (objNormLeft < minLeft) objNormLeft = minLeft;
                if (objNormLeft > maxLeft) objNormLeft = maxLeft;

                if (objNormTop  < minTop)  objNormTop  = minTop;
                if (objNormTop  > maxTop)  objNormTop  = maxTop;
                
                dialogBox.style.left = 100 * objNormLeft/appWindow.innerWidth + "%";
                dialogBox.style.top  = 100 * objNormTop/appWindow.innerHeight + "%";

                mousePosX    = event.clientX;
                mousePosY    = event.clientY;
            }

            function mouseUpCallback(event) {
                dialogBox.style.cursor = "default";                
                appWindow.document.removeEventListener("mousemove", mouseMoveCallback);
                appWindow.document.removeEventListener("mouseup", mouseUpCallback);
            }

            btnClose.addEventListener("click", function() {
                u.remove();
            });

            btnOK.addEventListener("click", function() {
                let formData = {};
                Fields.forEach(function(field) {
                    let inputField = appWindow.document.querySelector(`input[data-tag="${UUID}_${field.id}"]`);
                    formData[field.id] = inputField.value.trim();
                });
    
                // Validation
                let firstEmptyField = Object.keys(formData).find(key => formData[key] === "");
                if (firstEmptyField) {
                    let emptyField = appWindow.document.querySelector(`input[data-tag="${UUID}_${firstEmptyField}"]`);
                    emptyField.focus();
                    return;
                }

                formData.uuid = UUID;
                if (Context) formData.context = Context;
                if (Varargin) formData.varargin = Varargin;
                htmlComponent.sendEventToMATLAB("customForm", formData);

                u.remove();
            });

            const focusElements = Array.from(w.querySelectorAll('button, input, select, [contenteditable]')).filter(el => !el.disabled && el.tabIndex !== -1);

            w.addEventListener("keydown", function(event) {                
                    if (focusElements.length === 0) return;
                
                    if (event.key === 'Tab') {
                        const activeElement = appWindow.document.activeElement;
                        let currentIndex = focusElements.indexOf(activeElement);
                        currentIndex = (currentIndex === -1) ? 0 : currentIndex;
            
                        event.preventDefault();
            
                        let nextIndex;
                        if (event.shiftKey) {
                            nextIndex = (currentIndex - 1 + focusElements.length) % focusElements.length;
                        } else {
                            nextIndex = (currentIndex + 1) % focusElements.length;
                        }
            
                        focusElements[nextIndex].focus();
                    }
            });

            const firstInput = appWindow.document.querySelector(`input[data-tag="${UUID}_${Fields[0].id}"]`);
            firstInput.focus();

        } catch (ME) {
            // console.log(ME);
        }
    });

    /*-----------------------------------------------------------------------------------
        ## TAB NAVIGATOR ##
    -----------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("tabNavigator", function(customEvent) {
        const tabConfig = customEvent.Data;

        switch (tabConfig.operation) {
            case "convertToInlineSVG": {
                tabConfig.buttons.forEach(button => {
                    const icon = findComponentHandle(button.dataTag)?.querySelector(".mwIconNode");
                    if (!icon) return;
                    icon.innerHTML = button.svgContent;
                    icon.classList.add("tab-navigator-icon");
                    icon.querySelector("svg").setAttribute('fill', button.value ? "#f0f022" : "#ffffff");
                    icon.style.backgroundImage = "none";
                });            
                break;
            }

            case "setIconColor": {
                tabConfig.buttons.forEach(button => {
                    const svg = findComponentHandle(button.dataTag)?.querySelector(".mwIconNode svg");
                    if (!svg) return;
                    svg.setAttribute('fill', button.value ? "#f0f022" : "#ffffff");
                });
                break;
            }
        }
    });

    /*-----------------------------------------------------------------------------------
        ## PROGRESS DIALOG ##
    -----------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("progressDialog", function(customEvent) {
        const { Type, UUID } = customEvent.Data;

        const handle = appWindow.document.body.querySelectorAll(`div[data-tag="${UUID}"]`);
        if ((Type == "Creation") || (handle.length === 0)) {
            const zBaseIndex = 900;

            if ("Size" in customEvent.Data) {
                Size = customEvent.Data.Size.toString();
            } else if (appWindow.sessionStorage.getItem("ProgressDialog") !== null) {
                Size = JSON.parse(appWindow.sessionStorage.getItem("ProgressDialog")).Size;
            } else {
                Size = "40px";
            }

            if ("Color" in customEvent.Data) {
                Color = customEvent.Data.Color.toString();
            } else if (appWindow.sessionStorage.getItem("ProgressDialog") !== null) {
                Color = JSON.parse(appWindow.sessionStorage.getItem("ProgressDialog")).Color;
            } else {
                Color = "#d95319";
            }

            if (appWindow.sessionStorage.getItem("ProgressDialog") === null) {
                appWindow.sessionStorage.setItem("ProgressDialog", JSON.stringify({ Type, UUID, Size, Color }))
            }

            try {
                injectBaseStyles();
        
                // Background layer
                let u = appWindow.document.getElementById('matlab-js-bridge-ui-blocker');
                if (!u) {
                    u = createUIBlocker(appWindow, 'matlab-js-bridge-ui-blocker', zBaseIndex+1);
                };
                u.setAttribute("data-tag", UUID);
        
                // Progress dialog
                const w = appWindow.document.createElement("div");
                w.setAttribute("data-tag", UUID);
                w.style.cssText = `visibility: visible; position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); z-index: ${zBaseIndex+2};`;
                w.innerHTML     = `
                    <div class="progress-dialog-chase">
                        <div class="progress-dialog-chase-dot"></div>
                        <div class="progress-dialog-chase-dot"></div>
                        <div class="progress-dialog-chase-dot"></div>
                        <div class="progress-dialog-chase-dot"></div>
                        <div class="progress-dialog-chase-dot"></div>
                        <div class="progress-dialog-chase-dot"></div>
                    </div>
                `;
                
                u.appendChild(w);
            } catch (ME) {
                // console.log(ME);
            }
        }
        
        switch (Type) {
            case "changeVisibility":
                const newVisibility = customEvent.Data.Visibility;
                handle.forEach(element => {
                    element.style.visibility = newVisibility;
                });
                break;

            case "changeColor":
                const newColor = customEvent.Data.Color;
                appWindow.document.documentElement.style.setProperty("--progress-dialog-color", newColor);
                break;

            case "changeSize":
                const newSize = customEvent.Data.Size;
                appWindow.document.documentElement.style.setProperty("--progress-dialog-size", newSize);
                break;
        };
    });

    /*-----------------------------------------------------------------------------------
        ## INDEXED DB ##
        No webapp e na execução direta no MATLAB, o indexedDB é persistente. Na versão desktop
        compilada, ele existe apenas durante a sessão, pois o sandbox do MATLAB (configuração
        do CEF) limpa o cache entre execuções do aplicativo.
    -----------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("indexedDB", async function(customEvent) {
        const dbConfig = customEvent.Data;

        switch (dbConfig.operation) {
            case "openDB": {
                try {
                    appWindow.app.indexedDB = await openDB(dbConfig.name, dbConfig.version, dbConfig.store);
                    htmlComponent.sendEventToMATLAB("indexedDB", { operation: "openDB", status: "success" });
                } catch (ME) {
                    // htmlComponent.sendEventToMATLAB("indexedDB", { operation: "openDB", status: "failure", message: ME.message });
                }
                break;
            }
            case "saveData": {
                const { key, data }  = dbConfig;
                try {
                    await saveDataInDB(dbConfig.store, key, data);
                    // htmlComponent.sendEventToMATLAB("indexedDB", { operation: "saveData", status: "success" });
                } catch (ME) {
                    // htmlComponent.sendEventToMATLAB("indexedDB", { operation: "saveData", status: "failure", message: ME.message });
                }
                break;
            }
            case "loadData": {
                const key = dbConfig.key;
                try {
                    const data = await loadDataFromDB(dbConfig.store, key);
                    htmlComponent.sendEventToMATLAB("indexedDB", { operation: "loadData", status: "success", data });
                } catch (ME) {
                    // htmlComponent.sendEventToMATLAB("indexedDB", { operation: "loadData", status: "failure", message: ME.message });
                }
                break;
            }
            case "deleteData": {
                const key = dbConfig.key;
                try {
                    await deleteDataFromDB(dbConfig.store, key);
                    // htmlComponent.sendEventToMATLAB("indexedDB", { operation: "deleteData", status: "success" });
                } catch (ME) {
                    // htmlComponent.sendEventToMATLAB("indexedDB", { operation: "deleteData", status: "failure", message: ME.message });
                }
                break;
            }
            default:
                consoleLog(`IndexedDB: unknown operation "${dbConfig.operation}"`);
        }
    });

    /*---------------------------------------------------------------------------------*/
    function openDB(DB_NAME, DB_VERSION, DB_STORE) {
        return new Promise((resolve, reject) => {
            const request = indexedDB.open(DB_NAME, DB_VERSION);

            request.onupgradeneeded = (event) => {
                const db = event.target.result;
                if (!db.objectStoreNames.contains(DB_STORE)) {
                    db.createObjectStore(DB_STORE, { keyPath: "key" } );
                }
            };

            request.onsuccess = (event) => resolve(event.target.result);
            request.onerror   = (event) => reject(event.target.error);
        });
    }

    /*---------------------------------------------------------------------------------*/
    function saveDataInDB(DB_STORE, key, data) {
        const db = appWindow.app.indexedDB;
        if (!db) {
            throw new Error("IndexedDB is not opened yet.");
        }

        return new Promise((resolve, reject) => {
            const tx = db.transaction(DB_STORE, "readwrite");
            const store = tx.objectStore(DB_STORE);
            store.put({
                key,
                data, 
                timestamp: Date.now()
            });

            tx.oncomplete = () => resolve(true);
            tx.onerror    = () => reject(tx.error);
        });
    }

    /*---------------------------------------------------------------------------------*/
    function loadDataFromDB(DB_STORE, key) {
        if (!appWindow.app.indexedDB) {
            throw new Error("IndexedDB is not opened yet.");
        }

        return new Promise((resolve, reject) => {
            const tx = appWindow.app.indexedDB.transaction(DB_STORE, "readonly");
            const store = tx.objectStore(DB_STORE);
            const request = store.get(key);

            request.onsuccess = () => {
                const result  = request.result;
                resolve(result ? result.data : null);
            };
            request.onerror   = () => reject(request.error);
        });
    }

    /*---------------------------------------------------------------------------------*/
    function deleteDataFromDB(DB_STORE, key) {
        if (!appWindow.app.indexedDB) {
            throw new Error("IndexedDB is not opened yet.");
        }

        return new Promise((resolve, reject) => {
            const tx = appWindow.app.indexedDB.transaction(DB_STORE, "readwrite");
            const store = tx.objectStore(DB_STORE);
            const request = store.delete(key);

            request.onsuccess = () => resolve(true);
            request.onerror   = () => reject(request.error);
        });
    }

    /*-----------------------------------------------------------------------------------
        ## WORDCLOUD ##
        O wordcloud é renderizada na própria window do uihtml.
    -----------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("wordcloud", () => {
        injectScript(window.document, "matlab-js-bridge-wordcloud", ["js/d3.v7.min.js", "js/d3.layout.cloud.min.js"]);

        let canvas = window.document.getElementById('wordcloudCanvas');
        if (!canvas) {
            canvas = window.document.createElement('canvas');
            canvas.id = 'wordcloudCanvas';
            canvas.style.display = "none";
            canvas.getContext('2d', { willReadFrequently: true });

            window.document.body.appendChild(canvas);
        }

        let container = window.document.getElementById('wordcloud');
        if (!container) {
            container = window.document.createElement("div");
            container.id = "wordcloud";
            Object.assign(container.style, {
                height: "100vh",
                width: "100vw"
            });
            window.document.body.appendChild(container);
        }

        let containerStyle = window.document.getElementById("wordcloud-style");
        if (!containerStyle) {
            containerStyle = window.document.createElement("style");
            containerStyle.id = "wordcloud-style";
            containerStyle.innerHTML = `
                #wordcloud text::selection {
                    background: #0078d4 !important;
                    fill: white !important;
                }
            `;
            window.document.head.appendChild(containerStyle);
        }

        if (!appWindow.app.wordcloud) {
            appWindow.app.wordcloud = { 
                canvas, 
                container,                
                drawCloud, 
                eraseCloud, 
                data: [] 
            };
        }

        htmlComponent.addEventListener("drawWordCloud", (event) => {
            const { words, weights } = event.Data;        
            const currentWords = words.map((word, index) => {
                return {
                    text: word,
                    size: weights[index]
                };
            });

            drawCloud(currentWords);
            appWindow.app.wordcloud.data = currentWords;
        });

        htmlComponent.addEventListener("eraseWordCloud", () => {
            eraseCloud();
            appWindow.app.wordcloud.data = [];        
        });

        function drawCloud(words) {
            eraseCloud();

            const { innerWidth: width, innerHeight: height } = window;        
            const scale = getFontScale(words, width, height);
            const layout = d3.layout.cloud()
                .size([width, height])
                .words(words.map(d => ({text: d.text, size: scale(d.size)})))
                .padding(2)
                .rotate(0)
                .font("Helvetica")
                .fontSize(d => d.size)
                .canvas(() => canvas)
                .on("end", draw);

            layout.start();

            function draw(words) {
                const svg = d3.select("#wordcloud").append("svg")
                    .attr("width", width)
                    .attr("height", height)
                    .attr("viewBox", `0 0 ${width} ${height}`)
                    .attr("preserveAspectRatio", "xMidYMid meet")
                    .append("g")
                    .attr("transform", "translate(" + width / 2 + "," + height / 2 + ")");

                const topWords = words.slice(0, 3).map(d => d.text);

                svg.selectAll("text")
                    .data(words, d => d.text)
                    .join(
                        enter => enter.append("text")
                            .attr("text-anchor", "middle")
                            .style("font-family", "Helvetica")
                            .style("fill", d => topWords.includes(d.text) ? "#d95319" : "black")
                            .text(d => d.text),
                        update => update,
                        exit => exit.remove()
                    )
                    .style("font-size", d => d.size + "px")
                    .attr("transform", d => `translate(${d.x},${d.y})rotate(0)`);
            }

            function getFontScale(words, width, height) {
                const maxSize = d3.max(words, d => d.size);
                const minSize = d3.min(words, d => d.size);

                return d3.scalePow().exponent(0.5).domain([minSize, maxSize]).range([10, Math.min(width, height) / 3]);
            }
        }

        function eraseCloud() {
            d3.select("#wordcloud").selectAll("*").remove();
        }
    });

    /*-----------------------------------------------------------------------------------
        ## TOOLTIP ##
    -----------------------------------------------------------------------------------*/
    function createTooltip(target, textContent, defaultPosition = "top") {
        let tooltip;
        const tooltipColor = getComputedStyle(appWindow.document.documentElement).getPropertyValue('--tooltip-backgroundColor').trim();

        if (target.dataset.tooltipText != textContent ) {
            target.dataset.tooltipText  = textContent;
            target.dataset.tooltipState = 'hidden';
        }

        target.addEventListener('mouseenter', () => tooltip = tooltipShow(tooltip, target, defaultPosition));
        target.addEventListener('mouseleave', () => tooltipHide(tooltip, target));

        /*-----------------------------------------------------------------------------*/
        function tooltipShow(tooltip, target, defaultPosition) {
            if (!tooltip || target.dataset.tooltipState === 'hidden') {
                tooltip = tooltipRender(target, defaultPosition);
                target.dataset.tooltipState = 'hover';
            }

            return tooltip;
        }

        /*-----------------------------------------------------------------------------*/
        function tooltipHide(tooltip, target) {
            if (tooltip && target.dataset.tooltipState === 'hover') {
                tooltip.remove();
                tooltip = null;

                target.dataset.tooltipState = 'hidden';
            }
        }

        /*-----------------------------------------------------------------------------*/
        function tooltipRender(target, defaultPosition) {
            let tooltip, tooltipArrow;
    
            tooltip = appWindow.document.createElement('div');
            tooltip.className = 'tooltip-container';
            tooltip.innerHTML = target.dataset.tooltipText;;
    
            tooltipArrow = appWindow.document.createElement('div');
            tooltipArrow.className = 'tooltip-arrow';
    
            tooltip.appendChild(tooltipArrow);
            appWindow.document.body.appendChild(tooltip);
    
            const rect = target.getBoundingClientRect();
            const scrollX  = appWindow.scrollX;
            const scrollY  = appWindow.scrollY;
            const centerX  = rect.left + scrollX + rect.width / 2;
            const maxRight = scrollX + appWindow.innerWidth - 4;
    
            const tooltipWidth  = tooltip.offsetWidth;
            const tooltipHeight = tooltip.offsetHeight;    
            
            let left = centerX - tooltipWidth / 2;
            if (left < 4) { left = 4; }
            if (left + tooltipWidth > maxRight) { left = maxRight - tooltipWidth; }
    
            let top, showAbove;
            
            if (defaultPosition === 'bottom') {
                top = rect.bottom + scrollY + 8;
                showAbove = false;

                if (top + tooltipHeight > scrollY + appWindow.innerHeight - 4) {
                    top = rect.top + scrollY - tooltipHeight - 8;
                    showAbove = true;
                }
            } else {
                top = rect.top + scrollY - tooltipHeight - 8
                showAbove = true;

                if (top < scrollY + 4) {
                    top = rect.bottom + scrollY + 8;
                    showAbove = false;
                }
            }
    
            Object.assign(tooltip.style, {
                left: `${left}px`,
                top: `${top}px`
            });
    
            Object.assign(tooltipArrow.style, {
                left: `${centerX-left-6}px`,
                top: showAbove ? 'unset' : '-6px',
                bottom: showAbove ? '-6px' : 'unset',
                borderTop: showAbove ? `6px solid ${tooltipColor}` : 'none',
                borderBottom: showAbove ? 'none' : `6px solid ${tooltipColor}`
            });
    
            return tooltip;
        }
    }

    /*-----------------------------------------------------------------------------------
        ## FUNÇÕES ##
    -----------------------------------------------------------------------------------*/
    function consoleLog(msg) {
        const now      = new Date();
        const hours    = String(now.getHours()).padStart(2, '0');
        const minutes  = String(now.getMinutes()).padStart(2, '0');
        const seconds  = String(now.getSeconds()).padStart(2, '0');
        const millisec = String(now.getMilliseconds()).padStart(3, '0');

        console.log(`${hours}:${minutes}:${seconds}.${millisec} [matlab-js-bridge] ${msg}`);
    }

    /*---------------------------------------------------------------------------------*/
    function uuid() {
        return (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') 
            ? crypto.randomUUID()
            : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
                const r = Math.random() * 16 | 0;
                const v = c === 'x' ? r : (r & 0x3 | 0x8);
                return v.toString(16);
            });
    }

    /*---------------------------------------------------------------------------------*/
    function createUIBlocker(parentWindow, id, zIndex = 900, delay = 50) {
        const uiBlocker = parentWindow.document.createElement("div");
        Object.assign(uiBlocker.style, {
            visibility: 'visible',
            position: 'fixed',
            inset: '0',
            background: 'rgba(255, 255, 255, 0.65)',
            opacity: '0',
            pointerEvents: 'auto',
            zIndex: `${zIndex}`,
            transition: 'opacity 2s ease'
        });

        uiBlocker.id = id;
        uiBlocker.tabIndex = -1;
        uiBlocker.addEventListener('keydown', evt => evt.stopPropagation(), true);

        parentWindow.document.body.appendChild(uiBlocker);
        uiBlocker.focus();
        parentWindow.document.offsetWidth;

        setTimeout(() => {
            uiBlocker.style.opacity = '1';
        }, delay);

        return uiBlocker;
    }
    
    /*---------------------------------------------------------------------------------*/
    function findComponentHandle(dataTag) {
        return appWindow.document.querySelector(`div[data-tag="${dataTag}"]`);
    }

    /*---------------------------------------------------------------------------------*/
    function injectBaseStyles() {
        let styleElement = appWindow.document.getElementById('matlab-js-bridge');
        if (styleElement) {
            return;
        }

        const cssText = `/*
  ## Customizações gerais (MATLAB Built-in Components) ##
*/
:root {
    --tabButton-border-color: rgb(255, 255, 255) !important;
    --tabContainer-border-color: rgb(230, 230, 230) !important;
    --tabGroup-tab-selected-background: rgb(191, 191, 191);
    --tabGroup-tab-unselected-background: rgb(230, 230, 230);
    --tabGroup-tab-hover-background: rgba(191, 191, 191, 0.5);
    --tabGroup-tab-selected-border: rgb(51, 51, 51);
    --tabGroup-tab-hover-border: rgba(51, 51, 51, 0.5);
    --tooltip-backgroundColor: rgb(51, 51, 51);
    --tooltip-borderColor: rgba(255, 255, 255, 0.25);
    --tooltip-fontColor: rgb(255, 255, 255);
}

.mw-theme-light {
    --mw-backgroundColor-dataWidget-selected: rgba(180, 222, 255, 0.45) !important;
    --mw-backgroundColor-selected: rgba(180, 222, 255, 0.45) !important;
    --mw-backgroundColor-selectedFocus: rgba(180, 222, 255, 0.45) !important;
    --mw-backgroundColor-list-hover: rgb(191, 191, 191) !important;
    --mw-backgroundColor-tab: rgb(255, 255, 255) !important;
}

.mwDialog {
    --mw-fontSize-dialog: 12px !important;
    word-break: break-word !important;
}

.mw-table-component {
    --mw-fontSize-table-cell: 10px !important;
}

a, a:hover {
    text-decoration: none;
}

.mw-table-row-header-cell {
    color: var(--mw-color-secondary,#616161) !important;
    font-weight: var(--mw-fontWeight-table-header-index) !important;
    text-align: center !important;
}

.treenode.selected {
    background-image: rgba(180, 222, 255, 0.45) !important;
}

.mw-tree .mw-tree-scroll-component.focused.hoverable .treeNode.selected.mw-tree-node-hover {
    background-image: rgb(191, 191, 191) !important;
}

.mw-default-header-cell {
    font-size: 10px !important; 
    white-space: pre-wrap !important; 
    margin-bottom: 5px !important;
}

.gbtWidget.gbtGrid {
    border-radius: 5px !important;
}

.tabBar {
    height: 24px !important;
    background: transparent !important;
    border-left: none !important;
}

.topTabContentWrapper {
    top: 24px !important;
}

.mwTabContainer {
    border: 1px solid var(--tabGroup-tab-unselected-background) !important;
    border-radius: 5px !important;
}

.mwTabLabel {
    position: relative !important;
    font-size: 10px !important;
    text-decoration: none !important;
    cursor: pointer !important;
    padding-left: 0 !important;
}

.tab {
    background: var(--tabGroup-tab-unselected-background) !important;
    border-bottom: 2px solid transparent !important;
    border-top-left-radius: 5px !important;
    border-top-right-radius: 5px !important;
    cursor: pointer !important;
    text-align: center !important;
}

.tab:hover {
    background: var(--tabGroup-tab-hover-background) !important;
    border-bottom-color: var(--tabGroup-tab-hover-border) !important;
}

.tab:not(.checkedTab):hover {
    background: var(--tabGroup-tab-hover-background) !important;
}

.checkedTab {
    background: var(--tabGroup-tab-selected-background) !important;
    border-bottom-color: var(--tabGroup-tab-selected-border) !important;
}

.gbtTabGroup,
.gbtWidget.gbtPanel,
.mwRadioButton,
.mwDatePicker {
    background-color: transparent !important;
}

/*
  ## Tooltip ##
*/
.tooltip-container {
    position: absolute;
    background: var(--tooltip-backgroundColor);
    opacity: 0.95;
    border: 1px solid var(--tooltip-borderColor);
    box-shadow: none;
    color: var(--tooltip-fontColor);
    padding: 6px 10px;
    border-radius: 3px;
    font-size: 12px;
    white-space: nowrap;
    pointer-events: none;
    z-index: 800;
}

.tooltip-arrow {
    position: absolute;
    width: 0;
    height: 0;
    border-left: 6px solid transparent;
    border-right: 6px solid transparent;
}

/*
  ## ui.TextView ##
*/
.textview {
    border: 1px solid rgb(125, 125, 125);
    overflow: hidden auto;
    word-break: break-all;
    user-select: text;
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
    font-size: 11px;
    color: rgb(0, 0, 0);
    text-align: center;
    width: 100% !important;
    height: 100% !important;
}

.mwDialog *::selection,
.textview::selection,
.textview *::selection { background: #0078d4; color: white; }

.textview-from-uiimage { display: flex; flex-direction: column; gap: 10px;}

/*
  ## Tab Navigator ##
*/
.tab-navigator-button { cursor: pointer !important; }
.tab-navigator-button:hover { border-color: #7d7d7d !important; }
.tab-navigator-icon:hover svg { transform: scale(1.08); }

/*
  ## ProgressDialog ##
*/
:root {
    --progress-dialog-size: 40px;
    --progress-dialog-color: rgb(217, 83, 25);
}

.progress-dialog-chase { width: var(--progress-dialog-size); height: var(--progress-dialog-size); position: relative; animation: progress-dialog-chase 2.5s infinite linear both; }
.progress-dialog-chase-dot { width: 100%; height: 100%; position: absolute; left: 0; top: 0;  animation: progress-dialog-chase-dot 2.0s infinite ease-in-out both; }
.progress-dialog-chase-dot:before { content: ""; display: block; width: 25%; height: 25%; background-color: var(--progress-dialog-color); border-radius: 100%; animation: progress-dialog-chase-dot-before 2.0s infinite ease-in-out both; }

.progress-dialog-chase-dot:nth-child(1),
.progress-dialog-chase-dot:nth-child(1):before { animation-delay: -1.1s; }
.progress-dialog-chase-dot:nth-child(2),
.progress-dialog-chase-dot:nth-child(2):before { animation-delay: -1.0s; }
.progress-dialog-chase-dot:nth-child(3),
.progress-dialog-chase-dot:nth-child(3):before { animation-delay: -0.9s; }
.progress-dialog-chase-dot:nth-child(4),
.progress-dialog-chase-dot:nth-child(4):before { animation-delay: -0.8s; }
.progress-dialog-chase-dot:nth-child(5),
.progress-dialog-chase-dot:nth-child(5):before { animation-delay: -0.7s; }
.progress-dialog-chase-dot:nth-child(6),
.progress-dialog-chase-dot:nth-child(6):before { animation-delay: -0.6s; }

@keyframes progress-dialog-chase { 100% { transform: rotate(360deg); } }
@keyframes progress-dialog-chase-dot { 80%, 100% { transform: rotate(360deg); } }
@keyframes progress-dialog-chase-dot-before { 50% { transform: scale(0.4); } 100%, 0% { transform: scale(1); } }

/*
  ## CustomForm ##
*/
.custom-form-entry { overflow: hidden; padding-left: 4px; font-size: 11px; border: 1px solid #7d7d7d;}
.custom-form-entry:focus { border-color: #268cdd; outline: none; }`;
        
        styleElement = appWindow.document.createElement("style");
        styleElement.type = "text/css";
        styleElement.id = "matlab-js-bridge";
        styleElement.innerHTML = `${cssText}`;

        appWindow.document.head.appendChild(styleElement);
    }

    /*---------------------------------------------------------------------------------*/
    function injectStyle(parentDocument, className, fileList) {
        const styleElement = parentDocument.getElementsByClassName(className);
        if (styleElement.length > 0) {
            return;
        }

        fileList.forEach((file) => {
            const linkElement = parentDocument.createElement("link");
            linkElement.className = className;
            linkElement.rel  = "stylesheet";
            linkElement.type = "text/css";
            linkElement.href = new URL(file, appWindow.app.staticBaseURL).href;

            parentDocument.head.appendChild(linkElement);
        });
    }

    /*---------------------------------------------------------------------------------*/
    function injectScript(parentDocument, className, fileList) {
        const scriptElement = parentDocument.getElementsByClassName(className);
        if (scriptElement.length > 0) {
            return;
        }

        fileList.forEach((file) => {
            const scriptElement = parentDocument.createElement("script");
            scriptElement.className = className;
            scriptElement.type = "text/javascript";
            scriptElement.src  = new URL(file, appWindow.app.staticBaseURL).href;

            parentDocument.head.appendChild(scriptElement);
        });
    }

    /*---------------------------------------------------------------------------------*/
    function isMobile() {
        let userAgent = navigator.userAgent || "";
        return /Mobi|Android|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(userAgent);
    }

    /*---------------------------------------------------------------------------------*/
    function camelToKebab(prop) {
        return prop.replace(/[A-Z]/g, m => "-" + m.toLowerCase());
    }

    /*---------------------------------------------------------------------------------*/
    window.requestAnimationFrame(() => {
        appWindow.requestAnimationFrame(() => {
            const msg = 'DOM render cycle finished';
            consoleLog(msg);

            htmlComponent.sendEventToMATLAB('renderer');
        });
    });
}