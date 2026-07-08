const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

async function configCellular() {
    const modelResp = await fetch('/modem_model', { cache: "no-store" });
    const model = (await modelResp.text()).trim();

    const resp = await fetch('/modem_stats', {
        cache: "no-store"
    });

    if (!resp.ok) throw new Error("File not ready");
    const statsData = await resp.json();

    let auto = document.getElementById("autoToggle").checked;
    let carrier = document.getElementById("lteApn").value;
    let service = document.getElementById("lteService").value;
    let slot = document.getElementById("simSlot").value;
    let body = "";
    let band = "";

    if (auto === false) {
        if (!carrier) {
            alert("Carrier selection needed for configuration!");
            return false;
        }

        if (service == "AUTO") {
            if (statsData.rat == 7) {
                band = "LTE";
            }
            else if (statsData.rat == 11) {
                band = "NR5G";
            }
            else if (model.includes("RM500U")) {
                band = "NR5G";
            }
        }
        else {
            band = service;
        }

        if (!band) {
            alert("Cellular sevice needed for configuration!");
            return false;
        }

        let apn;
        if (carrier === "others") {
            apn = document.getElementById("adLteApn").value.trim();
            if (!apn) {
                alert("Please enter an APN for manual configuration!");
                return false;
            }
        } else {
            apn = await getApn(carrier, band);
            if (!apn) {
                alert(`Could not find APN for carrier '${carrier}' on ${band}. Please select 'Others (Manual)' and enter the APN manually.`);
                return false;
            }
        }

        let serviceValue = band;
        if (model.includes("RG255A") || model.includes("RM500U")) {
            if (band === "NR5G") serviceValue = "NR5G-SA";
            else if (band === "LTE") serviceValue = "lte";
        }

        body = "apn=" + encodeURIComponent(apn) +
            "&service=" + encodeURIComponent(serviceValue) +
            "&slot=" + encodeURIComponent(slot);
    }

    let confirmation = confirm(`Saving and applying the cause network interruptions. Continue?`);

    console.log(body);

    if (confirmation) {
        showLoading("Configuring LTE network ...");
        let url;
        if (!auto) {
            console.log("Manual configuration triggered. Detecting model for script selection...");
            console.log("Modem model detected:", model);
            if (model.includes("RG255A")) {
                url = "/cgi-bin/rg255a_config_apn_lte.sh";
            } else if (model.includes("RM500U")) {
                url = "/cgi-bin/rm500u_config_apn_lte.sh";
            } else if (model.includes("A7908E") || model.includes("A7808E")) {
                url = "/cgi-bin/a7908e_config_apn_lte.sh";
            } else if (model.includes("SRM810")) {
                url = "/cgi-bin/srm810_config_apn_lte.sh";
            }
        }

        console.log("Selected configuration script URL:", url);

        try {
            await fetch(url, {
                method: "POST",
                headers: { "Content-Type": "application/x-www-form-urlencoded" },
                body: auto ? "" : body
            });
            await sleep(30000);

            const finalStats = await checkAndRefresh(40, model);

            // Verify modem_stats is fully populated before declaring success
            let verified = false;
            const MAX_VERIFY = 10;
            for (let i = 0; i < MAX_VERIFY; i++) {
                const verifyResp = await fetch(`/modem_stats?_=${Date.now()}`, { cache: "no-store" });
                const verifyData = await verifyResp.json();

                const hasOperator = verifyData.operator && verifyData.operator !== "No operator detected";
                const hasRat = verifyData.rat && verifyData.rat !== "UNKNOWN" && verifyData.rat !== "No band found";
                const isReady = verifyData.status === "ready";

                console.log(`Verify attempt ${i + 1}/${MAX_VERIFY}: operator=${verifyData.operator}, rat=${verifyData.rat}, status=${verifyData.status}`);

                if (hasOperator && hasRat && isReady) {
                    verified = true;
                    break;
                }

                // Nudge stats script if still stale
                await fetchLteStats(model);
                await sleep(3000);
            }

            hideLoading();

            if (verified) {
                alert(`Success!`);
            } else {
                alert(`Configuration applied, but cellular status could not be fully verified. Please check the status page.`);
            }

            location.reload();
        }
        catch (error) {
            console.error("Config Error:", error);
            hideLoading();
            alert(error);
        }
    }
}

function hasValidCellularData(data) {
    if (!data) return false;
    const hasOperator = data.operator && data.operator !== "No operator detected";
    const hasRat = data.rat && data.rat !== "No band found" && data.rat !== "UNKNOWN";
    return hasOperator && hasRat;
}

async function fetchLteStats(model = "") {
    try {
        if (!model) {
            const modelResp = await fetch('/modem_model', { cache: "no-store" });
            model = (await modelResp.text()).trim();
        }

        let statsUrl = "/cgi-bin/get_lte_stats.sh";
        if (model.includes("RG255A")) statsUrl = "/cgi-bin/rg255a_get_lte_stats.sh";
        else if (model.includes("RM500U")) statsUrl = "/cgi-bin/rm500u_get_lte_stats.sh";
        else if (model.includes("A7908E") || model.includes("A7808E")) statsUrl = "/cgi-bin/a7908e_get_lte_stats.sh";
        else if (model.includes("SRM810")) statsUrl = "/cgi-bin/srm810_get_lte_stats.sh";

        console.log(`fetchLteStats: running ${statsUrl}`);
        const resp = await fetch(`${statsUrl}?_=${Date.now()}`, { cache: "no-store" });
        if (!resp.ok) throw new Error(`Stats script returned ${resp.status}`);
        const result = await resp.json();
        console.log("fetchLteStats result:", result);
        return result;
    } catch (err) {
        console.error("fetchLteStats error:", err);
        return null;
    }
}

async function triggerLteStatsIfConfiguring(model = "") {
    try {
        // Resolve model if not provided
        if (!model) {
            const modelResp = await fetch('/modem_model', { cache: "no-store" });
            model = (await modelResp.text()).trim();
        }

        const statsResp = await fetch(`/modem_stats?_=${Date.now()}`, { cache: "no-store" });
        if (!statsResp.ok) throw new Error("modem_stats not ready");
        const stats = await statsResp.json();

        if (stats.status !== "configuring") {
            console.log(`triggerLteStatsIfConfiguring: status is "${stats.status}", no action needed.`);
            return null;
        }

        // Resolve the correct get_lte_stats script for the detected model
        let statsUrl = "/cgi-bin/get_lte_stats.sh";
        if (model.includes("RG255A")) {
            statsUrl = "/cgi-bin/rg255a_get_lte_stats.sh";
        } else if (model.includes("RM500U")) {
            statsUrl = "/cgi-bin/rm500u_get_lte_stats.sh";
        } else if (model.includes("A7908E") || model.includes("A7808E")) {
            statsUrl = "/cgi-bin/a7908e_get_lte_stats.sh";
        } else if (model.includes("SRM810")) {
            statsUrl = "/cgi-bin/srm810_get_lte_stats.sh";
        }

        console.log(`triggerLteStatsIfConfiguring: status is "configuring" – triggering ${statsUrl}`);

        const scriptResp = await fetch(`${statsUrl}?_=${Date.now()}`, { cache: "no-store" });
        if (!scriptResp.ok) throw new Error(`Stats script returned ${scriptResp.status}`);

        const result = await scriptResp.json();
        console.log("triggerLteStatsIfConfiguring: stats script result:", result);
        return result;

    } catch (err) {
        console.error("triggerLteStatsIfConfiguring error:", err);
        return null;
    }
}

async function checkAndRefresh(maxAttempts = 40, model = "") {
    let attempts = 0;
    let ledReady = false;

    return new Promise((resolve, reject) => {
        const pollInterval = setInterval(async () => {
            attempts++;
            console.log(`Connection check ${attempts}/${maxAttempts}...`);

            // If halfway through attempts and still no internet, run diagnostic/recovery script
            if (attempts === 15 && (model.includes("RG255A") || model.includes("RM500U"))) {
                console.log("Internet still not established. Running APN diagnostic and recovery...");
                const checkUrl = model.includes("RM500U") ? '/cgi-bin/rm500u_check_apn_config.sh' : '/cgi-bin/rg255a_check_apn_config.sh';
                fetch(checkUrl, { cache: "no-store" })
                    .then(r => r.json()).then(d => console.log("Recovery script result:", d));
            }

            // Failover: If still not connected by attempt 30, attempt to switch SIM slots or re-detect SIMs
            if (attempts === 30) {
                console.log("Failover triggered: Attempting SIM slot recovery due to persistent connection failure...");
                let simDetUrl = "";
                if (model.includes("RG255A")) simDetUrl = "/cgi-bin/rg255a_sim_det.sh";
                else if (model.includes("RM500U")) simDetUrl = "/cgi-bin/rm500u_sim_det.sh";
                else if (model.includes("A7908E")) simDetUrl = "/cgi-bin/a7908e_sim_det.sh";
                else if (model.includes("SRM810")) simDetUrl = "/cgi-bin/srm810_sim_det.sh";

                if (simDetUrl) fetch(simDetUrl, { cache: "no-store" }).catch(e => console.error("Failover trigger failed:", e));
            }

            try {

                // Check status to ensure we are not reading stale data from before configuration
                const statsResp = await fetch(`/modem_stats?_=${Date.now()}`, { cache: "no-store" });
                const stats = await statsResp.json();

                console.log(`DEBUG: Current modem_stats status: ${stats.status}, LED ready: ${ledReady}`);

                if (stats.status !== "ready") {
                    console.log(`Modem status is ${stats.status}. Waiting for fresh data update...`);

                    // If LED is ready, nudge the stats script to perform a refresh pass
                    if (!ledReady) {
                        const ledResp = await fetch(`/cgi-bin/check_led.sh?_=${Date.now()}`, { cache: "no-store" });
                        const ledData = await ledResp.json();
                        if (ledData.led === "green") {
                            ledReady = true;
                            console.log("Modem LED is green. Will start nudging stats script.");
                        } else {
                            console.log("Waiting for Modem LED to turn green...");
                        }
                    } else {
                        let statsUrl = "/cgi-bin/get_lte_stats.sh";
                        if (model.includes("RG255A")) {
                            statsUrl = "/cgi-bin/rg255a_get_lte_stats.sh";
                        } else if (model.includes("RM500U")) {
                            statsUrl = "/cgi-bin/rm500u_get_lte_stats.sh";
                        } else if (model.includes("A7908E")) {
                            statsUrl = "/cgi-bin/a7908e_get_lte_stats.sh";
                        } else if (model.includes("SRM810")) {
                            statsUrl = "/cgi-bin/srm810_get_lte_stats.sh";
                        }
                        // Nudge the stats script to re-evaluate and update /tmp/lte_stats
                        console.log(`Nudging stats script: ${statsUrl}`);
                        fetch(`${statsUrl}?_=${Date.now()}`, { cache: "no-store" });
                    }
                    return;
                }

                // If stats.status is "ready" but ledReady is false, check LED again
                if (stats.status === "ready" && !ledReady) {
                    const ledResp = await fetch(`/cgi-bin/check_led.sh?_=${Date.now()}`, { cache: "no-store" });
                    const ledData = await ledResp.json();
                    if (ledData.led === "green") {
                        console.log("LED is green. Starting ping tests ...");
                        ledReady = true;
                    } else {
                        console.log("Waiting for Modem LED ...");
                    }
                    return
                }

                // Both stats.status is "ready" and ledReady is true, now check ping
                const pingResp = await fetch(`/cgi-bin/check_ping.sh?_=${Date.now()}`, { cache: "no-store" });
                const pingData = await pingResp.json();

                if (pingData.ping === "ok") {
                    console.log("Internet alive and stats are fresh!");

                    // Final check to ensure status is still ready
                    if (stats.status === "ready") {
                        await showBandConfig();
                        clearInterval(pollInterval);
                        console.log("Sync complete. System ready.")
                        resolve(stats);
                    }
                } else {
                    console.log("Ping failed, but modem status is 'ready' and LED is green. Retrying ping...");
                }
            } catch (e) {
                console.log(`Modem interface resetting or fetch error: ${e.message}`);
            }

            if (attempts >= maxAttempts) {
                clearInterval(pollInterval);
                reject("Timeout: Modem reached internet but failed to report status or ping successfully.");
            }
        }, 4000);
    });
}

async function getCurCell() {
    try {
        let carrier = "";

        const modelResp = await fetch('/modem_model', { cache: "no-store" });
        const model = (await modelResp.text()).trim();

        // Read modem_stats first
        const resp = await fetch('/modem_stats', { cache: "no-store" });
        if (!resp.ok) throw new Error("File not ready");
        let cellularInfo = await resp.json();

        // Only trigger fresh stats if operator is missing or stale
        if (!cellularInfo.operator || cellularInfo.operator === "No operator detected") {
            const fresh = await fetchLteStats(model);
            if (fresh) cellularInfo = fresh;
        }

        if (cellularInfo.noCellularInfo) {
            document.getElementById("cellularStat").innerText = "No cellular connection detected";
            return false;
        }

        console.log(cellularInfo.operator);
        if (cellularInfo.operator !== "No operator detected") {
            carrier = await getCarrier(cellularInfo.operator);
        }

        let html = "";

        cellInfo = document.getElementById("cellularStat");
        html += `
        <h1>Cellular Status</h1>
        <p class="description">View cellular information</p>
        <hr>
        `;

        if (cellularInfo) {
            if (cellularInfo.iface) {
                html += `<p><strong>Device: </strong>${cellularInfo.iface || 'N/A'}</p>`
            }

            if (cellularInfo.proto) {
                if (cellularInfo.proto === "dhcp") {
                    cellularInfo.proto = "DHCP client";
                }
                html += `<p><strong>Connection Type: </strong>${cellularInfo.proto || 'N/A'}</p>`
            }

            if (cellularInfo.ip) {
                html += `<p><strong>IP Address: </strong>${cellularInfo.ip || 'N/A'}</p>`
            }

            if (cellularInfo.subnet) {
                html += `<p><strong>Subnet Mask: </strong>${cellularInfo.subnet || 'N/A'}</p>`
            }

            if (cellularInfo.gateway) {
                html += `<p><strong>Gateway: </strong>${cellularInfo.gateway || 'N/A'}</p>`
            }

            if (cellularInfo.bcast) {
                html += `<p><strong>Broadcast Address: </strong>${cellularInfo.bcast || 'N/A'}</p>`
            }

            if (carrier) {
                html += `<p><strong>Telco Provider: </strong>${carrier || 'Not Connected'}</p>`
            }

            if (cellularInfo.rat) {
                switch (String(cellularInfo.rat).trim()) {
                    case "7":
                        cellularInfo.rat = "4G";
                        break;
                    case "11":
                        cellularInfo.rat = "5G";
                        break;
                    case "13":
                        cellularInfo.rat = "5G-NSA";
                        break;
                    default:
                        cellularInfo.rat = "Not Connected";
                        break;
                }
                html += `<p><strong>Service: </strong>${cellularInfo.rat || 'Not Connected'}</p>`
            }

            if (cellularInfo.sim1iccid) {
                html += `<p><strong>SIM 1 ICCID: </strong>${cellularInfo.sim1iccid || 'Not Detected'}</p>`
            }

            if (cellularInfo.sim2iccid) {
                html += `<p><strong>SIM 2 ICCID: </strong>${cellularInfo.sim2iccid || 'Not Detected'}</p>`
            }

            if (cellularInfo.curSlot) {
                html += `<p><strong>Selected SIM Slot: </strong>SIM slot ${cellularInfo.curSlot || 'Not Detected'}</p>`
            }
        }
        else if (!cellularInfo) {
            html += `<p><strong>No cellular information found</strong></p>`
        }
        cellInfo.innerHTML = html;
    }
    catch (err) {
        console.error("Failed to load cellular info:", err);
    }
}

function showConfigForm() {
    configForm = document.getElementById("cellularConfig");
    let html = "";

    html += `
    <h1>Cellular Configuration</h1>
    <p class="description">Configure cellular network</p>
    <hr>
    `
    html += `
    <div class="autoToggle">
        <label class="switch">
            <input type="checkbox" id="autoToggle" checked>
            <span class="slider round"></span>
        </label>
        <span class="toggle-label">Auto configure</span>
    </div>
    <div class="cellForm" id="autoConfig" style="display: block">
        <p>Detecting configuration ...</p>
    </div>
    <div class="cellForm" id="manualConfig" style="display: none">
        <form id="lteConfig">
            <br><br>
            <label for="lteApn">Telco Provider: </label>
            <select class="lteApn-select" id="lteApn" name="lteApn" style="width: 150px;" onchange="toggleAdvancedConfig()">
            </select>
            <br><br>
            <div id="advanced" style="display: none;">
                <label for=adLte>APN: </label>
                <input type="text" id="adLteApn"/>
                <br><br>
            </div>
            <label for="lteService">Service: </label>
            <select class="lteService-select" id="lteService" name="lteService">
                <option value="LTE">4G</option>
                <option value="NR5G">5G</option>
                <option value="AUTO" selected>AUTO</option>
            </select>
            <br><br>
            <label for="simSlot">Sim slot: </label>
            <select class="simSlot-select" id="simSlot" name="simSlot">
                <option value="1" selected>1</option>
                <option value="2">2</option>
            </select>
            <br><br>
            <div id="username" style="display: none">
                <label for=username>Username: </label>
                <input type="text" id="lteUsername"/>
                <br><br>
            </div>
            <br><br>
            <div id="pin" style="display: none">
                <label for=pin>Pin: </label>
                <input type="password" id="ltePin"/>
                <br><br>
            </div>
        </form>
    </div>
    `;
    html += `<button id="lteSave" onclick="configCellular()" style="display: none">Save</button>`;
    configForm.innerHTML = html;

    // Pre-select Service and SIM Slot based on current status
    (async () => {
        try {
            const resp = await fetch('/modem_stats', { cache: "no-store" });
            const stats = await resp.json();
            if (stats.curSlot) document.getElementById("simSlot").value = stats.curSlot;

            const svc = document.getElementById("lteService");
            if (stats.rat == "7") svc.value = "LTE";
            else if (stats.rat == "11" || stats.rat == "13") svc.value = "NR5G";
            else svc.value = "AUTO";
        } catch (e) { console.error("Error pre-selecting cellular config:", e); }
    })();

    const checkbox = document.getElementById('autoToggle');
    checkbox.addEventListener('change', function () {
        toggleAutoConfig();
        if (this.checked) {
            getAutoConfig();
        }
    });

    if (checkbox.checked) {
        getAutoConfig();
    }
}

async function waitForCellular(maxRetries = 5, delay = 2000) {
    for (let i = 0; i < maxRetries; i++) {
        try {
            const resp = await fetch('/cgi-bin/get_lte_stats.sh');
            const data = await resp.json();

            // Check if we have valid operator data (not "No operator detected")
            if (data.operator && data.operator !== "No operator detected" && data.rat && data.rat !== "Not Connected") {
                console.log("Cellular info ready", data);
                return data;
            }
            else {
                console.log(`No valid operator detected, retrying (${i + 1}/${maxRetries})...`);
                await new Promise(r => setTimeout(r, delay));
            }
        }
        catch (error) {
            console.error(`Error fetching cellular data (attempt ${i + 1}/${maxRetries}):`, error);
            await new Promise(r => setTimeout(r, delay));
        }
    }
    return {
        noCellularInfo: true,
        error: "Cellular info not found after waiting",
        operator: null,
        rat: null
    };
}

async function showBandConfig() {
    const bandContainer = document.getElementById('cellularBand');

    try {
        const modelResp = await fetch('/modem_model', { cache: "no-store" });
        let model = (await modelResp.text()).trim();
        if (model === "5G Module") model = "SRM810";
        if (model.includes("RM500U")) model = "RM500U";

        const statsResp = await fetch('/modem_stats', { cache: "no-store" });
        const stats = await statsResp.json();

        const rat = String(stats.rat).trim();
        console.log(`showBandConfig: model=${model}, rat=${rat}`);

        const dbResp = await fetch('/db/band-db.json');
        const db = await dbResp.json();

        if (!db[model]) {
            bandContainer.innerHTML = `<p>Model ${model} not found in database.</p>`;
            return;
        }

        const modelData = db[model];
        let html = `<h1>Cellular Band Configuration</h1>
                    <p class="description">Configure band for cellular network</p>
                    <hr>
        `;

        const renderSection = (title, bands, prefix) => {
            if (!bands || bands.length === 0) return "";

            let section = `<div class="band-section-title">${title}</div>`;
            section += `<div class="band-grid">`;
            bands.forEach(band => {
                section += `
                    <label class="band-pill">
                        <input type="checkbox" name="lock_band" value="${band}">
                        ${prefix}${band} 
                    </label>`;
            });
            section += `</div>`;
            return section;
        };

        if (rat === "7") {
            html += renderSection("4G LTE - FDD", modelData["LTE_FDD"], "B");
            html += renderSection("4G LTE - TDD", modelData["LTE_TDD"], "B");
        } else if (rat === "11") {
            html += renderSection("5G Standalone (SA) Bands", modelData["NR5G"], "N");
        } else if (rat === "13") {
            html += renderSection("4G LTE - FDD", modelData["LTE_FDD"], "B");
            html += renderSection("4G LTE - TDD", modelData["LTE_TDD"], "B");
            html += renderSection("5G NSA Bands", modelData["NR5G"], "N");
        } else {
            bandContainer.innerHTML = `<p>No bands available for current RAT: ${rat}</p>`;
            return;
        }

        html += `
            <div style="display: flex; gap: 12px; margin-top: 15px; margin-bottom: 15px;">
                <button class="btn-green" 
                        style="display: flex; align-items: center; justify-content: center; text-align: center; height: 50px; min-width: 100px; padding: 5px 15px; line-height: 1.2;" 
                        onclick="applyBandLock()">Apply Band</button>
                
                <button class="btn-green" 
                        style="display: flex; align-items: center; justify-content: center; text-align: center; height: 50px; min-width: 100px; padding: 5px 15px; line-height: 1.2;" 
                        onclick="selectAllBands(true)">Select All</button>
                
                <button class="btn-green" 
                        style="display: flex; align-items: center; justify-content: center; text-align: center; height: 50px; min-width: 100px; padding: 5px 15px; line-height: 1.2;" 
                        onclick="selectAllBands(false)">Clear All</button>
            </div>
        `;

        const activeLteBands = [];
        const activeNrBands = [];

        if (rat === "13") {
            if (stats.lte_band) activeLteBands.push(String(stats.lte_band).trim());
            if (stats.band) activeNrBands.push(String(stats.band).trim());
        } else if (rat === "7") {
            if (stats.band) activeLteBands.push(String(stats.band).trim());
        } else if (rat === "11") {
            if (stats.band) activeNrBands.push(String(stats.band).trim());
        }

        console.log(`showBandConfig: activeLteBands=${JSON.stringify(activeLteBands)}, activeNrBands=${JSON.stringify(activeNrBands)}`);

        const tempDiv = document.createElement('div');
        tempDiv.innerHTML = html;

        tempDiv.querySelectorAll('.band-section-title').forEach(title => {
            const isNr = title.textContent.includes("5G");
            const activeSet = isNr ? activeNrBands : activeLteBands;
            const grid = title.nextElementSibling;
            if (grid) {
                grid.querySelectorAll('input[name="lock_band"]').forEach(cb => {
                    cb.checked = activeSet.includes(cb.value);
                });
            }
        });

        bandContainer.innerHTML = "";
        while (tempDiv.firstChild) {
            bandContainer.appendChild(tempDiv.firstChild);
        }

    } catch (error) {
        console.error("UI Render Error:", error);
    }
}

function selectAllBands(checked) {
    const checkbox = document.querySelectorAll('input[name="lock_band"]');
    checkbox.forEach(cb => cb.checked = checked);
}

async function applyBandLock() {
    const selectedBands = Array.from(document.querySelectorAll('input[name="lock_band"]:checked'))
        .map(cb => cb.value)
        .join(':');

    if (!selectedBands) {
        alert("Please select at least one band.");
        return;
    }

    const statsResp = await fetch('/modem_stats', { cache: "no-store" });
    const stats = await statsResp.json();
    const rat = String(stats.rat).trim();

    const is5G = document.getElementById('cellularBand').innerText.includes('5G');
    let cmdType;
    if (!is5G) {
        cmdType = "lte_band";
    } else if (rat === "13") {
        cmdType = "nsa_nr5g_band";
    } else {
        cmdType = "nr5g_band";
    }

    const modelResp = await fetch('/modem_model', { cache: "no-store" });
    const model = (await modelResp.text()).trim();

    let url = "/cgi-bin/set_band.sh";
    if (model.includes("RG255A")) {
        url = "/cgi-bin/rg255a_set_band.sh";
        console.log("RG255A detected, using rg255a_set_band.sh for band lock");
    } else if (model.includes("RM500U")) {
        url = "/cgi-bin/rm500u_set_band.sh";
        console.log("RM500U detected, using rm500u_set_band.sh for band lock");
    } else if (model.includes("A7908E") || model.includes("A7808E")) {
        url = "/cgi-bin/a7908e_set_band.sh";
        console.log("A7908E detected, using a7908e_set_band.sh for band lock");
    } else if (model.includes("SRM810")) {
        url = "/cgi-bin/srm810_set_band.sh";
        console.log("SRM810 detected, using srm810_set_band.sh for band lock");
    }

    if (confirm(`Lock to ${cmdType}: ${selectedBands}?`)) {
        if (typeof showLoading === "function") showLoading("Applying Band Lock...");

        try {
            const formData = new URLSearchParams();
            formData.append('type', cmdType);
            formData.append('bands', selectedBands);
            console.log(`Sending band lock request to ${url} with data:`, formData.toString());

            const response = await fetch(url, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded'
                },
                body: formData.toString()
            });

            if (!response.ok) {
                const errorBody = await response.text().catch(() => "No error details");
                throw new Error(`Server returned ${response.status} (${response.statusText}): ${errorBody}`);
            }

            const result = await response.json();

            if (result.status === "success") {
                try {
                    // Wait for the modem to re-establish connection by polling LED and Ping
                    await checkAndRefresh(40, model);

                    // Update UI components (checkAndRefresh handles showBandConfig internally)
                    await getAutoConfig();
                    alert(`Success! Bands locked to ${result.active}.`);
                } catch (error) {
                    console.error("Post-lock refresh failed:", error);
                    alert(`Success! Bands locked to ${result.active}, but verification timed out.`);
                } finally {
                    if (typeof hideLoading === "function") hideLoading();
                }
            } else {
                alert("Modem Error: " + result.message);
                if (typeof hideLoading === "function") hideLoading();
            }
        } catch (error) {
            console.error("Band lock failed:", error);
            alert("Error: " + error.message);
            if (typeof hideLoading === "function") hideLoading();
        }
    }
}

async function refreshCellular() {
    try {
        console.log("Forcing background JSON update...");

        const response = await fetch('/cgi-bin/get_lte_stats.sh');

        if (!response.ok) throw new Error("Failed to execute stats script");

        const data = await response.json();
        console.log("JSON file updated and retrieved:", data);

        return data;
    } catch (error) {
        console.error("Manual refresh failed:", error);
        return null;
    }
}

async function getAutoConfig() {
    try {
        const resp = await fetch('modem_stats', {
            cache: "no-store"
        });

        if (!resp.ok) throw new Error("File not ready yet");

        let data = await resp.json();

        let html = "";
        let carrier = "";
        auto = document.getElementById("autoConfig");

        if (data.status === "configuring") {
            const fresh = await triggerLteStatsIfConfiguring();
            if (fresh) data = fresh;
        }

        const MAX_RETRIES = 3;
        const RETRY_DELAY_MS = 3000;
        for (let attempt = 1; attempt <= MAX_RETRIES && !hasValidCellularData(data); attempt++) {
            console.log(`getAutoConfig: missing cellular data (operator/rat). Retry ${attempt}/${MAX_RETRIES}...`);
            await new Promise(r => setTimeout(r, RETRY_DELAY_MS));
            const fresh = await fetchLteStats();
            if (fresh) data = fresh;
        }

        if (!hasValidCellularData(data)) {
            console.warn("getAutoConfig: cellular data still unavailable after retries.");
        }

        if (data.operator && data.operator !== "No operator detected") {
            carrier = await getCarrier(data.operator);
        }

        if (data) {
            if (carrier) {
                html += `<p><strong>Telco Provider: </strong>${carrier || 'Not Connected'}</p>`;
            }

            if (data.rat) {
                switch (data.rat) {
                    case "7":
                        data.rat = "4G";
                        break;
                    case "11":
                        data.rat = "5G";
                        break;
                    case "13":
                        data.rat = "5G-NSA";
                        break;
                    default:
                        data.rat = "Not Connected";
                        break;
                }
                html += `<p><strong>Service: </strong>${data.rat || 'Not Connected'}</p>`;
            }

            if (data.operator) {
                html += `<p><strong>PLMN: </strong>${data.operator || 'N/A'}</p>`;
            }

            if (data.mcc) {
                html += `<p><strong>MCC: </strong>${data.mcc || 'N/A'}</p>`;
            }

            if (data.mnc) {
                html += `<p><strong>MNC: </strong>${data.mnc || 'N/A'}</p>`;
            }

            if (data.band) {
                if (data.rat === "4G") {
                    html += `<p><strong>Band: </strong>B${data.band || 'N/A'}</p>`;
                }
                else if (data.rat === "5G") {
                    html += `<p><strong>Band: </strong>N${data.band || 'N/A'}</p>`;
                }
                else if (data.rat === "5G-NSA") {
                    html += `<p><strong>Anchor Band: </strong>B${data.lte_band || 'N/A'}</p>
                            <p><strong>Band: </strong>N${data.band || 'N/A'}</p>`;
                }
            }

            if (data.rsrp) {
                rankRsrp = classifyReceivePower(data.rsrp, data.rat);
                html += `<p><strong>Receive Signal: </strong>${data.rsrp || 'N/A'} (${rankRsrp})</p>`;
            }

            if (data.rsrq) {
                rankRsrq = classifyReceiveQuality(data.rsrq, data.rat);
                html += `<p><strong>Receive Quality: </strong>${data.rsrq || 'N/A'} (${rankRsrq})</p>`;
            }

            if (data.snr) {
                rankSnr = classifySNR(data.snr);
                html += `<p><strong>SNR: </strong>${data.snr || 'N/A'} (${rankSnr})</p>`;
            }
        }
        else {
            html += `<p>Not Connected</p>`;
        }
        auto.innerHTML = html;
    }
    catch (err) {
        console.error("Failed to establish connection:", err);
    }
}

function classifySNR(snr) {
    let result = "";
    snr = parseFloat(snr);

    if (snr >= 25 && snr <= 40) {
        result = "Excellent";
    }
    else if (snr >= 9 && snr <= 24) {
        result = "Good";
    }
    else if (snr >= -7 && snr <= 8) {
        result = "Fair";
    }
    else if (snr >= -40 && snr <= -9) {
        result = "Poor";
    }
    else {
        result = "Invalid SNR reading";
    }
    return result;
}

function classifyReceivePower(rsrp, band) {
    let result = "";
    rsrp = parseFloat(rsrp);

    if (band === "4G") {
        if (rsrp >= -68 && rsrp <= -44) {
            result = "Excellent";
        }
        else if (rsrp >= -93 && rsrp <= -69) {
            result = "Good";
        }
        else if (rsrp >= -117 && rsrp <= -94) {
            result = "Fair";
        }
        else if (rsrp >= -140 && rsrp <= -118) {
            result = "Poor";
        }
        else {
            result = "Invalid RSRP reading";
        }
    }
    else if (band === "5G" || band === "5G-NSA") {
        if (rsrp >= -62 && rsrp <= -31) {
            result = "Excellent";
        }
        else if (rsrp >= -94 && rsrp <= -63) {
            result = "Good";
        }
        else if (rsrp >= -126 && rsrp <= -95) {
            result = "Fair";
        }
        else if (rsrp >= -156 && rsrp <= -127) {
            result = "Poor";
        }
        else {
            result = "Invalid RSRP reading";
        }
    }
    else {
        result = "Invalid RSRP";
    }
    return result;
}

function classifyReceiveQuality(rsrq, band) {
    let result = "";
    rsrq = parseFloat(rsrq);

    if (band === "4G") {
        if (rsrq >= -7 && rsrq <= -3) {
            result = "Excellent";
        }
        else if (rsrq >= -12 && rsrq <= -8) {
            result = "Good";
        }
        else if (rsrq >= -17 && rsrq <= -13) {
            result = "Fair";
        }
        else if (rsrq >= -20 && rsrq <= -18) {
            result = "Poor";
        }
        else {
            result = "Invalid RSRQ reading";
        }
    }
    else if (band === "5G-NSA") {
        if (rsrq >= -6 && rsrq <= -3) {
            result = "Excellent";
        }
        else if (rsrq >= -10 && rsrq <= -7) {
            result = "Good";
        }
        else if (rsrq >= -14 && rsrq <= -11) {
            result = "Fair";
        }
        else if (rsrq >= -20 && rsrq <= -15) {
            result = "Poor";
        }
        else {
            result = "Invalid RSRQ reading";
        }
    }
    else if (band === "5G") {
        if (rsrq >= 4 && rsrq <= 20) {
            result = "Excellent";
        }
        else if (rsrq >= -13 && rsrq <= 3) {
            result = "Good";
        }
        else if (rsrq >= -30 && rsrq <= -14) {
            result = "Fair";
        }
        else if (rsrq >= -43 && rsrq <= -31) {
            result = "Poor";
        }
        else {
            result = "Invalid RSRQ reading";
        }
    }
    else {
        result = "Invalid RSRQ";
    }
    return result;
}

async function getCarrier(mccmnc) {
    const res = await fetch('/db/apn-db.json');
    const apnDB = await res.json();
    console.log(mccmnc);
    console.log(apnDB[mccmnc]);
    console.log(apnDB[mccmnc].carrier);
    return apnDB[mccmnc].carrier;
}

async function getApn(carrier, band) {
    try {
        const apnDB = await fetch('/db/apn-db.json').then(res => res.json());

        const entry = Object.values(apnDB).find(
            e => e.carrier.toLowerCase() === carrier.toLowerCase()
        );

        if (!entry) {
            console.warn(`Carrier '${carrier}' not found.`);
            return null;
        }

        const apnInfo = entry.APNs[band];
        if (!apnInfo) {
            console.warn(`Band '${band}' not found for carrier '${carrier}'.`);
            return null;
        }
        console.log(apnInfo.apn);
        return apnInfo.apn;
    }
    catch (err) {
        console.error("Failed to get APN:", err);
        return null;
    }
}

async function loadCarrierByMCC(maxRetries = 5) {
    let retries = 0;

    while (retries < maxRetries) {
        try {
            const resp = await fetch(`/modem_stats?_=${Date.now()}`, { cache: "no-store" });
            if (!resp.ok) throw new Error("Stat file not found on server");
            const mccData = await resp.json();
            const mcc = mccData.mcc;

            if (!mcc) {
                throw new Error("MCC not found");
            }

            const apnDB = await fetch('/db/apn-db.json').then(res => res.json());

            const carriers = Object.entries(apnDB)
                .filter(([key, value]) => value.mcc === mcc)
                .map(([key, value]) => value.carrier);

            console.log(`Found carriers for MCC ${mcc}:`, carriers);
            return carriers;
        }
        catch (err) {
            retries++;
            console.warn(`loadCarrierByMCC attempt ${retries}/${maxRetries} failed:`, err.message);

            if (retries >= maxRetries) {
                console.error("Max retries reached. Failed to get carriers by MCC", err);
                return [];
            }

            console.log("loadCarrierByMCC: triggering stats refresh before retry...");
            await fetchLteStats();

            const delay = Math.min(1000 * Math.pow(2, retries - 1), 5000);
            console.log(`Retrying in ${delay}ms...`);
            await new Promise(resolve => setTimeout(resolve, delay));
        }
    }
}

async function populateCarrierOp() {
    const statsResp = await fetch('/modem_stats', { cache: "no-store" });
    const stats = await statsResp.json();

    let currentCarrier = "";
    if (stats.operator && stats.operator !== "No operator detected") {
        currentCarrier = await getCarrier(stats.operator);
    }

    const carriers = await loadCarrierByMCC();
    const select = document.getElementById("lteApn");
    select.innerHTML = "";

    if (!carriers.length) {
        const noOpt = document.createElement("option");
        noOpt.value = "";
        noOpt.text = "-- No operators found --";
        noOpt.disabled = true;
        select.add(noOpt);

        const othersOpt = document.createElement("option");
        othersOpt.value = "others";
        othersOpt.text = "Others (Manual)";
        select.add(othersOpt);

        select.value = "others";
        toggleAdvancedConfig();
    } else {
        let matched = false;
        carriers.forEach(carrier => {
            const opt = document.createElement("option");
            opt.value = carrier;
            opt.text = carrier;
            if (currentCarrier && carrier === currentCarrier) {
                opt.selected = true;
                matched = true;
            }
            select.add(opt);
        });

        const othersOpt = document.createElement("option");
        othersOpt.value = "others";
        othersOpt.text = "Others (Manual)";
        if (!matched) othersOpt.selected = true;
        select.add(othersOpt);

        toggleAdvancedConfig();
    }

    // Pre-select band
    if (stats.band) {
        const bandSelect = document.getElementById("lteBand");
        if (bandSelect) {
            for (const opt of bandSelect.options) {
                if (
                    opt.value === stats.band ||
                    opt.value === `B${stats.band}` ||
                    opt.value.replace(/[^0-9]/g, "") === stats.band
                ) {
                    opt.selected = true;
                    bandSelect.dispatchEvent(new Event("change"));
                    break;
                }
            }
        }
    }

    // Pre-select SIM slot
    if (stats.curSlot) {
        const simSelect = document.getElementById("simSlot");
        if (simSelect) {
            for (const opt of simSelect.options) {
                if (opt.value === String(stats.curSlot)) {
                    opt.selected = true;
                    simSelect.dispatchEvent(new Event("change"));
                    break;
                }
            }
        }
    }
}

function toggleAdvancedConfig() {
    const dropdown = document.getElementById("lteApn");
    const textbox = document.getElementById("advanced");

    if (dropdown.value === "others") {
        textbox.style.display = "block";
    }
    else {
        textbox.style.display = "none";
    }
}

function toggleAutoConfig() {
    const checkbox = document.getElementById("autoToggle");
    const autoConfig = document.getElementById("autoConfig");
    const manualConfig = document.getElementById("manualConfig");
    const button = document.getElementById("lteSave");

    if (checkbox.checked) {
        autoConfig.style.display = "block";
        manualConfig.style.display = "none";
        button.style.display = "none";
    }
    else {
        autoConfig.style.display = "none";
        manualConfig.style.display = "block";
        button.style.display = "inline-block";
    }
}

function showLoading(message) {
    let overlay = document.getElementById("loading-overlay");
    let loadingText = document.getElementById("loading-text");

    if (!overlay) {
        console.error("showLoading: loading-overlay not found!");
        return;
    }

    if (loadingText) {
        loadingText.textContent = message;
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