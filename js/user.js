function getCred() {
    const credCont = document.getElementById("cred");
    html = `
    <div class="usr">
    <h1>Change Password</h1>
    <hr style="width:100%;text-align:left;margin-left:0">
    <form id="cred">
        <label for="oriPwd"><strong>Old Password:</strong></label>
        <input type="password" id="oriPwd" name="oriPwd" required style="margin-left:73px;"><br>

        <label for="newPwd"><strong>New Password:</strong></label>
        <input type="password" id="newPwd" name="newPwd" required style="margin-left:65px;"><br>

        <label for="confirmPwd"><strong>Confirm New Password:</strong></label>
        <input type="password" id="confirmPwd" name="confirmPwd" required><br>
        <div class="chkbox">
            <input id="showPwdChk" type="checkbox" onclick="showPwd()">
            <label for="showPwdChk">Show Password</label>
        </div>
        <br>
        <button type="button" onclick="changeCred()">Save Changes</button>
    </form>
    </div>
    `;
    credCont.innerHTML = html;
}

function changeCred() {
    let name = sessionStorage.getItem("loggedInUname");
    let oPwd = document.getElementById("oriPwd").value;
    let nPwd = document.getElementById("newPwd").value;
    let conPwd = document.getElementById("confirmPwd").value;

    body = "uname=" + encodeURIComponent(name);
    
    //document.getElementById("output").innerHTML = `oldPassword:${oPwd} newPassword:${nPwd} confirmPassword:${conPwd}`;

    if (!oPwd || !nPwd || !conPwd) {
        alert("Please fill in all fields.");
        return false;
    }

    if (oPwd === nPwd) {
        alert("Old and new passwords are the same, please re-enter ...");
        return false;
    }

    if (nPwd !== conPwd) {
        alert("New password and confirm password do not match.");
        return false;
    }

    body += "&oriPwd=" + encodeURIComponent(oPwd) +
            "&newPwd=" + encodeURIComponent(nPwd);
    
    
    //document.getElementById("body").innerHTML = `${body}`;
    
    fetch("/cgi-bin/changePwd.sh", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: body
    })
    .then(response => response.text())
    .then(text => {
        try {
            let data = JSON.parse(text);

            if (data.status === "Success") {
                alert("Password changed successfully");
            } else {
                alert(data.status);
            }
        } catch (error) {
            console.error("JSON Parse Error:", error);
            document.getElementById("output").innerText = `Invalid JSON: ${text}`;
        }
    })
        .catch(error => {
            console.error("Error:", error);
            document.getElementById("output").innerText = `Request failed: ${error.message}`;
        }) 
}

function showPwd() {
    let passwordFields = document.querySelectorAll("#oriPwd, #newPwd, #confirmPwd");

    passwordFields.forEach(field => {
        field.type = field.type === "password" ? "text" : "password";
    });
}
