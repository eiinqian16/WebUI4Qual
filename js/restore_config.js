function backup_config() {
    fetch('/cgi-bin/backup_config.sh')
        .then(response => response.json())
        .then(data => {
            const local = document.getElementById("dlLocal");
            if (data.status === "success") {
                alert(t('restore.backup_created', { file: data.file }));
            } else {
                alert(t('restore.backup_failed'));
            }

            if (local.checked) {
                downloadConfig(data.filename);
            }
        })
        .catch(err => {
            console.error("Error running backup:", err);
            alert(t('restore.backup_script_error'));
        });
}

function uploadBackup() {
    showLoading();
    const fileInput = document.getElementById("backupFile");

    if (!fileInput.files.length) {
        alert(t('restore.no_file_selected'));
        return;
    }

    const file = fileInput.files[0];
    fetch("/cgi-bin/upload_backup.sh", {
        method: "POST",
        headers: { "Content-Type": "application/octet-stream" },
        body: file
    })
    .then(res => res.json())
    .then(data => {
        hideLoading();
        document.getElementById("md5sum").textContent = data.md5;
        document.getElementById("sha256sum").textContent = data.sha256;
        document.getElementById("backup-popup").classList.remove("hidden");
    })
    .catch(err => {
        alert(t('restore.upload_failed', { error: err }))
        hideLoading();
    });
}

function confirmBackup() {
    fetch("/cgi-bin/restore_config.sh")
        .then(response => response.json())
        .then(data => {
            if (data.status === "success") {
                alert(t('restore.restore_success'))
                waitForReboot();
            }
            else {
                alert(t('restore.restore_failed', { error: data.error || t('wireless.unknown_error') }));
            }
        })
}

function downloadConfig(filename) {
    if(!filename) {
        alert(t('restore.no_backup_found'));
    }

    const encodedFilename = encodeURIComponent(filename);

    const link = document.createElement("a");
    link.href = `cgi-bin/download_backup.sh?file=${encodedFilename}`;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
}

function closePopup() {
    document.getElementById("backup-popup").classList.add("hidden");
}

function waitForReboot() {
    const checkInterval = 5000; 
    const timeout = 180000;
    const start = Date.now();

    const interval = setInterval(() => {
        fetch("/")
            .then(response => {
                if (response.ok) {
                    clearInterval(interval);
                    hideLoading()
                    window.location.href = "/login.html";
                    console.log("Router is back online!");
                    location.reload();
                }
            })
            .catch(() => {
                // still rebooting...
                if (Date.now() - start > timeout) {
                    clearInterval(interval);
                    alert(t('restore.router_offline'));
                }
            });
    }, checkInterval);
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
