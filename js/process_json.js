function loadTime() {
    const now = new Date();
    const options = {
        day: 'numeric',
        month: 'short',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        hour12: false
    };

    const formatted = now.toLocaleString('en-GB', options).replace(',', '');
    const dateElem = document.getElementById("overview-date");
    if (dateElem) {
        dateElem.textContent = formatted;
    }
}

function fetchSysStats() {
    fetch('/cgi-bin/extract_system_info.sh')
        .then(response => {

            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();

        })
        .then(data => {
            console.log("Successfully fetched data:", data);


            const percentAvailMem = ((data.memAvail / data.memTotal * 100).toFixed(2));
            const percentUsedMem = ((data.memUsed / data.memTotal * 100).toFixed(2));
            const percentCache = ((data.cache / data.memTotal * 100).toFixed(2));
            const sysInfo = document.getElementById("sys");

            let html = `
                <div class="status-item">
                    <span class="status-label">${t('overview.model')}</span>

                    <span class="status-value"> ${data.model || 'N/A'}</span>
                </div>
                <div class="status-item">
                    <span class="status-label">${t('overview.firmware_version')}</span>

                    <span class="status-value"> ${data.fw_version || 'N/A'}</span>
                </div>
                <div class="status-item">
                    <span class="status-label">${t('overview.host')}</span>

                    <span class="status-value"> ${data.host || 'N/A'}</span>
                </div>
                <div class="status-item">
                    <span class="status-label">${t('overview.architecture')}</span>

                    <span class="status-value"> ${data.arch || 'N/A'}</span>
                </div>
                <div class="status-item">

                    <span class="status-label">${t('overview.target_platform')}</span>
                    <span class="status-value"> ${data.target || 'N/A'}</span>
                </div>
                <div class="status-item">

                    <span class="status-label">${t('overview.kernel_version')}</span>
                    <span class="status-value"> ${data.kernel || 'N/A'}</span>
                </div>
                <div class="status-item">

                    <span class="status-label">${t('overview.date')}</span>
                    <span class="status-value" id="overview-date"></span>
                </div>
                <br>
                <h3>${t('overview.memory')}</h3>
                <div class="memory-item">
                    <span class="memory-label">${t('overview.total_available')}</span>

                    <progress class="memory-progress" value="${data.memAvail}" max="${data.memTotal}"></progress>
                    <span class="memory-value">${(data.memAvail / 1000).toFixed(2)}MB / ${(data.memTotal / 1000).toFixed(2)}MB (${percentAvailMem}%)</span>
                </div>
                <div class="memory-item">

                    <span class="memory-label">${t('overview.used')}</span>
                    <progress class="memory-progress" value="${data.memUsed}" max="${data.memTotal}"></progress>
                    <span class="memory-value">${(data.memUsed / 1000).toFixed(2)}MB / ${(data.memTotal / 1000).toFixed(2)}MB (${percentUsedMem}%)</span>
                </div>
            `;


            sysInfo.innerHTML = html;
            loadTime();
        })
        .catch(error => {
            console.error("Fetch Error:", error);

            document.getElementById("errorMessage").innerHTML = `<p style="color: red;">${t('common.error_prefix', { message: error.message })}</p>`;
        });
}
setInterval(loadTime, 1000);

function fetchStorageStats() {
    const storeInfo = document.getElementById("storage");
    const errorMessage = document.getElementById("errorMessage");

    fetch('/cgi-bin/extract_system_info.sh')
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            console.log("Successfully fetched data:", data);

            const totStorage = data.totStorage || 0;
            const usedStorage = data.usedStorage || 0;
            const perStorage = totStorage > 0 ? ((usedStorage / totStorage) * 100).toFixed(2) : 0;

            const totTmp = data.totTmp || 0;
            const usedTmp = data.usedTmp || 0;
            const perTmp = totTmp > 0 ? ((usedTmp / totTmp) * 100).toFixed(2) : 0;

            const fwTotMem = data.fwTotMem || 0;
            const fwUsedMem = data.fwUsedMem || 0;
            const perFwMem = fwTotMem > 0 ? ((fwUsedMem / fwTotMem) * 100).toFixed(2) : 0;

            function formatSize(sizeKB) {
                if (sizeKB > 1024 * 1024) {
                    return (sizeKB / 1024 / 1024).toFixed(2) + " GB";
                } else if (sizeKB > 1024) {
                    return (sizeKB / 1024).toFixed(2) + " MB";
                } else {
                    return sizeKB + " KB";
                }
            }

            function renderStorageItem(label, used, total, percent) {
                return `
                    <div class="storage-item">
                        <span class="storage-label">${label}</span>
                        <progress class="storage-progress" value="${used}" max="${total}"></progress>
                        <span class="storage-value">${formatSize(used)} / ${formatSize(total)} (${percent}%)</span>
                    </div>
                `;
            }


            let html = `
                <h3>${t('overview.storage')}</h3>
                ${renderStorageItem(t('overview.disk_space'), usedStorage, totStorage, perStorage)}
                ${renderStorageItem(t('overview.temp_space'), usedTmp, totTmp, perTmp)}
            `;

            storeInfo.innerHTML = html;
            errorMessage.innerHTML = ""; 

        })
        .catch(error => {
            console.error("Fetch Error:", error);
            errorMessage.innerHTML = `<p style="color: red;">${t('common.error_prefix', { message: error.message })}</p>`;
            storeInfo.innerHTML = "";
        });
}

function fetchLanStatus() {
    fetch('/cgi-bin/extract_wired_data.sh')
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            console.log("Successfully fetched data:", data);
            let html = "";
            data.forEach(iface => { 
                if (iface.type === "LAN") {
                    const lanstat = document.getElementById("lan");
                    html += `
                    <div class="interface">
                        <h3><strong>${iface.iface || 'N/A'}</strong> </h3>
                        <p><strong>${t('common.mac_address')}:</strong> <span>${iface.MAC || 'N/A'}</span></p>
                        <p><strong>${t('common.ip_address')}:</strong> <span>${iface.IP || 'N/A'}</span></p>
                        <p><strong>${t('common.subnet_mask')}:</strong><span> ${iface.netmask || 'N/A'}</span></p>
                        <p><strong>${t('common.protocol')}:</strong> <span>${iface.proto || 'N/A'}</span></p>
                        <p><strong>${t('common.interface_type')}:</strong> <span>${iface.type || 'N/A'}</span></p>
                        <p><strong>${t('common.tx_packets')}:</strong> <span>${iface.txpkt || 'N/A'}</span></p>
                        <p><strong>${t('common.rx_packets')}:</strong> <span>${iface.rxpkt || 'N/A'}</span></p>
                        <p><strong>${t('common.tx_bytes')}:</strong> <span>${iface.txbytes || 'N/A'}</span></p>
                        <p><strong>${t('common.rx_bytes')}:</strong> <span>${iface.rxbytes || 'N/A'}</span></p>
                    </div>
                    `;
                    lanstat.innerHTML = html;
                }
            });
            
        })
        .catch(error => {
            console.error("Fetch Error:", error);
            document.getElementById("errorMessage").innerHTML = `<p style="color: red;">${t('common.error_prefix', { message: error.message })}</p>`;
        });
}

function fetchWanStatus() {
    fetch('/cgi-bin/extract_wired_data.sh')
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            console.log("Successfully fetched data:", data);
            const wanIf = data.find(iface => iface.type === "WAN");
            const wanstat = document.getElementById("wan");
            let html = "";
            if (wanIf) {
            data.forEach(iface => {
                if (iface.proto === "dhcp") {
                    iface.proto = t('common.dhcp_client');
                }
                if (iface.type === "WAN") {
                html += `
                <div class="interface">
                    <h3><strong>${iface.iface || 'N/A'}</strong></h3>
                    <p><strong>${t('common.mac_address')}:</strong><span>${iface.MAC || 'N/A'}</span></p>
                    <p><strong>${t('common.ip_address')}:</strong> <span>${iface.IP || 'N/A'}</span></p>
                    <p><strong>${t('common.subnet_mask')}:</strong> <span>${iface.netmask || 'N/A'}</span></p>
                    <p><strong>${t('common.protocol')}:</strong> <span>${iface.proto || 'N/A'}</span></p>
                    <p><strong>${t('common.interface_type')}:</strong> <span>${iface.type || 'N/A'}</span></p>
                    <p><strong>${t('common.tx_packets')}:</strong> <span>${iface.txpkt || 'N/A'}</span></p>
                    <p><strong>${t('common.rx_packets')}:</strong> <span>${iface.rxpkt || 'N/A'}</span></p>
                    <p><strong>${t('common.tx_bytes')}:</strong> <span>${iface.txbytes || 'N/A'}</span></p>
                    <p><strong>${t('common.rx_bytes')}:</strong> <span>${iface.rxbytes || 'N/A'}</span></p>
                </div>
                `;
                }
            });
            wanstat.innerHTML = html;
        } else {
            wanstat.innerHTML = `<p>${t('network.no_wan_interface')}</p>`;
        }
            
        })
        .catch(error => {
            console.error("Fetch Error:", error);
            document.getElementById("errorMessage").innerHTML = `<p style="color: red;">${t('common.error_prefix', { message: error.message })}</p>`;
        });
}

function fetchOthStatus() {
    fetch('/cgi-bin/extract_wired_data.sh')
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            console.log("Successfully fetched data:", data);
            let html = "";
            data.forEach(iface => { 
                if (iface.type === "other") {
                    const lanstat = document.getElementById("other");
                    html += `
                    <div class="interface">
                        <h3><strong>${iface.iface || 'N/A'}</strong></h3>
                        <p><strong>${t('common.mac_address')}:</strong><span>${iface.MAC || 'N/A'}</span></p>
                        <p><strong>${t('common.ip_address')}:</strong> <span>${iface.IP || 'N/A'}</span></p>
                        <p><strong>${t('common.subnet_mask')}:</strong> <span>${iface.netmask || 'N/A'}</span></p>
                        <p><strong>${t('common.protocol')}:</strong> <span>${iface.proto || 'N/A'}</span></p>
                        <p><strong>${t('common.tx_packets')}:</strong> <span>${iface.txpkt || 'N/A'}</span></p>
                        <p><strong>${t('common.rx_packets')}:</strong> <span>${iface.rxpkt || 'N/A'}</span></p>
                        <p><strong>${t('common.tx_bytes')}:</strong> <span>${iface.txbytes || 'N/A'}</span></p>
                        <p><strong>${t('common.rx_bytes')}:</strong> <span>${iface.rxbytes || 'N/A'}</span></p>
                    </div>
                    `;
                    lanstat.innerHTML = html;
                }
            });
            
        })
        .catch(error => {
            console.error("Fetch Error:", error);
            document.getElementById("errorMessage").innerHTML = `<p style="color: red;">${t('common.error_prefix', { message: error.message })}</p>`;
        });
}

function refreshStatus() {
    fetchLanStatus();
}
