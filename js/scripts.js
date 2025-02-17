let deviceConfig = {};

function loadSection(section) {
    fetch(section + '.html')
        .then(response => response.text())
        .then(html => {
            document.querySelector('#main-content').innerHTML = html;
            if (section === 'wireless') {
                let script = document.createElement('script');
                script.src = 'js/wireless.js';
                script.onload = () => {
                    console.log('Wireless script loaded');
                    getConfig(); 
                };
                document.body.appendChild(script);
            }
        })
        .catch(err => console.error('Error loading section:', err));
}

function showSection(section) {
    loadSection(section);
}

document.addEventListener('DOMContentLoaded', () => {
    loadSection('wireless');
});

