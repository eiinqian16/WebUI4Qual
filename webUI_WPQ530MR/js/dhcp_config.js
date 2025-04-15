function configDhcp() {
    let startIp = document.getElementById("startIp").value;
    let endIp = document.getElementById("endIp").value;
    let leasetime = document.getElementById("leasetime").value;
    let isEnabled = document.getElementById("dhcpEnable").value;
    let checkbox = document.getElementById("dhcpEnable");
    let body = "";

    if(checkbox.checked) {
        body += "isEnabled=" + encodeURIComponent(isEnabled); 

        if(!validateIP(startIp)) {
            alert("Invalid IP address! Please enter a correct IPv4 address.");
            return false;
        }
        body += "&startIp=" + encodeURIComponent(startIp);
    
        if(!validateIP(endIp)) {
            alert("Invalid IP address! Please enter a correct IPv4 address.");
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

    let confirmation = confirm(`Saving and applying the changes will reboot the device. Continue?`)

    if (confirmation) {
        fetch("/cgi-bin/configDhcp.sh", {
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
            html += `<div class="dhcp">
            <h1>DHCP Configuration</h1>
            <p class="description">Dynamically assign IP addresses to connected devices</p>
            <hr style="width:100%;text-align:left;margin-left:0">
            `
            const curDhcp = document.getElementById("curDhcp");
            if (data.isEnabled == "Enabled") {
                html += `
                <div class="container"
                <p><strong>DHCP server:</strong> ${data.isEnabled || 'N/A'}</p>
                <p><strong>Current lease pool:</strong> ${data.startIp || 'N/A'} - ${data.endIp || 'N/A'}</p>
                <p><strong>Current lease time:</strong> ${data.leasetime || 'N/A'} hours</p>
                `
            } else if (data.isEnabled == "Disabled") {
                html += `
                <p><strong>DHCP server:</strong> ${data.isEnabled || 'N/A'}</p>
                `
            }

            html += `
            <label for="dhcpEnable">DHCP Server:</label>
            <input type="checkbox" id="dhcpEnable" name="dhcpEnable" value="server" onchange="toggleDhcpConfig()">
            <label for="dhcpEnable">Enable</label>

            <br>
            `

            html += `
            <form class=dhcpForm id="dhcpConfig" style="display: none;">
                <label for="startIp">IP Address Pool:</label>
                <input type="text" id="startIp" name="startIp" required>
                <label for="endIp">-</label>
                <input type="text" id="endIp" name="endIp" required>
                <br>
                <label for="leasetime">Lease Time: </label>
                <input type="number" id="leasetime" name="leasetime" required><span> hours</span>
            </form>
            <br>
            <button onclick="configDhcp()">Save</button>
            </div>
            `;
            html += `</div>`
            curDhcp.innerHTML = html;
        })
        .catch(error => {
            console.error("Fetch Error:", error);
            document.getElementById("errorMessage").innerHTML = `<p style="color: red;">Error: ${error.message}</p>`;
        });
}

function toggleDhcpConfig() {
    let dhcpCheckbox = document.getElementById("dhcpEnable");
    let dhcpConfig = document.getElementById("dhcpConfig");

    // Show the form when checked, hide when unchecked
    dhcpConfig.style.display = dhcpCheckbox.checked ? "block" : "none";
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
            <h1>DHCP Clients</h1>
            <p class="description">Devices using IP address assigned by DHCP server</p>
            <hr style="width:100%;text-align:left;margin-left:0">`
            if (isJsonEmpty(data)) {
                html += `<h3>No Client Information Available</h3></div>`;
                clients.innerHTML = html;
                return;
            }
            console.log("Successfully fetched data:", data);
            html += `
            <table>
                <tr>
                    <th>Hostname</th>
                    <th>MAC</th>
                    <th>IP Address</th>
                    <th>Lease Expiration Date</th>
                </tr>
            `;
            data.forEach(client => { 
                const hostname = client.hostname && typeof client.hostname === "string" && client.hostname.includes('*')
                    ? 'Unknown'
                    : client.hostname || 'Unknown';
                html += `
                <tr>
                    <td>${hostname}</td>
                    <td>${client.mac || 'Unknown'}</td>
                    <td>${client.ip || 'Unknown'}</td>
                    <td>${client.expDate || 'Unknown'}</td>
                </tr>
                `;
            });
            html += `</table>
            <br>
            <button onclick="refreshPage()">Refresh</button>
            </div>`
            clients.innerHTML = html;
        })
        .catch(error => {
            console.error("Fetch Error:", error);
            document.getElementById("errorMessage").innerHTML = `<p style="color: red;">Error: ${error.message}</p>`;
        });
}

function isJsonEmpty(data) {
    return !data || data.length === 0 || (data.length === 1 && Object.keys(data[0]).length === 0);
}

function refreshPage() {
    location.reload();
}
