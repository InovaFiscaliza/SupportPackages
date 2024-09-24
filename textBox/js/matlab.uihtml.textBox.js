function setup(htmlComponent) {
    let textBoxContainer = document.getElementById("textbox");

    htmlComponent.addEventListener("draw", function(event) {
        let EventName = event.Data.EventName.toString();
        let htmlContent = event.Data.htmlContent.toString();
        let htmlImageID = event.Data.ImageID.toString();

        textBoxContainer.innerHTML = htmlContent;

        let hImage = document.getElementById(htmlImageID);
        if (hImage) {
            hImage.addEventListener("click", function() {
                htmlComponent.sendEventToMATLAB(EventName);
            });
        }
    });
}