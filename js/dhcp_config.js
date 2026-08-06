function configDhcp() {
    let startIp = document.getElementById("startIp").value;
    let endIp = document.getElementById("endIp").value;
    let leasetime = document.getElementById("leasetime").value;
    let isEnabled = document.getElementById("dhcpToggle").value;
    let checkbox = document.getElementById("dhcpToggle");
    let body = "";

    if (checkbox.checked) {
        body += "isEnabled=" + encodeURIComponent(isEnabled);

        if (!validateIP(startIp)) {
            alert(t('network.invalid_ip'));
            return false;
        }
        body += "&startIp=" + encodeURIComponent(startIp);

        if (!validateIP(endIp)) {
            alert(t('network.invalid_ip'));
            return false;
        }
        body += "&endIp=" + encodeURIComponent(endIp);

        body += "&leasetime=" + encodeURIComponent(leasetime);

        //document.getElementById("bodyOutput").innerText = `<p>checked loop: ${body}`;
    } else {
        isEnabled = "disable";
        body += "isEnabled=" + encodeURIComponent(isEnabled);
        //document.getElementById("bodyOutput").innerText = `<p>unchecked loop: ${body}`;;
    }

    let confirmation = confirm(t('network.confirm_dhcp_changes'))

    if (confirmation) {
        fetch("/cgi-bin/config_dhcp.sh", {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: body
        })
            .then(response => response.text())
            .then(data => {
                location.reload();
                // document.getElementById("wanResult").innerText = "Response: " + data;
            })
            .catch(error => {
                // document.getElementById("wanResult").innerText = "Error: " + error;
            });
    }
}

function validateIP(ip) {
    let ipPattern = /^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])){3}$/;
    return ipPattern.test(ip);
}

function fetchCurDhcpConfig() {
    fetch('/cgi-bin/extract_dhcp_config.sh')
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            console.log("Successfully fetched data:", data);
            let html = "";
            isChecked = data.isEnabled === "Enabled" ? "checked" : "";
            html += `<div class="dhcp">
            <h1>${t('network.dhcp_config_title')}</h1>
            <p class="description">${t('network.dhcp_config_desc')}</p>
            <hr style="width:100%;text-align:left;margin-left:0">
            `
            const curDhcp = document.getElementById("curDhcp");
            if (data.isEnabled == "Enabled") {
                html += `
                <div class="container">
                <p id="isEnabled"><strong>${t('network.dhcp_server_colon')}</strong><span>${data.isEnabled || 'N/A'}</span></p>
                <p><strong>${t('network.current_lease_pool_colon')}</strong><span>${data.startIp || 'N/A'} - ${data.endIp || 'N/A'}</span></p>
                <p><strong>${t('network.current_lease_time_colon')}</strong><span>${data.leasetime || 'N/A'}${t('network.hours_suffix')}</span></p>
                </div>
                `
            } else if (data.isEnabled == "Disabled") {
                html += `
                <p><strong>${t('network.dhcp_server_colon')}</strong><span>${data.isEnabled || 'N/A'}</span></p>
                `
            }

            html += `
            <div class="dhcpToggle">
                <label class="switch">
                    <input type="checkbox" id="dhcpToggle" ${isChecked}>
                    <span class="slider round"></span>
                </label>
                <span class="toggle-label" id="toggle-label"><strong></strong></span>
            </div>

            <br>
            `

            html += `
            <div id="dhcpConfigWrapper">
                <form class=dhcpForm id="dhcpConfig">
                    <label for="startIp">${t('network.ip_address_pool_label')}</label>
                    <input type="text" id="startIp" name="startIp" required>
                    <label for="endIp">-</label>
                    <input type="text" id="endIp" name="endIp" required>
                    <br>
                    <label for="leasetime">${t('network.lease_time_colon')}</label>
                    <input type="number" id="leasetime" name="leasetime" required><span>${t('network.hours_suffix')}</span>
                </form>
                <br>
                <button id="dhcpSave" onclick="configDhcp()">${t('common.save')}</button>
                </div>
            </div>
            `;
            curDhcp.innerHTML = html;

            const dhcpCheckbox = document.getElementById('dhcpToggle');
            toggleDhcpConfig();

            dhcpCheckbox.addEventListener('change', function () {
                toggleDhcpConfig();

                if (!this.checked) {
                    userConfirm = confirm(t('network.confirm_disable_dhcp'))
                    if (userConfirm) {
                        disableDhcp();
                    }
                    else {
                        this.checked = true;
                        toggleDhcpConfig();
                    }
                }
            });
        })
        .catch(error => {
            console.error("Fetch Error:", error);
            document.getElementById("errorMessage").innerHTML = `<p style="color: red;">${t('common.error_prefix', { message: error.message })}</p>`;
        });
}

function toggleDhcpConfig() {
    const checkbox = document.getElementById("dhcpToggle");
    const configWrapper = document.getElementById("dhcpConfigWrapper");
    const label = document.getElementById("toggle-label");

    if (checkbox.checked) {
        configWrapper.style.display = "block";
        label.innerHTML = `<strong>${t('network.dhcp_server_enabled')}</strong>`;
    }
    else {
        configWrapper.style.display = "none";
        label.innerHTML = `<strong>${t('network.dhcp_server_disabled')}</strong>`;
    }
}

function disableDhcp() {
    showLoading(t('network.disabling_dhcp_server'));

    fetch('/cgi-bin/disable_dhcp.sh')
        .then(response => {
            if (!response.ok) {
                throw new Error("Server returned 502 or 404");
            }
            return response.text();
        })
        .then(data => {
            if (data.trim() === "SUCCESS") {
                alert(t('network.dhcp_disabled_success'));
                setTimeout(() => {
                    location.reload();
                }, 2000);
            }
        })
        .catch(error => {
            console.error("Error:", error);
            alert(t('network.error_disabling_dhcp', { message: error.message }));
            document.getElementById('dhcpToggle').checked = true;
            toggleDhcpConfig();
        })
        .finally(() => {
            hideLoading();
        })
}

function fetchDchpClient() {
    fetch('/cgi-bin/extract_dhcp_clients.sh')
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            const clients = document.getElementById("client");
            let html = "";
            html += `
            <div class="dhcp">
            <h1>${t('network.dhcp_leases_title')}</h1>
            <p class="description">${t('network.dhcp_leases_desc')}</p>
            <hr style="width:100%;text-align:left;margin-left:0">`
            if (isJsonEmpty(data)) {
                html += `<h3>${t('network.no_client_info')}</h3></div>`;
                clients.innerHTML = html;
                return;
            }
            console.log("Successfully fetched data:", data);
            html += `
            <table>
                <tr>
                    <th>${t('common.hostname')}</th>
                    <th>${t('network.mac_short')}</th>
                    <th>${t('common.ip_address')}</th>
                    <th>${t('network.lease_expiration_date')}</th>
                </tr>
            `;
            data.forEach(client => {
                const hostname = client.hostname && typeof client.hostname === "string" && client.hostname.includes('*')
                    ? t('common.unknown')
                    : client.hostname || t('common.unknown');
                html += `
                <tr>
                    <td>${hostname}</td>
                    <td>${client.mac || t('common.unknown')}</td>
                    <td>${client.ip || t('common.unknown')}</td>
                    <td>${client.expDate || t('common.unknown')}</td>
                </tr>
                `;
            });
            html += `</table>
            <br>
            <button onclick="refreshPage()">${t('common.refresh')}</button>
            </div>`
            clients.innerHTML = html;
        })
        .catch(error => {
            console.error("Fetch Error:", error);
            document.getElementById("errorMessage").innerHTML = `<p style="color: red;">${t('common.error_prefix', { message: error.message })}</p>`;
        });
}

function showLoading(message) {
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

function isJsonEmpty(data) {
    return !data || data.length === 0 || (data.length === 1 && Object.keys(data[0]).length === 0);
}

function refreshPage() {
    location.reload();
}
