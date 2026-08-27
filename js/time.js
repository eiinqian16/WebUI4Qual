let sys_serverTime = null;
let sys_timezone = null;
let sys_clockInterval = null;

function showTimeConfig() {
    let html = `
        <h1>${t('time.title')}</h1>
        <p class="description">${t('time.desc')}</p>
        <hr>
        <div class="time-row">
            <span class="time-label">${t('advanced.system_time_label')}</span>
            <span class="time-value" id="current-time"></span>
        </div>
        <div class="time-row">
            <label class="time-label" for="timezone-select">${t('time.timezone_label')}</label>
            <select id="timezone-select">
                <option value="">${t('time.loading_timezones')}</option>
            </select>
        </div>
        <br>
        <button onclick="saveAndApply()">${t('eco.save_apply_button')}</button>
    `;

    document.getElementById('time-container').innerHTML = html;
    initSysClock();
    loadTimeZones();
}

async function initSysClock() {
    try {
        const resp = await fetch('/cgi-bin/get_time.sh');
        const text = await resp.text();
        const data = JSON.parse(text);
        sys_timezone = data.timezone;

        if (data && data.epoch) {
            sys_serverTime = new Date(data.epoch * 1000);
            updateSysClock();
            if (sys_clockInterval) clearInterval(sys_clockInterval);
            sys_clockInterval = setInterval(updateSysClock, 1000);
        }
        else {
            throw new Error("Invalid data format received");
        }
    }
    catch (error) {
        console.error("DEBUG CLOCK ERROR:", error);
        document.getElementById('current-time').innerText = t('advanced.sync_error');
    }
}

function updateSysClock() {
    if (!sys_serverTime) return;
    sys_serverTime.setSeconds(sys_serverTime.getSeconds() + 1);
    const options = {
        weekday: 'long',
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        hour12: true,
        timeZone: sys_timezone
    };

    const clockEl = document.getElementById('current-time');
    if (clockEl) {
        let timeString = sys_serverTime.toLocaleString(undefined, options);
        clockEl.innerText = timeString.toUpperCase();
    }
}

async function loadTimeZones() {
    try {
        const resp = await fetch('/db/timezones-db.json');
        timezoneData = await resp.json();

        const select = document.getElementById('timezone-select');
        select.innerHTML = `<option value-"">${t('time.select_timezone')}</option>`;
        const groups = {};
        timezoneData.forEach(tz => {
            const region = tz.zone_name.split('/')[0];
            if (!groups[region]) groups[region] = [];
            groups[region].push(tz);
        });

        Object.keys(groups).sort().forEach(region => {
            const optgroup = document.createElement('optgroup');
            optgroup.label = region;

            groups[region].forEach(tz => {
                const option = document.createElement('option');
                option.value = tz.timezone;
                option.dataset.zoneName = tz.zone_name;
                option.textContent = `${tz.zone_name.split('/').slice(1).join('/')} (${tz.utc_offset})`;
                optgroup.appendChild(option);
            });

            select.appendChild(optgroup);
        });

        const savedTz = localStorage.getItem('selected_timezone');
        if (savedTz) select.value = savedTz;
    } catch (error) {
        console.error("Failed to load timezones:", error);
        const select = document.getElementById('timezone-select');
        select.innerHTML = `<option value="">${t('time.failed_to_load')}</option>`;
    }
}

async function saveAndApply() {
    const select = document.getElementById('timezone-select');
    const selectTz = select.value;
    const selectedZoneName = select.options[select.selectedIndex]?.dataset.zoneName;

    if (!selectTz) {
        alert(t('time.select_timezone_required'));
        return;
    }

    try {
        const resp = await fetch('cgi-bin/set_timezone.sh', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                timezone: selectTz,
                zone_name: selectedZoneName
            })
        });

        const result = await resp.json();

        if (result.success) {
            localStorage.setItem('selected_timezone', selectTz);
            setTimeout(async () => {
                await initSysClock();
            }, 2000);
            alert(t('time.timezone_updated', { zone: selectedZoneName }));
        }
        else {
            alert(t('time.set_timezone_failed', { error: result.error }));
        }
    }
    catch (error) {
        console.error("Save failed:", error);
        alert(t('time.apply_timezone_failed'));
    }
}

window.addEventListener('load', () => {
    if (document.getElementById('time-container')) {
        showTimeConfig();
    }
});