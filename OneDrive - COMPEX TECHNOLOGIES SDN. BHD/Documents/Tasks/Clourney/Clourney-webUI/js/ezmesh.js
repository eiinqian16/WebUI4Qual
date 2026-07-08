/*
function initEzmesh() {
	console.log("Initializing EZMesh...");

	const toggleController = document.getElementById("toggleController");
	const toggleAgent = document.getElementById("toggleAgent");
	const startBtn = document.getElementById("startBtn");
	const wpsBtn = document.getElementById("wpsBtn");

	if (!toggleController || !toggleAgent || !startBtn || !wpsBtn) {
		console.error("EZMesh elements not found");
		return false;
	}

	let selectedRole = null;
	let currentRole = null; // role read from UCI / SSID

	// --- Loading overlay helpers ---
	function showLoading(message = "Loading...") {
		const overlay = document.getElementById("loading-overlay");
		const loadingText = document.getElementById("loading-text");
		if (!overlay) return;
		if (loadingText) loadingText.textContent = message;
		overlay.classList.add("show");
	}

	function hideLoading() {
		const overlay = document.getElementById("loading-overlay");
		if (!overlay) return;
		overlay.classList.remove("show");
	}

	// --- Update Start Button ---
	function updateStartButton() {
		if (selectedRole) {
			startBtn.classList.add("active");
			startBtn.dataset.enabled = "true";
			startBtn.style.opacity = 1;
		} else {
			startBtn.classList.remove("active");
			startBtn.dataset.enabled = "false";
			startBtn.style.opacity = 0.6;
		}
	}

	// --- Initialize from UCI / SSID ---
	fetch('/cgi-bin/get_ezmesh_mode.sh')
		.then(r => r.json())
		.then(data => {
			currentRole = data.role; // "controller", "agent", "none"

			if (currentRole === "controller") {
				toggleController.checked = true;
				selectedRole = "controller";
				toggleAgent.checked = false;
			} else if (currentRole === "agent") {
				toggleAgent.checked = true;
				selectedRole = "agent";
				toggleController.checked = false;
			} else {
				// EZMesh not running
				toggleController.checked = false;
				toggleAgent.checked = false;
				selectedRole = null;
			}

			updateStartButton();
		})
		.catch(err => {
			console.warn("Failed to load EZMesh mode, defaulting toggles to off");
			currentRole = null;
			selectedRole = null;
			toggleController.checked = false;
			toggleAgent.checked = false;
			updateStartButton();
		});

	// --- Controller Toggle ---
	toggleController.addEventListener("change", () => {
		if (toggleController.checked) {
			// Only force reset if switching from agent → controller
			if (currentRole === "agent") {
				alert("Board must be factory reset before switching to Controller mode!");
				toggleController.checked = false;
				return;
			}

			toggleAgent.checked = false;
			selectedRole = "controller";
		} else {
			selectedRole = null;
		}
		updateStartButton();
	});

	// --- Agent Toggle ---
	toggleAgent.addEventListener("change", () => {
		if (toggleAgent.checked) {
			// Only force reset if switching from controller → agent
			if (currentRole === "controller") {
				alert("Board must be factory reset before switching to Agent mode!");
				toggleAgent.checked = false;
				return;
			}

			toggleController.checked = false;
			selectedRole = "agent";
		} else {
			selectedRole = null;
		}
		updateStartButton();
	});

	// --- Start EZMesh ---
	startBtn.addEventListener("click", () => {
		if (startBtn.dataset.enabled !== "true") return;

		const confirmation = confirm(
			"After setting the EZMesh role, the current Wi-Fi settings will be replaced with the EZMesh default configuration.\n\n" +
			"Please change the SSID or password only after EZMesh setup is completed.\n\n" +
			"Continue?"
		);

		if (!confirmation) return;

		showLoading(`Starting EZMesh as ${selectedRole}... Please wait around 1 minute`);

		fetch('/cgi-bin/ezmesh.sh', {
			method: 'POST',
			headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
			body: `role=${selectedRole}&action=start`
		})
		.then(response => {
			if (!response.ok) throw new Error("Failed to start EZMesh");

			setTimeout(() => {
				hideLoading();
				alert(
					"EZMesh start process completed.\n\n" +
					"Please go to the wireless settings to view your wireless status.\n\n" +
					"Important Note: Press the WPS button on both the controller and the agent to automatically pair their wireless configurations!"
				);
			}, 60000);
		})
		.catch(err => {
			hideLoading();
			alert("Failed to start EZMesh. Please try again.");
		});
	});

	// --- WPS Button ---
	wpsBtn.addEventListener("click", () => {
		if (!selectedRole) {
			alert("Please select a role (Controller or Agent) before starting WPS pairing.");
			return;
		}

		const ok = confirm(
			"This will start WPS pairing.\n\n" +
			"Make sure both the Controller and Agent are powered on.\n" +
			"Continue?"
		);
		if (!ok) return;

		showLoading("Starting WPS pairing... Please wait 2 minutes");

		fetch('/cgi-bin/wps.sh', {
			method: 'POST',
			headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
			body: `role=${selectedRole}`
		})
			.then(response => {
				if (!response.ok) throw new Error("WPS script failed");
				return response.text();
			})
			.then(output => {
				hideLoading();
				alert("WPS pairing started.\n\nPress the WPS button on the other device to complete the pairing process.");
			})
			.catch(err => {
				hideLoading();
				alert("Failed to start WPS. Please try again.");
			});
	});

	console.log("EZMesh initialized - toggles reflect current role and force reset only on mode change");
	return true;
}
*/

function initEzmesh() {
	console.log("Initializing EZMesh...");

	const toggleController = document.getElementById("toggleController");
	const toggleAgent = document.getElementById("toggleAgent");
	const startBtn = document.getElementById("startBtn");
	const wpsBtn = document.getElementById("wpsBtn");

	if (!toggleController || !toggleAgent || !startBtn || !wpsBtn) {
		console.error("EZMesh elements not found");
		return false;
	}

	let selectedRole = null;
	let currentRole = null; // role read from UCI / SSID

	// --- Loading overlay helpers ---
	function showLoading(message = "Loading...") {
		const overlay = document.getElementById("loading-overlay");
		const loadingText = document.getElementById("loading-text");
		if (!overlay) return;
		if (loadingText) loadingText.textContent = message;
		overlay.classList.add("show");
	}

	function hideLoading() {
		const overlay = document.getElementById("loading-overlay");
		if (!overlay) return;
		overlay.classList.remove("show");
	}

	// --- Update Start Button & Toggles State ---
	function updateStartButton() {
		// Scenario A: EZMesh is already running
		if (currentRole === "controller" || currentRole === "agent") {
			startBtn.textContent = "Disable EZMesh";
			startBtn.classList.add("active", "danger"); // 'danger' class can be styled as red/grey in CSS
			startBtn.dataset.enabled = "true";
			startBtn.dataset.action = "stop"; 
			startBtn.style.opacity = 1;

			// Lock out toggles from being changed while active
			toggleController.disabled = true;
			toggleAgent.disabled = true;
			return;
		}

		// Scenario B: EZMesh is NOT running (Configuring mode)
		toggleController.disabled = false;
		toggleAgent.disabled = false;
		startBtn.textContent = "Start EZMesh";
		startBtn.classList.remove("danger");
		startBtn.dataset.action = "start";

		if (selectedRole) {
			startBtn.classList.add("active");
			startBtn.dataset.enabled = "true";
			startBtn.style.opacity = 1;
		} else {
			startBtn.classList.remove("active");
			startBtn.dataset.enabled = "false";
			startBtn.style.opacity = 0.6;
		}
	}

	// --- Initialize from UCI / SSID ---
	fetch('/cgi-bin/get_ezmesh_mode.sh')
		.then(r => r.json())
		.then(data => {
			currentRole = data.role; // "controller", "agent", "none"

			if (currentRole === "controller") {
				toggleController.checked = true;
				selectedRole = "controller";
				toggleAgent.checked = false;
			} else if (currentRole === "agent") {
				toggleAgent.checked = true;
				selectedRole = "agent";
				toggleController.checked = false;
			} else {
				// EZMesh not running
				toggleController.checked = false;
				toggleAgent.checked = false;
				selectedRole = null;
			}

			updateStartButton();
		})
		.catch(err => {
			console.warn("Failed to load EZMesh mode, defaulting toggles to off");
			currentRole = null;
			selectedRole = null;
			toggleController.checked = false;
			toggleAgent.checked = false;
			updateStartButton();
		});

	// --- Controller Toggle ---
	toggleController.addEventListener("change", () => {
		if (toggleController.checked) {
			// Only force reset if switching from agent → controller
			if (currentRole === "agent") {
				alert("Board must be factory reset before switching to Controller mode!");
				toggleController.checked = false;
				return;
			}

			toggleAgent.checked = false;
			selectedRole = "controller";
		} else {
			selectedRole = null;
		}
		updateStartButton();
	});

	// --- Agent Toggle ---
	toggleAgent.addEventListener("change", () => {
		if (toggleAgent.checked) {
			// Only force reset if switching from controller → agent
			if (currentRole === "controller") {
				alert("Board must be factory reset before switching to Agent mode!");
				toggleController.checked = false;
				return;
			}

			toggleController.checked = false;
			selectedRole = "agent";
		} else {
			selectedRole = null;
		}
		updateStartButton();
	});

	// --- Start / Disable EZMesh Handler ---
	startBtn.addEventListener("click", () => {
		if (startBtn.dataset.enabled !== "true") return;

		const currentAction = startBtn.dataset.action;

		// --- HANDLE DISABLE NETWORK ACTION ---
		if (currentAction === "stop") {
			const confirmDisable = confirm(
				"Are you sure you want to disable EZMesh?\n\n" +
				"This will stop the mesh network and disconnect all agent nodes. Your Wi-Fi will temporarily reboot.\n\n" +
				"Continue?"
			);
			if (!confirmDisable) return;

			showLoading("Disabling EZMesh... Please wait around 1 minute");

			// Changed body payload to explicitly post role=none
			fetch('/cgi-bin/ezmesh.sh', {
				method: 'POST',
				headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
				body: `role=none&action=stop`
			})
			.then(response => {
				if (!response.ok) throw new Error("Failed to stop EZMesh");

				setTimeout(() => {
					hideLoading();
					alert("EZMesh has been successfully disabled.");
					
					// Reset internal states back to baseline
					currentRole = "none";
					selectedRole = null;
					toggleController.checked = false;
					toggleAgent.checked = false;
					
					updateStartButton();
				}, 60000);
			})
			.catch(err => {
				hideLoading();
				alert("Failed to disable EZMesh. Please try again.");
			});

			return; // Stop execution here for the disable workflow
		}

		// --- HANDLE EXISTING START ACTION ---
		const confirmation = confirm(
			"After setting the EZMesh role, the current Wi-Fi settings will be replaced with the EZMesh default configuration.\n\n" +
			"Please change the SSID or password only after EZMesh setup is completed.\n\n" +
			"Continue?"
		);

		if (!confirmation) return;

		showLoading(`Starting EZMesh as ${selectedRole}... Please wait around 1 minute`);

		fetch('/cgi-bin/ezmesh.sh', {
			method: 'POST',
			headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
			body: `role=${selectedRole}&action=start`
		})
		.then(response => {
			if (!response.ok) throw new Error("Failed to start EZMesh");

			setTimeout(() => {
				hideLoading();
				alert(
					"EZMesh start process completed.\n\n" +
					"Please go to the wireless settings to view your wireless status.\n\n" +
					"Important Note: Press the WPS button on both the controller and the agent to automatically pair their wireless configurations!"
				);
				// Elevate selected role to active running role
				currentRole = selectedRole;
				updateStartButton();
			}, 60000);
		})
		.catch(err => {
			hideLoading();
			alert("Failed to start EZMesh. Please try again.");
		});
	});

	// --- WPS Button ---
	wpsBtn.addEventListener("click", () => {
		if (!selectedRole) {
			alert("Please select a role (Controller or Agent) before starting WPS pairing.");
			return;
		}

		const ok = confirm(
			"This will start WPS pairing.\n\n" +
			"Make sure both the Controller and Agent are powered on.\n" +
			"Continue?"
		);
		if (!ok) return;

		showLoading("Starting WPS pairing... Please wait 2 minutes");

		fetch('/cgi-bin/wps.sh', {
			method: 'POST',
			headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
			body: `role=${selectedRole}`
		})
			.then(response => {
				if (!response.ok) throw new Error("WPS script failed");
				return response.text();
			})
			.then(output => {
				hideLoading();
				alert("WPS pairing started.\n\nPress the WPS button on the other device to complete the pairing process.");
			})
			.catch(err => {
				hideLoading();
				alert("Failed to start WPS. Please try again.");
			});
	});

	console.log("EZMesh initialized - toggles reflect current role and force reset only on mode change");
	return true;
}