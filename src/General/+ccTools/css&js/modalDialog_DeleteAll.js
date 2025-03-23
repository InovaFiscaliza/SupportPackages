var elements = document.querySelectorAll('[data-type="ccTools.%s"]');

elements.forEach(element => element.remove());
elements = undefined;