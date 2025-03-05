function getLoginCred() {
    const loginCont = document.getElementById("login");
    html = `
    <form id="login">
        <div class="container">
            <label for="uname"><strong>Username:</strong></label>
            <input type="text" placeholder="Enter Username" id="uname" name="uname" required><br>

            <label for="pwd"><strong>Password:</strong></label>
            <input type="password" placeholder="Enter Password" id="pwd" name="pwd" required><br>

            <div class="chkbox">
                <input id="showPwdChk" type="checkbox" onclick="showPwd()">
                <label for="showPwdChk">Show Password</label>
            </div>

            <br>
            <button type="button" onclick="validateCred()">Login</button>
        </div>
    </form>
    `;
    loginCont.innerHTML = html;
}

function validateCred() {
    let name = document.getElementById("uname").value;
    let pwd = document.getElementById("pwd").value;
    
    fetch("/cgi-bin/validate_login.sh", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: "name=" + encodeURIComponent(name) +
              "&pwd=" + encodeURIComponent(pwd)
    })
    .then(response => response.text())
    .then(text => {
        console.log("Raw Response:", text);
        try {
            let data = JSON.parse(text);
            console.log("Parsed JSON:", data);

            if (data.status === "Success") {
                sessionStorage.setItem("loggedInUname", name);
                window.location.href = "/overview.html";
            } else {
                alert(data.status);
            } 
        }catch (error) {
            console.error("JSON Parse Error:", error);
            document.getElementById("output").innerText = `Invalid JSON: ${text}`;
        }
    })
        .catch(error => {
            console.error("Error:", error);
            document.getElementById("output").innerText = `Request failed: ${error.message}`;
        });
}

function showPwd() {
    let passwordFields = document.querySelectorAll("#pwd");

    passwordFields.forEach(field => {
        field.type = field.type === "password" ? "text" : "password";
    });
}
