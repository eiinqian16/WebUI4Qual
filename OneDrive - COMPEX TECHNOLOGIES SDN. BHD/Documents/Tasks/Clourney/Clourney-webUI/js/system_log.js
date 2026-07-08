function loadTime() {
    const now = new Date();
     const dateElem = document.getElementById("date");
    if (dateElem) {
        dateElem.innerHTML = `<p>Current Date: ${now.toLocaleString()}</p>`;
    }
}
setInterval(loadTime, 1000);

async function getLog() {
    try{
        const resp = await fetch("/cgi-bin/get_sys_log.sh");
        if(!resp.ok) throw new Error("Failed to fetch log");
        const data = await resp.text();
        return data;
    } catch (err) {
        console.error("Failed to get logs:", err);
        return "Error fetching log";
    }
}

async function refreshLog() {
    const spinner = document.getElementById("loading-spinner");
    spinner.classList.remove("hidden"); // show spinner

    try {
        const logData = await getLog();
        document.getElementById("logBox").textContent = logData;
        await new Promise(resolve => setTimeout(resolve, 2000));
    } catch (err) {
        console.error("Failed to refresh log:", err);
    } finally {
        spinner.classList.add("hidden"); // hide spinner
    }
}

function clearLogs() {
    const log = document.getElementById("logBox");
    log.value = "";
}

let timer = null;

function stopAutoUpdate() {
    if (timer) clearInterval(timer);
    timer = null;
}

function autoUpdate() {
    stopAutoUpdate();
    getLog();
    timer = setInterval(getLog, 3000);
}

async function loadPage() {
    const logData = await getLog();
    const bLog= document.getElementById("logBox");
    let html = "";
    html += `${logData}`
    bLog.innerHTML = html;
}

function escapeHtml(text) {
    return text
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");
}

let matches = [];
let currentMatch = 0;
let totalMatch = 0;

function searchLog() {
    const input = document.getElementById("search").value.trim();
    const logBox = document.getElementById("logBox");

    // Save original HTML only once
    if (!logBox.dataset.original) {
        logBox.dataset.original = logBox.textContent;
    }

    const originalText = logBox.dataset.original;

    // If search box is empty → restore original text
    if (!input) {
        logBox.textContent = originalText;
        document.getElementById("resultCount").textContent = "";
        matches = [];
        return;
    }

    const escapedInput = input.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const regex = new RegExp(`(${escapedInput})`, "gi");

    const escapedText = escapeHtml(originalText);
    const highlighted = escapedText.replace(regex, "<mark>$1</mark>");
    logBox.innerHTML = highlighted;

    matches = Array.from(logBox.querySelectorAll("mark"));
    totalMatch = matches.length;
    currentMatch = totalMatch > 0 ? 1 : 0;

    if (totalMatch > 0) highlightCurrentMatch();
    document.getElementById("resultCount").textContent = `${totalMatch} results`;
    document.getElementById("nextButton").innerHTML = `<button id="toggle" onclick="nextMatch()">Prev</button>`;
    document.getElementById("prevButton").innerHTML = `<button id="toggle" onclick="prevMatch()">Next</button>`;
}

function highlightCurrentMatch() {
    if (matches.length === 0) return;

    matches.forEach(m => m.classList.remove("active-match"));

    const current = matches[currentMatch - 1];
    current.classList.add("active-match");
    current.scrollIntoView({ behaviour: "smooth", block: "center"});

    document.getElementById("resultCount").textContent = `Results: ${currentMatch} / ${totalMatch}`;
}

function nextMatch() {
    if (matches.length === 0) return;
    currentMatch = (currentMatch - 2 + totalMatch) % totalMatch + 1;
    highlightCurrentMatch();
}

function prevMatch() {
    if (matches.length === 0) return;
    currentMatch = currentMatch % totalMatch + 1;
    highlightCurrentMatch();
}

var input = document.getElementById("search");
input.addEventListener("keypress", function (event) {
    if (event.key === "Enter") {
        event.preventDefault();
        searchLog();
    }
});

function downloadLog() {
    const link = document.createElement("a");
    link.href = "cgi-bin/download_syslog.sh";
    link.download = "syslog.txt";
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
}