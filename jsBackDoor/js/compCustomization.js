function setup(htmlComponent) {
    htmlComponent.addEventListener("delProgressDialog", function() {
        try {
            window.top.document.getElementsByClassName("mw-busyIndicator")[0].remove();
        } catch (ME) {
            // console.log(ME)
        }
    });

    htmlComponent.addEventListener("getURL", function() {
        try {
            let URL = window.top.location.href;
            htmlComponent.sendEventToMATLAB("getURL", URL);
        } catch (ME) {
            // console.log(ME)
        }
    });

    htmlComponent.addEventListener("getNavigatorBasicInformation", function() {
        try {
            let navigatorBasicInformation = {
                "userAgent": navigator.userAgent,
                "platform": navigator.userAgentData.platform,
                "mobile": navigator.userAgentData.mobile
            }

            htmlComponent.sendEventToMATLAB("getNavigatorBasicInformation", navigatorBasicInformation);
        } catch (ME) {
            // console.log(ME)
        }
    });

    htmlComponent.addEventListener("addKeyDownListener", function(customEvent) {
        let objDataName  = customEvent.Data.componentName.toString();
        let objDataTag   = customEvent.Data.componentDataTag.toString();
        let keyEvents    = customEvent.Data.keyEvents;
        let objHandle    = window.parent.document.querySelector(`div[data-tag="${objDataTag}"]`).children[0];

        objHandle.addEventListener("keydown", function(event) {
            if (keyEvents.includes(event.key)) {
                event.preventDefault();
                event.stopPropagation();
                htmlComponent.sendEventToMATLAB(objDataName, event.key);
            }
        });
    });

    htmlComponent.addEventListener("setFocus", function(customEvent) {
        let objDataName  = customEvent.Data.componentName.toString();
        let objDataTag   = customEvent.Data.componentDataTag.toString();
        let objHandle    = window.parent.document.querySelector(`div[data-tag="${objDataTag}"]`).querySelector("input");

        try {
            objHandle.focus();
            objHandle.setSelectionRange(objHandle.value.length, objHandle.value.length);
        } catch (ME) {
            // console.log(ME)
        }
    });

    htmlComponent.addEventListener("turningBackgroundColorInvisible", function(customEvent) {
        let objDataName = customEvent.Data.componentName.toString();
        let objDataTag  = customEvent.Data.componentDataTag.toString();
        let objHandle   = window.parent.document.querySelector(`div[data-tag="${objDataTag}"]`);

        try {
            let opacityValue = 1.0;
            let intervalId = setInterval(() => {
                opacityValue -= 0.02;
                objHandle.style.opacity = opacityValue;

                if (opacityValue <= 0.02) {
                    clearInterval(intervalId);
                    htmlComponent.sendEventToMATLAB("BackgroundColorTurnedInvisible", objDataName);
                }
            }, 25);
        } catch (ME) {
            // console.log(ME)
        }
    });

    htmlComponent.addEventListener("htmlClassCustomization", function(customEvent) {
        try {
            var className       = customEvent.Data.className.toString();
            var classAttributes = customEvent.Data.classAttributes.toString();
    
            var s = document.createElement("style");
            s.type = "text/css";
            s.appendChild(document.createTextNode(className + " { " + classAttributes + " }"));
            window.parent.document.head.appendChild(s);
        } catch (ME) {
            // console.log(ME)
        }
    });

    htmlComponent.addEventListener("panelDialog", function(customEvent) {
        let objDataTag = customEvent.Data.componentDataTag.toString();
        let objHandle  = window.parent.document.querySelector(`div[data-tag="${objDataTag}"]`);

        if (objHandle) {
            objHandle.style.borderRadius             = "5px";
            objHandle.style.boxShadow                = "0 2px 5px 1px var(--mw-boxShadowColor,#a6a6a6)";
            objHandle.children[0].style.borderRadius = "5px";
            objHandle.children[0].style.borderColor  = "var(--mw-borderColor-secondary,#bfbfbf)";
        }
    });

    htmlComponent.addEventListener("credentialDialog", function(customEvent) {
        try {    
            var UUID = customEvent.Data.UUID.toString();
            var zIndex = 1000;

            // Style
            var s = document.createElement("style");
            s.type = "text/css";
            s.innerHTML = `
                .ccToolsEditField {
                    overflow: hidden;
                    padding-left: 4px;
                    font-size: 11px;
                    border: 1px solid #7d7d7d;
                }

                .ccToolsEditField:focus {
                    border-color: #268cdd;
                    outline: none;
                }
            `;

            // Background layer
            var u = document.createElement("div");
            u.style.cssText = "visibility: visible; position: absolute; left: 0%; top: 0%; width: 100%; height: 100%; background: var(--mw-backgroundColor-tertiary,#fff); opacity: var(--mw-opacity-dialogUnderlay); z-index: " + (zIndex + 3) + ";";

            // Progress dialog
            var w = document.createElement("div");
            w.setAttribute("data-tag", UUID);
            w.innerHTML = `
                <div class="mwDialog mwAlertDialog mwModalDialog mw-theme-light mwModalDialogFg" data-tag="${UUID}_uiCredential" style="width: 260px; height: 162px; visibility: visible; z-index: ${zIndex + 4}; color-scheme: light; position: fixed; top: 50%; left: 50%; transform: translate(-50%, -50%);">
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
                    <div class="mwDialogBody" style="height: 49px; padding: 13px 10px 10px 10px;">
                        <form style="display: grid; grid-template-columns: 60px auto; gap: 5px; font-size: 12px; align-items: center;">
                            <label style="grid-column: 1;">Usuário:</label>
                            <input type="text" class="ccToolsEditField" data-tag="${UUID}_Login" style="grid-column: 2; height: 18px;">                                
                            <label style="grid-column: 1;">Senha:</label>
                            <input type="password" class="ccToolsEditField" data-tag="${UUID}_Password" style="grid-column: 2; height: 18px;">
                        </form>
                    </div>
                    <div class="mwDialogButtonBar mwNoSplBtn">
                        <div class="mwActionButtonBar">
                            <button class="mwButton" data-tag="${UUID}_OK">OK</button>
                        </div>
                    </div>    
                </div>
            `;
            
            window.parent.document.head.appendChild(s);
            window.parent.document.body.appendChild(u);
            window.parent.document.body.appendChild(w);

            // Handles
            let uiCredential = window.parent.document.querySelector(`div[data-tag="${UUID}_uiCredential"]`);
            let panelTitle   = window.parent.document.querySelector(`div[data-tag="${UUID}_PanelTitle"]`);
            let btnClose     = window.parent.document.querySelector(`button[data-tag="${UUID}_Close"]`);
            let loginField   = window.parent.document.querySelector(`input[data-tag="${UUID}_Login"]`);
            let passField    = window.parent.document.querySelector(`input[data-tag="${UUID}_Password"]`);
            let btnOK        = window.parent.document.querySelector(`button[data-tag="${UUID}_OK"]`);

            // Callbacks
            let mousePosX, mousePosY;
            let objNormLeft, objNormTop;
            panelTitle.addEventListener("mousedown", function(event) {
                event.preventDefault();

                mousePosX    = event.clientX;
                mousePosY    = event.clientY;

                objNormLeft  = uiCredential.offsetLeft;
                objNormTop   = uiCredential.offsetTop;
                
                uiCredential.style.cursor = "move";
                window.parent.document.addEventListener("mousemove", mouseMoveCallback);
                window.parent.document.addEventListener("mouseup", mouseUpCallback);
            });

            function mouseMoveCallback(event) {
                mouseDiffX   = event.clientX - mousePosX;
                mouseDiffY   = event.clientY - mousePosY;

                objNormLeft += mouseDiffX;
                objNormTop  += mouseDiffY;

                let minLeft  = uiCredential.offsetWidth/2;
                let maxLeft  = window.parent.innerWidth  - uiCredential.offsetWidth/2;
                let minTop   = uiCredential.offsetHeight/2;
                let maxTop   = window.parent.innerHeight - uiCredential.offsetHeight/2;

                if (objNormLeft < minLeft) objNormLeft = minLeft;
                if (objNormLeft > maxLeft) objNormLeft = maxLeft;

                if (objNormTop  < minTop)  objNormTop  = minTop;
                if (objNormTop  > maxTop)  objNormTop  = maxTop;
                
                uiCredential.style.left = 100 * objNormLeft/window.parent.innerWidth + "%";
                uiCredential.style.top  = 100 * objNormTop/window.parent.innerHeight + "%";

                mousePosX    = event.clientX;
                mousePosY    = event.clientY;
            }

            function mouseUpCallback(event) {
                uiCredential.style.cursor = "default";                
                window.parent.document.removeEventListener("mousemove", mouseMoveCallback);
                window.parent.document.removeEventListener("mouseup", mouseUpCallback);
            }

            btnClose.addEventListener("click", function() {
                s.remove();
                u.remove();
                w.remove();
            });

            btnOK.addEventListener("click", function() {
                loginField.value = loginField.value.trim();
                passField.value  = passField.value.trim();

                if (loginField.value == "") {
                    loginField.focus();
                    return;
                } else if (passField.value == "") {
                    passField.focus();
                    return;
                }

                htmlComponent.sendEventToMATLAB("credentialDialog", {"login": loginField.value, "password": passField.value});

                s.remove();
                u.remove();
                w.remove();
            });

            w.addEventListener("keydown", function(event) {
                if (event.key == "Tab") {
                    switch (window.parent.document.activeElement) {
                        case btnClose:
                            if (event.shiftKey) {
                                btnOK.focus();
                                event.preventDefault();
                            }
                            break;

                        case btnOK:
                            if (!event.shiftKey) {
                                btnClose.focus();
                                event.preventDefault();
                            }
                            break;
                    }                    
                }
            });

            loginField.focus();

        } catch (ME) {
            console.log(ME)
        }
    });

    htmlComponent.addEventListener("progressDialog", function(customEvent) {
        try {
            var Type = customEvent.Data.Type.toString();
            var UUID = customEvent.Data.UUID.toString();
    
            switch (Type) {
                case "changeVisibility":
                    var Visible  = customEvent.Data.Visibility.toString();
                    var elements = window.parent.document.querySelectorAll(`div[data-tag="${UUID}"]`);                    
                    elements.forEach(element => {
                        element.style.visibility = Visible;
                    });
                    break;

                case "changeColor":
                    var newColor = customEvent.Data.Color.toString();
                    window.parent.document.documentElement.style.setProperty("--sk-color", newColor);
                    break;

                case "changeSize":
                    var newSize  = customEvent.Data.Size.toString();
                    window.parent.document.documentElement.style.setProperty("--sk-size", newSize);
                    break;

                case "Creation":
                    var zIndex = 1000;
                    var Size   = customEvent.Data.Size.toString();
                    var Color  = customEvent.Data.Color.toString();

                    // Style
                    var s = document.createElement("style");
                    s.type = "text/css";                    
                    s.innerHTML = `
                        :root {
                            --sk-size: ${Size};
                            --sk-color: ${Color};
                        }
                        
                        .sk-chase {
                            width: var(--sk-size);
                            height: var(--sk-size);
                            position: relative;
                            animation: sk-chase 2.5s infinite linear both; 
                        }
                        
                        .sk-chase-dot {
                            width: 100%;
                            height: 100%;
                            position: absolute;
                            left: 0;
                            top: 0; 
                            animation: sk-chase-dot 2.0s infinite ease-in-out both; 
                        }
                        
                        .sk-chase-dot:before {
                            content: "";
                            display: block;
                            width: 25%;
                            height: 25%;
                            background-color: var(--sk-color);
                            border-radius: 100%;
                            animation: sk-chase-dot-before 2.0s infinite ease-in-out both; 
                        }
                        
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
                        
                        @keyframes sk-chase {
                            100% { transform: rotate(360deg); } 
                        }
                        
                        @keyframes sk-chase-dot {
                            80%, 100% { transform: rotate(360deg); } 
                        }
                        
                        @keyframes sk-chase-dot-before {
                            50% {
                                transform: scale(0.4); 
                            } 100%, 0% {
                                transform: scale(1.0); 
                            } 
                        }
                    `;

                    // Background layer
                    var u = document.createElement("div");
                    u.setAttribute("data-tag", UUID);
                    u.style.cssText = "visibility: hidden; position: absolute; left: 0%; top: 0%; width: 100%; height: 100%; background-color: rgba(255, 255, 255, 0.65); z-index: " + (zIndex + 1) + ";";

                    // Progress dialog
                    var w = document.createElement("div");
                    w.setAttribute("data-tag", UUID);
                    w.style.cssText = "visibility: hidden; position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); z-index: " + (zIndex + 2) + ";";
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
                    
                    window.parent.document.head.appendChild(s);
                    window.parent.document.body.appendChild(u);
                    window.parent.document.body.appendChild(w);
                    break;
            };
        } catch (ME) {
            // console.log(ME)
        }
    });
        
    htmlComponent.addEventListener("compCustomization", function(customEvent) {
        let objClass    = customEvent.Data.Class.toString();
        let objDataTag  = customEvent.Data.DataTag.toString();
        let objProperty = customEvent.Data.Property.toString();
        let objValue    = customEvent.Data.Value.toString();
        let objHandle   = window.parent.document.querySelector(`div[data-tag="${objDataTag}"]`);
        
        if (!objHandle) {
            return;
        }
        
        try {
            let elements = null;

            switch (objClass) {
                case "matlab.ui.container.ButtonGroup":
                case "matlab.ui.container.CheckBoxTree":
                case "matlab.ui.container.Tree":
                case "matlab.ui.container.Label":
                    objHandle.style[objProperty] = objValue;
                    objHandle.children[0].style[objProperty] = objValue;
                    break;
                    
                case "matlab.ui.container.GridLayout":
                case "matlab.ui.container.Panel":
                    objHandle.style[objProperty] = objValue;
                    break;
                    
                case "matlab.ui.container.TabGroup":
                    switch (objProperty) {
                        case "backgroundColor":
                            // Pendente!
                            return;                         
                        case "backgroundHeaderColor":
                            objHandle.style.backgroundColor = "transparent";
                            objHandle.children[1].style.backgroundColor = objValue;
                            break;
                        case "transparentHeader":
                            objHandle.style.border = "none";
                            objHandle.style.backgroundColor = "transparent";
                            
                            objHandle.children[1].style.border = "none";
                            objHandle.children[1].style.backgroundColor = "transparent";                            

                            var childElements = objHandle.children[1].querySelectorAll("*");

                            childElements.forEach(function(child) {
                                child.style.border = "none";
                                child.style.backgroundColor = "transparent";                                
                            });
                            break;
                        case "borderRadius":
                        case "borderWidth":
                        case "borderColor":
                            objHandle.style[objProperty] = objValue;
                            break;
                        case "fontFamily":
                        case "fontStyle":
                        case "fontWeight":
                        case "fontSize":
                        case "color":
                            elements = objHandle.getElementsByClassName("mwTabLabel");                            
                            for (let ii = 0; ii < elements.length; ii++) {
                                elements[ii].style[objProperty] = objValue;
                            }
                            break;
                    }
                
                case "matlab.ui.control.Button":
                case "matlab.ui.control.DropDown":
                case "matlab.ui.control.EditField":
                case "matlab.ui.control.ListBox":
                case "matlab.ui.control.NumericEditField":
                case "matlab.ui.control.StateButton":
                    objHandle.children[0].style[objProperty] = objValue;
                    break;
                    
                case "matlab.ui.control.TextArea":
                    switch (objProperty) {
                        case "backgroundColor":
                            objHandle.style.backgroundColor = "transparent";
                            objHandle.children[0].style.backgroundColor = objValue;
                            break;                            
                        case "textAlign":
                            objHandle.getElementsByTagName("textarea")[0].style.textAlign = objValue;
                            break;                            
                        default:
                            objHandle.children[0].style[objProperty] = objValue;
                            break;
                    }
                    
                case "matlab.ui.control.CheckBox":
                    objHandle.getElementsByClassName("mwCheckBoxRadioIconNode")[0].style[objProperty] = objValue;
                    break;

                case "matlab.ui.control.Table":
                    switch (objProperty) {
                        case "backgroundColor":
                            objHandle.children[0].style.backgroundColor = "transparent";
                            objHandle.children[0].children[0].style.backgroundColor = objValue;
                            break;    
                        case "backgroundHeaderColor":
                            objHandle.children[0].children[0].children[0].style.backgroundColor = objValue;
                            break;    
                        case "borderRadius":
                            objHandle.children[0].style.borderRadius = objValue;
                            objHandle.children[0].children[0].style.borderRadius = objValue;
                            break;    
                        case "borderWidth":
                        case "borderColor":
                            objHandle.children[0].children[0].style[objProperty] = objValue;
                            break;
                        case "textAlign":
                        case "paddingTop":
                            elements = objHandle.getElementsByClassName("mw-table-header-row")[0].children;                      
                            for (let ii = 0; ii < elements.length; ii++) {
                                elements[ii].style[objProperty] = objValue;
                            }
                            break;
                        case "fontFamily":
                        case "fontStyle":
                        case "fontWeight":
                        case "fontSize":
                        case "color":
                            elements = objHandle.getElementsByClassName("mw-default-header-cell");
                            for (let ii = 0; ii < elements.length; ii++) {
                                elements[ii].style[objProperty] = objValue;
                            }
                            break;
                    }

                default:
                    objHandle.style[objProperty] = objValue;
                    break;
            }
        } catch (ME) {
            // console.log(ME)
        }
    });
}