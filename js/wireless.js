async function getConfig(updateOnly = false) {                                                                                                  
    try {                                                                                                        
        const response = await fetch('/cgi-bin/get_wifi_config.sh');                                                 
        console.log('HTTP Status:', response.status);                                                          
                                                                                                                                   
        if (!response.ok) {                                                                                               
            throw new Error('Network response was not ok: ' + response.statusText);                                           
        }                                                                                                        
                                                                                                                     
        const data = await response.json();                                                                    
        console.log('Fetched data:', data);                                                                                        
                                                                                                                          
        if (!updateOnly) {
            deviceConfig = {};
            Object.keys(data).forEach(device => {                                                                    
                deviceConfig[device] = {                                                                                 
                    ...data[device],                                                                               
                    interfaces: Array.isArray(data[device].interfaces) ? data[device].interfaces : []                                  
                };                                                                                                            
            });                                                                                                                   
            renderWifiList(); 
        } else {
            console.log("Updating only bitrate, channel, BSSID..."); 

            Object.keys(data).forEach(device => {
                if (deviceConfig[device]) {
                    deviceConfig[device].bitrate = data[device].bitrate || deviceConfig[device].bitrate;
                    deviceConfig[device].current_channel = data[device].current_channel || deviceConfig[device].current_channel;
                    
                    data[device].interfaces.forEach((iface, index) => {
                        if (deviceConfig[device].interfaces[index]) {
                            deviceConfig[device].interfaces[index].bssid = iface.bssid || deviceConfig[device].interfaces[index].bssid;
                        }
                    });
                }
            });

            updateWifiInfoUI();
        }
    } catch (err) {                                                                                            
        console.error('Error fetching configuration:', err);                                                                       
    }                                                                                                                     
}

            

function renderWifiList() {                                                                                          
    const wifiListContainer = document.getElementById('wifi-list');
    wifiListContainer.innerHTML = ''; 

    Object.values(deviceConfig).forEach(wifi => {   
        const table = document.createElement('table');
        table.classList.add('wifi-table'); 

        const thead = document.createElement('thead');
        thead.innerHTML = `
            <tr>
                <td>
                    <div class="main-wifi-header">
                        <div class="wifi-header">
                            <h3>WiFi Device (${wifi.device}) - Bands: ${wifi.supported_bands || 'Unknown'}</h3>
                            <div class="wifi-header-content">
                                <p class="wifi-info" data-device="${wifi.device}">
                                    ${wifi.current_channel ? `Current Channel: ${wifi.current_channel}` : ""}
                                    ${wifi.bitrate ? `| Bitrate: ${wifi.bitrate}` : ""}
                                </p>
                            </div>
                        </div>
                        <div class="header-buttons">
                            <button class="scan-btn" data-device="${wifi.device}">Scan</button>
                            <button class="add-btn" data-device="${wifi.device}">Add</button>
                        </div>
                    </div>
                </td>
            </tr>
        `;
        table.appendChild(thead);

        const tbody = document.createElement('tbody');
        wifi.interfaces.forEach(iface => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td class="ssid-mode-bssid-column">
                    <div class="ssid-mode-bssid-wrapper">
                        <span class="ssid">${iface.ssid}</span>
                        <div class="mode-bssid">
                            <span class="mode">Mode : ${iface.mode === "ap" ? "Master" : "Client"}</span>
                            <span class="bssid" data-iface="${iface.iface}">BSSID : ${iface.bssid || "Unknown"}</span>
                        </div>
                    </div>
                </td>


                <td class="actions">
                    <button class="edit-btn" data-device="${wifi.device}" data-iface="${iface.iface}">Edit</button>
                    <button class="delete-btn" data-iface="${iface.iface}">Delete</button>
                </td>
            `;

            tbody.appendChild(row);
        });
        table.appendChild(tbody);

        wifiListContainer.appendChild(table);
    });

    document.querySelectorAll('.scan-btn').forEach(btn => {                                                               
        btn.addEventListener('click', function() {                                                                            
            const device = this.getAttribute('data-device');                                                     
            startScan(device);                                                                                       
        });                                                                                                    
    });

    document.querySelectorAll('.edit-btn').forEach(btn => {                                                                   
        btn.addEventListener('click', function() {                                                               
            const device = this.getAttribute('data-device');                                                         
            const iface = this.getAttribute('data-iface');                                                     
            openEditModal(device, iface);                                                                                          
        });                                                                                                               
    });

    document.querySelectorAll('.delete-btn').forEach(btn => {                                                        
        btn.addEventListener('click', function() {                                                                     
            const iface = this.getAttribute('data-iface');                                                                         
            deleteIface(iface);                                                                                           
        });                                                                                                                   
    });

    document.querySelectorAll('.add-btn').forEach(btn => {                                                                    
        btn.addEventListener('click', function() {                                                               
            const device = this.getAttribute('data-device');                                                         
            openAddModal(device);                                                                              
        });                                                                                                                        
    });
}                             
    
function updateWifiInfoUI() {
    Object.values(deviceConfig).forEach(wifi => {
        const info = document.querySelector(`.wifi-info[data-device="${wifi.device}"]`);
        if (info) {
            info.innerHTML = `
                ${wifi.current_channel ? `Current Channel: ${wifi.current_channel}` : ""}
                ${wifi.bitrate ? `| Bitrate: ${wifi.bitrate}` : ""}
            `;
        }
        wifi.interfaces.forEach(iface => {
            const bssidElement = document.querySelector(`.bssid[data-iface="${iface.iface}"]`);
            if (bssidElement) {
                bssidElement.textContent = `BSSID : ${iface.bssid || "Unknown"}`;
            }
        });
    });
}

         
async function openEditModal(device, iface) {                                                                        
    const modalContent = document.getElementById('edit-modal-content');                                        
    const modal = document.getElementById('editModal');                                                                            
    const overlay = document.getElementById('modalOverlay');                                                              
                                                                                                                              
    const wifi = deviceConfig[device];                                                                           
    if (!wifi) {                                                                                                     
        console.error(`Device ${device} not found.`);                                                          
        return;                                                                                                                    
    }                                                                                                                     
                                                                                                                              
    const ifaceConfig = wifi.interfaces.find(i => i.iface === iface);                                            
    if (!ifaceConfig) {                                                                                              
        console.error(`Interface ${iface} not found.`);                                                        
        return;                                                                                                                    
    }                                                                                                                     
                                                                                                                              
    let txpowerValue = wifi.txpower || "MAX";                                                                    
                                                                                                                     
    const txpowerOptions = [5, 8, 11, 14, 17, 20, 23, "MAX"].map(value =>                                              
        `<option value="${value}" ${txpowerValue == value ? "selected" : ""}>${value}</option>`                                    
    ).join('');                                                                                                           
                                                                                                                              
    let channelOptionsHtml = "";                                                                                 
    if (wifi.channel_options) {                                                                                      
        Object.keys(wifi.channel_options).forEach(band => {                                                    
            channelOptionsHtml += `<optgroup label="--- ${band} ---"></optgroup>`;                                                 
            wifi.channel_options[band].forEach(chan => {                                                                  
                let selected = (chan.startsWith(wifi.channel)) ? "selected" : "";                                             
                channelOptionsHtml += `<option value="${chan}" ${selected}>${chan}</option>`;                    
            });                                                                                                      
        });                                                                                                    
    }                                                                                                                              

    let hwmodeValue = wifi.hwmode || "11bea";  // .........                                                      
    let htmodeValue = wifi.htmode || "EHT320"; // .........                                                          
                                                                                                               
    console.log(`Current hwmode: ${hwmodeValue}, htmode: ${htmodeValue}`);                                                         
     
    let is6GHz = wifi.supported_bands && wifi.supported_bands.includes("6G"); 

    console.log(`Editing ${device}, is6GHz: ${is6GHz}`);
                                                                                  
    let hwModesResponse = await fetch(`/cgi-bin/get_hw_modes.sh?device=${device}`);                              
    let hwModesData = await hwModesResponse.json();                                                                  
    console.log("Available HW Modes:", hwModesData);

    let hwmodeOptions = Object.keys(hwModesData.hw_modes)                                                                     
        .map(hw => `<option value="${hw}" ${hw === hwmodeValue ? "selected" : ""}>${hw.toUpperCase()}</option>`) 
        .join('');                                                                                                   

    const modeValue = ifaceConfig.mode || "ap"; 
    updateCipherOptions(iface, modeValue,device);
    
    let encryptionValue = is6GHz ? "ccmp" : (ifaceConfig.encryption || "none");
    let cipherValue = ifaceConfig.cipher || "auto";
    
    let encryptionOptions = is6GHz ? `
        <option value="ccmp" selected>WPA3-SAE (Forced for 6GHz)</option>
    ` : `
        <option value="none" ${encryptionValue === "none" ? "selected" : ""}>None</option>
        <option value="psk" ${encryptionValue === "psk" ? "selected" : ""}>WPA-PSK (WPA1)</option>
        <option value="psk2" ${encryptionValue === "psk2" ? "selected" : ""}>WPA2-PSK</option>
        <option value="psk-mixed" ${encryptionValue === "psk-mixed" ? "selected" : ""}>WPA1/WPA2 Mixed</option>
        <option value="sae" ${encryptionValue === "sae" ? "selected" : ""}>WPA3-SAE</option>
        <option value="owe" ${encryptionValue === "owe" ? "selected" : ""}>OWE (Enhanced Open)</option>
    `;

    let cipherOptions = `
        <option value="auto" ${cipherValue === "auto" ? "selected" : ""}>Auto</option>
        <option value="CCMP" ${cipherValue === "CCMP" ? "selected" : ""}>CCMP</option>
        <option value="TKIP" ${cipherValue === "TKIP" ? "selected" : ""}>TKIP</option>
        <option value="GCMP" ${cipherValue === "GCMP" ? "selected" : ""}>GCMP</option>
    `;

    let modalHtml = `                                                                                                              
        <h3>Edit Device: ${device}</h3>                                                                                   
        <table>                                                                                                               
            <tr><td>Type:</td><td><input type="text" id="device-type-${device}" value="${wifi.type || ''}" disabled></td></tr>
            <tr>                                                                                                              
                <td>Channel:</td>                                                                                             
                <td>                                                                                                               
                    <select id="device-channel-${device}">                                                                
                        ${channelOptionsHtml}                                                                                 
                    </select>                                                                                    
                </td>                                                                                                
            </tr>                                                                                                             
            <tr>                                                                                                                   
                <td>TX Power:</td>                                                                                        
                <td>                                                                                                          
                    <select id="device-txpower-${device}">                                                       
                        ${txpowerOptions}                                                                            
                    </select>                                                                                          
                </td>                                                                                                              
            </tr>                                                                                                         
            <tr>                                                                                                              
                <td>Country:</td>                                                                                
                <td>                                                                                                 
                    <input type="text" id="device-country-${device}" value="${wifi.country || ''}"             
                        oninput="validateCountryCode('${device}')">                                                                
                    <span id="country-error-${device}" style="color: red; font-size: 0.9em;"></span>                      
                </td>                                                                                                         
            </tr>                                                                                                
            <tr>                                                                                                     
                <td>HW Mode:</td>                                                                              
                <td>                                                                                                               
                    <select id="device-hwmode-${device}" onchange="updateHtmode('${device}')">                            
                        ${hwmodeOptions}                                                                                      
                    </select>                                                                                                      
                </td>                                                                                                     
            </tr>                                                                                              
            <tr id="htmode-row-${device}">                                                                                         
                <td>HT Mode:</td>                                                                                         
                <td>                                                                                                          
                    <select id="device-htmode-${device}"></select>                                                                 
                </td>                                                                                                     
            </tr>                                                                                                      
            <tr>                                                                                                                   
                <td>Disabled:</td>                                                                                        
                <td>                                                                                                          
                    <select id="device-disabled-${device}">                                                                        
                        <option value="0" ${wifi.disabled == "0" ? "selected" : ""}>Enabled</option>                      
                        <option value="1" ${wifi.disabled == "1" ? "selected" : ""}>Disabled</option>               
                    </select>                                                                                                 
                </td>                                                                                                         
            </tr>                                                                                                             
        </table>                                                                                                                   
                                                                                                                              
        <h3>Edit Interface: ${iface}</h3>                                                                                     
        <table>                                                                                                               
            <tr><td>Network:</td><td><input type="text" id="iface-network-${iface}" value="${ifaceConfig.network || ''}"></td></tr>
            <tr><td>SSID:</td><td><input type="text" id="iface-ssid-${iface}" value="${ifaceConfig.ssid || ''}"></td></tr>    
     
            <tr>                                                                                                                   
                <td>Mode:</td>                                                                                                     
                <td>                                                                                                               
                    <select id="iface-mode-${iface}" 
                            onchange="updateCipherOptions('${iface}', this.value,'${device}'); togglePasswordField('${iface}');">
                        <option value="ap" ${ifaceConfig.mode === "ap" ? "selected" : ""}>Access Point (AP)</option>               
                        <option value="sta" ${ifaceConfig.mode === "sta" ? "selected" : ""}>Station (STA)</option>                 
                    </select>                                                                                                      
                </td>                                                                                                              
            </tr>
                                                                                                                
            <tr>                                                                                                                   
                <td>Encryption:</td>                                                                                               
                <td>                                                                                                               
                    <select id="iface-encryption-${iface}" ${is6GHz ? "disabled" : ""} onchange="updateCipherOptions('${iface}', document.getElementById('iface-mode-${iface}').value,'${device}'); togglePasswordField('${iface}');">
                        ${encryptionOptions}
                    </select>                                                                                               
                </td>                                                                                                              
            </tr>  
            <tr id="cipher-row-${iface}" style="display: none;">
                <td>Cipher Mode:</td>
                <td>
                    <select id="iface-cipher-${iface}"></select>
                </td>
            </tr>
            <tr id="password-row-${iface}" style="display: ${ifaceConfig.encryption === "none" ? "none" : "table-row"};">          
                <td>Password:</td>                                                                                                 
                <td><input type="password" id="iface-key-${iface}" value="${ifaceConfig.key || ''}"></td>                          
            </tr>       
                                                                                                     
        </table>                                                                                                                   
                                                                                                                                   
        <button onclick="saveConfig('${device}', '${iface}')">Save</button>                                                        
        <button class="modal-close-btn" onclick="closeEditModal()">Close</button>                                                  
    `;                                                                                                                             
                  
    modalContent.innerHTML = modalHtml; 
    updateHtmode(device, htmodeValue);
    document.getElementById(`iface-encryption-${iface}`).innerHTML = encryptionOptions;
    document.getElementById(`iface-cipher-${iface}`).innerHTML =cipherOptions;    
    updateCipherOptions(iface, modeValue, device);                                                                       
    togglePasswordField(iface);                                                                                                    
    overlay.classList.add('show');                                                                                                 
    modal.classList.add('show');                                                                                                   
}                                

function updateCipherOptions(iface, mode, device) { 
    const encryptionSelect = document.getElementById(`iface-encryption-${iface}`);
    const cipherRow = document.getElementById(`cipher-row-${iface}`);
    const cipherSelect = document.getElementById(`iface-cipher-${iface}`);

    if (!encryptionSelect || !cipherRow || !cipherSelect) {
        console.error(`Missing elements for iface: ${iface}`);
        return;
    }

    if (!mode) {
        const modeSelect = document.getElementById(`iface-mode-${iface}`);
        mode = modeSelect ? modeSelect.value : "ap"; 
    }

    let selectedEnc = encryptionSelect.value || "none";
    let selectedCipher = cipherSelect.value || "auto";
    let cipherOptions = [];

    console.log(`Updating cipher options for iface: ${iface}, mode: ${mode}, encryption: ${selectedEnc}`);

    const wifi = deviceConfig[device];
    if (!wifi) {
        console.error(`❌ Device ${device} not found in deviceConfig!`);
        return;
    }

    console.log("🔹 DeviceConfig entry:", wifi);
    console.log("🔹 Current Channel:", wifi.current_channel);

    let freqMHz = null;
    Object.values(wifi.channel_options || {}).forEach(bandChannels => {
        bandChannels.forEach(ch => {
            const match = ch.match(/\((\d+) MHz\)/);
            if (match && parseInt(ch) === parseInt(wifi.current_channel)) {
                freqMHz = parseInt(match[1]); 
            }
        });
    });

    console.log(`🔹 Detected Frequency: ${freqMHz} MHz`);

    const is6GHz = freqMHz !== null && freqMHz >= 5955 && freqMHz <= 7115;
    console.log(`🔹 is6GHz for ${device}:`, is6GHz);

    if (selectedEnc === "sae") {
        cipherOptions = [{ value: "ccmp", text: "CCMP (Forced for SAE)" }];
        selectedCipher = "CCMP"; 
    } else if (is6GHz) {
        cipherOptions = [{ value: "ccmp", text: "CCMP (Forced for SAE)" }];
        selectedCipher = "CCMP"; 
    } else if (mode === "ap") {
        switch (selectedEnc) {
            case "psk":  
                cipherOptions = [
                    { value: "auto", text: "Auto (Default)" },
                    { value: "tkip", text: "TKIP" },
                    { value: "ccmp", text: "CCMP" },
                    { value: "ccmp+tkip", text: "CCMP+TKIP (Legacy)" }
                ];
                break;
            case "psk2": 
                cipherOptions = [
                    { value: "auto", text: "Auto (Default)" },
                    { value: "ccmp", text: "CCMP" },
                    { value: "ccmp+tkip", text: "CCMP+TKIP (Legacy)" }
                ];
                break;
            case "psk-mixed":
                cipherOptions = [
                    { value: "auto", text: "Auto (Default)" },
                    { value: "tkip", text: "TKIP" },
                    { value: "ccmp", text: "CCMP" },
                    { value: "ccmp+tkip", text: "CCMP+TKIP (Legacy)" }
                ];
                break;
            case "sae": 
                cipherOptions = [
                    { value: "ccmp", text: "CCMP" }
                ]; 
                break;
            case "owe":  
                cipherOptions = [
                    { value: "auto", text: "Auto (Default)" },
                    { value: "ccmp", text: "CCMP" },
                    { value: "gcmp", text: "GCMP" }
                ];
                break;
            default:
                cipherOptions = [{ value: "auto", text: "Auto (Default)" }];
        }
    } else if (mode === "sta") {
        cipherOptions = [{ value: "auto", text: "Auto (Default)" }];
        if (["psk", "psk2"].includes(selectedEnc)) {
            cipherOptions.push({ value: "ccmp", text: "CCMP" });
        } else if (selectedEnc === "sae") {
            cipherOptions.push({ value: "ccmp", text: "CCMP" });
        } else if (selectedEnc === "owe") {
            cipherOptions.push(
                { value: "ccmp", text: "CCMP" },
                { value: "gcmp", text: "GCMP" }
            );
        }
    }

    cipherSelect.innerHTML = cipherOptions.map(opt =>
        `<option value="${opt.value}" ${opt.value === selectedCipher ? "selected" : ""}>${opt.text}</option>`
    ).join('');

    if (mode === "sta" && !cipherSelect.querySelector('option[value="auto"]')) {
        let autoOption = document.createElement("option");
        autoOption.value = "auto";
        autoOption.textContent = "Auto (Default)";
        cipherSelect.insertBefore(autoOption, cipherSelect.firstChild);
    }

    cipherSelect.value = selectedCipher || "auto";

    cipherRow.style.display = cipherOptions.length > 0 ? "table-row" : "none";
}

function updateHtmode(device, htmodeValue) {      
    console.log(`updateHtmode() called for device: ${device}, htmodeValue: ${htmodeValue}`);               
    const hwmodeSelect = document.getElementById(`device-hwmode-${device}`);                                                       
    const htmodeSelect = document.getElementById(`device-htmode-${device}`);                                                       
    const htmodeRow = document.getElementById(`htmode-row-${device}`);                                                             
                                                                                                                                   
    if (!hwmodeSelect || !htmodeSelect || !htmodeRow) {                                                                                          
        console.error("Error: Cannot find HW mode or HT mode select elements.");                                               
        return;                                                                                                                    
    }                                                                                                                              
                                                                                                                                   
    const hwmode = hwmodeSelect.value.trim();                                                                                      
    console.log("Current selected hwmode:", hwmode);                                                                          
                                                                                                                                   
    fetch(`/cgi-bin/get_hw_modes.sh?device=${device}`)                                                                             
        .then(response => response.json())                                                                                         
        .then(data => {                                                                                                            
            console.log("Fetched HW Modes Data:", data);                                                                      
                                                                                                                                   
            if (!data.hw_modes) {                                                                                                  
                console.error("Error: hw_modes data is missing.");                                                                 
                return;                                                                                                            
            }                                                                                                                      
                                                                                                                                   
            console.log("Available HW Modes:", Object.keys(data.hw_modes));                                                   
                                                                                                                                   
            let matchedHwmode = Object.keys(data.hw_modes).find(key => key.trim().toLowerCase() === hwmode.trim().toLowerCase());                              
            if (!matchedHwmode) {                                                                                                  
                console.warn(`Warning: HW Mode '${hwmode}' not found in`, data.hw_modes);                                      
                htmodeSelect.innerHTML = `<option value="">No HT Modes Available</option>`;                                        
                htmodeRow.style.display = "none";                                                                                  
                return;                                                                                                            
            }                                                                                                                      
                                                                                                                                   
            console.log(`Found HW Mode '${matchedHwmode}'`);                                                                       
                                                                                                                                   
            const availableHtModes = data.hw_modes[matchedHwmode] || [];                                                           
            console.log(`HT Modes for ${matchedHwmode}:`, availableHtModes);                                                       
                                                                                                                                   
            if (["11b", "11g", "11a"].includes(matchedHwmode)) {                                                                   
                htmodeRow.style.display = "none";                                                                                  
                htmodeSelect.innerHTML = "";                                                                                       
                return;                                                                                                            
            }                                                                                                                      
                                                                                                                                   
            htmodeRow.style.display = "table-row";                                                                                 
            if (availableHtModes.length > 0) {                                                                                     
                htmodeSelect.innerHTML = availableHtModes                                                                          
                    .map(ht => `<option value="${ht}" ${ht === htmodeValue ? "selected" : ""}>${ht}</option>`)                     
                    .join('');
            console.log("Final HT Modes HTML:", optionsHTML);
            } else { 
                console.warn("No HT Modes Available");                                                                                                              
                htmodeSelect.innerHTML = `<option value="">No HT Modes Available</option>`;                                        
            }                                                                                                                      
        })                                                                                                                         
        .catch(error => console.error("Error fetching HT mode options:", error));  
}

function togglePasswordField(iface) {
    const encryptionElement = document.getElementById(iface === "new" ? "iface-encryption-new" : `iface-encryption-${iface}`);
    const passwordRow = document.getElementById(iface === "new" ? "password-row-new" : `password-row-${iface}`);

    if (!encryptionElement || !passwordRow) {
        console.error(`togglePasswordField: Elements not found for iface ${iface}`);
        return;
    }

    passwordRow.style.display = (encryptionElement.value === "none" || encryptionElement.value === "owe") ? "none" : "table-row";
}                                                                                                       
                                                                                                                                   
function validateCountryCode(device) {                                                                                             
    const inputElement = document.getElementById(`device-country-${device}`);                                                      
    let countryCode = inputElement.value.trim().toUpperCase();                                                                     
    const countryError = document.getElementById(`country-error-${device}`);                                                       
                                                                                                                                   
    const isoCountries = new Set(["US", "CN", "TW", "HK", "JP", "KR", "DE", "GB", "FR", "CA", "IN", "AU", "SG",                    
        "BR", "MX", "ES", "IT", "NL", "RU", "SE", "CH", "FI", "NO", "DK", "PL", "AT"]);                                            
                                                                                                                                   
    if (countryCode === "") {                                                                                                      
        countryError.textContent = "";                                                                                             
        inputElement.classList.remove("input-error");                                                                              
        return true;                                                                                                               
    }                                                                                                                              
                                                                                                                                   
    if (countryCode.length !== 2 || !isoCountries.has(countryCode)) {                                                              
        countryError.textContent = "Invalid country code"; //must be ISO 3166-1                                                    
        inputElement.classList.add("input-error");                                                                                 
        return false;                                                                                                              
    } else {                                                                                                                       
        countryError.textContent = "";                                                                                             
        inputElement.classList.remove("input-error");                                                                              
        return true;                                                                                                               
    }                                                                                                                              
}            

function saveConfig(device, iface) {
    console.log(`Saving config for device: ${device}, iface: ${iface}`);

    if (!validateCountryCode(device)) {
        alert("Invalid country code! Please enter a valid ISO 3166-1 alpha-2 country code.");
        return false;
    }

    showLoading(); 

    const getValue = (id) => {
        const element = document.getElementById(id);
        if (!element) {
            console.error(`Error: Element with ID '${id}' not found.`);
            return "";
        }
        return element.value.trim();
    };

    const getSelectedValue = (id) => {
        const element = document.getElementById(id);
        if (!element) {
            console.error(`Error: Element with ID '${id}' not found.`);
            return "";
        }
        return element.value;
    };

    let rawChannel = getSelectedValue(`device-channel-${device}`);
    console.log("🔹 rawChannel:", rawChannel);

    let finalChannel = "auto";
    let currentChannelMHz = null;
    let bandInfo = null;
    let band = 0;

    if (!rawChannel.startsWith("auto")) {
        let match = rawChannel.match(/^(\d+)\s\((\d+)\sMHz\)$/);
        if (match) {
            finalChannel = match[1];  
            currentChannelMHz = parseInt(match[2]);  
        } else {
            finalChannel = rawChannel;  
        }
    } else {
        let bandMatch = rawChannel.match(/\((.*?)\)/);
        if (bandMatch) {
            bandInfo = bandMatch[1]; // 5GHz 或 6GHz
        }
    }

    if (currentChannelMHz !== null) {
        if (currentChannelMHz >= 2412 && currentChannelMHz <= 2484) {
            band = 1; // 2.4GHz
        } else if (currentChannelMHz >= 5180 && currentChannelMHz <= 5885) {
            band = 2; // 5GHz
        } else if (currentChannelMHz >= 5955 && currentChannelMHz <= 7115) {
            band = 3; // 6GHz
        }
    } else if (bandInfo === "5GHz") {
        band = 2;
    } else if (bandInfo === "6GHz") {
        band = 3;
    } else {
        let supportedBands = deviceConfig[device]?.supported_bands || "";
        if (supportedBands.includes("6G")) {
            band = 3;
        } else if (supportedBands.includes("5G")) {
            band = 2;
        } else if (supportedBands.includes("2G")) {
            band = 1;
        }
    }

    console.log(`🔹 Final Channel: ${finalChannel}, Frequency: ${currentChannelMHz} MHz, Band: ${band}`);

    const is6GHz = (band === 3);
    console.log(`🔹 is6GHz: ${is6GHz}`);

    let txpower = getSelectedValue(`device-txpower-${device}`);
    if (txpower === "MAX") {
        txpower = null; 
    }

    let hwmode = getSelectedValue(`device-hwmode-${device}`);
    let htmode = getSelectedValue(`device-htmode-${device}`);
    if (["11b", "11g", "11a"].includes(hwmode)) {
        htmode = null; 
    }

    let encryption = getSelectedValue(`iface-encryption-${iface}`);
    let cipher = getSelectedValue(`iface-cipher-${iface}`);

    if (["psk", "psk2", "sae", "sae-mixed"].includes(encryption) && cipher && cipher !== "auto") {
        encryption = `${encryption}+${cipher}`;
    }

    if (!iface || iface.trim() === "") {
        alert("Error: No iface provided for modification.");
        hideLoading();
        return;
    }

    const updatedConfig = {
        device,
        create_new: false, 
        type: getValue(`device-type-${device}`),
        channel: finalChannel,
        current_channel: currentChannelMHz,  
        txpower: txpower,
        country: getValue(`device-country-${device}`),
        hwmode: hwmode,
        htmode: htmode,
        band: band,  // ✅ 传 `band` 值
        disabled: getValue(`device-disabled-${device}`) || "0",
        iface: {
            iface: iface, 
            network: getValue(`iface-network-${iface}`),
            ssid: getValue(`iface-ssid-${iface}`),
            mode: getValue(`iface-mode-${iface}`),
            encryption: encryption
        }
    };
    
    if (encryption.startsWith("sae")) {
        updatedConfig.iface.sae = "1";
    } else {
        delete updatedConfig.iface.sae;
    }

    if (encryption !== "none") {
        let key = getValue(`iface-key-${iface}`);
        if (key) {
            updatedConfig.iface.key = key;
        }
    }

    console.log("Final updatedConfig JSON:", JSON.stringify(updatedConfig, null, 2));

    fetch('/cgi-bin/save_wifi_config.sh', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(updatedConfig)
    })
    .then(response => {
        console.log('HTTP Status:', response.status);
        if (!response.ok) {
            throw new Error('Network response was not ok: ' + response.statusText);
        }
        return response.text();
    })
    .then(data => {
        console.log('Save response:', data);
        closeEditModal();
        getConfig();
    })
    .catch(err => {
        console.error('Error saving configuration:', err);
        alert('Failed to save configuration.');
    })
    .finally(() => {
        hideLoading();
    });
}



function closeEditModal() {
    document.getElementById('modalOverlay').classList.remove('show');
    document.getElementById('editModal').classList.remove('show');
}

function deleteIface(iface) {
    if (!confirm(`确定要删除 ${iface} 吗？`)) {
        return;
    }

    const deleteBtn = document.querySelector(`.delete-btn[data-iface="${iface}"]`);
    if (deleteBtn) {
        deleteBtn.textContent = "Deleting...";
        deleteBtn.disabled = true;
    }

    disableButtons(true);
    showLoading();

    fetch('/cgi-bin/delete_iface.sh', {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ iface: iface })
    })
    .then(response => response.text())
    .then(data => {
        console.log("Response from server:", data);

        if (data.includes("Done")) { 
            getConfig();
        } else {
            console.log("删除完成，但未检测到 Done，可能 WiFi 还在重启...");
            return new Promise(resolve => setTimeout(resolve, 1000));
        }
    })
    .catch(error => {
        console.error("Error:", error);
        alert("删除失败！");
    })
    .finally(() => {
        hideLoading();
        if (deleteBtn) {
            deleteBtn.textContent = "Delete";
            deleteBtn.disabled = false;
        }
        disableButtons(false); 
    });
}

function disableButtons(disable) {
    document.querySelectorAll("button").forEach(button => {
        button.disabled = disable;
    });

    if (disable) {
        console.log("所有按钮已禁用...");
    } else {
        console.log("所有按钮已恢复...");
    }
}

//add
async function openAddModal(device) {
    const modalContent = document.getElementById('edit-modal-content');
    const modal = document.getElementById('editModal');
    const overlay = document.getElementById('modalOverlay');

    const wifi = deviceConfig[device];
    if (!wifi) {
        console.error(`Device ${device} not found in deviceConfig.`);
        return;
    }

    let hwModesData = wifi.hw_modes || {};

    if (Object.keys(hwModesData).length === 0) {
        try {
            const hwModesResponse = await fetch(`/cgi-bin/get_hw_modes.sh?device=${device}`);
            const hwModesJson = await hwModesResponse.json();
            hwModesData = hwModesJson.hw_modes || {};
            console.log("Fetched HW Modes:", hwModesData);
        } catch (error) {
            console.error("Error fetching HW modes:", error);
        }
    }

    let defaultHwmode = wifi.hwmode || Object.keys(hwModesData)[0] || "11beg";

    let defaultHtmode = wifi.htmode;
    if (!defaultHtmode && hwModesData[defaultHwmode] && hwModesData[defaultHwmode].length > 0) {
        defaultHtmode = hwModesData[defaultHwmode][0];  // 选第一个可用 HT Mode
    }
    defaultHtmode = defaultHtmode || "EHT40";  // 兜底防止 undefined

    console.log(`Default HW Mode: ${defaultHwmode}, Default HT Mode: ${defaultHtmode}`);

    let hwmodeOptions = Object.keys(hwModesData)
        .map(hw => `<option value="${hw}" ${hw === defaultHwmode ? "selected" : ""}>${hw.toUpperCase()}</option>`)
        .join('');

    let htmodeOptions = hwModesData[defaultHwmode]
        ? hwModesData[defaultHwmode].map(ht => `<option value="${ht}" ${ht === defaultHtmode ? "selected" : ""}>${ht}</option>`).join('')
        : `<option value="">No HT Modes Available</option>`;

    let channelOptionsHtml = `<option value="auto" selected>Auto</option>`;
    if (wifi.channel_options) {
        Object.keys(wifi.channel_options).forEach(band => {
            channelOptionsHtml += `<optgroup label="--- ${band} ---"></optgroup>`;
            wifi.channel_options[band].forEach(chan => {
                channelOptionsHtml += `<option value="${chan}">${chan}</option>`;
            });
        });
    }

    let txpowerOptions = [5, 8, 11, 14, 17, 20, 23, "MAX"].map(value => 
        `<option value="${value}" ${value === "MAX" ? "selected" : ""}>${value}</option>`
    ).join('');

    let modalHtml = `
        <h3>Add Interface to ${device}</h3>
        <table>
            <tr>
                <td>Channel:</td>
                <td>
                    <select id="device-channel-${device}">
                        ${channelOptionsHtml}
                    </select>
                </td>
            </tr>
            <tr>
                <td>TX Power:</td>
                <td>
                    <select id="device-txpower-${device}">
                        ${txpowerOptions}
                    </select>
                </td>
            </tr>
            <tr>
                <td>Country:</td>
                <td>
                    <input type="text" id="device-country-${device}" value="${wifi.country || ''}" oninput="validateCountryCode('${device}')">
                    <span id="country-error-${device}" style="color: red; font-size: 0.9em;"></span>
                </td>
            </tr>
            <tr>
                <td>HW Mode:</td>
                <td>
                    <select id="device-hwmode-${device}" onchange="updateAddHtmode('${device}', '${defaultHtmode}', hwModesData)">
                        ${hwmodeOptions}
                    </select>
                </td>
            </tr>
            <tr id="htmode-row-${device}">
                <td>HT Mode:</td>
                <td>
                    <select id="device-htmode-${device}">
                        ${htmodeOptions}
                    </select>
                </td>
            </tr>
            <tr>
                <td>Disabled:</td>
                <td>
                    <select id="device-disabled-${device}">
                        <option value="0" selected>Enabled</option>
                        <option value="1">Disabled</option>
                    </select>
                </td>
            </tr>
        </table>

        <h3>New Interface</h3>
        <table>
            <tr><td>SSID:</td><td><input type="text" id="iface-ssid-new" value="myAP" required></td></tr>
            <tr>
                <td>Mode:</td>
                <td>
                    <select id="iface-mode-new" onchange="updateCipherOptions('new', this.value); togglePasswordField('new');">
                        <option value="ap" selected>Access Point (AP)</option>
                        <option value="sta">Station (STA)</option>
                    </select>
                </td>
            </tr>
            <tr>
                <td>Encryption:</td>
                <td>
                    <select id="iface-encryption-new" onchange="updateCipherOptions('new', document.getElementById('iface-mode-new').value); togglePasswordField('new');">
                        <option value="none" selected>None</option>
                        <option value="psk">WPA-PSK (WPA1)</option>
                        <option value="psk2">WPA2-PSK</option>
                        <option value="psk-mixed">WPA1/WPA2 Mixed</option>
                        <option value="sae">WPA3-SAE</option>
                        <option value="owe">OWE (Enhanced Open)</option>
                    </select>
                </td>
            </tr>
            <tr id="cipher-row-new" style="display: none;">
                <td>Cipher Mode:</td>
                <td>
                    <select id="iface-cipher-new"></select>
                </td>
            </tr>
            <tr id="password-row-new" style="display: none;">
                <td>Password:</td>
                <td><input type="password" id="iface-key-new"></td>
            </tr>
        </table>

        <button onclick="saveNewInterface('${device}')">Save</button>
        <button class="modal-close-btn" onclick="closeEditModal()">Close</button>
    `;

    modalContent.innerHTML = modalHtml;
    updateAddHtmode(device, defaultHtmode, hwModesData);
    updateCipherOptions("new", "ap");
    togglePasswordField("new");
    overlay.classList.add('show');
    modal.classList.add('show');
}

function updateAddHtmode(device, defaultHtmode, hwModesData = null) {
    const hwmodeSelect = document.getElementById(`device-hwmode-${device}`);
    const htmodeSelect = document.getElementById(`device-htmode-${device}`);
    const htmodeRow = document.getElementById(`htmode-row-${device}`);

    if (!hwmodeSelect || !htmodeSelect || !htmodeRow) {
        console.error(`Error: Missing elements for device ${device}`);
        return;
    }

    const hwmode = hwmodeSelect.value.trim();
    console.log("Selected HW Mode:", hwmode);

    if (!hwModesData) {
        console.log("Fetching HW Modes from API...");
        return fetch(`/cgi-bin/get_hw_modes.sh?device=${device}`)
            .then(response => response.json())
            .then(data => {
                console.log("Fetched HW Modes Data:", data);
                if (!data.hw_modes) {
                    console.error("Error: hw_modes data is missing.");
                    return;
                }
                hwModesData = data.hw_modes;
                updateAddHtmode(device, defaultHtmode, hwModesData);
            })
            .catch(error => console.error("Error fetching HT mode options:", error));
    }

    console.log("Available HW Modes:", hwModesData);

    if (!hwModesData || Object.keys(hwModesData).length === 0) {
        console.warn("No HW Modes found, hiding HT Mode select.");
        htmodeSelect.innerHTML = `<option value="">No HT Modes Available</option>`;
        htmodeRow.style.display = "none";
        return;
    }

    let matchedHwmode = Object.keys(hwModesData).find(
        key => key.trim().toLowerCase() === hwmode.trim().toLowerCase()
    );

    if (!matchedHwmode) {
        console.warn(`Warning: HW Mode '${hwmode}' not found in`, hwModesData);
        htmodeSelect.innerHTML = `<option value="">No HT Modes Available</option>`;
        htmodeRow.style.display = "none";
        return;
    }

    console.log(`Found HW Mode '${matchedHwmode}'`);

    const availableHtModes = hwModesData[matchedHwmode] || [];
    console.log(`HT Modes for ${matchedHwmode}:`, availableHtModes);

    if (["11b", "11g", "11a"].includes(matchedHwmode)) {
        htmodeRow.style.display = "none";
        htmodeSelect.innerHTML = "";
        return;
    }

    htmodeRow.style.display = "table-row";
    if (availableHtModes.length > 0) {
        htmodeSelect.innerHTML = availableHtModes
            .map(ht => `<option value="${ht}" ${ht === defaultHtmode ? "selected" : ""}>${ht}</option>`)
            .join('');
        console.log("Final HT Modes HTML:", htmodeSelect.innerHTML);
    } else {
        console.warn("No HT Modes Available");
        htmodeSelect.innerHTML = `<option value="">No HT Modes Available</option>`;
    }
}


function saveNewInterface(device) {
    console.log(`Saving new interface for device: ${device}`);

    const saveButton = document.querySelector(`button[onclick="saveNewInterface('${device}')"]`);
    const closeButton = document.querySelector(".modal-close-btn");

    saveButton.disabled = true;
    saveButton.textContent = "Saving...";
    closeButton.disabled = true;
    
    showLoading();
    const getValue = (id) => document.getElementById(id)?.value.trim() || "";

    let newConfig = {
        device,
        create_new: true, 
        channel: getValue(`device-channel-${device}`),
        txpower: getValue(`device-txpower-${device}`),
        country: getValue(`device-country-${device}`),
        hwmode: getValue(`device-hwmode-${device}`), 
        htmode: getValue(`device-htmode-${device}`), 
        iface: {
            ssid: getValue("iface-ssid-new"), 
            mode: getValue("iface-mode-new"), 
            encryption: getValue("iface-encryption-new"),
        }
    };

    if (newConfig.iface.encryption !== "none") {
        newConfig.iface.key = getValue("iface-key-new");
    }

    console.log("Final new interface JSON:", JSON.stringify(newConfig, null, 2));

    fetch('/cgi-bin/save_wifi_config.sh', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(newConfig)
    })
    .then(response => response.text())
    .then(async (data) => {
        console.log('Save response:', data);

        if (data.includes("Configuration saved successfully")) {
            console.log("WiFi reload in progress... Waiting for completion...");
            alert("New interface added successfully! Waiting for WiFi reload...");

            await new Promise(resolve => setTimeout(resolve, 8000));

            console.log("WiFi reload complete. Closing modal...");
            closeEditModal();
            getConfig();
        } else {
            alert("Failed to save configuration.");
        }
    })
    .catch(err => {
        console.error('Error saving new interface:', err);
        alert("Error: Could not save the configuration.");
    })
    .finally(() => {
        hideLoading();
        saveButton.disabled = false;
        saveButton.textContent = "Save";
        closeButton.disabled = false; 
        
    });
}

//scan
async function startScan(device) {
    try {
        showLoading();
        const response = await fetch(`/cgi-bin/scan.sh?device=${device}`);
        console.log('HTTP Status:', response.status);

        if (!response.ok) {
            throw new Error('Network response was not ok: ' + response.statusText);
        }

        const data = await response.json();
        console.log('Scan Result:', data);

        showScanResult(data);
    } catch (err) {
        console.error('Error during scanning:', err);
        alert('Failed to scan networks.');
    }finally{
        hideLoading();
    }
}

function showScanResult(scanData) {
    let modalContent = document.getElementById('scan-modal-content');
    let modal = document.getElementById('scanModal');
    let overlay = document.getElementById('scanOverlay');

    if (!modal || !overlay) {
        console.error('Modal elements not found.');
        return;
    }
     console.log("before Sorted Scan Data:", scanData.results);
    scanData.results.sort((a, b) => {
          const signalA = parseInt(a.signal, 10);  
          const signalB = parseInt(b.signal, 10);  
          return signalB - signalA;
    });
    console.log("Sorted Scan Data:", scanData.results);
    let resultHtml = `<h3>Scan Result for ${scanData.device}</h3>`;
    resultHtml += `
        <table class="scan-table">
            <thead>
                <tr>
                    <th>Signal (dBm)</th>
                    <th>SSID</th>
                    <th>Channel</th>
                    <th>BSSID</th>
                    <th>Mode</th>
                    <th>Encryption</th>
                    <th>Join</th>
                </tr>
            </thead>
            <tbody>
    `;

    scanData.results.forEach(result => {
        if (result.ssid) {
            let encryption = result.encryption ? (result.encryption.includes("Open") ? "none" : result.encryption) : "Unknown";
            resultHtml += `
                <tr>
                    <td>${result.signal} dBm</td>
                    <td>${result.ssid}</td>
                    <td>${result.channel || 'N/A'}</td>
                    <td>${result.bssid || 'N/A'}</td>
                    <td>${result.mode || 'Unknown'}</td>
                    <td>${encryption}</td>
                    <td>
                        <button class="join-btn" onclick="joinNetwork('${scanData.device}', '${result.ssid}', '${result.bssid}', '${result.channel}', '${result.encryption}')">Join</button>
                    </td>
                </tr>
            `;
        }
    });

    resultHtml += `</tbody></table>`;
    resultHtml += `<button class="modal-close-btn" onclick="closeScanModal()">Close</button>`;

    modalContent.innerHTML = resultHtml;
    overlay.classList.add('show');
    modal.classList.add('show');

}

function showPasswordModal(ssid, callback) {
    console.log("Opening password modal for SSID:", ssid);

    let existingModal = document.getElementById("password-modal");
    if (existingModal) {
        console.log("Password modal already exists, removing...");
        document.body.removeChild(existingModal);
    }

    let modal = document.createElement("div");
    modal.id = "password-modal";
    modal.classList.add("modal", "show");  
    modal.innerHTML = `
        <div class="modal-content">
            <h3>Connect to ${ssid}</h3>
            <label>Password:</label>
            <div class="password-wrapper">
                <input type="password" id="wifi-password"
                       onmousedown="this.type='text'" 
                       onmouseup="this.type='password'" 
                       onmouseleave="this.type='password'"
                       autofocus>
            </div>
            <div class="modal-actions">
                <button id="join-btn">Join</button>
                <button id="cancel-btn">Cancel</button>
            </div>
        </div>`;

    modal.style.zIndex = "10000";  // 
    modal.style.display = "block";
    modal.style.visibility = "visible";
    modal.style.opacity = "1";

    document.body.appendChild(modal);

    document.getElementById("join-btn").addEventListener("click", function() {
        let password = document.getElementById("wifi-password").value;
        document.body.removeChild(modal);

        if (scanOverlay) {
            scanOverlay.style.display = "block";
        }

        callback(password);
    });

    document.getElementById("cancel-btn").addEventListener("click", function() {
        document.body.removeChild(modal);
        
        if (scanOverlay) {
            scanOverlay.style.display = "block";
        }
    });
}


async function joinNetwork(device, ssid, bssid, channel, encryption) {
    console.log("Join clicked:", { device, ssid, bssid, channel, encryption });

    if (encryption !== "Open") {
        showPasswordModal(ssid, async (password) => {
            if (!password) {
                alert("Password is required.");
                return;
            }
            await sendJoinRequest(device, ssid, bssid, channel, encryption, password);
        });
    } else {
        await sendJoinRequest(device, ssid, bssid, channel, encryption, "");
    }
}

async function sendJoinRequest(device, ssid, bssid, channel, encryption, password) {
    try {

        showLoading();
        const response = await fetch(`/cgi-bin/join_wifi.sh`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ device, ssid, bssid, channel, encryption, password })
        });

        const text = await response.text();
        console.log("Raw response:", text);

        const match = text.match(/{.*}/s); 
        if (!match) throw new Error("No valid JSON found");

        const result = JSON.parse(match[0]);

        if (result.success) {
            closeScanModal();
            getConfig();
        } else {
            alert(`Failed to join ${ssid}: ${result.error || "Unknown error"}`);
        }
    } catch (err) {
        console.error("Join network error:", err);
        alert("Error joining the network.");
    }finally{
        hideLoading();
    }
}


function closeScanModal() {
    console.log("Closing scan modal...");
    document.getElementById('scanOverlay').classList.remove('show');
    document.getElementById('scanModal').classList.remove('show');
}

function showLoading() {
    let overlay = document.getElementById("loading-overlay");
    if (!overlay) {
        console.error("showLoading: loading-overlay not found!");
        return;
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


function fetchAssociatedStations() {
    fetch("/cgi-bin/get_associated_stations.sh")
        .then(response => response.json())
        .then(data => updateStationsTable(data))
        .catch(error => console.error("Failed to fetch stations:", error));
}

function updateStationsTable(stationsData) {
    const tableBody = document.getElementById("associated-stations");

    if (!tableBody) {
        console.error("Error: Table body not found!");
        return;
    }

    let newRowsHtml = "";

    stationsData.forEach(device => {
        device.stations.forEach(station => {
            newRowsHtml += `
                <tr>
                    <td>${device.ssid}</td>
                    <td>${device.mode}</td>
                    <td>${station.mac}</td>
                    <td>${station.rssi}</td>
                    <td>${station.rx_rate}</td>
                    <td>${station.tx_rate}</td>
                </tr>
            `;
        });
    });

    requestAnimationFrame(() => {
        tableBody.innerHTML = newRowsHtml;
    });
}
