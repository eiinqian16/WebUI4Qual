let loadedScripts = {}; // Track loaded scripts
let currentSection = null; // Track current section

function changeLanguage(lang) {
    let select = document.getElementById('langSelect');
    if (select) select.disabled = true;

    i18n.setLanguage(lang).then(() => {
        // i18n.setLanguage already re-translates static markup document-wide.
        // Dynamically-rendered section content (built by JS template strings)
        // needs its section reloaded so it regenerates text in the new language.
        let sectionToReload = currentSection;
        currentSection = null;
        loadSection(sectionToReload || 'overview');
    }).finally(() => {
        if (select) select.disabled = false;
    });
}

function loadSection(section) {
    // Prevent duplicate section loads
    if (currentSection === section) {
        console.log(`Section ${section} already loaded, skipping...`);
        return;
    }
    currentSection = section;

    fetch(section + '.html')
        .then(response => response.text())
        .then(html => i18n.init().then(() => html))
        .then(html => {
            let mainContent = document.querySelector('#main-content');
            if (!mainContent) {
                console.error('Error: #main-content not found');
                return;
            }
            mainContent.innerHTML = html;
            i18n.applyTranslations(mainContent);

            if (section === 'overview') {
                loadScript('js/process_json.js', () => {
                    fetchSysStats();
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

                if (section === 'ezmesh') {
		    console.log("Loading EZMesh section...");
		    
		 // Debug: Check what's in the HTML before we load scripts
		fetch(section + '.html')
		    .then(response => response.text())
		    .then(html => {
			console.log("EZMesh HTML content length:", html.length);
			console.log("Contains toggleController:", html.includes('toggleController'));
			console.log("Contains toggleAgent:", html.includes('toggleAgent'));
			console.log("Contains startBtn:", html.includes('startBtn'));
		    });

		// Force reload the script to ensure fresh initialization
		const existingScript = document.querySelector('script[src*="ezmesh.js"]');
		if (existingScript) {
			existingScript.remove();
		}
		    
		// Add timestamp to bypass cache
		const scriptSrc = 'js/ezmesh.js?' + new Date().getTime();
		    
		loadScript(scriptSrc, () => {
			console.log("EZMesh script loaded, waiting for DOM...");
			
			let attempts = 0;
			
			function tryInitialize() {
				attempts++;
				console.log(`EZMesh initialization attempt ${attempts}`);
			    
				// Debug: Check if elements exist in DOM
				const elements = {
					toggleController: document.getElementById("toggleController"),
					toggleAgent: document.getElementById("toggleAgent"),
					startBtn: document.getElementById("startBtn")
				};
				console.log("Elements found:", elements);
			    
				if (typeof initEzmesh === 'function') {
					const success = initEzmesh();
					if (success) {
						console.log("EZMesh initialized successfully on attempt", attempts);
				    
					setTimeout(() => {
						console.log("Testing elements after initialization:");
						console.log("toggleController:", document.getElementById("toggleController"));
						console.log("toggleAgent:", document.getElementById("toggleAgent"));
						console.log("startBtn disabled:", document.getElementById("startBtn").disabled);
					}, 500);
						return;
					}
				}
			    
				if (attempts < 10) {
					setTimeout(tryInitialize, 200);
				} else {
					console.error("EZMesh failed to initialize after 10 attempts");
				}
			}
			
			setTimeout(tryInitialize, 100);
		});
			}
                if (section === 'cellular') {
                    loadScript('js/cellular.js', () => {
                        getCurCell();
                        showConfigForm();
                        populateCarrierOp();
                        getAutoConfig();
                        showBandConfig();
                    });
                }
            
                if (section === 'advanced') {
                    loadScript('js/advanced.js', () => {
                        initAckTimeout();
                        console.log('test acktimeout test');
                        initAdvanced();
                        openDenyList();
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
                
                if (section === 'factory_reset') {
                    loadScript('js/system.js', () => {});
                }
                
                if (section === 'restore_config') {
                    loadScript('js/restore_config.js', () => {});
                }

                if (section === 'firmware_update') {
                    loadScript('js/firmware_update.js', () => {});
                }
                
                if (section === 'system_log') {
                    loadScript('js/system_log.js', () => {
                        loadTime();
                        loadPage();
                    });
                }
                
                if (section === 'eco') {
                    loadScript('js/eco_mode.js', () => {
                        loadPowerMode();
                        initEcoAdvanced();
                    });
                }

                if (section === 'time') {
                    loadScript('js/time.js', () => {
                        showTimeConfig();
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
    // Check if already loaded
    if (loadedScripts[src]) {
        console.log(`Script ${src} already loaded, executing callback...`);
        if (callback) callback();
        return;
    }
    
    // Check if script tag already exists in DOM
    let existingScript = document.querySelector(`script[src="${src}"]`);
    if (existingScript) {
        console.log(`Script tag for ${src} already exists`);
        loadedScripts[src] = true;
        if (callback) callback();
        return;
    }
    
    let script = document.createElement('script');
    script.src = src;
    script.onload = () => {
        loadedScripts[src] = true;
        console.log(`Loaded script: ${src}`);
        if (callback) callback();
    };
    script.onerror = () => {
        console.error(`Failed to load script: ${src}`);
        delete loadedScripts[src]; // Allow retry on error
    };
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

window.redirectToAccessControl = function(event) {
    if (event) {
        event.preventDefault();
        event.stopPropagation();
    }

    console.log("Navigation triggered to Access Control");

    // 1. Call your existing page switcher
    if (typeof showSection === 'function') {
        showSection('advanced');
    }

    // 2. Scroll and Render
    setTimeout(() => {
        const section = document.getElementById('accessControl');
        if (section) {
            section.scrollIntoView({ behavior: 'smooth', block: 'start' });
            
            // Re-run the list fetcher we built earlier
            if (typeof renderDenyList === 'function') {
                renderDenyList();
            }
        }
    }, 150);
};

window.redirectToTime = function(event) {
    if (event) {
        event.preventDefault();
        event.stopPropagation();
    }

    console.log("Navigation triggered to Time");

    if (typeof showSection === 'function') {
        showSection('time');
    }

    setTimeout(() => {
        const section = document.getElementById('time-container');
        if (section) {
            section.scrollIntoView({ behavior: 'smooth', block: 'start' });

            if (typeof showTimeConfig === 'function') {
                showTimeConfig();
            }
        }
    }, 150);
};

// CONSOLIDATED DOMContentLoaded - Only ONE listener now!
document.addEventListener("DOMContentLoaded", () => {
    i18n.init().then(() => {
        let select = document.getElementById('langSelect');
        if (select) select.value = i18n.currentLang;
    });

    // Session check
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
            return;
        }
        
        // Only load section after session is validated
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
    })
    .catch(error => {
        console.error("Error:", error);
        sessionStorage.clear();
        window.location.href = "login.html";
    });

    // Dropdown toggles
    let dropdownToggles = document.querySelectorAll(".sidebar-dropdown");
    dropdownToggles.forEach((toggle) => {
        toggle.addEventListener("click", function () {
            let dropdownMenu = this.nextElementSibling; 
            dropdownMenu.style.display = dropdownMenu.style.display === "block" ? "none" : "block";
        });
    });
});