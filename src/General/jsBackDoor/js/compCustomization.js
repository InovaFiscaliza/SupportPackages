function setup(htmlComponent) {
    window.top.app = {
        executionMode: null,
        matlabBackDoor: htmlComponent,
        ui: []
    };

    /*---------------------------------------------------------------------------------*/
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
    --tabContainer-border-color: rgb(255, 255, 255) !important;   
}

.mw-theme-light {
    --mw-backgroundColor-dataWidget-selected: rgba(180, 222, 255, 0.45) !important;
    --mw-backgroundColor-selected: rgba(180, 222, 255, 0.45) !important;
    --mw-backgroundColor-selectedFocus: rgba(180, 222, 255, 0.45) !important;
    --mw-backgroundColor-list-hover: rgb(191, 191, 191) !important;
    --mw-backgroundColor-tab: rgb(255, 255, 255) !important;
}

.treenode.selected {
    background-image: linear-gradient(rgba(180, 222, 255, 0.45), rgba(180, 222, 255, 0.45)) !important;
}

.mw-tree .mw-tree-scroll-component.focused.hoverable .treeNode.selected.mw-tree-node-hover {
    background-image: linear-gradient(rgb(191, 191, 191), rgb(191, 191, 191)) !important;
}

.mw-default-header-cell {
    font-size: 10px !important; 
    white-space: pre-wrap !important; 
    margin-bottom: 5px !important;
}

.gbtTabGroupBorder {
    border: none !important;
}

.gbtWidget.gbtPanel {
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
}

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
    htmlComponent.addEventListener("startup", function(customEvent) {
        const executionMode = customEvent.Data;
        window.top.app.executionMode = executionMode;        

        if (executionMode === "webApp") {
            window.top.addEventListener("beforeunload", (event) => {
                event.preventDefault();
                event.returnValue = '';
                
                htmlComponent.sendEventToMATLAB("beforeonload");
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
                            handle.dataset.keydownListener = 'on';
                            
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
        const style   = customEvent.Data.style;

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
    htmlComponent.addEventListener("getURL", function() {
        htmlComponent.sendEventToMATLAB("getURL", window.top.location.href);
    });

    /*---------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("getNavigatorBasicInformation", function() {
        let navigatorBasicInformation = {
            "userAgent": navigator.userAgent,
            "platform": navigator.userAgentData.platform,
            "mobile": navigator.userAgentData.mobile
        }

        htmlComponent.sendEventToMATLAB("getNavigatorBasicInformation", navigatorBasicInformation);
    });

    /*---------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("setFocus", function(customEvent) {
        let dataTag = customEvent.Data.dataTag;
        let handle  = findComponentHandle(dataTag).querySelector("input");

        try {
            handle.focus();
            handle.setSelectionRange(handle.value.length, handle.value.length);
        } catch (ME) {
            // console.log(ME)
        }
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

    /*---------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("htmlClassCustomization", function(customEvent) {
        try {
            const className       = customEvent.Data.className.toString();
            const classAttributes = customEvent.Data.classAttributes.toString();
    
            const styleElement = document.createElement("style");
            styleElement.type = "text/css";
            styleElement.appendChild(document.createTextNode(`${className} { ${classAttributes} }`));
            window.parent.document.head.appendChild(styleElement);
        } catch (ME) {
            console.warn(`CSS injection failed: ${className}`)
        }
    });

    /*-----------------------------------------------------------------------------------
        ## MATLAB-STYLE PANEL DIALOG ##
    -----------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("panelDialog", function(customEvent) {
        let objDataTag = customEvent.Data.componentDataTag.toString();
        let handle  = findComponentHandle(objDataTag);

        if (handle) {
            handle.style.borderRadius             = "5px";
            handle.style.boxShadow                = "0 2px 5px 1px var(--mw-boxShadowColor,#a6a6a6)";
            handle.children[0].style.borderRadius = "5px";
            handle.children[0].style.borderColor  = "var(--mw-borderColor-secondary,#bfbfbf)";
        }
    });

    /*-----------------------------------------------------------------------------------
        ## CUSTOM FORM ##
    -----------------------------------------------------------------------------------*/
    htmlComponent.addEventListener("customForm", function(customEvent) {
        try {
            const UUID    = customEvent.Data.UUID;
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
            const zIndex = 1000;

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
    });    
}