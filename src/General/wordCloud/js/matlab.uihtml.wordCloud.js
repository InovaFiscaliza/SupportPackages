function setup(htmlComponent) {
    if (!window.top.app) {
        window.top.app = {};
    }

    let canvas = window.document.getElementById('wordcloudCanvas');
    if (!canvas) {
        canvas = window.document.createElement('canvas');
        canvas.id = 'wordcloudCanvas';
        canvas.style.display = "none";
        canvas.getContext('2d', { willReadFrequently: true });

        window.document.body.appendChild(canvas);
    }

    let currentWords = [];
    htmlComponent.addEventListener("drawWordCloud", (event) => {
        const { words, weights } = event.Data;        
        currentWords = words.map((word, index) => {
            return {
                text: word,
                size: weights[index]
            };
        });

        drawCloud(currentWords);
        window.top.app.wordcloud.data = currentWords;
    });

    htmlComponent.addEventListener("eraseWordCloud", () => erase);

    /*
    let resizeTimeout;
    window.addEventListener("resize", () => {
        clearTimeout(resizeTimeout);

        resizeTimeout = setTimeout(() => {
            if (currentWords.length > 0) {
                drawCloud(currentWords);
            }
        }, 200);
    });
    */

    function drawCloud(words) {
        erase();

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
    }

    function getFontScale(words, width, height) {
        const maxSize = d3.max(words, d => d.size);
        const minSize = d3.min(words, d => d.size);

        return d3.scalePow().exponent(0.5).domain([minSize, maxSize]).range([10, Math.min(width, height) / 3]);
    }

    function erase() {
        d3.select("#wordcloud").selectAll("*").remove();
    }

    window.top.app.wordcloud = { 
        canvas, 
        drawCloud, 
        erase, 
        data: null 
    };
}