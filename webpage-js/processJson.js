function fetchStorageStats() {
    const storeInfo = document.getElementById("storage");
    const errorMessage = document.getElementById("errorMessage"); // Get error message element

    fetch('/cgi-bin/extract_system_info.sh')
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            console.log("Successfully fetched data:", data);

            // Calculate percentages, handling potential undefined values:
            const totStorage = data.totStorage || 0; // Default to 0 if undefined
            const usedStorage = data.usedStorage || 0;
            const perStorage = totStorage > 0 ? ((usedStorage / totStorage) * 100).toFixed(2) : 'N/A';

            const totTmp = data.totTmp || 0;
            const usedTmp = data.usedTmp || 0;
            const perTmp = totTmp > 0 ? ((usedTmp / totTmp) * 100).toFixed(2) : 'N/A';

            const fwTotMem = data.fwTotMem || 0;
            const fwUsedMem = data.fwUsedMem || 0;
            const perFwMem = data.perFwMem > 0 ? ((fwUsedMem / fwTotMem) * 100).toFixed(2) : 'N/A'

            let html = `
                <h3>Storage</h3>
                <div class="status-item">
                    <span class="status-label">Disk Space</span>
                    <span class="status-value"> ${(usedStorage/1000).toFixed(2)}MB / ${(totStorage/1000).toFixed(2)}MB (${perStorage}%)</span>
                </div>
                <div class="status-item">
                    <span class="status-label">Tmp Space</span>
                    <span class="status-value"> ${(usedTmp/1000).toFixed(2)}MB / ${(totTmp/1000).toFixed(2)}MB (${perTmp}%)</span>
                </div>
                <div class="status-item">
                    <span class="status-label">${data.fwBlk} (${data.fwDir})</span>
                    <span class="status-value"> ${fwUsedMem}KB / ${fwTotMem}KB (${perFwMem}%)</span>
                </div>
            `;

            storeInfo.innerHTML = html;
            errorMessage.innerHTML = ""; // Clear any previous error messages

        })
        .catch(error => {
            console.error("Fetch Error:", error);
            errorMessage.innerHTML = `<p style="color: red;">Error: ${error.message}</p>`;
            storeInfo.innerHTML = ""; // Clear storage info if there's an error
        });
}

function fetchSysStats() {
    fetch('/cgi-bin/extract_system_info.sh')
        .then(response =>{
            if(!response.ok) {
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
                    <span class="status-label">Model</span>
                    <span class="status-value"> ${data.model || 'N/A'}</span>
                </div>
                <div class="status-item">
                    <span class="status-label">Host</span>
                    <span class="status-value"> ${data.host || 'N/A'}</span>
                </div>
                <div class="status-item">
                    <span class="status-label">Architecture</span>
                    <span class="status-value"> ${data.arch || 'N/A'}</span>
                </div>
                <div class="status-item">
                    <span class="status-label">Target Platform</span>
                    <span class="status-value"> ${data.target || 'N/A'}</span>
                </div>
                <div class="status-item">
                    <span class="status-label">Kernel Version</span>
                    <span class="status-value"> ${data.kernel || 'N/A'}</span>
                </div>
                <div class="status-item">
                    <span class="status-label">Date</span>
                    <span class="status-value"> ${data.date || 'N/A'}</span>
                </div>
                <h3>Memory</h3>
                <div class="status-item">
                    <span class="status-label">Total Available</span>
                    <span class="status-value"> ${(data.memAvail/1000).toFixed(2) || 'N/A'}MB / ${(data.memTotal/1000).toFixed(2) || 'N/A'}MB (${percentAvailMem}%)</span>
                </div>
                <div class="status-item">
                    <span class="status-label">Used</span>
                    <span class="status-value"> ${(data.memUsed/1000).toFixed(2) || 'N/A'}MB / ${(data.memTotal/1000).toFixed(2) || 'N/A'}MB (${percentUsedMem}%)</span>
                </div>
                <div class="status-item">
                    <span class="status-label">Cached</span>
                    <span class="status-value"> ${(data.cache/1000).toFixed(2) || 'N/A'}MB / ${(data.memTotal/1000).toFixed(2) || 'N/A'}MB (${percentCache}%)</span>
                </div>

                    
            `;
            sysInfo.innerHTML = html;
            
        })
        .catch(error => {
            console.error("Fetch Error:", error);
            document.getElementById("errorMessage").innerHTML = `<p style="color: red;">Error: ${error.message}</p>`;
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
            // Display network status
            let html = "";
            data.forEach(iface => { 
                if (iface.type === "LAN") {
                    const lanstat = document.getElementById("lan");
                    html += `
                    <div class="interface"> 
                        <h2><strong>${iface.iface || 'N/A'}</strong> </h2>
                        <p><strong>MAC Address:</strong> <span>${iface.MAC || 'N/A'}</span></p>
                        <p><strong>IP Addr:</strong> <span>${iface.IP || 'N/A'}</span></p>
                        <p><strong>Subnet Mask:</strong><span> ${iface.netmask || 'N/A'}</span></p>
                        <p><strong>Protocol:</strong> <span>${iface.proto || 'N/A'}</span></p>
                        <p><strong>Interface Type:</strong> <span>${iface.type || 'N/A'}</span></p>
                        <p><strong>TX Packets:</strong> <span>${iface.txpkt || 'N/A'}</span></p>
                        <p><strong>RX Packets:</strong> <span>${iface.rxpkt || 'N/A'}</span></p>
                        <p><strong>TX Bytes:</strong> <span>${iface.txbytes || 'N/A'}</span></p>
                        <p><strong>RX Bytes:</strong> <span>${iface.rxbytes || 'N/A'}</span></p>
                    </div>
                    `;
                    lanstat.innerHTML = html;
                }
            });
            
        })
        .catch(error => {
            console.error("Fetch Error:", error);
            document.getElementById("errorMessage").innerHTML = `<p style="color: red;">Error: ${error.message}</p>`;
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
            // Display network status
            let html = "";
            if (wanIf) {
            data.forEach(iface => {
                if (iface.type === "WAN") {
                html += `
                <div class="interface">
                    <h2><strong>${iface.iface || 'N/A'}</strong></h2>
                    <p><strong>MAC Address:</strong><span>${iface.MAC || 'N/A'}</span></p>
                    <p><strong>IP Addr:</strong> <span>${iface.IP || 'N/A'}</span></p>
                    <p><strong>Subnet Mask:</strong> <span>${iface.netmask || 'N/A'}</span></p>
                    <p><strong>Protocol:</strong> <span>${iface.proto || 'N/A'}</span></p>
                    <p><strong>Interface Type:</strong> <span>${iface.type || 'N/A'}</span></p>
                    <p><strong>TX Packets:</strong> <span>${iface.txpkt || 'N/A'}</span></p>
                    <p><strong>RX Packets:</strong> <span>${iface.rxpkt || 'N/A'}</span></p>
                    <p><strong>TX Bytes:</strong> <span>${iface.txbytes || 'N/A'}</span></p>
                    <p><strong>RX Bytes:</strong> <span>${iface.rxbytes || 'N/A'}</span></p>
                </div>
                `;
                }
            });
            wanstat.innerHTML = html;
        } else {
            wanstat.innerHTML = `<p>No WAN interface configured</p>`;
        }
            
        })
        .catch(error => {
            console.error("Fetch Error:", error);
            document.getElementById("errorMessage").innerHTML = `<p style="color: red;">Error: ${error.message}</p>`;
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
            // Display network status
            let html = "";
            data.forEach(iface => { 
                if (iface.type === "other") {
                    const lanstat = document.getElementById("other");
                    html += `
                    <div class="interface">
                        <h2><strong>${iface.iface || 'N/A'}</strong></h2>
                        <p><strong>MAC Address:</strong><span>${iface.MAC || 'N/A'}</span></p>
                        <p><strong>IP Addr:</strong> <span>${iface.IP || 'N/A'}</span></p>
                        <p><strong>Subnet Mask:</strong> <span>${iface.netmask || 'N/A'}</span></p>
                        <p><strong>Protocol:</strong> <span>${iface.proto || 'N/A'}</span></p>
                        <p><strong>TX Packets:</strong> <span>${iface.txpkt || 'N/A'}</span></p>
                        <p><strong>RX Packets:</strong> <span>${iface.rxpkt || 'N/A'}</span></p>
                        <p><strong>TX Bytes:</strong> <span>${iface.txbytes || 'N/A'}</span></p>
                        <p><strong>RX Bytes:</strong> <span>${iface.rxbytes || 'N/A'}</span></p>
                    </div>
                    `;
                    lanstat.innerHTML = html;
                }
            });
            
        })
        .catch(error => {
            console.error("Fetch Error:", error);
            document.getElementById("errorMessage").innerHTML = `<p style="color: red;">Error: ${error.message}</p>`;
        });
}

function fetchWiFiStatus() {
    fetch('/cgi-bin/extract_iwconfig_v2.sh')
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            console.log("Successfully fetched data:", data);

            let networksFound = {"2g": false, "5g": false, "6g": false};
            // Display network status
            let html = "";
            data.forEach(network => { 
                const statusDiv = document.getElementById("wireless");
                if (network.Network === "2G") {
                    //statusDiv = document.getElementById("2gstatus");
                    networksFound["2g"] = true;
                } else if (network.Network === "5G") {
                    //statusDiv = document.getElementById("5gstatus");
                    networksFound["5g"] = true;
                } else if (network.Network === "6G") {
                    //statusDiv = document.getElementById("6gstatus");
                    networksFound["6g"] = true;
                } else {
                    console.warn("Unknown network");
                }
                html += `
                <div class="interface">
                    <h2>${network.Network} WiFi (${network.iface})</h2>
                    <h4>SSID: ${network.ESSID || 'N/A'}</h4>
                    <p><strong>Mode:</strong> ${network.Mode || 'N/A'}</p>
                    <p><strong>Frequency:</strong> ${network.Frequency || 'N/A'}</p>
                    <p><strong>Access Point:</strong> ${network.AccessPoint || 'N/A'}</p>
                    <p><strong>Bitrate:</strong> ${network.BitRate || 'N/A'}</p>
                    <p><strong>TxPower:</strong> ${network.TxPower || 'N/A'}</p>
                    <p><strong>Encryption Key:</strong> ${network.EncryptionKey || 'N/A'}</p>
                    <p><strong>Signal Level:</strong> ${network.SignalLevel || 'N/A'}</p>
                    <p><strong>Noise Level:</strong> ${network.NoiseLevel || 'N/A'}</p>
                    <p><strong>MAC Address:</strong> ${network.macAddr || 'N/A'}</p>
                </div>
                `;
                wireless.innerHTML = html;
                
            });
            Object.keys(networksFound).forEach(key => {
                if(!networksFound[key]){
                    let disabled = document.getElementById("disabled");
                    if (disabled) {
                        disabled.innerHTML=`
                        <div class="interface">
                        <p>${key} WiFi Disabled</p>
                        </div>
                        `;
                    }
                }
            })
        })
        .catch(error => {
            console.error("Fetch Error:", error);
            document.getElementById("errorMessage").innerHTML = `<p style="color: red;">Error: ${error.message}</p>`;
        });
}

// Function to refresh JSON data
function refreshStatus() {
    fetchWiFiStatus();
    fetchLanStatus();
}
