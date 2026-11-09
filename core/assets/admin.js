/* WordCore admin — Copyright (C) 2026 WordCore contributors. GPLv3 + WordCore Addon and Theme Exception.
   Small progressive enhancements only; every page works without JavaScript. */
(function () {
  "use strict";

  // Password strength meter: <input data-strength="meter-id"> + <div class="strength" id="meter-id">
  // Mirrors users.password_score() on the server, which is what actually decides.
  var COMMON = ["password1234", "password123", "1234567890", "qwertyuiop", "0123456789", "iloveyou123",
                "administrator", "qwerty12345", "letmein123", "welcome123", "changeme123", "admin12345"];
  function score(pw) {
    if (!pw || pw.length < 10) return pw ? 1 : 0;
    var classes = 0;
    if (/[a-z]/.test(pw)) classes++;
    if (/[A-Z]/.test(pw)) classes++;
    if (/[0-9]/.test(pw)) classes++;
    if (/[^A-Za-z0-9]/.test(pw)) classes++;
    var unique = new Set(pw.split("")).size;
    if (unique < 5 || COMMON.indexOf(pw.toLowerCase()) >= 0) return 1;
    var s = 1;
    if (pw.length >= 12) s++;
    if (pw.length >= 16 || classes >= 3) s++;
    if (pw.length >= 20 || (pw.length >= 14 && classes >= 3)) s++;
    return Math.min(s, 4);
  }
  var LABELS = ["", "Too weak", "Okay", "Strong", "Very strong"];
  document.querySelectorAll("input[data-strength]").forEach(function (input) {
    var meter = document.getElementById(input.getAttribute("data-strength"));
    var label = document.getElementById(input.getAttribute("data-strength") + "-label");
    if (!meter) return;
    function update() {
      var s = score(input.value);
      meter.setAttribute("data-score", String(s));
      if (label) label.textContent = input.value ? LABELS[s] : label.getAttribute("data-default") || "";
    }
    input.addEventListener("input", update);
    update();
  });

  // Copy buttons: <button data-copy="text">
  document.querySelectorAll("button[data-copy]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      if (!navigator.clipboard) return;
      navigator.clipboard.writeText(btn.getAttribute("data-copy")).then(function () {
        var old = btn.textContent;
        btn.textContent = "Copied";
        setTimeout(function () { btn.textContent = old; }, 1500);
      });
    });
  });

  // Ask before dangerous actions: <form data-confirm="Are you sure?">
  document.querySelectorAll("form[data-confirm]").forEach(function (form) {
    form.addEventListener("submit", function (e) {
      if (!window.confirm(form.getAttribute("data-confirm"))) e.preventDefault();
    });
  });

  // Prevent double submits
  document.querySelectorAll("form").forEach(function (form) {
    form.addEventListener("submit", function (e) {
      if (e.defaultPrevented) return;
      setTimeout(function () {
        form.querySelectorAll("button[type=submit]").forEach(function (b) { b.disabled = true; });
      }, 0);
    });
  });
})();
