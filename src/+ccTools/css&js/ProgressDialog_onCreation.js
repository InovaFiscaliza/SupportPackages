// zIndex
var zIndex = 1000;
var objList = document.querySelectorAll('div[role="dialog"]');
objList.forEach(element => {
    let idx = parseInt(element.style.zIndex);
    zIndex = (zIndex < idx ? idx : zIndex);
});
objList = undefined;

// Elements creation
let s<uniqueSuffix> = document.createElement("style");
let u<uniqueSuffix> = document.createElement("div");
let w<uniqueSuffix> = document.createElement("div");

document.head.appendChild(s<uniqueSuffix>);
%s

s<uniqueSuffix>.setAttribute("data-type", "ccTools.ProgressDialog");
u<uniqueSuffix>.setAttribute("data-type", "ccTools.ProgressDialog");
w<uniqueSuffix>.setAttribute("data-type", "ccTools.ProgressDialog");

s<uniqueSuffix>.setAttribute("data-tag", "%s");
u<uniqueSuffix>.setAttribute("data-tag", "%s");
w<uniqueSuffix>.setAttribute("data-tag", "%s");

// CSS
s<uniqueSuffix>.innerHTML = `
    :root {
      --sk-size: %s;
      --sk-color: %s;
    }
    
    .sk-chase {
      width: var(--sk-size);
      height: var(--sk-size);
      position: relative;
      animation: sk-chase 2.5s infinite linear both; 
    }
    
    .sk-chase-dot {
      width: 100%%;
      height: 100%%;
      position: absolute;
      left: 0;
      top: 0; 
      animation: sk-chase-dot 2.0s infinite ease-in-out both; 
    }
    
    .sk-chase-dot:before {
      content: '';
      display: block;
      width: 25%%;
      height: 25%%;
      background-color: var(--sk-color);
      border-radius: 100%%;
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
      100%% { transform: rotate(360deg); } 
    }
    
    @keyframes sk-chase-dot {
      80%%, 100%% { transform: rotate(360deg); } 
    }
    
    @keyframes sk-chase-dot-before {
      50%% {
        transform: scale(0.4); 
      } 100%%, 0%% {
        transform: scale(1.0); 
      } 
    }
`;

// Background layer
u<uniqueSuffix>.setAttribute("class", "backgroundLayer");
u<uniqueSuffix>.style.position  = "absolute";
u<uniqueSuffix>.style.left      = "0%%";
u<uniqueSuffix>.style.top       = "0%%";
u<uniqueSuffix>.style.width     = "100%%";
u<uniqueSuffix>.style.height    = "100%%";
u<uniqueSuffix>.style.zIndex    = zIndex+1;

// Progress dialog
w<uniqueSuffix>.setAttribute("role", "dialog");
w<uniqueSuffix>.style.position  = "absolute";
w<uniqueSuffix>.style.left      = "50%%";
w<uniqueSuffix>.style.top       = "50%%";
w<uniqueSuffix>.style.transform = "translate(-50%%, -50%%)";
w<uniqueSuffix>.style.zIndex    = zIndex+2;
w<uniqueSuffix>.innerHTML       = `
    <div class="sk-chase">
      <div class="sk-chase-dot"></div>
      <div class="sk-chase-dot"></div>
      <div class="sk-chase-dot"></div>
      <div class="sk-chase-dot"></div>
      <div class="sk-chase-dot"></div>
      <div class="sk-chase-dot"></div>
    </div>
`;