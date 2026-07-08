let sys_serverTime = null;
let sys_timezone = null;

function showTimeConfig() {
    let html = `
        <h1>System Time</h1>
        <p class="description">Configure system time of router</p>
        <hr>
        <div>System Time: <span id="current-time"></span></div>
        <div>Timezone:
            <select id="timezone-select">
                <option value="">--- Loading timezones... ---</option>
            </select>
        </div>
        <br>
        <button onclick="saveAndApply()">Save and Apply</button>
    `;

    document.getElementById('time-container').innerHTML = html;
    initClock();
    loadTimeZones();
}

async function initClock() {
    try {
        const resp = await fetch('/cgi-bin/get_time.sh');
        const text = await resp.text();
        const data = JSON.parse(text);
        sys_timezone = data.timezone;

        if (data && data.epoch) {
            sys_serverTime = new Date(data.epoch * 1000);
            updateClock();
            setInterval(updateClock, 1000);
        }
        else {
            throw new Error("Invalid data format received");
        }
    }
    catch (error) {
        console.error("DEBUG CLOCK ERROR:", error);
        document.getElementById('current-time').innerText = "Sync Error";
    }
}

function updateClock() {
    if(!sys_serverTime) return;
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
        select.innerHTML = '<option value-"">-- Select Timezone --</option>';
        const groups = {};
        timezoneData.forEach(tz => {
            const region = tz.zone_name.split('/')[0];
            if(!groups[region]) groups[region] = [];
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
        select.innerHTML = '<option value="">-- Failed to load --</option>';
    }
}

async function saveAndApply() {
    const select = document.getElementById('timezone-select');
    const selectTz = select.value;
    const selectedZoneName = select.options[select.selectedIndex]?.dataset.zoneName;

    if(!selectTz) {
        alert("Please select a timezone");
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
                await initClock();
            }, 2000);
            alert(`Timezone updated to ${selectedZoneName}`);
        }
        else {
            alert(`Failed to set timezone: ${result.error}`);
        }
    }
    catch (error) {
        console.error("Save failed:", error);
        alert("Failed to apply timezone. Check the console for details.");
    }
}

window.addEventListener('load', () => {
    if (document.getElementById('time-container')) {
        showTimeConfig();
    }
});