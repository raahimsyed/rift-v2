/* global $scramjetLoadController, BareMux */
"use strict";

const isFile = location.protocol === "file:";
const swAllowedHostnames = ["localhost", "127.0.0.1"];

const els = {
  urlForm: document.getElementById("urlForm"),
  urlInput: document.getElementById("urlInput"),
  frameWrap: document.getElementById("frameWrap"),
  hint: document.getElementById("browserHint"),
  backToRift: document.getElementById("backToRift"),
  back: document.getElementById("navBack"),
  forward: document.getElementById("navForward"),
  reload: document.getElementById("navReload")
};

const riftUrl = isFile ? "../rift/index.html" : "/rift/";

const normalizeInputToUrl = (raw) => {
  const s = String(raw || "").trim();
  if (!s) return null;

  const hasScheme = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(s);
  if (hasScheme) return s;

  // Heuristic: if it looks like a domain (contains a dot, no spaces) treat as URL.
  if (s.includes(".") && !/\s/.test(s)) return `https://${s}`;

  // Otherwise, search.
  return `https://www.google.com/search?q=${encodeURIComponent(s)}`;
};

async function registerSW() {
  if (!navigator.serviceWorker) {
    if (location.protocol !== "https:" && !swAllowedHostnames.includes(location.hostname)) {
      throw new Error("Service workers cannot be registered without https.");
    }
    throw new Error("Your browser doesn't support service workers.");
  }

  // Keep SW scoped to /browser/ so it doesn't mess with the rest of Rift.
  await navigator.serviceWorker.register("./sw.js", { scope: "./" });
}

let scramjet = null;
let connection = null;
let frame = null;

const ensureStack = async () => {
  if (scramjet && connection) return;
  if (typeof $scramjetLoadController !== "function") throw new Error("scramjet not loaded");
  if (!window.BareMux?.BareMuxConnection) throw new Error("baremux not loaded");

  const { ScramjetController } = $scramjetLoadController();

  scramjet = new ScramjetController({
    prefix: "/browser/service/",
    files: {
      wasm: "/scram/scramjet.wasm.wasm",
      all: "/scram/scramjet.all.js",
      sync: "/scram/scramjet.sync.js"
    }
  });

  scramjet.init();

  connection = new BareMux.BareMuxConnection("/baremux/worker.js");
};

const ensureTransport = async () => {
  if (!connection) return;
  const current = await connection.getTransport();
  if (current === "/libcurl/index.mjs") return;

  const stored = localStorage.getItem("rift_wisp_url");
  const wispUrl = stored || ((location.protocol === "https:" ? "wss" : "ws") + "://" + location.host + "/wisp/");
  await connection.setTransport("/libcurl/index.mjs", [{ websocket: wispUrl }]);
};

const ensureFrame = () => {
  if (frame) return frame;
  if (!scramjet) throw new Error("scramjet not ready");
  frame = scramjet.createFrame();
  frame.frame.id = "rift-browser-frame";
  els.frameWrap?.appendChild(frame.frame);
  return frame;
};

const setHintHidden = (hidden) => {
  if (!els.hint) return;
  els.hint.dataset.hidden = hidden ? "true" : "false";
};

const goTo = async (raw) => {
  const url = normalizeInputToUrl(raw);
  if (!url) return;

  try {
    await registerSW();
    await ensureStack();
    await ensureTransport();
    ensureFrame().go(url);
    setHintHidden(true);
  } catch (err) {
    setHintHidden(false);
    console.error(err);
    alert(String(err?.message || err));
  }
};

const navTry = (fn) => {
  try {
    if (!frame?.frame?.contentWindow) return;
    fn(frame.frame.contentWindow);
  } catch {
    // Ignore: cross-origin / not ready.
  }
};

if (els.urlForm) {
  els.urlForm.addEventListener("submit", (e) => {
    e.preventDefault();
    goTo(els.urlInput?.value);
  });
}

if (els.urlInput) {
  els.urlInput.addEventListener("focus", () => els.urlInput.select());
}

if (els.backToRift) {
  els.backToRift.addEventListener("click", () => {
    window.location.href = riftUrl;
  });
}

if (els.back) els.back.addEventListener("click", () => navTry((w) => w.history.back()));
if (els.forward) els.forward.addEventListener("click", () => navTry((w) => w.history.forward()));
if (els.reload) els.reload.addEventListener("click", () => navTry((w) => w.location.reload()));

if (els.urlInput) els.urlInput.focus();

