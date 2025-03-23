var elements       = document.querySelectorAll('[data-type="ccTools.%s"].backgroundLayer');
var elementsFigure = [];
var elementsOthers = [];

elements.forEach(element => {
  let parent = element.parentNode;
  (parent == document.body ? elementsFigure : elementsOthers).push(element);
});

if (elementsFigure.length > 0) {
  switch (elementsFigure[0].dataset.type) {
      case "ccTools.MessageBox":
          elementsFigure[0].style.backgroundColor = "%s";
          elementsFigure.slice(1).forEach(element => element.style.backgroundColor = "transparent");
          break;
      case "ccTools.ProgressDialog":
          elementsFigure[elementsFigure.length-1].style.backgroundColor = "%s";
          elementsFigure.slice(0, elementsFigure.length-1).forEach(element => element.style.backgroundColor = "transparent");
          break;
  }
  elementsOthers.forEach(element => element.style.backgroundColor = "transparent");
} else {
  let nonTransparentElements = [];  
  elementsOthers.forEach(element => {
    let parent = element.parentNode;
    if (!nonTransparentElements.includes(parent)) {
      nonTransparentElements.push(parent);
      element.style.backgroundColor = "%s";
    } else {
      element.style.backgroundColor = "transparent";
    }
  });
}