function setup(htmlComponent) {
    const canvas = createCanvas();
    let words = [];

    htmlComponent.addEventListener("drawWordCloud", function(event) {
        const wordsArray   = event.Data.words;
        const weightsArray = event.Data.weights;
        
        words = wordsArray.map((word, ii) => {
            return {
                text: word,
                size: weightsArray[ii]
            };
        });

        drawCloud(words);
    });

    htmlComponent.addEventListener("eraseWordCloud", function() {
        erase();
    });

    // window.addEventListener("resize", () => drawCloud(words));

    function createCanvas() {
        const canvas = document.createElement('canvas');
        const context = canvas.getContext('2d', { willReadFrequently: true });
        return canvas;
    }

    function drawCloud(words) {
        const width  = window.innerWidth;
        const height = window.innerHeight;

        const maxSize = d3.max(words, d => d.size);
        const minSize = d3.min(words, d => d.size);

        const scale = d3.scalePow().exponent(0.5)
            .domain([minSize, maxSize])
            .range([10, Math.min(width, height) / 3]);

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
            erase();

            const svg = d3.select("#wordcloud").append("svg")
                .attr("width", width)
                .attr("height", height)
                .attr("viewBox", `0 0 ${width} ${height}`)
                .attr("preserveAspectRatio", "xMidYMid meet")
                .append("g")
                .attr("transform", "translate(" + width / 2 + "," + height / 2 + ")");

            const topWords = words.slice(0, 3).map(d => d.text);

            svg.selectAll("text")
                .data(words)
                .enter().append("text")
                .style("font-family", "Helvetica")
                .style("font-size", d => d.size + "px")
                .style("fill", d => topWords.includes(d.text) ? "#d95319" : "black")
                .attr("text-anchor", "middle")
                .attr("transform", d => "translate(" + [d.x, d.y] + ")rotate(0)")
                .text(d => d.text);
        }
    }

    function erase() {
        d3.select("#wordcloud").selectAll("*").remove();
    }
}