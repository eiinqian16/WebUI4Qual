let deviceConfig = {};

async function getConfig() {
    try {
        const response = await fetch('/cgi-bin/get_wifi_config.sh');
        console.log('HTTP Status:', response.status);

        if (!response.ok) {
            throw new Error('Network response was not ok: ' + response.statusText);
        }

        const data = await response.json();
        console.log('Fetched data:', data);
        deviceConfig = data;

        renderWifiList();
    } catch (err) {
        console.error('Error fetching configuration:', err);
    }
}

function renderWifiList() {
    const wifiList = document.getElementById('wifi-list');
    wifiList.innerHTML = '';

    Object.keys(deviceConfig).forEach(device => {
        const wifi = deviceConfig[device];
        wifiList.innerHTML += `
            <tr>
                <td>${wifi.device}</td>
                <td><button class="edit-btn btn-green" data-device="${device}">Edit</button></td>
            </tr>
        `;
    });

    document.querySelectorAll('.edit-btn').forEach(btn => {
        btn.addEventListener('click', function() {
            const device = this.getAttribute('data-device');
            openEditModal(device);
        });
    });
}

function openEditModal(device) {
    let config = deviceConfig[device];
    console.log('Editing device:', device, config);

    if (config) {
        document.getElementById('wifi-device-config').innerHTML = `
            <div class="form-grid">
                <label>Type:</label>
                <input type="text" id="device_type" value="${config.type}" />

                <label>Channel:</label>
                <input type="text" id="device_channel" value="${config.channel}" />

                <label>MAC Address:</label>
                <input type="text" id="device_macaddr" value="${config.macaddr}" />

                <label>HW Mode:</label>
                <input type="text" id="device_hwmode" value="${config.hwmode}" />

                <label>Disabled:</label>
                <input type="text" id="device_disabled" value="${config.disabled}" />
            </div>
        `;

        document.getElementById('wifi-iface-config').innerHTML = `
            <div class="form-grid">
                <label>Device:</label>
                <input type="text" id="iface_device" value="${config.iface.device}" />

                <label>Network:</label>
                <input type="text" id="iface_network" value="${config.iface.network}" />

                <label>Mode:</label>
                <input type="text" id="iface_mode" value="${config.iface.mode}" />

                <label>SSID:</label>
                <input type="text" id="iface_ssid" value="${config.iface.ssid}" />

                <label>Encryption:</label>
                <input type="text" id="iface_encryption" value="${config.iface.encryption}" />
            </div>
        `;

        document.getElementById('modalOverlay').style.display = 'block';
        document.getElementById('editModal').style.display = 'block';
    }
}

function closeEditModal() {
    document.getElementById('modalOverlay').style.display = 'none';
    document.getElementById('editModal').style.display = 'none';
}


