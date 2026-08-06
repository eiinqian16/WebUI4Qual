function getCred() {
    const credCont = document.getElementById("cred-container");
    html = `
    <div class="usr">
    <h1>${t('user.change_password_title')}</h1>
    <hr style="width:100%;text-align:left;margin-left:0">
    <form id="cred">
        <div class="form-row">
            <label for="oriPwd"><strong>${t('user.old_password_label')}&nbsp;</strong></label>
            <input type="password" id="oriPwd" name="oriPwd" required>
        </div>
        <br>

        <div class="form-row">
            <label for="newPwd"><strong>${t('user.new_password_label')}&nbsp;</strong></label>
            <input type="password" id="newPwd" name="newPwd" required>
        </div>
        <br>

        <div class="form-row">
            <label for="confirmPwd"><strong>${t('user.confirm_new_password_label')}&nbsp;</strong></label>
            <input type="password" id="confirmPwd" name="confirmPwd" required>
        </div>
        <br>
        <div class="chkbox">
            <input id="showPwdChk" type="checkbox" onclick="showPwd()">
            <label for="showPwdChk">${t('user.show_password')}</label>
        </div>
        <br>
        <button type="button" onclick="changeCred()">${t('user.save_changes_button')}</button>
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
        alert(t('user.fill_all_fields'));
        return false;
    }

    if (oPwd === nPwd) {
        alert(t('user.same_password_error'));
        return false;
    }

    if (nPwd !== conPwd) {
        alert(t('user.password_mismatch'));
        return false;
    }

    body += "&oriPwd=" + encodeURIComponent(oPwd) +
        "&newPwd=" + encodeURIComponent(nPwd);


    //document.getElementById("body").innerHTML = `${body}`;

    fetch("/cgi-bin/change_pwd.sh", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: body
    })
        .then(response => response.text())
        .then(text => {
            try {
                let data = JSON.parse(text);

                if (data.status === "Success") {
                    alert(t('user.password_changed_success'));
                } else {
                    alert(data.status);
                }
            } catch (error) {
                console.error("JSON Parse Error:", error);
                document.getElementById("output").innerText = t('user.invalid_json', { text: text });
            }
        })
        .catch(error => {
            console.error("Error:", error);
            document.getElementById("output").innerText = t('login.request_failed', { error: error.message });
        })
}

function showPwd() {
    let passwordFields = document.querySelectorAll("#oriPwd, #newPwd, #confirmPwd");

    passwordFields.forEach(field => {
        field.type = field.type === "password" ? "text" : "password";
    });
}
