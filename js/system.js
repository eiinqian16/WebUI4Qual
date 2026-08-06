function resetBoard() {
    const statusText = document.getElementById("reset-status") || document.getElementById("status");

    let confirmation = confirm(t('system.confirm_factory_reset'));

    if (confirmation) {
        fetch('/cgi-bin/reset.sh', {
            method: "POST"
        })
            .then(response => {
                if (response.ok) {
                    showLoading();
                    statusText.innerText = t('system.reset_triggered');
                    setTimeout(() => {
                        checkDeviceReboot();
                    }, 7000);
                } else {
                    statusText.innerText = t('system.reset_failed');
                }
            })
            .catch(error => {
                statusText.innerText = t('system.error_contacting_server', { error: error });
            });
    }
}

function rebootBoard() {
    const statusText = document.getElementById("reboot-status") || document.getElementById("status");

    let confirmation = confirm(t('system.confirm_reboot'));

    if (confirmation) {
        showLoading();
        fetch('/cgi-bin/reboot.sh', {
            method: "POST"
        })
            .then(response => {
                if (response.ok) {
                    showLoading();
                    statusText.innerText = t('system.reboot_triggered');
                    setTimeout(() => {
                        checkDeviceReboot();
                    }, 7000);
                } else {
                    statusText.innerText = t('system.reset_failed');
                }
            })
            .catch(error => {
                statusText.innerText = t('system.error_contacting_server', { error: error });
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
                alert(t('wireless.reboot_timeout'));
            }
        });
}
