function changeLanguage(lang) {
    let select = document.getElementById('langSelect');
    if (select) select.disabled = true;

    i18n.setLanguage(lang).then(() => {
        getLoginCred();
    }).finally(() => {
        // getLoginCred() rebuilds the form, so no need to re-enable the old select
    });
}

function getLoginCred() {
    const loginCont = document.getElementById("login");
    let html = `
    <form id="loginForm">
        <div class="container">
            <div class="login-header-row">
                <a href="https://www.airioncomm.com/" target="_blank">
                    <img src="/logo/logo.png" alt="Logo">
                </a>
                <div class="lang-switcher-login">
                    <select id="langSelect" aria-label="Language / Bahasa / 语言" onchange="changeLanguage(this.value)">
                        <option value="en">English</option>
                        <option value="ms">Bahasa Melayu</option>
                        <option value="zh">中文</option>
                    </select>
                </div>
            </div>

            <br>
            <label class="auth-title" data-i18n="login.title">Authorization Required</label>
            <br>
            <label class="auth-desc" data-i18n="login.description">Please enter your username and password.</label>
            <br>
            <input type="text" placeholder="Enter Username" id="uname" name="uname" required data-i18n-placeholder="login.username_placeholder">

            <input type="password" placeholder="Enter Password" id="pwd" name="pwd" data-i18n-placeholder="login.password_placeholder">

            <!--
            <div class="chkbox">
                <input id="showPwdChk" type="checkbox" onclick="showPwd()">
                <label for="showPwdChk">Show Password</label>
            </div>
            -->
            <p><p>
            <button type="button" onclick="validateCred()" data-i18n="login.login_button">Login</button>
        </div>
    </form>
    `;
    loginCont.innerHTML = html;

    let select = document.getElementById("langSelect");
    if (select) select.value = i18n.currentLang;

    i18n.applyTranslations(loginCont);

    document.getElementById("loginForm").addEventListener("keypress", function (event) {
        if (event.key === "Enter") {
            event.preventDefault();
            validateCred();
        }
    });
}

function validateCred() {
    let name = document.getElementById("uname").value.trim();
    let pwd = document.getElementById("pwd").value.trim();
    let loginBtn = document.querySelector("button");

    if (!name) {
        alert(t("login.username_required"));
        return;
    }

    loginBtn.innerHTML = `<span class="loader"></span> ${t("login.logging_in")}`;
    loginBtn.disabled = true;

    fetch("/cgi-bin/validate_login.sh", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: `name=${encodeURIComponent(name)}&pwd=${encodeURIComponent(pwd)}`
    })
        .then(response => response.json())
        .then(data => {
            console.log("Login Response:", data);

            setTimeout(() => {
                if (data.status === "Success") {
                    sessionStorage.setItem("sessionID", data.session_id);
                    console.log("Stored sessionID:", sessionStorage.getItem("sessionID"));
                    window.location.href = "index.html#overview";
                } else {
                    alert(data.status);
                    //document.getElementById("output").innerText = data.status;
                }

                loginBtn.innerHTML = t("login.login_button");
                loginBtn.disabled = false;
            }, 2000);
        })
        .catch(error => {
            console.error("Error:", error);
            document.getElementById("output").innerText = t("login.request_failed", { error: error.message });

            setTimeout(() => {
                loginBtn.innerHTML = t("login.login_button");
                loginBtn.disabled = false;
            }, 2000);
        });
}

function showPwd() {
    let passwordFields = document.querySelectorAll("#pwd");

    passwordFields.forEach(field => {
        field.type = field.type === "password" ? "text" : "password";
    });
}
