// zIndex
var zIndex = 1000;
var objList = document.querySelectorAll('div[role="dialog"]');
objList.forEach(element => {
    let idx = parseInt(element.style.zIndex);
    zIndex = (zIndex < idx ? idx : zIndex);
});
objList = undefined;

// Elements creation
let u<uniqueSuffix> = document.createElement("div");
let w<uniqueSuffix> = document.createElement("div");
let s<uniqueSuffix> = document.createElement("script");

document.body.appendChild(u<uniqueSuffix>);
document.body.appendChild(w<uniqueSuffix>);
document.body.appendChild(s<uniqueSuffix>);

u<uniqueSuffix>.setAttribute("data-type", "ccTools.MessageBox");
w<uniqueSuffix>.setAttribute("data-type", "ccTools.MessageBox");
s<uniqueSuffix>.setAttribute("data-type", "ccTools.MessageBox");

u<uniqueSuffix>.setAttribute("data-tag", "%s");
w<uniqueSuffix>.setAttribute("data-tag", "%s");
s<uniqueSuffix>.setAttribute("data-tag", "%s");

// Background layer
u<uniqueSuffix>.setAttribute("class", "backgroundLayer");
u<uniqueSuffix>.style.position   = "absolute";
u<uniqueSuffix>.style.left       = "0%%";
u<uniqueSuffix>.style.top        = "0%%";
u<uniqueSuffix>.style.width      = "100%%";
u<uniqueSuffix>.style.height     = "100%%";
u<uniqueSuffix>.style.zIndex     = zIndex+1;

// Message Box
w<uniqueSuffix>.setAttribute("class", "mwDialog mwAlertDialog mwModalDialog mwModalDialogFg focused");
w<uniqueSuffix>.setAttribute("role", "dialog");
w<uniqueSuffix>.style.position   = "absolute";
w<uniqueSuffix>.style.left       = "50%%"; 
w<uniqueSuffix>.style.top        = "50%%";
w<uniqueSuffix>.style.transform  = "translate(-50%%, -50%%)"; 
w<uniqueSuffix>.style.width      = "%s"; 
w<uniqueSuffix>.style.height     = "%s"; 
w<uniqueSuffix>.style.padding    = "10px";
w<uniqueSuffix>.style.backgroundColor = "%s"; 
w<uniqueSuffix>.style.visibility = "visible"; 
w<uniqueSuffix>.style.zIndex     = zIndex+2;
w<uniqueSuffix>.innerHTML        = `
    <div style="display: grid; grid-template-columns: %s auto %s; grid-template-rows: %s auto %s; height: 100%%; gap: 10px;">
        <img src="data:image/%s;base64,%s" style="width: 100%%; height: 100%%; grid-area: 1 / 1 / auto / auto;">
        <div class="textarea" readonly="true" style="resize: none; background-color: %s; border-width: 0px; outline: none; overflow-y: auto; overflow-x: hidden; word-wrap: break-word; font-family: %s; font-size: %s; color: %s; text-align: %s; grid-area: 1 / 2 / span 2 / span 2;">%s</div>
        <button style="background-color: %s; border-radius: %s; border-width: %s; border-color: %s; font-family: %s; font-size: %s; color: %s; text-align: %s; grid-area: 3 / 3 / auto / auto;">OK</button>
    </div>
`;

// Script (JS)
s<uniqueSuffix>.textContent = `
    w<uniqueSuffix>.querySelector("button").addEventListener("click", function() {
        zIndex = undefined;

        u<uniqueSuffix>.remove();
        w<uniqueSuffix>.remove();
        s<uniqueSuffix>.remove();

        delete u<uniqueSuffix>;
        delete w<uniqueSuffix>;        
        delete s<uniqueSuffix>;
    });`