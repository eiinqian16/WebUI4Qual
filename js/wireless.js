async function getConfig() {                                                                                                  
    try {                                                                                                        
        const response = await fetch('/cgi-bin/get_wifi_config.sh');                                                 
        console.log('HTTP Status:', response.status);                                                          
                                                                                                                                   
        if (!response.ok) {                                                                                               
            throw new Error('Network response was not ok: ' + response.statusText);                                           
        }                                                                                                        
                                                                                                                     
        const data = await response.json();                                                                    
        console.log('Fetched data:', data);                                                                                        
                                                                                                                          
        deviceConfig = {};                                                                                                    
        Object.keys(data).forEach(device => {                                                                    
            deviceConfig[device] = {                                                                                 
                ...data[device],                                                                               
                interfaces: Array.isArray(data[device].interfaces) ? data[device].interfaces : []                                  
            };                                                                                                            
        });                                                                                                                   
                                                                                                                 
        renderWifiList();                                                                                            
    } catch (err) {                                                                                            
        console.error('Error fetching configuration:', err);                                                                       
    }                                                                                                                     
}                

function renderWifiList() {                                                                                          
    const wifiList = document.getElementById('wifi-list');                                                     
    wifiList.innerHTML = '';                                                                                                       
                                                                                                                          
    Object.values(deviceConfig).forEach(wifi => {                                                                             
        wifiList.innerHTML += `                                                                                  
            <tr>                                                                                                     
                <td><strong>WiFi Device (${wifi.device})</strong></td>                                         
                <td>                                                                                                               
                    <button class="scan-btn" data-device="${wifi.device}">Scan</button>                                   
                    <button class="add-btn" data-device="${wifi.device}">Add</button>                                         
                </td>                                                                                            
            </tr>                                                                                                    
        `;                                                                                                     
        wifi.interfaces.forEach(iface => {                                                                                         
            wifiList.innerHTML += `                                                                                       
                <tr>                                                                                                          
                    <td>SSID: ${iface.ssid} (${iface.mode})</td>                                             
                    <td>                                                                                             
                        <button class="edit-btn" data-device="${wifi.device}" data-iface="${iface.iface}">Edit</button>
                        <button class="delete-btn" data-iface="${iface.iface}">Delete</button>                                     
                    </td>                                                                                                 
                </tr>                                                                                                         
            `;                                                                                                   
        });                                                                                                          
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
                                                                                       
    let hwModesResponse = await fetch(`/cgi-bin/get_hw_modes.sh?device=${device}`);                              
    let hwModesData = await hwModesResponse.json();                                                                  
    console.log("Available HW Modes:", hwModesData);

    let hwmodeOptions = Object.keys(hwModesData.hw_modes)                                                                     
        .map(hw => `<option value="${hw}" ${hw === hwmodeValue ? "selected" : ""}>${hw.toUpperCase()}</option>`) 
        .join('');                                                                                                   

    const modeValue = ifaceConfig.mode || "ap"; 
    updateCipherOptions(iface, modeValue);


    const encryptionValue = ifaceConfig.encryption || "none";
    const cipherValue = ifaceConfig.cipher || "auto";
    
    let encryptionOptions = `
        <option value="none" ${encryptionValue === "none" ? "selected" : ""}>None</option>
        <option value="psk" ${encryptionValue === "psk" ? "selected" : ""}>WPA-PSK (WPA1)</option>
        <option value="psk2" ${encryptionValue === "psk2" ? "selected" : ""}>WPA2-PSK</option>
        <option value="psk-mixed" ${encryptionValue === "psk-mixed" ? "selected" : ""}>WPA1/WPA2 Mixed</option>
        <option value="sae" ${encryptionValue === "sae" ? "selected" : ""}>WPA3-SAE</option>
        <option value="sae-mixed" ${encryptionValue === "sae-mixed" ? "selected" : ""}>WPA2/WPA3 Mixed</option>
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
                            onchange="updateCipherOptions('${iface}', this.value); togglePasswordField('${iface}');">
                        <option value="ap" ${ifaceConfig.mode === "ap" ? "selected" : ""}>Access Point (AP)</option>               
                        <option value="sta" ${ifaceConfig.mode === "sta" ? "selected" : ""}>Station (STA)</option>                 
                    </select>                                                                                                      
                </td>                                                                                                              
            </tr>
                                                                                                                
            <tr>                                                                                                                   
                <td>Encryption:</td>                                                                                               
                <td>                                                                                                               
                    <select id="iface-encryption-${iface}" onchange="updateCipherOptions('${iface}', document.getElementById('iface-mode-${iface}').value); togglePasswordField('${iface}');">
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
    document.getElementById(`iface-encryption-${iface}`).innerHTML = encryptionOptions;
    document.getElementById(`iface-cipher-${iface}`).innerHTML =cipherOptions;                                                                           
    togglePasswordField(iface);                                                                                                    
    overlay.classList.add('show');                                                                                                 
    modal.classList.add('show');                                                                                                   
}                                

function updateCipherOptions(iface, mode) { 
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

    if (mode === "ap") {
        switch (selectedEnc) {
            case "psk":  
                cipherOptions = [
                    { value: "tkip", text: "TKIP" },
                    { value: "ccmp", text: "CCMP" },
                    { value: "ccmp+tkip", text: "CCMP+TKIP (Legacy)" }
                ];
                break;
            case "psk2": 
                cipherOptions = [
                    { value: "ccmp", text: "CCMP" },
                    { value: "ccmp+tkip", text: "CCMP+TKIP (Legacy)" }
                ];
                break;
            case "psk-mixed":
                cipherOptions = [
                    { value: "tkip", text: "TKIP" },
                    { value: "ccmp", text: "CCMP" },
                    { value: "ccmp+tkip", text: "CCMP+TKIP (Legacy)" }
                ];
                break;
            case "sae": 
                cipherOptions = [
                    { value: "gcmp", text: "GCMP" },
                    { value: "ccmp", text: "CCMP" }
                ];
                break;
            case "sae-mixed":
                cipherOptions = [
                    { value: "ccmp", text: "CCMP" },
                    { value: "gcmp", text: "GCMP" }
                ];
                break;
            case "owe":  
                cipherOptions = [
                    { value: "ccmp", text: "CCMP" },
                    { value: "gcmp", text: "GCMP" }
                ];
                break;
            default:
                cipherOptions = [];
        }
    } else if (mode === "sta") {
        cipherOptions = [{ value: "auto", text: "Auto (Default)" }];
        if (["psk", "psk2"].includes(selectedEnc)) {
            cipherOptions.push({ value: "ccmp", text: "CCMP" });
        } else if (["sae", "sae-mixed"].includes(selectedEnc)) {
            cipherOptions.push(
                { value: "gcmp", text: "GCMP" },
                { value: "ccmp", text: "CCMP" }
            );
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
    const hwmodeSelect = document.getElementById(`device-hwmode-${device}`);                                                       
    const htmodeSelect = document.getElementById(`device-htmode-${device}`);                                                       
    const htmodeRow = document.getElementById(`htmode-row-${device}`);                                                             
                                                                                                                                   
    if (!hwmodeSelect || !htmodeSelect) {                                                                                          
        console.error("... Error: Cannot find HW mode or HT mode select elements.");                                               
        return;                                                                                                                    
    }                                                                                                                              
                                                                                                                                   
    const hwmode = hwmodeSelect.value.trim();                                                                                      
    console.log(".... Current selected hwmode:", hwmode);                                                                          
                                                                                                                                   
    fetch(`/cgi-bin/get_hw_modes.sh?device=${device}`)                                                                             
        .then(response => response.json())                                                                                         
        .then(data => {                                                                                                            
            console.log(".... Fetched HW Modes Data:", data);                                                                      
                                                                                                                                   
            if (!data.hw_modes) {                                                                                                  
                console.error("Error: hw_modes data is missing.");                                                                 
                return;                                                                                                            
            }                                                                                                                      
                                                                                                                                   
            console.log(".... Available HW Modes:", Object.keys(data.hw_modes));                                                   
                                                                                                                                   
            let matchedHwmode = Object.keys(data.hw_modes).find(key => key.trim() === hwmode.trim());                              
            if (!matchedHwmode) {                                                                                                  
                console.warn(`... Warning: HW Mode '${hwmode}' not found in`, data.hw_modes);                                      
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
            htmodeSelect.innerHTML = availableHtModes.length > 0                                                                   
                ? availableHtModes.map(ht => `<option value="${ht}" ${ht === htmodeValue ? "selected" : ""}>${ht}</option>`).join('')                                      
                : `<option value="">No HT Modes Available</option>`;                                                               
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
    let finalChannel = rawChannel === "auto" ? "auto" : rawChannel.split(" ")[0];

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
        return;
    }

    const updatedConfig = {
        device,
        create_new: false, 
        type: getValue(`device-type-${device}`),
        channel: finalChannel,
        txpower: txpower,
        country: getValue(`device-country-${device}`),
        hwmode: hwmode,
        htmode: htmode,
        disabled: getValue(`device-disabled-${device}`) || "0",
        iface: {
            iface: iface, 
            network: getValue(`iface-network-${iface}`),
            ssid: getValue(`iface-ssid-${iface}`),
            mode: getValue(`iface-mode-${iface}`),
            encryption: encryption
        }
    };
    
    if (encryption.includes("psk") || encryption.includes("sae")) {
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
        alert('Configuration saved successfully!');
        closeEditModal();
        getConfig();
    })
    .catch(err => {
        console.error('Error saving configuration:', err);
        alert('Failed to save configuration.');
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

    fetch('/cgi-bin/delete_iface.sh', {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ iface: iface })
    })
    .then(response => response.text())
    .then(data => {
        console.log("Response from server:", data);

        if (data.includes("Done")) { 
            alert(`删除 ${iface} 成功，WiFi 重新加载完成！`);
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
        console.error(`Device ${device} not found.`);
        return;
    }

    let txpowerOptions = [5, 8, 11, 14, 17, 20, 23, "MAX"].map(value => 
        `<option value="${value}" ${value === "MAX" ? "selected" : ""}>${value}</option>`
    ).join('');

    let channelOptionsHtml = `<option value="auto" selected>auto</option>`;
    if (wifi.channel_options) {
        Object.keys(wifi.channel_options).forEach(band => {
            channelOptionsHtml += `<optgroup label="--- ${band} ---"></optgroup>`;
            wifi.channel_options[band].forEach(chan => {
                channelOptionsHtml += `<option value="${chan}">${chan}</option>`;
            });
        });
    }

    let hwModesResponse = await fetch(`/cgi-bin/get_hw_modes.sh?device=${device}`);
    let hwModesData = await hwModesResponse.json();
    console.log("Available HW Modes for Add Modal:", hwModesData);

    let defaultHwmode = "11bea";
    let defaultHtmode = "EHT320";

    let hwmodeOptions = Object.keys(hwModesData.hw_modes)
        .map(hw => `<option value="${hw}" ${hw === defaultHwmode ? "selected" : ""}>${hw.toUpperCase()}</option>`)
        .join('');

    function generateHtmodeOptions(hwmode) {
        let htmodeOptions = "";
        if (hwModesData.hw_modes[hwmode]) {
            htmodeOptions = hwModesData.hw_modes[hwmode]
                .map(ht => `<option value="${ht}" ${ht === defaultHtmode ? "selected" : ""}>${ht}</option>`)
                .join('');
        }
        return htmodeOptions;
    }

    let htmodeOptions = generateHtmodeOptions(defaultHwmode);

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
                    <input type="text" id="device-country-${device}" value="" oninput="validateCountryCode('${device}')">
                    <span id="country-error-${device}" style="color: red; font-size: 0.9em;"></span>
                </td>
            </tr>
            <tr>
                <td>HW Mode:</td>
                <td>
                    <select id="device-hwmode-${device}" onchange="updateAddHtmode('${device}')">
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
        </table>

        <h3>New Interface</h3>
        <table>
            <tr><td>SSID:</td><td><input type="text" id="iface-ssid-new" value="myAP" required></td></tr>
            <tr>
                <td>Mode:</td>
                <td>
                    <select id="iface-mode-new">
                        <option value="ap" selected>Access Point (AP)</option>
                        <option value="sta">Station (STA)</option>
                    </select>
                </td>
            </tr>
            <tr>
                <td>Encryption:</td>
                <td>
                    <select id="iface-encryption-new" onchange="togglePasswordField('new')">
                        <option value="none" selected>None</option>
                        <option value="psk2">WPA2-PSK</option>
                    </select>
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
    updateAddHtmode(device);
    togglePasswordField("new");
    overlay.classList.add('show');
    modal.classList.add('show');
}

function updateAddHtmode(device) {
    const hwmode = document.getElementById(`device-hwmode-${device}`).value;
    const htmodeSelect = document.getElementById(`device-htmode-${device}`);
    const htmodeRow = document.getElementById(`htmode-row-${device}`);

    fetch(`/cgi-bin/get_hw_modes.sh?device=${device}`)
        .then(response => response.json())
        .then(data => {
            if (["11b", "11g", "11a"].includes(hwmode)) {
                htmodeRow.style.display = "none";
                htmodeSelect.innerHTML = "";
            } else {
                htmodeRow.style.display = "table-row";
                htmodeSelect.innerHTML = data.hw_modes[hwmode]
                    .map(ht => `<option value="${ht}">${ht}</option>`)
                    .join('');
            }
        })
        .catch(error => console.error("Error updating HT mode:", error));
}

function saveNewInterface(device) {
    console.log(`Saving new interface for device: ${device}`);

    const saveButton = document.querySelector(`button[onclick="saveNewInterface('${device}')"]`);
    const closeButton = document.querySelector(".modal-close-btn");

    saveButton.disabled = true;
    saveButton.textContent = "Saving...";
    closeButton.disabled = true;

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
        saveButton.disabled = false;
        saveButton.textContent = "Save";
        closeButton.disabled = false; 
    });
}

//scan
async function startScan(device) {
    try {
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
    }
}

function showScanResult(scanData) {
    let modalContent = document.getElementById('scan-modal-content');
    let modal = document.getElementById('scanModal');
    let overlay = document.getElementById('modalOverlay');

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
        <table>
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
            let encryption = result.encryption.includes("Open") ? "none" : result.encryption;
            resultHtml += `
                <tr>
                    <td>${result.signal}</td>
                    <td>${result.ssid}</td>
                    <td>${result.channel}</td>
                    <td>${result.bssid}</td>
                    <td>${result.mode}</td>
                    <td>${result.encryption}</td>
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

//join network(ing)
async function joinNetwork(device, ssid, bssid, channel, encryption) {
    let password = "";
    if (encryption !== "Open") {
        password = prompt(`Enter password for ${ssid}:`);
        if (!password) {
            alert("Password is required.");
            return;
        }
    }

    try {
        const response = await fetch(`/cgi-bin/join_wifi.sh`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify({ device, ssid, bssid, channel, encryption, password })
        });

        const result = await response.json();
        if (result.success) {
            alert(`Successfully joined ${ssid}`);
            getConfig();
        } else {
            alert(`Failed to join ${ssid}: ${result.error}`);
        }
    } catch (err) {
        console.error("Join network error:", err);
        alert("Error joining the network.");
    }
}

function closeScanModal() {
    console.log("Closing scan modal...");
    document.getElementById('modalOverlay').classList.remove('show');
    document.getElementById('scanModal').classList.remove('show');
}
