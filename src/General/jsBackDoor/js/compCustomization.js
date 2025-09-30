function setup(htmlComponent) {
    if (window.top.app?.rendererStatus) {
        return;
    }

    if (!window.top.app) {
        window.top.app = {};
    }

    window.top.app.executionMode  = null;
    window.top.app.rendererStatus = false;
    window.top.app.matlabBackDoor = htmlComponent;
    window.top.app.ui             = [];    
    window.top.app.modules        = {};

    /*-----------------------------------------------------------------------------------
    FUNÇÕES
    -----------------------------------------------------------------------------------*/
    function consoleLog(msg) {
        const now      = new Date();
        const hours    = String(now.getHours()).padStart(2, '0');
        const minutes  = String(now.getMinutes()).padStart(2, '0');
        const seconds  = String(now.getSeconds()).padStart(2, '0');
        const millisec = String(now.getMilliseconds()).padStart(3, '0');

        console.log(`${hours}:${minutes}:${seconds}.${millisec} [MATLAB-ccTools] ${msg}`);
    }
    
    /*---------------------------------------------------------------------------------*/
    function findComponentHandle(dataTag) {
        return window.parent.document.querySelector(`div[data-tag="${dataTag}"]`);
    }    

    /*---------------------------------------------------------------------------------*/
    function injectCustomStyle() {
        let styleElement = window.parent.document.getElementById('MATLAB-ccTools');
        if (styleElement) {
            return;
        }

        const cssText = `/*
  ## Customizações gerais (MATLAB Built-in Components) ##
*/
body {
    --tabButton-border-color: rgb(255, 255, 255) !important;
    --tabContainer-border-color: rgb(230, 230, 230) !important;
    --ccTools-tabGroup-tab-selected-background: rgb(191, 191, 191);
    --ccTools-tabGroup-tab-unselected-background: rgb(230, 230, 230);
    --ccTools-tabGroup-tab-hover-background: rgba(191, 191, 191, 0.5);    
    --ccTools-tabGroup-tab-selected-border: rgb(51, 51, 51);
    --ccTools-tabGroup-tab-hover-border: rgba(51, 51, 51, 0.5);
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
}

/*
.vc-widget {
    width: 100% !important;
    height: 100% !important;
}

.mwWidget {
    width: 100% !important;
    height: 100% !important;
}
*/

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

.gbtTabGroup {
    background-color: transparent !important;
}

.tabBar {
    background: transparent !important;
    border-left: none !important;
}

.mwTabContainer {
    border: 1px solid var(--ccTools-tabGroup-tab-unselected-background) !important;
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
    background: var(--ccTools-tabGroup-tab-unselected-background) !important;
    border-bottom: 2px solid transparent !important;
    border-top-left-radius: 5px !important;
    border-top-right-radius: 5px !important;
    cursor: pointer !important;
    text-align: center !important;
}

.tab:hover {
    background: var(--ccTools-tabGroup-tab-hover-background) !important;
    border-bottom-color: var(--ccTools-tabGroup-tab-hover-border) !important;
}

.tab:not(.checkedTab):hover {
    background: var(--ccTools-tabGroup-tab-hover-background) !important;
}

.checkedTab {
    background: var(--ccTools-tabGroup-tab-selected-background) !important;
    border-bottom-color: var(--ccTools-tabGroup-tab-selected-border) !important;
}

.gbtWidget.gbtPanel {
    background-color: transparent !important;
}

.mwRadioButton {
    background-color: transparent !important;
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
    font-weight: normal;
    font-style: normal;
    color: rgb(0, 0, 0);
    text-align: center;
    width: 100% !important;
    height: 100% !important;
}

.mwDialog *::selection,
.textview::selection,
.textview *::selection {
    background: #0078d4;
    color: white;
}

.textview--from-uiimage {
    display: flex;
    flex-direction: column;
    gap: 10px;
}

/*
  ## ProgressDialog ##
*/
:root {
    --sk-size: 40px;
    --sk-color: rgb(217, 83, 25);
}

.sk-chase { width: var(--sk-size); height: var(--sk-size); position: relative; animation: sk-chase 2.5s infinite linear both; }
.sk-chase-dot { width: 100%; height: 100%; position: absolute; left: 0; top: 0;  animation: sk-chase-dot 2.0s infinite ease-in-out both; }
.sk-chase-dot:before { content: ""; display: block; width: 25%; height: 25%; background-color: var(--sk-color); border-radius: 100%; animation: sk-chase-dot-before 2.0s infinite ease-in-out both; }
.sk-chase-dot:nth-child(1) { animation-delay: -1.1s; }
.sk-chase-dot:nth-child(2) { animation-delay: -1.0s; }
.sk-chase-dot:nth-child(3) { animation-delay: -0.9s; }
.sk-chase-dot:nth-child(4) { animation-delay: -0.8s; }
.sk-chase-dot:nth-child(5) { animation-delay: -0.7s; }
.sk-chase-dot:nth-child(6) { animation-delay: -0.6s; }
.sk-chase-dot:nth-child(1):before { animation-delay: -1.1s; }
.sk-chase-dot:nth-child(2):before { animation-delay: -1.0s; }
.sk-chase-dot:nth-child(3):before { animation-delay: -0.9s; }
.sk-chase-dot:nth-child(4):before { animation-delay: -0.8s; }
.sk-chase-dot:nth-child(5):before { animation-delay: -0.7s; }
.sk-chase-dot:nth-child(6):before { animation-delay: -0.6s; }
@keyframes sk-chase { 100% { transform: rotate(360deg); } }
@keyframes sk-chase-dot { 80%, 100% { transform: rotate(360deg); } }
@keyframes sk-chase-dot-before { 50% { transform: scale(0.4); } 100%, 0% { transform: scale(1); } }

/*
  ## CustomForm ##
*/
.custom-form-entry {
    overflow: hidden;
    padding-left: 4px;
    font-size: 11px;
    border: 1px solid #7d7d7d;
}

.custom-form-entry:focus {
    border-color: #268cdd;
    outline: none;
}`;
        
        styleElement = window.parent.document.createElement("style");
        styleElement.type = "text/css";
        styleElement.id = "MATLAB-ccTools";
        styleElement.innerHTML = `${cssText}`;

        window.parent.document.head.appendChild(styleElement);
    }

    /*---------------------------------------------------------------------------------*/
    function isMobile() {
        let userAgent = navigator.userAgent || "";
        return /Mobi|Android|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(userAgent);
    }

    function camelToKebab(prop) {
        return prop.replace(/[A-Z]/g, m => "-" + m.toLowerCase());
    }

    window.top.app.modules = {
        consoleLog, 
        findComponentHandle, 
        injectCustomStyle, 
        isMobile,
        camelToKebab
    }


    /*-----------------------------------------------------------------------------------
    LISTENERS
    -----------------------------------------------------------------------------------*/
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
        
        const propertyValue = window.getComputedStyle(handle).getPropertyValue(propertyName);
        htmlComponent.sendEventToMATLAB("getCssPropertyValue", { auxAppTag, componentName, propertyName, propertyValue });
    });

    /*---------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("changeTableRowHeight", function(customEvent) {
        let styleElement = window.parent.document.getElementById('MATLAB-ccTools-uitable');
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
        
        styleElement = window.parent.document.createElement("style");
        styleElement.type = "text/css";
        styleElement.id = "MATLAB-ccTools-uitable";
        styleElement.innerHTML = `${cssText}`;

        window.parent.document.head.appendChild(styleElement);
    });

    /*-----------------------------------------------------------------------------------
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
        window.top.app.executionMode = executionMode;        

        if (executionMode === "webApp") {
            window.top.addEventListener("beforeunload", (event) => {
                event.preventDefault();
                event.returnValue = '';
            });

            window.top.addEventListener("unload", () => {
                htmlComponent.sendEventToMATLAB("unload");
            });
        }

        injectCustomStyle();
    });

    /*---------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("initializeComponents", function (customEvent) {
        const components   = customEvent.Data;
        const maxAttempts  = 100;
        let modifyAttempts = 0;
        let dataTags       = '';

        window.top.app.ui.push(...components);

        const modifyInterval = setInterval(() => {
            modifyAttempts++;

            components.forEach((el, index) => {
                //consoleLog(`Attempt ${modifyAttempts}: Customizing element ${JSON.stringify(el)}`);

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
                            injectCustomStyle();
                            handle.classList.add(classElement);

                            modifyStatus = !!handle.classList.contains(classElement);
                            if (!modifyStatus) {
                                consoleLog(`Error: the class "${classElement}" could not be applied to the element ${el.dataTag}`);
                            }
                        })
                        handle.offsetHeight;
                    }

                    if (el.listener) {
                        const compName = el.listener.componentName;
                        const keyEvents = el.listener.keyEvents;
    
                        if (!handle.dataset.keydownListener) {
                            handle.dataset.keydownListener = keyEvents.join('-');
                            
                            handle.addEventListener('keydown', (event) => {
                                if (keyEvents.includes(event.key)) {
                                    event.preventDefault();
                                    event.stopPropagation();
                                    htmlComponent.sendEventToMATLAB(compName, event.key);
                                }
                            });
                        }
                    }

                    if (el.child) {
                        let child = handle.querySelector(`div[data-tag="${el.child.dataTag}"]`);
                        
                        if (child) {
                            child.innerHTML   = el.child.innerHTML;
                        } else {
                            child = window.parent.document.createElement('div');
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
            window.top.document.getElementsByClassName("mw-busyIndicator")[0].remove();
        } catch (ME) {
            // console.log(ME)
        }
    });

    /*---------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("getNavigatorBasicInformation", function() {
        const navigatorBasicInformation = {
            name: "BROWSER",
            url: window.top.location.href,
            platform: navigator.userAgentData?.platform || navigator.platform,
            mobile: navigator.userAgentData?.mobile ?? isMobile(),
            userAgent: navigator.userAgent,
            vendor: navigator.vendor
        };

        htmlComponent.sendEventToMATLAB("getNavigatorBasicInformation", navigatorBasicInformation);
    });

    /*---------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("setFocus", function(customEvent) {
        const dataTag = customEvent.Data.dataTag;
        const handle  = findComponentHandle(dataTag).querySelector("input");

        try {
            handle.focus();
            handle.setSelectionRange(handle.value.length, handle.value.length);
        } catch (ME) {
            // console.log(ME)
        }
    });

    /*---------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("forceReflow", function(customEvent) {
        const dataTag = customEvent.Data.dataTag;
        const handle  = findComponentHandle(dataTag)
        handle?.offsetHeight;
    });

    /*---------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("turningBackgroundColorInvisible", function(customEvent) {
        let objDataName = customEvent.Data.componentName.toString();
        let objDataTag  = customEvent.Data.componentDataTag.toString();
        let handle   = findComponentHandle(objDataTag);

        try {
            let opacityValue = 1.0;
            let intervalId = setInterval(() => {
                opacityValue -= 0.02;
                handle.style.opacity = opacityValue;

                if (opacityValue <= 0.02) {
                    clearInterval(intervalId);
                    htmlComponent.sendEventToMATLAB("BackgroundColorTurnedInvisible", objDataName);
                }
            }, 25);
        } catch (ME) {
            // console.log(ME)
        }
    });

    /*-----------------------------------------------------------------------------------
        ## CUSTOM FORM ##
    -----------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("customForm", function(customEvent) {
        try {
            const { UUID, Context } = customEvent.Data;
            let Fields    = customEvent.Data.Fields;
            Fields        = Array.isArray(Fields) ? Fields : [Fields];
            const zIndex  = 1000;

            let nFields = Fields.length;
            let Height  = nFields <= 3 ? 165 : 95+20*nFields+5*(nFields-1);

            injectCustomStyle();

            // Background layer
            var u = document.createElement("div");
            u.style.cssText = "visibility: visible; position: absolute; left: 0%; top: 0%; width: 100%; height: 100%; background: rgba(255,255,255,0.65); z-index: " + (zIndex + 3) + ";";

            // Progress dialog
            var w = document.createElement("div");
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
            window.parent.document.body.appendChild(u);

            // Form generation
            let formContainer = document.createElement("form");
            formContainer.style.cssText = "display: grid; grid-template-columns: 70px auto; gap: 5px; font-size: 12px; align-items: center;";
    
            Fields.forEach(function(field) {
                // Label
                let label = document.createElement("label");
                label.textContent = field.label;
                formContainer.appendChild(label);
    
                // Input field
                let input = document.createElement("input");
                input.type = field.type;
                input.className = "custom-form-entry";
                input.style.cssText = "height: 18px;";
                input.setAttribute("data-tag", UUID + "_" + field.id);
                formContainer.appendChild(input);
            });
    
            // Append form to the dialog body
            let dialogBody = window.parent.document.getElementById("mwDialogBody");
            dialogBody.appendChild(formContainer);

            // Handles
            let dialogBox  = window.parent.document.querySelector(`div[data-tag="${UUID}_uiCustomForm"]`);            
            let panelTitle = window.parent.document.querySelector(`div[data-tag="${UUID}_PanelTitle"]`);            
            let btnClose   = window.parent.document.querySelector(`button[data-tag="${UUID}_Close"]`);
            let btnOK      = window.parent.document.querySelector(`button[data-tag="${UUID}_OK"]`);

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
                window.parent.document.addEventListener("mousemove", mouseMoveCallback);
                window.parent.document.addEventListener("mouseup", mouseUpCallback);
            });

            function mouseMoveCallback(event) {
                mouseDiffX   = event.clientX - mousePosX;
                mouseDiffY   = event.clientY - mousePosY;

                objNormLeft += mouseDiffX;
                objNormTop  += mouseDiffY;

                let minLeft  = dialogBox.offsetWidth/2;
                let maxLeft  = window.parent.innerWidth  - dialogBox.offsetWidth/2;
                let minTop   = dialogBox.offsetHeight/2;
                let maxTop   = window.parent.innerHeight - dialogBox.offsetHeight/2;

                if (objNormLeft < minLeft) objNormLeft = minLeft;
                if (objNormLeft > maxLeft) objNormLeft = maxLeft;

                if (objNormTop  < minTop)  objNormTop  = minTop;
                if (objNormTop  > maxTop)  objNormTop  = maxTop;
                
                dialogBox.style.left = 100 * objNormLeft/window.parent.innerWidth + "%";
                dialogBox.style.top  = 100 * objNormTop/window.parent.innerHeight + "%";

                mousePosX    = event.clientX;
                mousePosY    = event.clientY;
            }

            function mouseUpCallback(event) {
                dialogBox.style.cursor = "default";                
                window.parent.document.removeEventListener("mousemove", mouseMoveCallback);
                window.parent.document.removeEventListener("mouseup", mouseUpCallback);
            }

            btnClose.addEventListener("click", function() {
                u.remove();
            });

            btnOK.addEventListener("click", function() {
                let formData = {};
                Fields.forEach(function(field) {
                    let inputField = window.parent.document.querySelector(`input[data-tag="${UUID}_${field.id}"]`);
                    formData[field.id] = inputField.value.trim();
                });
    
                // Validation
                let firstEmptyField = Object.keys(formData).find(key => formData[key] === "");
                if (firstEmptyField) {
                    let emptyField = window.parent.document.querySelector(`input[data-tag="${UUID}_${firstEmptyField}"]`);
                    emptyField.focus();
                    return;
                }

                formData.uuid = UUID;
                if (Context) formData.context = Context;
                htmlComponent.sendEventToMATLAB("customForm", formData);

                u.remove();
            });

            const focusElements = Array.from(w.querySelectorAll('button, input, select, [contenteditable]')).filter(el => !el.disabled && el.tabIndex !== -1);

            w.addEventListener("keydown", function(event) {                
                    if (focusElements.length === 0) return;
                
                    if (event.key === 'Tab') {
                        const activeElement = window.parent.document.activeElement;
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

            const firstInput = window.parent.document.querySelector(`input[data-tag="${UUID}_${Fields[0].id}"]`);
            firstInput.focus();

        } catch (ME) {
            // console.log(ME)
        }
    });

    /*-----------------------------------------------------------------------------------
        ## PROGRESS DIALOG ##
    -----------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("progressDialog", function(customEvent) {
        const Type = customEvent.Data.Type.toString();
        const UUID = customEvent.Data.UUID.toString();

        let handle = window.parent.document.body.querySelectorAll(`div[data-tag="${UUID}"]`);
        if ((Type === "Creation") || (handle.length === 0)) {
            const zIndex = 900;

            if ("Size" in customEvent.Data) {
                Size = customEvent.Data.Size.toString();
            } else if (window.parent.sessionStorage.getItem("ProgressDialog") !== null) {
                Size = JSON.parse(window.parent.sessionStorage.getItem("ProgressDialog")).Size;
            } else {
                Size = "40px";
            }

            if ("Color" in customEvent.Data) {
                Color = customEvent.Data.Color.toString();
            } else if (window.parent.sessionStorage.getItem("ProgressDialog") !== null) {
                Color = JSON.parse(window.parent.sessionStorage.getItem("ProgressDialog")).Color;
            } else {
                Color = "#d95319";
            }

            if (window.parent.sessionStorage.getItem("ProgressDialog") === null) {
                window.parent.sessionStorage.setItem("ProgressDialog", JSON.stringify({"Type": Type, "UUID": UUID, "Size": Size, "Color": Color}))
            }

            try {
                injectCustomStyle();
        
                // Background layer
                var u = window.parent.document.createElement("div");
                u.setAttribute("data-tag", UUID);
                u.style.cssText = `visibility: hidden; position: absolute; left: 0%; top: 0%; width: 100%; height: 100%; background-color: rgba(255, 255, 255, 0.65); z-index: ${zIndex+1};`;
        
                // Progress dialog
                var w = window.parent.document.createElement("div");
                w.setAttribute("data-tag", UUID);
                w.style.cssText = `visibility: hidden; position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); z-index: ${zIndex+2};`;
                w.innerHTML     = `
                    <div class="sk-chase">
                        <div class="sk-chase-dot"></div>
                        <div class="sk-chase-dot"></div>
                        <div class="sk-chase-dot"></div>
                        <div class="sk-chase-dot"></div>
                        <div class="sk-chase-dot"></div>
                        <div class="sk-chase-dot"></div>
                    </div>
                `;
                
                u.appendChild(w);
                window.parent.document.body.appendChild(u);
            } catch (ME) {
                console.log(ME)
            }
        }
        
        switch (Type) {
            case "changeVisibility":
                const newVisibility = customEvent.Data.Visibility.toString();
                handle.forEach(element => {
                    element.style.visibility = newVisibility;
                });
                break;

            case "changeColor":
                const newColor = customEvent.Data.Color.toString();
                window.parent.document.documentElement.style.setProperty("--sk-color", newColor);
                break;

            case "changeSize":
                const newSize = customEvent.Data.Size.toString();
                window.parent.document.documentElement.style.setProperty("--sk-size", newSize);
                break;
        };
    });

    /*---------------------------------------------------------------------------------*/
    window.requestAnimationFrame(() => {
        const msg = 'DOM render cycle finished';
        consoleLog(msg);

        htmlComponent.sendEventToMATLAB('renderer', msg);
        window.top.app.rendererStatus = true;
    });
}