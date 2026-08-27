if (typeof window.lockBodyScroll !== "function") {
    window._bodyScrollLockCount = 0;

    window.lockBodyScroll = function () {
        const body = document.body;
        if (!body) return;

        if (window._bodyScrollLockCount === 0) {
            const scrollY = window.scrollY || window.pageYOffset || 0;
            const scrollBarWidth = window.innerWidth - document.documentElement.clientWidth;
            body.dataset.scrollLockY = String(scrollY);
            body.classList.add("modal-open");
            body.style.position = "fixed";
            body.style.top = "-" + scrollY + "px";
            body.style.overflow = "hidden";
            if (scrollBarWidth > 0) {
                body.style.paddingRight = scrollBarWidth + "px";
            }
        }

        window._bodyScrollLockCount = 1;
    };

    window.unlockBodyScroll = function () {
        const body = document.body;
        if (!body || !window._bodyScrollLockCount) return;

        window._bodyScrollLockCount -= 1;
        if (window._bodyScrollLockCount > 0) return;

        const scrollY = parseInt(body.dataset.scrollLockY || "0", 10);
        body.style.position = "";
        body.style.top = "";
        body.style.overflow = "";
        body.style.paddingRight = "";
        body.classList.remove("modal-open");
        delete body.dataset.scrollLockY;
        window.scrollTo(0, scrollY);
    };
}

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
        return alert(t('eco.select_mode_required'));
    }

    const mode = selected.value;
    console.log(mode);

    try {
        const resp = await fetch(`/cgi-bin/eco_mode_v2.sh?action=${mode}`);
        if (!resp.ok) throw new Error(`Server responded with ${resp.status}`);

        const data = await resp.json();

        if (data.status === "OK") {
            alert(t('eco.mode_applied_success', { mode: data.applied_mode.toUpperCase() }));
            loadPowerMode();
        }
        else {
            alert(t('eco.mode_apply_failed', { error: data.error || t('wireless.unknown_error') }));
        }
    } catch (error) {
        console.error("Eco mode switch failed:", error);
        alert(t('eco.request_failed_restarting'));
    }
}

let isEcoMasterScheduleActive = false;
let currentEcoScheduleConfig = {
    repeatDays: ['Su', 'M', 'Tu', 'W', 'Th', 'F', 'Sa']
}

let savedEcoSchedules = [];
let eco_systemTime = null;
let eco_timezone = null;
let eco_clockInterval = null;

async function initEcoClock() {
    try {
        const resp = await fetch('/cgi-bin/get_time.sh');
        const text = await resp.text();
        const data = JSON.parse(text);
        eco_timezone = data.timezone;

        if (data && data.epoch) {
            eco_systemTime = new Date(data.epoch * 1000);
            updateEcoClock();
            if (eco_clockInterval) clearInterval(eco_clockInterval);
            eco_clockInterval = setInterval(updateEcoClock, 1000);
        }
        else {
            throw new Error("Invalid data format received");
        }
    }
    catch (error) {
        console.error("DEBUG CLOCK ERROR:", error);
        document.getElementById('currentTime').innerText = t('advanced.sync_error');
    }
}

function updateEcoClock() {
    if (!eco_systemTime) return;
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
    const title = stateToSet ? t('eco.enable_schedule_title') : t('eco.disable_schedule_title');
    const message = stateToSet ? t('eco.enable_schedule_message') : t('eco.disable_schedule_message');

    document.getElementById('eco-confirmation-title').textContent = title;
    document.getElementById('eco-confirmation-message').textContent = message;

    showEcoModal(document.getElementById('confirmation-eco-backdrop'));
}

async function confirmEcoToggle(confirmed) {
    hideEcoModal(document.getElementById('confirmation-eco-backdrop'));

    if (confirmed) {
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

            alertSuccess(t('eco.schedule_toggle_success', { state: newState ? t('common.enabled') : t('common.disabled') }));
        }
        catch (error) {
            console.error("Error sending schedule status:", error);
            alertSuccess(t('advanced.schedule_toggle_failed', { message: error.message }));
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
        alertSuccess(t('advanced.fetch_schedules_failed', { message: error.message }));
        return [];
    }
}

function openEcoAddModal() {
    const modalTitle = document.getElementById('modal-eco-title');
    const editIdInput = document.getElementById('edit-eco-id');

    if (modalTitle) modalTitle.textContent = t('advanced.add_schedule_entry_title');
    if (editIdInput) editIdInput.value = "";

    currentEcoScheduleConfig.repeatDays = ['Su', 'M', 'Tu', 'W', 'Th', 'F', 'Sa'];
    document.querySelectorAll('#day-eco-toggles .day-eco-toggle').forEach(el => {
        el.classList.add('selected');
    });

    populateEcoTime();
    if (document.getElementById('off-hour-eco')) document.getElementById('off-hour-eco').value = 11;
    if (document.getElementById('off-minute-eco')) document.getElementById('off-minute-eco').value = "00";
    if (document.getElementById('off-ampm-eco')) document.getElementById('off-ampm-eco').value = "PM";
    if (document.getElementById('on-hour-eco')) document.getElementById('on-hour-eco').value = 7;
    if (document.getElementById('on-minute-eco')) document.getElementById('on-minute-eco').value = "00";
    if (document.getElementById('on-ampm-eco')) document.getElementById('on-ampm-eco').value = "AM";

    const backdrop = document.getElementById('add-eco-schedule-backdrop');
    if (backdrop) showEcoModal(backdrop);
}

function closeEcoAddModal() {
    hideEcoModal(document.getElementById('add-eco-schedule-backdrop'));
}

function showEcoModal(backdropElement) {
    if (typeof window.lockBodyScroll === "function") {
        window.lockBodyScroll();
    }
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
    if (typeof window.unlockBodyScroll === "function") {
        window.unlockBodyScroll();
    }
    setTimeout(() => {
        backdropElement.classList.remove('show');
    }, 300);
}

function editEcoConfig(id) {
    const entry = getEcoConfigId(id);
    if (!entry) {
        alertSuccess(t('advanced.schedule_not_found_edit'));
        return;
    }

    document.getElementById('modal-eco-title').textContent = t('advanced.edit_schedule_entry_title');
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
            body: JSON.stringify({ action: "delete", id: id })
        });

        if (!resp.ok) {
            throw new Error(`HTTP error! Status: ${resp.status}`);
        }

        const result = await resp.json();
        console.log('Delete result', result);

        savedEcoSchedules = savedEcoSchedules.filter(entry => entry.id !== id);
        renderEcoScheduleList();
        alertSuccess(t('advanced.schedule_deleted_success'));
    }
    catch (error) {
        console.error("Error deleting schedule:", error);
        alertSuccess(t('eco.schedule_delete_failed', { message: error.message }));
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
            <span>${t('advanced.no_schedules_text')}</span>
        </div>
        `;
        return;
    }

    const DAY_KEYS = { Su: 'advanced.day_su', M: 'advanced.day_mon', Tu: 'advanced.day_tue', W: 'advanced.day_wed', Th: 'advanced.day_thu', F: 'advanced.day_fri', Sa: 'advanced.day_sat' };
    const dayBadges = days => (days || []).map(d => `<span class="day-badge">${DAY_KEYS[d] ? t(DAY_KEYS[d]) : d}</span>`).join('');

    savedEcoSchedules.forEach(entry => {
        const newEntry = document.createElement('div');
        newEntry.className = 'schedule-item';

        newEntry.innerHTML = `
        <div class="schedule-item-content">
            <div class="schedule-item-time">${t('eco.off_on_time_text', { off: entry.offTime, on: entry.onTime })}</div>
            <div class="schedule-item-days">${dayBadges(entry.repeatDays)}</div>
        </div>
        <div class="schedule-item-actions">
            <button class="icon-only-btn" onclick="editEcoConfig('${entry.id}')" title="${t('common.edit')}">
                <img src="/logo/edit.png" alt="${t('common.edit')}"
                style="width: 20px; height: 20px; filter: invert(48%) sepia(79%) saturate(2476%) hue-rotate(86deg) brightness(118%) contrast(119%);">
            </button>
            <button class="icon-only-btn" onclick="deleteEcoConfig('${entry.id}')" title="${t('common.delete')}">
                <img src="/logo/bin.png" alt="${t('common.delete')}"
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
        alertSuccess(t('advanced.select_one_day'));
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
            alertSuccess(t('advanced.schedule_updated_success'));
            console.log(finalData);
        }
    }
    else {
        const newId = generateEcoUUID();
        const finalData = { ...newScheduleEntry, id: newId };
        savedEcoSchedules.push(finalData);
        alertSuccess(t('advanced.schedule_added_success'));
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
    initEcoClock();
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

    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
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