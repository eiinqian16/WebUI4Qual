async function loadPowerMode() {
    const resp = await fetch('/cgi-bin/eco_mode_v2.sh?action=status');
    const data = await resp.json();
    if (data.status === "OK") {
        document.querySelector(`input[value="${data.applied_mode}"]`).checked = true;
    }
}

document.addEventListener("DOMContentLoaded", loadPowerMode);

async function setPowerMode() {
    const selected = document.querySelector('input[name="powerMode"]:checked');
    if (!selected) {
        return alert('Please select a mode');
    }

    const mode = selected.value;
    console.log(mode);
    
    try {
        const resp = await fetch(`/cgi-bin/eco_mode_v2.sh?action=${mode}`);
        if (!resp.ok) throw new Error(`Server responded with ${resp.status}`);
        
        const data = await resp.json();

        if (data.status === "OK") {
            alert(`Applied ${data.applied_mode.toUpperCase()} mode successfully!`);
            loadPowerMode();
        } 
        else {
            alert(`failed: ${data.error || "Unknown error"}`);
        }
    } catch (error) {
        console.error("Eco mode switch failed:", error);
        alert(`Request failed. The system may be applying changes and restarting Wi-Fi.`);
    }
}

let isEcoMasterScheduleActive = false;
let currentEcoScheduleConfig = {
    repeatDays: ['Su', 'M', 'Tu', 'W', 'Th', 'F', 'Sa']
}

let savedEcoSchedules = [];
let eco_systemTime = null;
let eco_timezone = null;

async function initClock() {
    try {
        const resp = await fetch('/cgi-bin/get_time.sh');
        const text = await resp.text();
        const data = JSON.parse(text);
        eco_timezone = data.timezone;

        if (data && data.epoch) {
            eco_systemTime = new Date(data.epoch * 1000);
            updateClock();
            setInterval(updateClock, 1000);
        }
        else {
            throw new Error("Invalid data format received");
        }
    }
    catch (error) {
        console.error("DEBUG CLOCK ERROR:", error);
        document.getElementById('currentTime').innerText = "Sync Error";
    }
}

function updateClock() {
    if(!eco_systemTime) return;
    eco_systemTime.setSeconds(eco_systemTime.getSeconds() + 1);
    const options = {
        weekday: 'long',
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        hour12: true,
        timeZone: eco_timezone
    };

    const clockEl = document.getElementById('currentTime');
    if (clockEl) {
        let timeString = eco_systemTime.toLocaleString(undefined, options);
        clockEl.innerText = timeString.toUpperCase();
    }
}

function updateEcoMasterToggle(isActive) {
    const toggle = document.getElementById('master-eco-toggle');
    if (isActive) {
        toggle.classList.add('active');
    }
    else {
        toggle.classList.remove('active');
    }
    isEcoMasterScheduleActive = isActive;
}

function toggleEcoScheduleWithConfirmation() {
    const stateToSet = !isEcoMasterScheduleActive;
    const title = stateToSet ? "Enable Wireless Schedule?" : "Disable Wireless Schedule?";
    const message = stateToSet ? "Enabling this feature might cause temporary disruption to the wireless connection. Continue?" : "Disabling this schedule will turn on wireless connection immediately. Continue?";

    document.getElementById('eco-confirmation-title').textContent = title;
    document.getElementById('eco-confirmation-message').textContent = message;

    showEcoModal(document.getElementById('confirmation-eco-backdrop'));
}

async function confirmEcoToggle(confirmed) {
    hideEcoModal(document.getElementById('confirmation-eco-backdrop'));

    if(confirmed) {
        const newState = !isEcoMasterScheduleActive;
        updateEcoMasterToggle(newState);
        
        console.log(`Master Wireless Schedule confirmed and set to: ${newState ? 'Enabled' : 'Disabled'}`);

        // Send each schedule entry individually to the backend
        try {
            for (const entry of savedEcoSchedules) {
                const resp = await fetch("/cgi-bin/eco_schedule.sh", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify(entry)
                });

                if (!resp.ok) {
                    throw new Error(`HTTP error! Status: ${resp.status}`);
                }

                const result = await resp.json();
                console.log('Schedule entry saved:', result);
            }

            alertSuccess(`Wireless Schedule ${newState ? 'Enabled' : 'Disabled'} and ALL configuration data sent.`);
        }
        catch (error) {
            console.error("Error sending schedule status:", error);
            alertSuccess(`Failed to update status: ${error.message}. Configuration reverted.`);
            updateEcoMasterToggle(!newState);
        }
    }
    else {
        console.log("Toggle cancelled by user");
    }
}

async function fetchEcoSchedules() {
    try {
        const resp = await fetch("/config/eco_schedule");

        if (!resp.ok) {
            const errorText = await resp.text();
            console.error(`HTTP Error: ${resp.status} - ${errorText}`);
            return [];
        }

        const data = await resp.json();

        if (!Array.isArray(data)) {
            console.error("Backend response is not a valid JSON array of schedules.", data);
            return [];
        }

        if (data.length === 0) {
            console.warn("Backend returned an empty list");
        }

        return data;
    }
    catch (error) {
        console.error("Error fetching schedules from /config/schedule:", error);
        alertSuccess(`Failed to fetch schedules: ${error.message}. Displaying empty list.`);
        return [];
    }
}

function openEcoAddModal() {
    const modalTitle = document.getElementById('modal-eco-title');
    const editIdInput = document.getElementById('edit-eco-id');

    if (modalTitle) modalTitle.textContent = "Add Schedule Entry";
    if (editIdInput) editIdInput.value = "";

    currentEcoScheduleConfig.repeatDays = ['Su', 'M', 'Tu', 'W', 'Th', 'F', 'Sa'];
    document.querySelectorAll('#day-eco-toggles .day-eco-toggle').forEach(el => {
        el.classList.add('selected');
    });

    populateEcoTime();
    if(document.getElementById('off-hour-eco')) document.getElementById('off-hour-eco').value = 11;
    if(document.getElementById('off-minute-eco')) document.getElementById('off-minute-eco').value = "00";
    if(document.getElementById('off-ampm-eco')) document.getElementById('off-ampm-eco').value = "PM";
    if(document.getElementById('on-hour-eco')) document.getElementById('on-hour-eco').value = 7;
    if(document.getElementById('on-minute-eco')) document.getElementById('on-minute-eco').value = "00";
    if(document.getElementById('on-ampm-eco')) document.getElementById('on-ampm-eco').value = "AM";
    
    const backdrop = document.getElementById('add-eco-schedule-backdrop');
    if (backdrop) showEcoModal(backdrop);
}

function closeEcoAddModal() {
    hideEcoModal(document.getElementById('add-eco-schedule-backdrop'));
}

function showEcoModal(backdropElement) {
    backdropElement.classList.add('show');
    const content = backdropElement.querySelector('.schedule-eco-modal-content');
    if (content) {
        setTimeout(() => content.style.transform = 'scale(1)', 10);
    }
}

function hideEcoModal(backdropElement) {
    const content = backdropElement.querySelector('.schedule-eco-modal-content');
    if (content) {
        content.style.transform = 'scale(0.95)';
    }
    setTimeout(() => {
        backdropElement.classList.remove('show');
    }, 300);
}

function editEcoConfig(id) {
    const entry = getEcoConfigId(id);
    if (!entry) {
        alertSuccess("Error: Could not find schedule entry to edit.");
        return;
    }

    document.getElementById('modal-eco-title').textContent = "Edit Schedule Entry";
    document.getElementById('edit-eco-id').value = entry.id;
    populateEcoTime();
    document.getElementById('off-hour-eco').value = entry.offHour;
    document.getElementById('off-minute-eco').value = entry.offMinute;
    document.getElementById('off-ampm-eco').value = entry.offAP;
    document.getElementById('on-hour-eco').value = entry.onHour;
    document.getElementById('on-minute-eco').value = entry.onMinute;
    document.getElementById('on-ampm-eco').value = entry.onAP;
    
    document.querySelectorAll('#day-eco-toggles .day-eco-toggle').forEach(el => {
        el.classList.remove('selected');
    });

    currentEcoScheduleConfig.repeatDays = [...entry.repeatDays];

    currentEcoScheduleConfig.repeatDays.forEach(day => {
        const el = document.querySelector(`#day-eco-toggles .day-eco-toggle[data-day="${day}"]`);
        if (el) {
            el.classList.add('selected');
        }
    });

    showEcoModal(document.getElementById('add-eco-schedule-backdrop'));
}

async function deleteEcoConfig(id) {
    try {
        const resp = await fetch("/cgi-bin/eco_schedule.sh", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ action: "delete", id: id})
        });

        if (!resp.ok) {
            throw new Error(`HTTP error! Status: ${resp.status}`);
        }

        const result = await resp.json();
        console.log('Delete result', result);

        savedEcoSchedules = savedEcoSchedules.filter(entry => entry.id !== id);
        renderEcoScheduleList();
        alertSuccess("Schedule entry deleted successfully.");
    }
    catch (error) {
        console.error("Error deleting schedule:", error);
        alertSuccess(`Failed to delete schedule: ${error.message}`);
    }
}

function alertSuccess(message) {
    const noti = document.createElement('div');
    // Fixed: added missing semicolon after background-color
    noti.style.cssText = `
    position: fixed;
    top: 20px;
    right: 20px;
    background-color: #d1fae5;
    color: #065f46;
    padding: 1rem 1.5rem;
    border-radius: 0.5rem;
    box-shadow: 0 4px 6px rgba(0,0,0,0.1);
    z-index: 101;
    font-size: 0.875rem;
    opacity: 0;
    transition: opacity 0.5s;
    `;
    noti.textContent = message;
    document.body.appendChild(noti);

    setTimeout(() => noti.style.opacity = 1, 10);
    setTimeout(() => {
        noti.style.opacity = 0;
        setTimeout(() => noti.remove(), 500);
    }, 3000);
}

function toggleEcoDay(element) {
    const day = element.getAttribute('data-day');
    const isSelected = element.classList.toggle('selected');

    if (isSelected) {
        if (!currentEcoScheduleConfig.repeatDays.includes(day)) {
            currentEcoScheduleConfig.repeatDays.push(day);
        }
    }
    else {
        currentEcoScheduleConfig.repeatDays = currentEcoScheduleConfig.repeatDays.filter(d => d !== day);
    }
    console.log("Selected Days:", currentEcoScheduleConfig.repeatDays);
}

function handleEcoCancel() {
    console.log("Add Schedule entry cancelled.");
    closeEcoAddModal();
}

function populateEcoTime() {
    const onTime = document.getElementById('on-hour-eco');
    const offTime = document.getElementById('off-hour-eco');

    onTime.innerHTML = "";
    offTime.innerHTML = "";

    for (let i = 1; i <= 12; i++) {
        displayVal = i.toString().padStart(2, "0");
        optionVal = i;

        let offOpt = document.createElement('option');
        offOpt.textContent = displayVal;
        offOpt.value = optionVal;
        offTime.appendChild(offOpt);

        let onOpt = document.createElement('option');
        onOpt.textContent = displayVal;
        onOpt.value = optionVal; // Fixed: was displayVal, should be optionVal
        onTime.appendChild(onOpt);
    }

    onTime.value = 7;
    offTime.value = 11;
}

function getEcoScheduleData() {
    return {
        masterEnabled: isEcoMasterScheduleActive,
        entries: savedEcoSchedules
    };
}

function renderEcoScheduleList() {
    const scheduleList = document.getElementById('schedule-list');
    scheduleList.innerHTML = '';

    if (savedEcoSchedules.length === 0) {
        scheduleList.innerHTML = `
        <div class="schedule-placeholder">
            <span>No schedules configured yet. </span>
        </div>
        `;
        return;
    }

    savedEcoSchedules.forEach(entry => {
        const repeatDaysText = (entry.repeatDays || []).join(', ');
        const newEntry = document.createElement('div');

        newEntry.style.cssText = 'padding: 0.75rem; background-color: white; border: 1px solid #93c5fd; border-radius: 0.5rem; color: #374151; display: flex; justify-content: space-between; align-items: center;';

        newEntry.innerHTML = `
        <span>
            <strong>Configured</strong>:
            Off at ${entry.offTime}, On at ${entry.onTime}
            <span style="color: #6b7280; margin-left: 10px;">(Repeat: ${repeatDaysText})</span>
        </span>
        <div style="display: flex; gap: 0.5rem;">
            <button class="icon-only-btn" onclick="editEcoConfig('${entry.id}')" title="Edit">
                <img src="/logo/edit.png" alt="Edit"
                style="width: 20px; height: 20px; filter: invert(48%) sepia(79%) saturate(2476%) hue-rotate(86deg) brightness(118%) contrast(119%);">
            </button>
            <button class="icon-only-btn" onclick="deleteEcoConfig('${entry.id}')" title="Delete">
                <img src="/logo/bin.png" alt="Delete"
                style="width: 20px; height: 20px; filter: invert(27%) sepia(91%) saturate(7352%) hue-rotate(358deg) brightness(104%) contrast(107%);">
            </button>
        </div>
        `;
        scheduleList.appendChild(newEntry);
    });
}

function handleEcoSave() {
    const editId = document.getElementById('edit-eco-id')?.value;

    if (currentEcoScheduleConfig.repeatDays.length === 0) {
        alertSuccess("Please select at least 1 day for schedule.");
        return;
    }

    const offHr = document.getElementById('off-hour-eco').value;
    const onHr = document.getElementById('on-hour-eco').value;
    const offMin = document.getElementById('off-minute-eco').value;
    const onMin = document.getElementById('on-minute-eco').value;
    const offAmPm = document.getElementById('off-ampm-eco').value;
    const onAmPm = document.getElementById('on-ampm-eco').value;
    const offTimeStr = `${offHr.padStart(2, '0')}:${offMin} ${offAmPm}`;
    const onTimeStr = `${onHr.padStart(2, '0')}:${onMin} ${onAmPm}`;

    const newScheduleEntry = {
        offHour: offHr,
        offMinute: offMin,
        offAP: offAmPm,
        onHour: onHr,
        onMinute: onMin,
        onAP: onAmPm,
        offTime: offTimeStr,
        onTime: onTimeStr,
        // Fixed: removed extra array wrapping
        repeatDays: [...currentEcoScheduleConfig.repeatDays].sort((a, b) => 
            ['Su', 'M', 'Tu', 'W', 'Th', 'F', 'Sa'].indexOf(a) - ['Su', 'M', 'Tu', 'W', 'Th', 'F', 'Sa'].indexOf(b)
        )
    };

    if (editId) {
        const index = savedEcoSchedules.findIndex(e => e.id === editId);
        if (index !== -1) {
            const finalData = { ...newScheduleEntry, id: editId };
            savedEcoSchedules[index] = finalData;
            alertSuccess("Schedule entry successfully updated.");
            console.log(finalData);
        }
    }
    else {
        const newId = generateEcoUUID();
        const finalData = { ...newScheduleEntry, id: newId };
        savedEcoSchedules.push(finalData);
        alertSuccess("New schedule entry saved.");
        console.log(finalData);
    }

    renderEcoScheduleList();
    closeEcoAddModal();
}

async function initEcoAdvanced() {
    console.log('Initializing advanced.js');
    
    updateEcoMasterToggle(isEcoMasterScheduleActive);

    //loadEcoScheduleTime();
    
    /*
    setInterval(() => {
        loadEcoScheduleTime();
    }, 1000);
    */
    initClock();
    console.log('Time interval started');

    const dayToggleContainer = document.getElementById('day-eco-toggles');
    if (dayToggleContainer) {
        const dayToggleElements = dayToggleContainer.children;
        for (let toggle of dayToggleElements) {
            toggle.addEventListener('click', () => toggleEcoDay(toggle));
        }
        currentEcoScheduleConfig.repeatDays.forEach(day => {
            const el = document.querySelector(`#day-eco-toggles .day-eco-toggle[data-day="${day}"]`);
            if (el) el.classList.add('selected');
        });
    }

    populateEcoTime();

    try {
        const fetchedData = await fetchEcoSchedules();
        if (Array.isArray(fetchedData)) {
            savedEcoSchedules = fetchedData;
            console.log("Successfully loaded schedules:", savedEcoSchedules);

            if (savedEcoSchedules.length > 0) {
                updateEcoMasterToggle(true);
            }
            else {
                updateEcoMasterToggle(false);
            }
        }
    }
    catch (error) {
        console.error("Failed to load schedules during initialization.", e);
    }

    renderEcoScheduleList();
}

function generateEcoUUID() {
    let d = new Date().getTime();
    if (typeof performance !== 'undefined' && typeof performance.now === 'function') {
        d += performance.now();
    }

    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
        const r = (d + Math.random() * 16) % 16 | 0;
        d = Math.floor(d / 16);
        return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
    });
}

function getEcoConfigId(id) {
    return savedEcoSchedules.find(entry => entry.id === id);
}

function parseEcoTime(timeStr) {
    const [time, ampm] = timeStr.split(' ');
    const [hour, minute] = time.split(':');
    return {
        hour: parseInt(hour, 10),
        minute: minute,
        ampm: ampm
    };
}

window.initEcoAdvanced = initEcoAdvanced;