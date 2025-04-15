function loadSection(section) {
    fetch(section + '.html')
        .then(response => response.text())
        .then(html => {
            let mainContent = document.querySelector('#main-content');
            if (!mainContent) {
                console.error('Error: #main-content not found');
                return;
            }
            mainContent.innerHTML = html;

            if (section === 'overview') {
                    loadScript('js/process_json.js', () => {
                        fetchSysStats();
                        fetchStorageStats();
                    });
            }
            setTimeout(() => {
                if (section === 'wireless') {
                    loadScript('js/wireless.js', () => {
                        if (typeof getConfig === 'function') {
                            getConfig();
                            fetchAssociatedStations();
                            if (!window.associatedStationsInterval) {
                                window.associatedStationsInterval = setInterval(fetchAssociatedStations, 5000);
                            }

                            if (!window.wifiInfoInterval) {
                                console.log("Starting wifiInfoInterval...");
                                window.wifiInfoInterval = setInterval(() => getConfig(true), 5000);
                            } else {
                                console.log("wifiInfoInterval already exists");
                            }

                        } else {
                            console.error("Error: getConfig is not defined after loading wireless.js");
                        }
                    });
                } else {
                    if (window.associatedStationsInterval) {
                        clearInterval(window.associatedStationsInterval);
                        window.associatedStationsInterval = null;
                    }

                    if (window.wifiInfoInterval) {
                        clearInterval(window.wifiInfoInterval);
                        window.wifiInfoInterval = null;
                    }
                }
            
                if (section === 'acktimeout') {
                    loadScript('js/acktimeout.js', () => {
                        initAckTimeout();
                        console.log('test acktimeout test');
                    });
                }
                if (section === 'lan_stat') {
                    loadScript('js/process_json.js', () => {
                        fetchLanStatus();
                        fetchWanStatus();
                        fetchOthStatus();
                        if (!window.lanStatInterval) {
                            window.lanStatInterval = setInterval(refreshStatus, 5000);
                        }
                    });
                } else {
                    if (window.lanStatInterval) {
                        clearInterval(window.lanStatInterval);
                        window.lanStatInterval = null;
                    }
                }
                if (section === 'lan_config') {
                    loadScript('js/lan_configure.js', () => {
                        getCurLanIf();
                        getCurWanIf();
                    });
                }
                if (section === 'dhcp') {
                    loadScript('js/dhcp_config.js', () => {
                        fetchCurDhcpConfig();
                        fetchDchpClient();
                    });
                }
                if (section === 'user') {
                    loadScript('js/user.js', () => {
                        getCred();
                    });
                }
            }, 100);
        })
        .catch(err => console.error('Error loading section:', err));
}

function logout() {
    let sessionID = sessionStorage.getItem("sessionID");

    fetch("/cgi-bin/logout.sh", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: `session_id=${encodeURIComponent(sessionID)}`
    })
    .then(() => {
        sessionStorage.clear();
        window.location.href = "login.html"; 
    })
    .catch(error => {
        console.error("Logout Error:", error);
    });
}


function loadScript(src, callback) {
    let script = document.createElement('script');
    script.src = src;
    script.onload = () => {
        console.log(`Loaded script: ${src}`);
        if (callback) callback();
    };
    script.onerror = () => console.error(`Failed to load script: ${src}`);
    document.body.appendChild(script);
}


function showSection(section) {
    if (!section || section.trim() === "") {
        console.warn("showSection received empty section, defaulting to overview");
        section = "overview";
    }

    let currentHash = location.hash.replace("#", "") || "overview";
    
    console.log("test ", section);

    if (currentHash !== section) {
        history.pushState(null, "", `#${section}`);
    }

    loadSection(section);

    document.querySelectorAll(".sidebar ul li").forEach(item => {
        item.classList.remove("active");
    });

    let currentItem = document.querySelector(`[onclick="showSection('${section}');"]`);
    if (currentItem) {
        currentItem.classList.add("active");
    }

    let isDropdownItem = currentItem && currentItem.closest(".dropdownContent");

    document.querySelectorAll(".dropdownContent").forEach(dropdown => {
        if (!isDropdownItem || dropdown !== currentItem.closest(".dropdownContent")) {
            dropdown.style.display = "none";
        }
    });
}

document.addEventListener("DOMContentLoaded", () => {
    let section = location.hash.replace("#", "") || "overview";

    if (!section || section.trim() === "") {
        console.warn("DOMContentLoaded detected empty section, defaulting to overview");
        section = "overview";
        history.replaceState(null, "", "#overview"); 
    }

    loadSection(section);

    let currentItem = document.querySelector(`[onclick="showSection('${section}');"]`);
    if (currentItem) {
        currentItem.classList.add("active");
    }
});

window.addEventListener("hashchange", () => {
    console.log("Current Hash:", location.hash);

    if (!location.hash || location.hash === "#") {
        console.warn("Hash is empty, correcting to #overview");
        history.replaceState(null, "", "#overview");
    }
});

window.addEventListener("popstate", () => {
    let section = location.hash.replace("#", "") || "overview";
    loadSection(section);
});

document.addEventListener("DOMContentLoaded", function () {

    let dropdownToggles = document.querySelectorAll(".sidebar-dropdown");
    dropdownToggles.forEach((toggle) => {
        toggle.addEventListener("click", function () {
            let dropdownMenu = this.nextElementSibling; 

            dropdownMenu.style.display = dropdownMenu.style.display === "block" ? "none" : "block";
        });

    });
});

document.addEventListener("DOMContentLoaded", () => {
    let sessionID = sessionStorage.getItem("sessionID");

    if (!sessionID) {
        window.location.href = "login.html";
        return;
    }

    fetch("/cgi-bin/check_session.sh", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: `session_id=${encodeURIComponent(sessionID)}`
    })
    .then(response => response.json())
    .then(data => {
        if (data.status !== "Valid") {
            sessionStorage.clear();
            window.location.href = "login.html";
        }
    })
    .catch(error => {
        console.error("Error:", error);
        sessionStorage.clear();
        window.location.href = "login.html";
    });

    let section = location.hash.replace("#", "") || "overview";
    loadSection(section);
});

