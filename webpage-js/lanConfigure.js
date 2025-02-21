function configWan() {
    let dev = document.getElementById("dev").value;
    let proto = document.getElementById("proto").value;
    let ip = document.getElementById("wanIp").value;
    let mask = document.getElementById("wanNetmask").value;
    let gateway = document.getElementById("gateway").value;
    let bcast = document.getElementById("bcast").value;
    let dns1 = document.getElementById("dns1").value;
    let dns2 = document.getElementById("dns2").value;
    let body = "";

    if (dev) {
        body += "dev=" + encodeURIComponent(dev);
    }

    if (proto) {
        body += "&proto=" + encodeURIComponent(proto);
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

    let confirmation = confirm(`Saving and applying the changes will restart both network and WiFi interfaces. Continue?`)

    console.log(body);
    if (confirmation) {
        fetch("/cgi-bin/configWan.sh", {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: body
        })
        .then(response => response.text())
        .then(data => {
            document.getElementById("wanResult").innerText = "Response: " + data;
        })
        .catch(error => {
            document.getElementById("wanResult").innerText = "Error: " + error;
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
            html += `<h3> Internet </h3>`
            const wanIP = document.getElementById("wanIP");
            //const curNetmask = document.getElementById("curNetmask");
            //const curDev = document.getElementById("curDev");
            const wan = data.find(item => item.type === "WAN");
            if (wan && wan.iface) {
                html += `<p><strong>Device: </strong>${wan.iface || 'N/A'}</p>`
            }
            if (wan && wan.proto) {
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
            <label for="dev">Device:</label>
            <select class="dev-select" id="dev" name="dev">
                <option value=""></option>
            </select>
            <label for="proto">Connection Type:</label>
            <select class="proto-select" id="proto" name="proto" onchange="toggleIPConfig()">
                <option value="dhcp">Dynamic IP</option>
                <option value="static">Static IP</option>
            </select>`
            html += `
            <form id="wanConfig" style="display: none;">
                <label for="ip">IPv4 address: </label>
                <input type="text" id="wanIp" name="wanIp" required> <br>
                <br>
                <label for="netmask">IPv4 netmask: </label>
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
            `

            html += `<button onclick="configWan()">Save and Apply</button>`
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
    let proto = document.getElementById("proto").value;
    let ipConfig = document.getElementById("wanConfig");

    if (proto === "static") {
        wanConfig.style.display = "block";
    } else {
        wanConfig.style.display = "none";
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
            html += `<h3> LAN </h3>`
            const curIP = document.getElementById("lanIP");
            //const curNetmask = document.getElementById("curNetmask");
            //const curDev = document.getElementById("curDev");
            const brLan = data.find(item => item.iface === "br-lan");
            if (brLan && brLan.IP) {
                html += `<p><strong>Current IP Address: </strong>${brLan.IP || 'N/A'}</p>`
            }
            if (brLan && brLan.netmask) {
                html += `<p><strong>Current Subnet Mask: </strong>${brLan.netmask || 'N/A'}</p>`
            }
            if (brLan && brLan.iface) {
                html += `<p><strong>Device: </strong>${brLan.iface || 'N/A'}</p>`
            }
            html += `
            <form id="ipConfig">
                <label for="ip">IPv4 address: </label>
                <input type="text" id="ip" name="ip" required> <br>
                <br>
                <label for="netmask">IPv4 netmask: </label>
                <input type="text" id="netmask" name="netmask" required> <br>
                <br>
                <button onclick="configIP()">Save and Apply</button>
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
        fetch("/cgi-bin/configLan.sh", {
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