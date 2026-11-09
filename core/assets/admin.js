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


  // ------------------------------------------------------------ small helpers
  function store(key, value) {
    try { if (value === undefined) return window.localStorage.getItem("wc." + key); window.localStorage.setItem("wc." + key, value); } catch (e) { return null; }
    return null;
  }
  function csrfOf(el) {
    var form = el.closest("form");
    var input = form && form.querySelector("input[name=_csrf]");
    return input ? input.value : (document.querySelector("input[name=_csrf]") || {}).value || "";
  }

  // Theme previews: <span data-accent="#hex"> (CSP allows CSSOM, not style attributes)
  document.querySelectorAll("[data-accent]").forEach(function (el) {
    var c = el.getAttribute("data-accent");
    if (/^#[0-9a-fA-F]{6}$/.test(c)) el.style.background = c;
  });

  // Upload drop zone
  document.querySelectorAll("form[data-upload]").forEach(function (form) {
    var zone = form.querySelector(".dropzone"), input = form.querySelector("input[type=file]");
    if (!zone || !input) return;
    var title = zone.querySelector("strong"), original = title ? title.textContent : "";
    input.addEventListener("change", function () {
      if (!title) return;
      var n = input.files.length;
      title.textContent = n === 0 ? original : n === 1 ? input.files[0].name : n + " files chosen";
    });
    ["dragenter", "dragover"].forEach(function (ev) { zone.addEventListener(ev, function (e) { e.preventDefault(); zone.classList.add("is-over"); }); });
    ["dragleave", "drop"].forEach(function (ev) { zone.addEventListener(ev, function () { zone.classList.remove("is-over"); }); });
    zone.addEventListener("drop", function (e) {
      e.preventDefault();
      if (e.dataTransfer && e.dataTransfer.files.length) { input.files = e.dataTransfer.files; form.requestSubmit ? form.requestSubmit() : form.submit(); }
    });
  });

  // datetime-local <-> unix time: <input type=datetime-local data-epoch-target="hidden-id" data-epoch="123">
  document.querySelectorAll("input[data-epoch-target]").forEach(function (input) {
    var hidden = document.getElementById(input.getAttribute("data-epoch-target"));
    var epoch = parseInt(input.getAttribute("data-epoch") || "", 10);
    function pad(n) { return (n < 10 ? "0" : "") + n; }
    if (epoch) {
      var d = new Date(epoch * 1000);
      input.value = d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) + "T" + pad(d.getHours()) + ":" + pad(d.getMinutes());
    }
    input.addEventListener("change", function () {
      var t = input.value ? Math.floor(new Date(input.value).getTime() / 1000) : "";
      if (hidden) hidden.value = isNaN(t) ? "" : String(t);
    });
  });

  // Address from title: <input data-slug-source> fills <input data-slug data-slug-auto> until the address is edited by hand
  function slugify(s) {
    return (s || "").normalize("NFKD").replace(/[̀-ͯ]/g, "").toLowerCase()
      .replace(/['’]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 80).replace(/-+$/, "");
  }
  var slugSource = document.querySelector("[data-slug-source]"), slugInput = document.querySelector("input[data-slug]");
  if (slugSource && slugInput) {
    var auto = slugInput.hasAttribute("data-slug-auto") && slugInput.value === "";
    slugSource.addEventListener("input", function () { if (auto) slugInput.value = slugify(slugSource.value); });
    slugInput.addEventListener("input", function () { auto = slugInput.value === ""; });
    slugInput.addEventListener("change", function () { slugInput.value = slugify(slugInput.value); });
  }

  // Warn before leaving a form with unsaved changes: <form data-warn-unsaved>
  var dirtyForm = null;
  document.querySelectorAll("form[data-warn-unsaved]").forEach(function (form) {
    var mark = function () {
      if (dirtyForm === form) return;
      dirtyForm = form;
      form.querySelectorAll("[data-dirty]").forEach(function (el) { el.hidden = false; });
    };
    form.addEventListener("input", mark);
    form.addEventListener("change", mark);
    form.addEventListener("submit", function () { dirtyForm = null; });
  });
  window.addEventListener("beforeunload", function (e) {
    if (dirtyForm) { e.preventDefault(); e.returnValue = ""; }
  });

  // ------------------------------------------------------------ Markdown editor
  document.querySelectorAll(".md-editor").forEach(function (ed) {
    var ta = ed.querySelector(".md-input"), preview = ed.querySelector(".md-preview"), panes = ed.querySelector(".md-panes");
    var words = ed.querySelector("[data-words]");
    var dialog = ed.parentNode.querySelector(".md-media");
    if (!ta) return;

    function replaceSel(before, after, placeholder) {
      var s = ta.selectionStart, e = ta.selectionEnd, v = ta.value;
      var sel = v.slice(s, e) || placeholder || "";
      ta.focus();
      ta.setRangeText(before + sel + after, s, e, "end");
      if (!v.slice(s, e) && placeholder) { ta.setSelectionRange(s + before.length, s + before.length + sel.length); }
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }
    function prefixLines(fn) {
      var v = ta.value, s = v.lastIndexOf("\n", ta.selectionStart - 1) + 1, e = ta.selectionEnd;
      var end = v.indexOf("\n", e); if (end < 0) end = v.length;
      var lines = v.slice(s, end).split("\n").map(fn);
      ta.focus();
      ta.setRangeText(lines.join("\n"), s, end, "select");
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }
    function insertBlock(text) {
      var s = ta.selectionStart, v = ta.value;
      var pre = s > 0 && v[s - 1] !== "\n" ? "\n\n" : (s > 1 && v[s - 2] !== "\n" ? "\n" : "");
      ta.focus();
      ta.setRangeText(pre + text + "\n", s, ta.selectionEnd, "end");
      ta.dispatchEvent(new Event("input", { bubbles: true }));
    }
    var actions = {
      h2: function () { prefixLines(function (l) { return l.replace(/^#{1,6}\s*/, "") === l ? "## " + l : l.replace(/^#{1,6}\s*/, ""); }); },
      bold: function () { replaceSel("**", "**", "bold text"); },
      italic: function () { replaceSel("_", "_", "italic text"); },
      link: function () { replaceSel("[", "](https://)", "link text"); },
      ul: function () { prefixLines(function (l) { return /^- /.test(l) ? l.slice(2) : "- " + l; }); },
      ol: function () { var n = 0; prefixLines(function (l) { n++; return /^\d+\. /.test(l) ? l.replace(/^\d+\. /, "") : n + ". " + l; }); },
      quote: function () { prefixLines(function (l) { return /^> ?/.test(l) ? l.replace(/^> ?/, "") : "> " + l; }); },
      code: function () {
        if (ta.value.slice(ta.selectionStart, ta.selectionEnd).indexOf("\n") >= 0) replaceSel("```\n", "\n```", "");
        else replaceSel("`", "`", "code");
      },
      image: function () { openMedia(); },
    };
    ed.querySelectorAll("[data-md]").forEach(function (b) {
      b.addEventListener("click", function () { var f = actions[b.getAttribute("data-md")]; if (f) f(); });
    });
    ed.querySelectorAll("[data-insert]").forEach(function (b) {
      b.addEventListener("click", function () {
        insertBlock(b.getAttribute("data-insert"));
        var d = b.closest("details"); if (d) d.open = false;
      });
    });
    ta.addEventListener("keydown", function (e) {
      if (!(e.ctrlKey || e.metaKey) || e.altKey) return;
      var k = e.key.toLowerCase();
      if (k === "b") { e.preventDefault(); actions.bold(); }
      else if (k === "i") { e.preventDefault(); actions.italic(); }
      else if (k === "k") { e.preventDefault(); actions.link(); }
    });
    document.addEventListener("keydown", function (e) {
      if ((e.ctrlKey || e.metaKey) && !e.altKey && e.key.toLowerCase() === "s") {
        var form = ta.closest("form");
        if (form) { e.preventDefault(); form.requestSubmit ? form.requestSubmit() : form.submit(); }
      }
    });

    // view tabs
    var tabs = ed.querySelectorAll("[data-view]");
    function setView(v) {
      panes.classList.remove("view-write", "view-split", "view-preview");
      panes.classList.add("view-" + v);
      tabs.forEach(function (t) { t.setAttribute("aria-pressed", t.getAttribute("data-view") === v ? "true" : "false"); });
      store("editor.view", v);
      if (v !== "write") refresh();
    }
    tabs.forEach(function (t) { t.addEventListener("click", function () { setView(t.getAttribute("data-view")); }); });
    var saved = store("editor.view");
    if (saved === "write" || saved === "preview" || saved === "split") setView(saved);

    // live preview + word count
    var timer = null, inflight = null, last = ta.value;
    function count() {
      var n = (ta.value.match(/\S+/g) || []).length;
      if (words) words.textContent = n + (n === 1 ? " word" : " words");
    }
    function refresh() {
      if (!preview || panes.classList.contains("view-write")) return;
      if (ta.value === last && preview.getAttribute("data-fresh") === "1") return;
      last = ta.value;
      if (inflight && inflight.abort) inflight.abort();
      inflight = window.AbortController ? new AbortController() : null;
      var body = new URLSearchParams();
      body.set("_csrf", csrfOf(ta));
      body.set("body", ta.value);
      fetch(ed.getAttribute("data-preview"), { method: "POST", body: body, credentials: "same-origin", signal: inflight && inflight.signal })
        .then(function (r) { return r.ok ? r.text() : Promise.reject(r.status); })
        .then(function (h) { preview.innerHTML = h; preview.setAttribute("data-fresh", "1"); })
        .catch(function (err) { if (err && err.name === "AbortError") return; preview.setAttribute("data-fresh", "0"); });
    }
    preview && preview.setAttribute("data-fresh", "1");
    ta.addEventListener("input", function () {
      count();
      clearTimeout(timer);
      timer = setTimeout(refresh, 350);
    });

    // media picker
    function openMedia() {
      if (!dialog || !dialog.showModal) { replaceSel("![", "](/media/)", "description"); return; }
      var grid = dialog.querySelector("[data-grid]");
      dialog.showModal();
      fetch(ed.getAttribute("data-media"), { credentials: "same-origin" })
        .then(function (r) { return r.json(); })
        .then(function (data) {
          grid.textContent = "";
          if (!data.items.length) {
            var p = document.createElement("p"); p.className = "muted";
            p.textContent = "No images yet. Upload some under Media first.";
            grid.appendChild(p); return;
          }
          data.items.forEach(function (it) {
            var b = document.createElement("button"); b.type = "button";
            var img = document.createElement("img"); img.src = it.url; img.alt = ""; img.loading = "lazy";
            var label = document.createElement("span"); label.textContent = it.name;
            b.appendChild(img); b.appendChild(label);
            b.addEventListener("click", function () {
              dialog.close();
              var alt = (it.alt || "").replace(/[\[\]]/g, "");
              insertBlock("![" + alt + "](" + it.path + ")");
            });
            grid.appendChild(b);
          });
        })
        .catch(function () { grid.textContent = "Couldn't load the media library."; });
    }
    if (dialog) {
      dialog.querySelector("[data-close]").addEventListener("click", function () { dialog.close(); });
      dialog.addEventListener("click", function (e) { if (e.target === dialog) dialog.close(); });
    }
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
