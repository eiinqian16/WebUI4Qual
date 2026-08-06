function uploadFirmware() {
    showLoading();
    const fileInput = document.getElementById("fwFile");
    if (!fileInput.files.length) {
        alert(t('restore.no_file_selected'));
        return;
    }

    const file = fileInput.files[0];

    fetch("/cgi-bin/upload_fw.sh", {
        method: "POST",
        headers: { "Content-Type": "application/octet-stream" },
        body: file
    })
    .then(res => res.json())
    .then(data => {
        hideLoading();
        document.getElementById("status").textContent = data.status;
        document.getElementById("md5sum").textContent = data.md5;
        document.getElementById("sha256sum").textContent = data.sha256;
        document.getElementById("popup").classList.remove("hidden");
    })
    .catch(err => {
        alert(t('restore.upload_failed', { error: err }))
        hideLoading();
    });
}

function confirmUpgrade() {
    showLoading();
    fetch("/cgi-bin/upgrade_fw.sh", { method: "POST" })
    .then(res => res.text())
    .then(txt => alert(txt))
    .catch(err => alert(t('firmware.upgrade_failed', { error: err })));
    closePopup();
}

function closePopup() {
    document.getElementById("popup").classList.add("hidden");
}

function showLoading(message) {
    if (message === undefined) message = t('firmware.flashing');
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