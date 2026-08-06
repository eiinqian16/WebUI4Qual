
function configWan() {
    let proto = document.getElementById("proto").value;
    let ip = document.getElementById("wanIp").value;
    let mask = document.getElementById("wanNetmask").value;
    let gateway = document.getElementById("gateway").value;
    let bcast = document.getElementById("bcast").value;
    let dns1 = document.getElementById("dns1").value;
    let dns2 = document.getElementById("dns2").value;
    let body = "";
    let dev;

    if (proto === "lte") {
        dev = document.getElementById("lteDev").value;
    } else {
        dev = document.getElementById("dev").value;
    }

    if (dev) {
        body += "dev=" + encodeURIComponent(dev);
    }

    if (proto) {
        body += "&proto=" + encodeURIComponent(proto);
    }

    if (proto === "dhcp" || proto === "static" || proto === "lte") {
        if (!dev) {
            alert(`Device is required for ${proto.toUpperCase()} configuration.`);
            return false;
        }
        if (!body.includes("dev=")) {
            body += "&dev=" + encodeURIComponent(dev);
        }
    }

    if (proto === "static") {
        if (!validateIP(ip)) {
            alert("Invalid IP address! Please enter correct IPv4 address.");
            return false;
        }
    }

    if (proto === "static") {
        if (!validateSubnetMask(mask)){
            alert("Invalid subnet mask! Please enter valid subnet mask.");
            return false;
        }
    }

    body += "&IP=" + encodeURIComponent(ip) +
            "&Netmask=" + encodeURIComponent(mask);

    if (proto === "static") {
        if (gateway) {
            if (!validateIP(gateway)) {
                alert("Invalid gateway IP address! Please enter a correct IPv4 address.");
                return false;
            }
            body += "&gateway=" + encodeURIComponent(gateway);
        }
    }

    if (proto === "static") {
        if (bcast) {
            if (!validateIP(bcast)) {
                alert("Invalid broadcast address! Please enter a correct broadcast address.");
                return false;
            }
            body += "&bcast=" + encodeURIComponent(bcast);
        }
    }

    if (dns1) {
        body += "&dns1=" + encodeURIComponent(dns1);
    }

    if (dns2) {
        body += "&dns2=" + encodeURIComponent(dns2);
    }

    if (proto === "lte") {
        const lteDev = document.getElementById("lteDev").value;
        const lteService = document.getElementById("lteService").value;
        const lteApn = document.getElementById("lteApn").value;
        const ltePin = document.getElementById("ltePin").value;
        const lteDial = document.getElementById("lteDial").value;
        const lteSimSlot = document.getElementById("lteSimSlot").value;
    
        if (!lteApn || !lteDev) {
            alert("APN and Modem Device are required for LTE configuration.");
            return false;
        }
    
        // Append LTE parameters to the POST body (ensure lowercase names match backend)
        body += "&lteDev=" + encodeURIComponent(lteDev) +
                "&lteService=" + encodeURIComponent(lteService) +
                "&lteApn=" + encodeURIComponent(lteApn) +
                "&ltePin=" + encodeURIComponent(ltePin) +
                "&lteDial=" + encodeURIComponent(lteDial) +
                "&lteSimSlot=" + encodeURIComponent(lteSimSlot);
    }

    let confirmation = confirm(`Saving and applying the changes will restart both network and WiFi interfaces. Continue?\n\nNote: Setting LTE/UMTS will reboot the device.`);

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
            alert('done.\n\nNote: Setting LTE/UMTS will reboot the device.');
            getCurWanIf();
            hideLoading();
        })
        .catch(error => {
            console.log("error");
            alert("error");
            hideLoading();
        });
    }
}

function getCurWanIf() {
    fetch('/cgi-bin/extract_wired_data.sh')
        .then(response => {
            if(!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data =>{
            console.log("Successfully fetched current WAN data:", data);
            
            let html = "";
            html += `<h1>WAN Configuration</h1>
                    <p class="description">View and configure Internet settings</p>
                    <hr>`;
            const wanIP = document.getElementById("wanIP");
            //const curNetmask = document.getElementById("curNetmask");
            //const curDev = document.getElementById("curDev");
            const wan = data.find(item => item.type === "WAN");
            if (wan && wan.iface) {
                html += `<p><strong>Device: </strong>${wan.iface || 'N/A'}</p>`
            }
            if (wan && wan.proto) {
                if (wan.proto === "dhcp") {
                    wan.proto = "DHCP client"
                }
                html += `<p><strong>Connection Type: </strong>${wan.proto || 'N/A'}</p>`
            }
            if (wan && wan.IP) {
                html += `<p><strong>IP Address: </strong>${wan.IP || 'N/A'}</p>`
            }
            if (wan && wan.netmask) {
                html += `<p><strong>Subnet Mask: </strong>${wan.netmask || 'N/A'}</p>`
            } 
            if (wan && wan.gateway) {
                html += `<p><strong>Gateway: </strong>${wan.gateway || 'N/A'}</p>`
            }
            if (wan && wan.bcast) {
                html += `<p><strong>Broadcast: </strong>${wan.bcast || 'N/A'}</p>`
            }
           
            html += `
            <div class="wanForm">
             <label for="proto">Connection Type:</label>
            <select class="proto-select" id="proto" name="proto" onchange="toggleIPConfig()">
                <option value="none">None</option>
                <option value="dhcp">Dynamic IP</option>
                <option value="static">Static IP</option>
                <option value="lte">LTE/UMTS/GPRS/EV-DO</option>
            </select>
            `
            html += `
            <form id="noneConfig" style="display: none;">
            </form>
            </div>
            `
            html += `
            <form id="dhcpConfig" style="display: none;">
                <label for="dev">Device:</label>
                <select class="dev-select" id="dev" name="dev">
                <option value=""></option>
                </select>
                <br>
            </form>
            </div>
            <br>`
            html += `
            <form id="wanConfig" style="display: none;">
                <label for="wanIp">IPv4 address: </label>
                <input type="text" id="wanIp" name="wanIp" required> <br>
                <br>
                <label for="wanNetmask">IPv4 netmask: </label>
                <input type="text" id="wanNetmask" name="wanNetmask" required> <br>
                <br>
                <label for="gateway">IPv4 gateway: </label>
                <input type="text" id="gateway" name="gateway"> <br>
                <br>
                <label for="broadcast">IPv4 broadcast: </label>
                <input type="text" id="bcast" name="bcast"> <br>
                <br>
                <label for="dns">Primary DNS: </label>
                <input type="text" id="dns1" name="dns1"> <br>
                <br>
                <label for="dns">Secondary DNS: </label>
                <input type="text" id="dns2" name="dns2"> <br>
                <br>
            </form>
            </div>
            `
            html += `
            <form id="lteConfig" style="display: none;">
                <label for="lteDev">Device: </label>
                <select class="lteDev-select" id="lteDev" name="lteDev">
                    <option value="/dev/ttyMSM0">ttyMSM0</option>
                    <option value="/dev/ttyMSM1">ttyMSM1</option>
                    <option value="/dev/ttyMSM2">ttyMSM2</option>
                    <option value="/dev/ttyUSB0">ttyUSB0</option>
                    <option value="/dev/ttyUSB1">ttyUSB1</option>
                    <option value="/dev/ttyUSB2">ttyUSB2</option>
                    <option value="/dev/ttyUSB3">ttyUSB3</option>
                    <option value="/dev/cdc-wdm0">cdc-wdm0</option>
                </select>
                <br><br>
                <label for="lteService">Service: </label>
                <select class="lteService-select" id="lteService" name="lteService">
                    <option value="umts">UMTS</option>
                </select>
                <br><br>
                <label for="lteApn">APN: </label>
                <input type="text" id="lteApn" name="lteApn"> <br>
                <br>
                <label for="ltePin">PIN: </label>
                <input type="text" id="ltePin" name="ltePin"> <br>
                <br>
                <label for="lteDial">Dial Number: </label>
                <input type="text" id="lteDial" name="lteDial"> <br>
                <br>
                <label for="lteSimSlot">Sim Slot: </label>
                <select class="SimSlot-select" id="lteSimSlot" name="lteSimSlot">
                    <option value="sim1">Sim 1</option>
                    <option value="sim2">Sim 2</option>
                </select>
                <br><br>
            </form>
            </div>
            `
            html += `<button onclick="configWan()">Save</button>`
            wanIP.innerHTML = html;
            window.onload = loadDev();
        }); 
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
            document.getElementById("networkInterface").innerHTML = "<option>Error loading</option>";
        });
}

function toggleIPConfig() {
    const proto = document.getElementById('proto').value;
    const dhcpConfig = document.getElementById('dhcpConfig');
    const wanConfig = document.getElementById('wanConfig');
    const lteConfig = document.getElementById('lteConfig');
    const noneConfig = document.getElementById('noneConfig');
    const devDropdown = document.getElementById('dev');

    dhcpConfig.style.display = 'none';
    wanConfig.style.display = 'none';
    lteConfig.style.display = 'none';
    noneConfig.style.display = 'none';

    if (proto === 'dhcp') {
        dhcpConfig.style.display = 'block';
    } else if (proto === 'static') {
        dhcpConfig.style.display = 'block';
        wanConfig.style.display = 'block';
    } else if (proto === 'lte') {
        lteConfig.style.display = 'block';
        devDropdown.value = ''; // Reset dev dropdown
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
            html += `<h1>LAN Configuration</h1>
                    <p class="description">View and configure LAN settings</p>
                    <hr>`;
            const curIP = document.getElementById("lanIP");
            //const curNetmask = document.getElementById("curNetmask");
            //const curDev = document.getElementById("curDev");
            const brLan = data.find(item => item.iface === "br-lan");
            if (brLan && brLan.IP) {
                html += `<div class="curIp"><p><strong>Current IP Address: </strong>${brLan.IP || 'N/A'}</p>`
            }
            if (brLan && brLan.netmask) {
                html += `<p><strong>Current Subnet Mask: </strong>${brLan.netmask || 'N/A'}</p>`
            }
            if (brLan && brLan.iface) {
                html += `<p><strong>Device: </strong>${brLan.iface || 'N/A'}</p></div>`
            }
            html += `
            <form id="ipConfig">
                <label for="ip"><strong>IPv4 address: </strong></label>
                <input type="text" id="ip" name="ip" required>

                <label for="netmask"><strong>IPv4 netmask: </strong></label>
                <input type="text" id="netmask" name="netmask" required>

                <div class="form-actions">
                <button type="button" onclick="configIP()">Save</button>
                </div>
            </form>
            `
            curIP.innerHTML = html;
        }); 
}

function configIP() {
    let ip = document.getElementById("ip").value;
    let mask = document.getElementById("netmask").value;
    let gateway=document.getElementById("gateway").value;

    if (!ip || !mask) {
        alert("Please ensure IP Address and Subnet Mask fields are entered.");
        return;
    }

    if (!validateIP(ip)) {
        alert("Invalid IP address! Please enter correct IPv4 address.");
        return false;
    }

    if (!validateSubnetMask(mask)){
        alert("Invalid subnet mask! Please enter valid subnet mask.");
        return false;
    }

    let body = "IP=" + encodeURIComponent(ip) +
                "&Netmask=" + encodeURIComponent(mask);

    if (gateway && !validateIP(gateway)) {
        alert("Invalid gateway IP address! Please enter a correct IPv4 address.");
        return false;
    }

    if (gateway) {
        body += "&gateway=" + encodeURIComponent(gateway);
    }

    let confirmation = confirm(`Saving and applying the changes will restart both network and WiFi interfaces. Continue?`)

    if (confirmation) {
        fetch("/cgi-bin/config_lan.sh", {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: body
        })
        .then(response => response.text())
        .then(data => {
            document.getElementById("result").innerText = "Response: " + data;
        })
        .catch(error => {
            document.getElementById("result").innerText = "Error: " + error;
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


