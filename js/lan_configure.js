function configWan() {
    let proto = document.getElementById("proto").value;
    let ip = document.getElementById("wanIP").value;
    let mask = document.getElementById("wanNetmask").value;
    let gateway = document.getElementById("gateway").value;
    let bcast = document.getElementById("bcast").value;
    let dns1 = document.getElementById("dns1").value;
    let dns2 = document.getElementById("dns2").value;
    let dev = document.getElementById("dev").value;

    if (!dev) {
        alert(t('network.device_required'));
        return false;
    }

    if (proto === "static") {
        if (!validateIP(ip)) {
            alert(t('network.invalid_ip'))
            return false;
        }

        if (!validateSubnetMask(mask)) {
            alert(t('network.invalid_subnet_mask'))
            return false;
        }
    }

    body += "&proto=" + encodeURIComponent(proto) +
        "&dev" + encodeURIComponent(dev) +
        "&IP" + encodeURIComponent(ip) +
        "&Netmask" + encodeURIComponent(mask);

    if (proto === "static") {
        if (gateway) {
            if (!validateIP(gateway)) {
                alert(t('network.invalid_gateway_ip'));
                return false;
            }
            body += "&gateway=" + encodeURIComponent(gateway);
        }
        if (bcast) {
            if (!validateIP(bcast)) {
                alert(t('network.invalid_broadcast'));
                return false;
            }
            body += "&bcast=" + encodeURIComponent(bcast);
        }
    }

    if (dns1) {
        body += "&dns1" + encodeURIComponent(dns1);
    }

    if (dns2) {
        body += "dns2" + encodeURIComponent(dns2);
    }

    let confirmation = confirm(t('network.confirm_restart_interfaces'))

    if (confirmation) {
        showLoading();
        fetch("/cgi-bin/config_wan.sh", {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: body
        })
            .then(response => {
                console.log('HTTP Status:', response.status);
                if (!response.ok) {
                    throw new Error('Network response was not ok: ' + response.statusText);
                }
                return response.text();
            })
            .then(data => {
                alert(t('common.done'))
                getCurWanIf();
                hideLoading();
            })
            .catch(error => {
                console.log("error");
                alert(t('common.error_generic'));
                hideLoading();
            });
    }
}

async function getCurWanIf() {
    try {
        const resp = await fetch('/cgi-bin/extract_wired_data.sh');
        const wiredData = await resp.json();
        const wan = wiredData.find(item => item.type === "WAN");

        let html = "";
        html += `<h1>${t('network.wan_config_title')}</h1>
                    <p class="description">${t('network.wan_config_desc')}</p>
                    <hr>`;
        const wanIP = document.getElementById("wanIP");
        if (wan && wan.iface) {
            html += `<p><strong>${t('cellular.device_colon')}</strong><span>${wan.iface || 'N/A'}</span></p>`
        }
        if (wan && wan.proto) {
            if (wan.proto === "dhcp") {
                wan.proto = t('common.dhcp_client');
            }
            html += `<p><strong>${t('cellular.connection_type_colon')}</strong><span>${wan.proto || 'N/A'}</span></p>`
        }
        if (wan && wan.IP) {
            html += `<p><strong>${t('cellular.ip_address_colon')}</strong><span>${wan.IP || 'N/A'}</span></p>`
        }
        if (wan && wan.netmask) {
            html += `<p><strong>${t('cellular.subnet_mask_colon')}</strong><span>${wan.netmask || 'N/A'}</span></p>`
        }
        if (wan && wan.gateway) {
            html += `<p><strong>${t('cellular.gateway_colon')}</strong><span>${wan.gateway || 'N/A'}</span></p>`
        }
        if (wan && wan.bcast) {
            html += `<p><strong>${t('network.broadcast_colon')}</strong><span>${wan.bcast || 'N/A'}</span></p>`
        }
        if (!wan) {
            html += `<p><strong>${t('network.no_wan_configured')}</strong></p>`
        }

        html += `
            <div class="wanForm">
             <label for="proto">${t('network.connection_type_label')}</label>
            <select class="proto-select" id="proto" name="proto" onchange="toggleIPConfig()">
                <option value="none">${t('common.none')}</option>
                <option value="dhcp">${t('network.dynamic_ip')}</option>
                <option value="static">${t('network.static_ip')}</option>
            </select>
            `
        html += `
            <form id="noneConfig" style="display: none;">
            </form>
            </div>
            `
        html += `
            <form id="dhcpConfig" style="display: none;">
                <label for="dev">${t('network.device_label')}</label>
                <select class="dev-select" id="dev" name="dev">
                <option value=""></option>
                </select>
                <br>
            </form>
            </div>
            <br>`
        html += `
            <form id="wanConfig" style="display: none;">
                <label for="wanIp">${t('network.ipv4_address_colon')}</label>
                <input type="text" id="wanIp" name="wanIp" required> <br>
                <br>
                <label for="wanNetmask">${t('network.ipv4_netmask_colon')}</label>
                <input type="text" id="wanNetmask" name="wanNetmask" required> <br>
                <br>
                <label for="gateway">${t('network.ipv4_gateway_colon')}</label>
                <input type="text" id="gateway" name="gateway"> <br>
                <br>
                <label for="broadcast">${t('network.ipv4_broadcast_colon')}</label>
                <input type="text" id="bcast" name="bcast"> <br>
                <br>
                <label for="dns">${t('network.primary_dns_colon')}</label>
                <input type="text" id="dns1" name="dns1"> <br>
                <br>
                <label for="dns">${t('network.secondary_dns_colon')}</label>
                <input type="text" id="dns2" name="dns2"> <br>
                <br>
            </form>
            </div>
            `
        html += `<button onclick="configWan()">${t('common.save')}</button>`
        wanIP.innerHTML = html;
        loadDev();
    }
    catch (err) {
        console.error("Failed to load WAN info:", err);
    }
}

function loadDev() {
    fetch('/cgi-bin/extract_wired_data.sh')
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            console.log("Successfully fetched data:", data);
            let dropdown = document.getElementById("dev");
            dropdown.innerHTML = "";

            data.forEach(dev => {
                if (dev.iface.startsWith("eth")) {
                    let option = document.createElement("option");
                    option.value = dev.iface;
                    option.textContent = dev.iface;
                    dropdown.appendChild(option);
                }
            })
        })
        .catch(error => {
            console.error("Error fetching interfaces:", error);
            document.getElementById("networkInterface").innerHTML = `<option>${t('network.error_loading')}</option>`;
        });
}

function toggleIPConfig() {
    const proto = document.getElementById('proto').value;
    const dhcpConfig = document.getElementById('dhcpConfig');
    const wanConfig = document.getElementById('wanConfig');
    const noneConfig = document.getElementById('noneConfig');
    const devDropdown = document.getElementById('dev');

    dhcpConfig.style.display = 'none';
    wanConfig.style.display = 'none';
    noneConfig.style.display = 'none';

    if (proto === 'dhcp') {
        dhcpConfig.style.display = 'block';
    } else if (proto === 'static') {
        dhcpConfig.style.display = 'block';
        wanConfig.style.display = 'block';
    } else if (proto === 'none') {
        noneConfig.style.display = 'block';
    }

}


function getCurLanIf() {
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
            html += `<h1>${t('network.lan_config_title')}</h1>
                    <p class="description">${t('network.lan_config_desc')}</p>
                    <hr>`;
            const curIP = document.getElementById("lanIP");
            //const curNetmask = document.getElementById("curNetmask");
            //const curDev = document.getElementById("curDev");
            const brLan = data.find(item => item.iface === "br-lan");
            if (brLan && brLan.IP) {
                html += `<div class="curIp"><p><strong>${t('network.current_ip_address_colon')}</strong><span>${brLan.IP || 'N/A'}</span></p>`
            }
            if (brLan && brLan.netmask) {
                html += `<p><strong>${t('network.current_subnet_mask_colon')}</strong><span>${brLan.netmask || 'N/A'}</span></p>`
            }
            if (brLan && brLan.iface) {
                html += `<p><strong>${t('cellular.device_colon')}</strong><span>${brLan.iface || 'N/A'}</span></p></div>`
            }
            html += `
            <form id="ipConfig">
                <label for="ip"><strong>${t('network.ipv4_address_colon')}</strong></label>
                <input type="text" id="ip" name="ip" required>

                <label for="netmask"><strong>${t('network.ipv4_netmask_colon')}</strong></label>
                <input type="text" id="netmask" name="netmask" required>

                <div class="form-actions">
                <button type="button" onclick="configIP()">${t('common.save')}</button>
                </div>
            </form>
            `
            curIP.innerHTML = html;
        });
}

function configIP() {
    let ip = document.getElementById("ip").value;
    let mask = document.getElementById("netmask").value;
    let gateway = document.getElementById("gateway").value;

    if (!ip || !mask) {
        alert(t('network.ip_mask_required'));
        return;
    }

    if (!validateIP(ip)) {
        alert(t('network.invalid_ip'));
        return false;
    }

    if (!validateSubnetMask(mask)) {
        alert(t('network.invalid_subnet_mask'));
        return false;
    }

    let body = "IP=" + encodeURIComponent(ip) +
        "&Netmask=" + encodeURIComponent(mask);

    if (gateway && !validateIP(gateway)) {
        alert(t('network.invalid_gateway_ip'));
        return false;
    }

    if (gateway) {
        body += "&gateway=" + encodeURIComponent(gateway);
    }

    let confirmation = confirm(t('network.confirm_restart_interfaces'))

    if (confirmation) {
        fetch("/cgi-bin/config_lan.sh", {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: body
        })
            .then(response => response.text())
            .then(data => {
                document.getElementById("result").innerText = t('network.response_prefix', { data: data });
            })
            .catch(error => {
                document.getElementById("result").innerText = t('common.error_prefix', { message: error });
            });
    }
}

function validateIP(ip) {
    // Regular expression for IPv4 address validation
    let ipPattern = /^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])){3}$/;
    return ipPattern.test(ip);
}

function validateSubnetMask(mask) {
    // Valid subnet masks in decimal notation
    const validMasks = [
        "255.0.0.0", "255.128.0.0", "255.192.0.0", "255.224.0.0", "255.240.0.0",
        "255.248.0.0", "255.252.0.0", "255.254.0.0", "255.255.0.0", "255.255.128.0",
        "255.255.192.0", "255.255.224.0", "255.255.240.0", "255.255.248.0",
        "255.255.252.0", "255.255.254.0", "255.255.255.0", "255.255.255.128",
        "255.255.255.192", "255.255.255.224", "255.255.255.240", "255.255.255.248",
        "255.255.255.252", "255.255.255.254", "255.255.255.255"
    ];
    return validMasks.includes(mask);
}

function refreshPage() {
    location.reload();
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
