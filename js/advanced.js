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

function initAckTimeout() {
    console.log('Initializing ACK Timeout settings...');

    fetch("/cgi-bin/get_acktimeout.sh")
        .then(res => res.json())
        .then(data => {
            const wifiList = document.getElementById("wifiListAck");
            if (!wifiList) {
                console.error("Error: #wifiListAck not found");
                return;
            }
            wifiList.innerHTML = "";

            const table = document.createElement("table");
            table.className = "ack-table";

            Object.entries(data).forEach(([wifi, values]) => {
                const tr = document.createElement("tr");

                const tdLabel = document.createElement("td");
                tdLabel.textContent = wifi;
                tdLabel.className = "ack-label";

                const tdInput = document.createElement("td");
                const input = document.createElement("input");
                input.type = "number";
                input.id = wifi;
                input.name = wifi;
                input.min = "64";
                input.max = "255";
                input.value = values.acktimeout ?? "112";
                input.className = "ack-input";

                const spanMs = document.createElement("span");
                spanMs.textContent = " ms";
                spanMs.className = "ack-unit";

                tdInput.appendChild(input);
                tdInput.appendChild(spanMs);
                tr.appendChild(tdLabel);
                tr.appendChild(tdInput);
                table.appendChild(tr);
            });

            wifiList.appendChild(table);

            const submitDiv = document.createElement("div");
            submitDiv.className = "ack-btn-container";

            const submitBtn = document.createElement("button");
            submitBtn.type = "submit";
            submitBtn.textContent = t('advanced.set_ack_timeout_button');
            submitBtn.className = "ack-button";

            submitDiv.appendChild(submitBtn);
            wifiList.appendChild(submitDiv);

            const form = document.getElementById("acktimeoutForm");
            if (form) {
                form.onsubmit = function (event) {
                    event.preventDefault();

                    const formData = new URLSearchParams();
                    document.querySelectorAll("input[type=number]").forEach(input => {
                        console.log("Appending:", input.name, input.value);
                        formData.append(input.name, input.value);
                    });

                    console.log("Sending Data:", formData.toString());
                    fetch("/cgi-bin/set_acktimeout.sh", {
                        method: "POST",
                        headers: { "Content-Type": "application/x-www-form-urlencoded" },
                        body: formData.toString()
                    }).then(response => response.text())
                        .then(data => {
                            console.log("Server Response:", data);
                            alert(t('advanced.ack_timeout_done'));
                        })
                        .catch(error => console.error("Error saving ACK timeout:", error));
                };
            } else {
                console.error("Error: #acktimeoutForm not found");
            }
        })
        .catch(error => console.error("Error fetching ACK timeout data:", error));
}

let isMasterScheduleActive = false;
let currentScheduleConfig = {
    repeatDays: ['Su', 'M', 'Tu', 'W', 'Th', 'F', 'Sa']
}

let savedSchedules = [];
let adv_systemTime = null;
let adv_timezone = null;
let adv_clockInterval = null;

async function initAdvClock() {
    try {
        const resp = await fetch('/cgi-bin/get_time.sh');
        const text = await resp.text();
        const data = JSON.parse(text);
        adv_timezone = data.timezone;

        if (data && data.epoch) {
            adv_systemTime = new Date(data.epoch * 1000);
            updateAdvClock();
            if (adv_clockInterval) clearInterval(adv_clockInterval);
            adv_clockInterval = setInterval(updateAdvClock, 1000);
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

function updateAdvClock() {
    if (!adv_systemTime) return;
    adv_systemTime.setSeconds(adv_systemTime.getSeconds() + 1);
    const options = {
        weekday: 'long',
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        hour12: true,
        timeZone: adv_timezone
    };

    const clockEl = document.getElementById('currentTime');
    if (clockEl) {
        let timeString = adv_systemTime.toLocaleString(undefined, options);
        clockEl.innerText = timeString.toUpperCase();
    }
}

function updateMasterToggle(isActive) {
    const toggle = document.getElementById('master-toggle');
    if (isActive) {
        toggle.classList.add('active');
    }
    else {
        toggle.classList.remove('active');
    }
    isMasterScheduleActive = isActive;
}

function toggleScheduleWithConfirmation() {
    const stateToSet = !isMasterScheduleActive;
    const title = stateToSet ? t('advanced.enable_schedule_title') : t('advanced.disable_schedule_title');
    const message = stateToSet ? t('advanced.enable_schedule_message') : t('advanced.disable_schedule_message');

    document.getElementById('confirmation-title').textContent = title;
    document.getElementById('confirmation-message').textContent = message;

    showModal(document.getElementById('confirmation-backdrop'));
}

async function confirmToggle(confirmed) {
    hideModal(document.getElementById('confirmation-backdrop'));

    if (confirmed) {
        const newState = !isMasterScheduleActive;
        updateMasterToggle(newState);

        console.log(`Master Wireless Schedule confirmed and set to: ${newState ? 'Enabled' : 'Disabled'}`);

        // Send each schedule entry individually to the backend
        try {
            for (const entry of savedSchedules) {
                const resp = await fetch("/cgi-bin/wireless_schedule.sh", {
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

            alertSuccess(t('advanced.schedule_toggle_success', { state: newState ? t('common.enabled') : t('common.disabled') }));
        }
        catch (error) {
            console.error("Error sending schedule status:", error);
            alertSuccess(t('advanced.schedule_toggle_failed', { message: error.message }));
            updateMasterToggle(!newState);
        }
    }
    else {
        console.log("Toggle cancelled by user");
    }
}

async function fetchSchedules() {
    try {
        const resp = await fetch("/config/schedule");

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

function openAddModal() {
    const modalTitle = document.getElementById('modal-title');
    const editIdInput = document.getElementById('edit-id');

    if (modalTitle) modalTitle.textContent = t('advanced.add_schedule_entry_title');
    if (editIdInput) editIdInput.value = "";

    currentScheduleConfig.repeatDays = ['Su', 'M', 'Tu', 'W', 'Th', 'F', 'Sa'];
    document.querySelectorAll('#day-toggles .day-toggle').forEach(el => {
        el.classList.add('selected');
    });

    populateTime();
    if (document.getElementById('off-hour')) document.getElementById('off-hour').value = 11;
    if (document.getElementById('off-minute')) document.getElementById('off-minute').value = "00";
    if (document.getElementById('off-ampm')) document.getElementById('off-ampm').value = "PM";
    if (document.getElementById('on-hour')) document.getElementById('on-hour').value = 7;
    if (document.getElementById('on-minute')) document.getElementById('on-minute').value = "00";
    if (document.getElementById('on-ampm')) document.getElementById('on-ampm').value = "AM";

    const backdrop = document.getElementById('add-schedule-backdrop');
    if (backdrop) showModal(backdrop);
}

function closeAddModal() {
    hideModal(document.getElementById('add-schedule-backdrop'));
}

// Unified modal show/hide functions
function showModal(backdropElement) {
    if (typeof window.lockBodyScroll === "function") {
        window.lockBodyScroll();
    }
    backdropElement.classList.add('show');
}

function hideModal(backdropElement) {
    backdropElement.classList.remove('show');
    if (typeof window.unlockBodyScroll === "function") {
        window.unlockBodyScroll();
    }
}

function editConfig(id) {
    const entry = getConfigId(id);
    if (!entry) {
        alertSuccess(t('advanced.schedule_not_found_edit'));
        return;
    }

    document.getElementById('modal-title').textContent = t('advanced.edit_schedule_entry_title');
    document.getElementById('edit-id').value = entry.id;

    const parsedOff = parseTime(entry.offTime);
    const parsedOn = parseTime(entry.onTime);

    populateTime();

    if (document.getElementById('off-hour')) document.getElementById('off-hour').value = parsedOff.hour;
    if (document.getElementById('off-minute')) document.getElementById('off-minute').value = parsedOff.minute;
    if (document.getElementById('off-ampm')) document.getElementById('off-ampm').value = parsedOff.ampm;

    if (document.getElementById('on-hour')) document.getElementById('on-hour').value = parsedOn.hour;
    if (document.getElementById('on-minute')) document.getElementById('on-minute').value = parsedOn.minute;
    if (document.getElementById('on-ampm')) document.getElementById('on-ampm').value = parsedOn.ampm;

    currentScheduleConfig.repeatDays = [...entry.repeatDays];

    document.querySelectorAll('#day-toggles .day-toggle').forEach(el => {
        const dayValue = el.getAttribute('data-day');
        if (entry.repeatDays.includes(dayValue)) {
            el.classList.add('selected');
        } else {
            el.classList.remove('selected');
        }
    });

    const backdrop = document.getElementById('add-schedule-backdrop');
    if (backdrop) showModal(backdrop);
}

async function deleteConfig(id) {
    const userConfirmed = confirm(t('advanced.confirm_delete_schedule'));
    if (!userConfirmed) return;

    const index = savedSchedules.findIndex(entry => entry.id === id);
    if (index === -1) {
        alertSuccess(t('advanced.schedule_not_found_delete'));
        return;
    }

    savedSchedules.splice(index, 1);

    renderScheduleList();

    console.log("Deleted entry ID:", id);
    console.log("Updated savedSchedules:", savedSchedules);

    try {
        const resp = await fetch("/cgi-bin/wireless_schedule.sh", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                action: "delete",
                id: id
            })
        });

        if (!resp.ok) {
            throw new Error(`HTTP error! Status: ${resp.status}`);
        }

        console.log("Delete sent to backend");

        if (savedSchedules.length === 0) {
            updateMasterToggle(false);
        }

        alertSuccess(t('advanced.schedule_deleted_success'));

    } catch (error) {
        console.error("Delete failed:", error);
        alertSuccess(t('advanced.schedule_delete_failed'));
    }
}

function handleCancel() {
    closeAddModal();
}

function handleSave() {
    const editIdValue = document.getElementById('edit-id').value;

    const offHour = parseInt(document.getElementById('off-hour').value, 10);
    const offMinute = document.getElementById('off-minute').value;
    const offAmPm = document.getElementById('off-ampm').value;
    const onHour = parseInt(document.getElementById('on-hour').value, 10);
    const onMinute = document.getElementById('on-minute').value;
    const onAmPm = document.getElementById('on-ampm').value;

    const offTimeStr = `${offHour}:${offMinute} ${offAmPm}`;
    const onTimeStr = `${onHour}:${onMinute} ${onAmPm}`;

    const repeatDays = [...currentScheduleConfig.repeatDays];

    if (repeatDays.length === 0) {
        alert(t('advanced.select_one_day'));
        return;
    }

    if (editIdValue) {
        const entry = getConfigId(editIdValue);
        if (entry) {
            entry.offTime = offTimeStr;
            entry.onTime = onTimeStr;
            entry.repeatDays = repeatDays;

            renderScheduleList();
            sendScheduleToBackend(savedSchedules);
            closeAddModal();

            console.log("Updated schedule entry:", entry);
            alertSuccess(t('advanced.schedule_updated_success'));
        } else {
            alertSuccess(t('advanced.schedule_not_found_update'));
        }
    } else {
        const newEntry = {
            id: generateUUID(),
            offTime: offTimeStr,
            onTime: onTimeStr,
            repeatDays: repeatDays
        };

        savedSchedules.push(newEntry);

        renderScheduleList();
        sendScheduleToBackend(savedSchedules);
        closeAddModal();

        console.log("Added new schedule entry:", newEntry);
        alertSuccess(t('advanced.schedule_added_success'));
    }
}

async function sendScheduleToBackend(scheduleArray) {
    try {
        for (const entry of scheduleArray) {
            const resp = await fetch("/cgi-bin/wireless_schedule.sh", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(entry)
            });

            if (!resp.ok) {
                throw new Error(`HTTP error! Status: ${resp.status}`);
            }

            const result = await resp.json();
            console.log('Backend response for entry:', result);
        }
    } catch (error) {
        console.error("Error sending schedule to backend:", error);
        alertSuccess(t('advanced.schedule_save_failed', { message: error.message }));
    }
}

function renderScheduleList() {
    const listContainer = document.getElementById('schedule-list');
    if (!listContainer) {
        console.error("Error: #schedule-list not found");
        return;
    }

    if (savedSchedules.length === 0) {
        listContainer.innerHTML = `
            <div class="schedule-placeholder">
                <span>${t('advanced.no_schedules_text')}</span>
            </div>
        `;
        return;
    }

    const DAY_KEYS = { Su: 'advanced.day_su', M: 'advanced.day_mon', Tu: 'advanced.day_tue', W: 'advanced.day_wed', Th: 'advanced.day_thu', F: 'advanced.day_fri', Sa: 'advanced.day_sat' };
    const dayBadges = days => days.map(d => `<span class="day-badge">${DAY_KEYS[d] ? t(DAY_KEYS[d]) : d}</span>`).join('');

    listContainer.innerHTML = savedSchedules.map(entry => `
        <div class="schedule-item">
            <div class="schedule-item-content">
                <div class="schedule-item-time">${entry.offTime} - ${entry.onTime}</div>
                <div class="schedule-item-days">${dayBadges(entry.repeatDays)}</div>
            </div>
            <div class="schedule-item-actions">
                <button class="icon-only-btn" onclick="editConfig('${entry.id}')" title="${t('common.edit')}">
                    <img src="/logo/edit.png" alt="${t('common.edit')}"
                    style="width: 20px; height: 20px; filter: invert(48%) sepia(79%) saturate(2476%) hue-rotate(86deg) brightness(118%) contrast(119%);">
                </button>
                <button class="icon-only-btn" onclick="deleteConfig('${entry.id}')" title="${t('common.delete')}">
                    <img src="/logo/bin.png" alt="${t('common.delete')}"
                        style="width: 20px; height: 20px; filter: invert(27%) sepia(91%) saturate(7352%) hue-rotate(358deg) brightness(104%) contrast(107%);">
                </button>
            </div>
        </div>
    `).join('');
}

function populateTime() {
    const offHourSelect = document.getElementById('off-hour');
    const onHourSelect = document.getElementById('on-hour');

    if (offHourSelect) {
        offHourSelect.innerHTML = '';
        for (let h = 1; h <= 12; h++) {
            const opt = document.createElement('option');
            opt.value = h;
            opt.textContent = h;
            offHourSelect.appendChild(opt);
        }
    }

    if (onHourSelect) {
        onHourSelect.innerHTML = '';
        for (let h = 1; h <= 12; h++) {
            const opt = document.createElement('option');
            opt.value = h;
            opt.textContent = h;
            onHourSelect.appendChild(opt);
        }
    }
}

function alertSuccess(message) {
    alert(message);
}

async function initAdvanced() {
    document.querySelectorAll('#day-toggles .day-toggle').forEach(btn => {
        btn.addEventListener('click', function () {
            const dayValue = this.getAttribute('data-day');
            if (this.classList.contains('selected')) {
                this.classList.remove('selected');
                const index = currentScheduleConfig.repeatDays.indexOf(dayValue);
                if (index > -1) {
                    currentScheduleConfig.repeatDays.splice(index, 1);
                }
            } else {
                this.classList.add('selected');
                currentScheduleConfig.repeatDays.push(dayValue);
            }
            console.log("Updated repeat days:", currentScheduleConfig.repeatDays);
        });
    });
    /*
        // Update time every second
        if (document.getElementById('currentTime')) {
            setInterval(loadScheduleTime, 1000);
            loadScheduleTime();
        }
    */
    initAdvClock();

    // Ack timeout initialization
    if (document.getElementById('acktimeout-page')) {
        initAckTimeout();
    }

    // Wireless schedule initialization
    if (document.getElementById('wireless-schedule')) {
        populateTime();

        try {
            const fetchedData = await fetchSchedules();
            if (Array.isArray(fetchedData)) {
                savedSchedules = fetchedData;
                console.log("Successfully loaded schedules:", savedSchedules);

                if (savedSchedules.length > 0) {
                    updateMasterToggle(true);
                }
                else {
                    updateMasterToggle(false);
                }
            }
        }
        catch (error) {
            console.error("Failed to load schedules during initialization.", error);
        }

        renderScheduleList();
    }

    // Access control initialization
    if (document.getElementById('accessControl')) {
        openDenyList();
    }
}

function generateUUID() {
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

function getConfigId(id) {
    return savedSchedules.find(entry => entry.id === id);
}

function parseTime(timeStr) {
    const [time, ampm] = timeStr.split(' ');
    const [hour, minute] = time.split(':');
    return {
        hour: parseInt(hour, 10),
        minute: minute,
        ampm: ampm
    };
}

function openDenyList() {
    console.log("Opening deny list");
    const container = document.getElementById('denyListContainer');

    fetch('/cgi-bin/gen_deny_list.sh')
        .then(res => res.json())
        .then(data => {
            let html = `
                <table class="deny-table">
                    <thead>
                        <tr>
                            <th>${t('advanced.access_point')}</th>
                            <th>${t('common.device_name')}</th>
                            <th>${t('common.mac_address')}</th>
                            <th>${t('common.ip_address')}</th>
                            <th style="text-align:center;">${t('common.modify')}</th>
                        </tr>
                    </thead>
                    <tbody>`;

            if (!data || data.length === 0) {
                html += `
                    <tr>
                        <td colspan="5" style="text-align:center; padding: 20px; color: #666;">
                            ${t('advanced.no_devices_blocked')}
                        </td>
                    </tr>`;
            } else {
                data.forEach(dev => {
                    html += `
                        <tr>
                            <td>${dev.ssid}</td>
                            <td>${dev.hostname}</td>
                            <td>${dev.mac}</td>
                            <td>${dev.ip}</td>
                            <td style="text-align:center;">
                                <button class="icon-only-btn access-action-btn" onclick="unblockDevice('${dev.mac}','${dev.hostname}', '${dev.ssid}')" title="${t('advanced.unblock')}">
                                   <img src="/logo/bin.png" alt="${t('advanced.unblock')}" class="green-icon">
                                   <span class="access-action-text">${t('advanced.unblock')}</span>
                                </button>
                            </td>
                        </tr>`;
                });
            }

            html += '</tbody></table>';
            container.innerHTML = html;
        })
        .catch(err => {
            console.error("Fetch error:", err);
            container.innerHTML = `<p style="color:red; text-align:center;">${t('advanced.error_loading_list')}</p>`;
        });
}

window.openAddDeviceModal = function () {
    let modal = document.getElementById('addDeviceModal');

    if (!modal) {
        modal = document.createElement('div');
        modal.id = 'addDeviceModal';
        modal.className = 'modal-overlay';

        modal.innerHTML = `
            <div class="modal-box">
                <div class="modal-header">
                    <h3 id="modal-title">${t('advanced.add_device_title')}</h3>
                    <span class="close-x" onclick="closeAddDeviceModalBtn()">&times;</span>
                </div>
                <div class="modal-body">
                    <div class="popup-scroll-area">
                        <table class="popup-table">
                            <thead>
                                <tr>
                                    <th>${t('advanced.access_point')}</th>
                                    <th>${t('common.device_name')}</th>
                                    <th>${t('advanced.ip_short')}</th>
                                    <th>${t('common.mac_address')}</th>
                                    <th>${t('common.modify')}</th>
                                </tr>
                            </thead>
                            <tbody id="popupDeviceListBody">
                                <tr><td colspan="5" style="text-align:center; padding:20px;">${t('advanced.scanning_devices')}</td></tr>
                            </tbody>
                        </table>
                    </div>
                </div>
                <div class="modal-footer">
                    <button onclick="closeAddDeviceModalBtn()" class="btn-secondary">${t('common.cancel_upper')}</button>
                </div>
            </div>
        `;
        document.body.appendChild(modal);
    }

    setTimeout(() => {
        if (typeof window.lockBodyScroll === "function") {
            window.lockBodyScroll();
        }
        modal.classList.add('active');
    }, 10);

    fetchAvailableDevices();
};

window.closeAddDeviceModalBtn = function () {
    const modal = document.getElementById('addDeviceModal');
    if (modal) {
        modal.classList.remove('active');
        if (typeof window.unlockBodyScroll === "function") {
            window.unlockBodyScroll();
        }

        setTimeout(() => {
            modal.remove();
        }, 300);
    }
};

function fetchAvailableDevices() {
    const blockIcon = "/logo/block.png";
    fetch('/cgi-bin/get_associated_clients.sh')
        .then(res => res.json())
        .then(data => {
            const tbody = document.getElementById('popupDeviceListBody');
            if (!data || data.length === 0) {
                tbody.innerHTML = `<tr><td colspan="5" style="text-align:center; padding:10px;">${t('advanced.no_active_devices')}</td></tr>`;
                return;
            }
            tbody.innerHTML = data.map(dev => {
                const name = dev.hostname || t('common.unknown');
                return `
                <tr>
                    <td>${dev.ssid}</td>
                    <td>${name}</td>
                    <td>${dev.ip}</td>
                    <td>${dev.mac}</td>
                    <td>
                        <button class="blockBtn access-action-btn" onclick="blockDevice('${dev.mac}', '${name}', '${dev.ssid}')">
                            <img src="${blockIcon}" alt="${t('wireless.block')}" class="blockBtnIcon">
                            <span class="access-action-text">${t('wireless.block')}</span>
                        </button>
                    </td>
                </tr>`;
            }).join('');
        });
}

function blockDevice(mac, devName, ap) {
    if (confirm(t('wireless.confirm_add_deny_list', { name: devName }))) {
        const url = `/cgi-bin/deny_list.sh?action=add&mac=${encodeURIComponent(mac)}&ssid=${encodeURIComponent(ap)}&policy=deny`;

        fetch(url)
            .then(resp => resp.text())
            .then(text => {
                try {
                    const data = JSON.parse(text);
                    if (data.result === "success" || data.status === "Success") {
                        alert(t('wireless.block_success', { name: devName }));
                        if (typeof closeAddDeviceModalBtn === "function") closeAddDeviceModalBtn();
                        if (typeof openDenyList === 'function') openDenyList();
                    } else {
                        alert(data.message || t('advanced.block_failed_default'));
                    }
                } catch (e) {
                    console.error("Server returned non-JSON:", text);
                    alert(t('wireless.router_error_invalid_format'));
                }
            })
            .catch(error => {
                console.error('Fetch error:', error);
                alert(t('wireless.communicate_failed'));
            });
    }
}

function unblockDevice(mac, devName, ap) {
    const confirmation = confirm(t('advanced.confirm_unblock', { name: devName }))

    if (confirmation) {
        const params = new URLSearchParams({
            action: 'remove',
            mac: mac,
            ssid: ap,
            policy: 'deny'
        });

        console.log(`${params.toString()}`);

        fetch(`/cgi-bin/deny_list.sh?${params.toString()}`)
            .then(resp => {
                if (!resp.ok) throw new Error('Network response was not ok');
                return resp.json();
            })
            .then(data => {
                if (data.result === "success" || data.status === "Success") {
                    alert(t('advanced.unblock_success', { name: devName, mac: mac }));
                    if (typeof openDenyList === 'function') openDenyList();
                } else {
                    alert(data.message || t('advanced.unblock_failed_default'));
                }
            })
            .catch(error => {
                console.error('Fetch error:', error);
                alert(t('wireless.communicate_failed'));
            });
    }
}

window.onload = function () {
    if (document.getElementById('accessControl')) {
        openDenyList();
    }
};

window.initAdvanced = initAdvanced;


