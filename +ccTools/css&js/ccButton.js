	function setup(htmlComponent) {
		const btn = document.querySelector("button");
		btn.addEventListener("click", function(event) {
			if (htmlComponent.Data == "") {
				htmlComponent.Data = "ButtonPushed";
			};
		});
	}