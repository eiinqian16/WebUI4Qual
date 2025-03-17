function getLoginCred() {
    const loginCont = document.getElementById("login");
    let html = `
    <form id="login">
        <div class="container">
            <a href="https://compex.com.sg/" target="_blank">
                <img src="/logo/logo.png" alt="Logo">
            </a>

            <br>
            <label class="auth-title">Authorization Required</label>
            <br>
            <label class="auth-desc">Please enter your username and password.</label>
            <br>
            <input type="text" placeholder="Enter Username" id="uname" name="uname" required>

            <input type="password" placeholder="Enter Password" id="pwd" name="pwd">

            <!--
            <div class="chkbox">
                <input id="showPwdChk" type="checkbox" onclick="showPwd()">
                <label for="showPwdChk">Show Password</label>
            </div>
            -->
            <p><p>
            <button type="button" onclick="validateCred()">Login</button>
        </div>
    </form>
    `;
    loginCont.innerHTML = html;
}

function validateCred() {
    let name = document.getElementById("uname").value.trim();
    let pwd = document.getElementById("pwd").value.trim();
    let loginBtn = document.querySelector("button");

    if (!name) {
        alert("Username is required!");
        return;
    }

    // 禁用按钮，显示加载图标
    loginBtn.innerHTML = `<span class="loader"></span> Logging in...`;
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
                document.getElementById("output").innerText = data.status;
            }
            
            loginBtn.innerHTML = "Login";
            loginBtn.disabled = false;
        }, 2000);
    })
    .catch(error => {
        console.error("Error:", error);
        document.getElementById("output").innerText = `Request failed: ${error.message}`;
        
        setTimeout(() => {
            loginBtn.innerHTML = "Login";
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
