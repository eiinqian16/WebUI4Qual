/*
function toggleDropdown(id) {
    let dropdown = document.getElementById(id);
    dropdown.classList.toggle("active");
}
*/

document.addEventListener("DOMContentLoaded", function () {
    let dropdownToggles = document.querySelectorAll(".sidebar-dropdown");

    dropdownToggles.forEach((toggle) => {
        toggle.addEventListener("click", function () {
            let dropdownMenu = this.nextElementSibling; // Get the next element (dropdown menu)
            let arrow = this.querySelector(".arrow");

            dropdownMenu.style.display = dropdownMenu.style.display === "block" ? "none" : "block";

            arrow.style.transform = dropdownMenu.style.display === "block" ? "rotate(90deg)" : "rotate(0deg)";
        });
    });
});
