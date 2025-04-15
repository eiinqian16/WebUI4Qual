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
            submitBtn.textContent = "SET ACK TIMEOUT";
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
                          alert("Done！");
                      })
                      .catch(error => console.error("Error saving ACK timeout:", error));
                };
            } else {
                console.error("Error: #acktimeoutForm not found");
            }
        })
        .catch(error => console.error("Error fetching ACK timeout data:", error));
}

