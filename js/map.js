function getCurWanIf() {
    fetch('/cgi-bin/extract_wired_data.sh')
        .then(response => {
            if(!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data =>{
            console.log("Successfully fetched current WAN data:", data);

            let html = "";
            html += `<h1>Internet Status</h1>
                    <p class="description">View and configure Internet settings</p>
                    <hr>`;
            const wanContent = document.getElementById("wanContent");
            //const curNetmask = document.getElementById("curNetmask");
            //const curDev = document.getElementById("curDev");
            const wan = data.find(item => item.type === "WAN");
            if (wan && wan.iface) {
                html += `<p><strong>Device: </strong>${wan.iface || 'N/A'}</p>`
            }
            if (wan && wan.proto) {
                html += `<p><strong>Connection Type: </strong>${wan.proto || 'N/A'}</p>`
            }
            if (wan && wan.IP) {
                html += `<p><strong>IP Address: </strong>${wan.IP || 'N/A'}</p>`
            }
            if (wan && wan.netmask) {
                html += `<p><strong>Subnet Mask: </strong>${wan.netmask || 'N/A'}</p>`
            } 
            if (wan && wan.gateway) {
                html += `<p><strong>Gateway: </strong>${wan.gateway || 'N/A'}</p>`
            }
            if (wan && wan.bcast) {
                html += `<p><strong>Broadcast: </strong>${wan.bcast || 'N/A'}</p>`
            }

            wanContent.innerHTML = html;
       }); 
}

function getClients() {
    fetch('/cgi-bin/get_associated_stations.sh')
        .then(response => {
            if(!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data =>{
            console.log("Successfully fetched current WAN data:", data);
            
}