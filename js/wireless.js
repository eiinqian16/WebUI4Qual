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
                <td>WiFi Device (${wifi.device})</td>
                <td><button class="edit-btn" data-device="${device}">Edit</button></td>
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
        document.getElementById('modal-content').innerHTML = `
            <h3>Editing ${config.device}</h3>
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

            <h4>Interface Configuration</h4>
            <label>Network:</label>
            <input type="text" id="iface_network" value="${config.iface.network}" />

            <label>Mode:</label>
            <input type="text" id="iface_mode" value="${config.iface.mode}" />

            <label>SSID:</label>
            <input type="text" id="iface_ssid" value="${config.iface.ssid}" />

            <label>Encryption:</label>
            <input type="text" id="iface_encryption" value="${config.iface.encryption}" />

            <button class="modal-save-btn" onclick="saveWifiConfig('${device}')">Save</button>
            <button class="modal-close-btn" onclick="closeEditModal()">Close</button>
        `;

        document.getElementById('modalOverlay').classList.add('show');
        document.getElementById('editModal').classList.add('show');
    }
}

async function saveWifiConfig(device) {
    const updatedConfig = {
        device: device,
        type: document.getElementById('device_type').value,
        channel: document.getElementById('device_channel').value,
        macaddr: document.getElementById('device_macaddr').value,
        hwmode: document.getElementById('device_hwmode').value,
        disabled: document.getElementById('device_disabled').value,
        iface: {
            device: device,
            network: document.getElementById('iface_network').value,
            mode: document.getElementById('iface_mode').value,
            ssid: document.getElementById('iface_ssid').value,
            encryption: document.getElementById('iface_encryption').value
        }
    };

    try {
        const response = await fetch('/cgi-bin/save_wifi_config.sh', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(updatedConfig)
        });

        if (!response.ok) {
            throw new Error('Network response was not ok: ' + response.statusText);
        }

        const result = await response.text();
        console.log('Save Result:', result);
        alert('Configuration saved successfully!');
        closeEditModal();
        getConfig();
    } catch (err) {
        console.error('Error saving configuration:', err);
        alert('Failed to save configuration.');
    }
}




function closeEditModal() {
    document.getElementById('modalOverlay').classList.remove('show');
    document.getElementById('editModal').classList.remove('show');
}


