function setup(htmlComponent) {
    previousData = {};
    eventSource = {};

    changingCell = {};
    cellRow = {};
    cellCol = {};

    table = document.querySelector("table");
    rows = table.getElementsByTagName("tr");
    columnType = document.head.getElementsByTagName("meta")["column-type"].getAttribute("content").split(",");

    for (let ii = 0; ii < rows.length; ii++) {
        previousData[ii] = {};
        const cells = rows[ii].getElementsByTagName("td");
        for (let jj = 0; jj < cells.length; jj++) {
            previousData[ii][jj] = {};

            if (cells[jj].contentEditable == "true") {
                cells[jj].addEventListener("blur", function (event) { blurEvent(htmlComponent); });
                previousData[ii][jj] = cells[jj].innerText;
            }
        }

        if (ii >%s 0) {
            rows[ii].addEventListener("click", function (event) { clickEvent(event, htmlComponent); });
        }
    }

    table.addEventListener("keydown", function (event) { keydownEvent(event); });
    table.addEventListener("input", function (event) { inputEvent(event); });

    htmlComponent.addEventListener("DataChanged", function (event) { mat2jsCallbacks(event); });
}

// SelectionChanged_js2matlab
function clickEvent(event, htmlComponent) {
    eventSource = event.target;
    if ((eventSource.tagName != "TD" && eventSource.tagName != "TH") || !eventSource.parentElement || eventSource.parentElement.tagName != "TR") {
        return;
    }
    const Selection = eventSource.parentElement.rowIndex;
    if (rows[Selection].classList.contains("selected")) {
        return;
    } else {
        CellEditCallback(htmlComponent);
        updateData(Selection);

        htmlComponent.Data = {
            Event: "SelectionChanged_js2mat",
            Value: Selection
        };
    }
}

function updateData(Selection) {
    for (let ii = 0; ii < rows.length; ii++) {
        if (rows[ii].classList.contains("selected")) {
            rows[ii].classList.remove("selected");
        };
    }
    rows[Selection].classList.add("selected");
}

// CellEdited_js2mat
function keydownEvent(event) {
    eventSource = event.target;
    if (eventSource.tagName != "TD" || !eventSource.parentElement || eventSource.parentElement.tagName != "TR") {
        return;
    };
    cellRow = eventSource.parentElement.rowIndex;
    cellCol = eventSource.cellIndex;
    if (event.keyCode == 13 && !event.shiftKey) {
        eventSource.blur();
    }
}

function inputEvent(event) {
    const cellID = `(${cellRow}, ${cellCol})`;
    if ((Object.keys(changingCell).length == 0) || (changingCell[0] != cellID)) {
        changingCell = [cellID, eventSource.innerText];
    } else {
        changingCell[1] = eventSource.innerText;
    }
}

function blurEvent(htmlComponent) {
    if (!table.contains(document.activeElement)) {
        CellEditCallback(htmlComponent);
    }
}

function CellEditCallback(htmlComponent) {
    if (Object.keys(changingCell).length == 0) {
        return
    };
    var newValue;
    switch (columnType[cellCol]) {
        case "text":
            newValue = changingCell[1];
            break;
        case "numeric":
            newValue = parseFloat(changingCell[1]);
            if (String(newValue) != changingCell[1]) {
                newValue = NaN;
            };
            break;
    };
    if (changingCell[1].length == 0 || (columnType[cellCol] == "numeric" && isNaN(newValue))) {
        table.rows[cellRow].cells[cellCol].innerText = previousData[cellRow][cellCol];
    } else {
        if (changingCell[1] != previousData[cellRow][cellCol]) {
            htmlComponent.Data = {
                Event: "CellEdited_js2mat",
                Value: {
                    Row: cellRow,
                    Column: cellCol + 1,
                    PreviousValue: previousData[cellRow][cellCol],
                    Value: newValue
                }
            };
            previousData[cellRow][cellCol] = changingCell[1];
            changingCell = {};
        };
    };
}

// SelectionChanged_mat2js
function mat2jsCallbacks(event) {
    if (event.Data != "") {
        switch (event.Data.Event) {
            case "SelectionChanged_mat2js":
                updateData(event.Data.Value);
                break;
        };
    };
}