function resetBoard() {
    const statusText = document.getElementById("status");
  
    let confirmation = confirm(`Saving and applying the changes will ERASE ALL YOUR SETTINGS and RESET TO FACTORY SETTINGS. Continue?`);

    if (confirmation) {
        fetch('/cgi-bin/reset.sh', {
        method: "POST"
        })
        .then(response => {
            if (response.ok) {
                showLoading();
                statusText.innerText = "Board reset triggered. Rebooting now...\nRefresh the web page when the board is ready...";
                setTimeout(() => {
                    checkDeviceReboot();
                }, 7000);
            } else {
                statusText.innerText = "Reset failed. Server responded with error.";
            }
        })
        .catch(error => {
        statusText.innerText = "Error contacting server: " + error;
        });
    }
  }

function showLoading(message = "Loading...") {
    let overlay = document.getElementById("loading-overlay");
    let loadingText = document.getElementById("loading-text");

    if (!overlay) {
        console.error("showLoading: loading-overlay not found!");
        return;
    }

    if (loadingText) {
        loadingText.textContent = message; 
    }

    overlay.classList.add("show");
}


function hideLoading() {
    let overlay = document.getElementById("loading-overlay");
    if (!overlay) {
        console.error("hideLoading: loading-overlay not found!");
        return;
    }
    overlay.classList.remove("show");
}

function checkDeviceReboot(attempts = 0) {
    fetch('/cgi-bin/get_wifi_config.sh', { method: 'GET', cache: 'no-store' })
    .then(response => {
        if (!response.ok) throw new Error("Device not ready");
        return response.json();
    })
    .then(data => {
        console.log("Device rebooted successfully!");
        hideLoading();
        getConfig(); 
    })
    .catch(() => {
        if (attempts < 30) {
            console.log(`Device not ready, retrying... (${attempts + 1})`);
            setTimeout(() => checkDeviceReboot(attempts + 1), 3000);
        } else {
            alert("Device took too long to reboot. Try refreshing manually.");
        }
    });
}
  