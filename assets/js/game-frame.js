const backButton = document.getElementById("backToLibrary");
const fpsCounter = document.getElementById("fpsCounter");
const titleEl = document.getElementById("gameTitle");
const subEl = document.getElementById("gameSub");
const frameEl = document.getElementById("gameFrame");

const librarySlug = document.body.dataset.librarySlug || "selenite";
const libraryName = document.body.dataset.libraryName || librarySlug;
const slug = document.body.dataset.gameSlug || "";
const name = document.body.dataset.gameName || slug;
const loadMode = document.body.dataset.loadMode || "url";
const sourceBaseUrl = document.body.dataset.sourceBaseUrl || "";
const sourceExtra = (() => {
  const raw = document.body.dataset.sourceExtra;
  if (!raw) return null;

  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
})();
const normalizeSourceUrl = (url) => {
  const value = String(url || "").trim();
  const match = value.match(/^https:\/\/cdn\.jsdelivr\.net\/gh\/([^/]+)\/([^@]+)@([^/]+)\/(.+)$/i);
  if (!match) return value;
  const [, owner, repo, ref, path] = match;
  return `https://rawcdn.githack.com/${owner}/${repo}/${ref}/${path}`;
};
const escapeAttr = (value) =>
  String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/"/g, "&quot;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
const escapeHtml = (value) =>
  String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");

const sourceUrl = normalizeSourceUrl(document.body.dataset.sourceUrl || "");
const libraryUrl = location.protocol === "file:" ? "./index.html" : `/games/${librarySlug}/`;

if (titleEl) titleEl.textContent = name.toLowerCase();
if (subEl) subEl.textContent = slug ? `${libraryName} / ${slug}` : libraryName;

const buildDoc = (body, extraHead = "") => `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <base href="${escapeAttr(sourceBaseUrl)}">
  <style>
    html, body {
      width: 100%;
      height: 100%;
      margin: 0;
      overflow: hidden;
      background: #000;
      color: #fff;
    }

    body {
      font-family: Arial, sans-serif;
    }

    * {
      box-sizing: border-box;
    }
  </style>
  ${extraHead}
</head>
<body>
${body}
</body>
</html>`;

const getRuffleDoc = () =>
  buildDoc(
    `<div id="ruffle-stage" style="width:100%;height:100%;"></div>
<script src="https://unpkg.com/@ruffle-rs/ruffle"></script>
<script>
  const container = document.getElementById("ruffle-stage");
  const player = window.RufflePlayer.newest().createPlayer();
  player.style.width = "100%";
  player.style.height = "100%";
  container.appendChild(player);
  player.load("${escapeAttr(sourceUrl)}");
</script>`
  );

const getScriptDoc = () =>
  buildDoc(
    `<div id="app-shell" style="width:100%;height:100%;"></div>
<script src="${escapeAttr(sourceUrl)}"></script>`
  );

const getUnityDoc = () => {
  const config = sourceExtra || {};
  const encodedConfig = escapeHtml(JSON.stringify(config));

  return buildDoc(
    `<div id="unity-shell" style="position:relative;width:100%;height:100%;background:#000;">
  <canvas id="unity-canvas" style="width:100%;height:100%;display:block;background:#000;"></canvas>
  <div id="unity-loading" style="position:absolute;inset:0;display:grid;place-items:center;background:radial-gradient(circle at center, rgba(48,48,48,0.22), rgba(0,0,0,0.96));font-size:14px;letter-spacing:0.08em;text-transform:lowercase;">loading...</div>
</div>
<script src="${escapeAttr(sourceUrl)}"></script>
<script type="application/json" id="unity-config">${encodedConfig}</script>
<script>
  const config = JSON.parse(document.getElementById("unity-config").textContent || "{}");
  const canvas = document.getElementById("unity-canvas");
  const loading = document.getElementById("unity-loading");
  createUnityInstance(canvas, config, (progress) => {
    loading.textContent = "loading " + Math.round(progress * 100) + "%";
  }).then(() => {
    loading.remove();
  }).catch((error) => {
    loading.textContent = "failed to load unity build";
    console.error(error);
  });
</script>`
  );
};

const getFaceDoc = () =>
  buildDoc(
    `<div id="placeholder"></div>
<template id="loading-template">
  <div id="loading-bar" style="position:fixed;inset:0;display:grid;place-items:center;background:#000;color:#fff;">
    <div style="width:min(420px,78vw);">
      <div style="margin-bottom:14px;font-size:12px;letter-spacing:0.18em;text-transform:uppercase;opacity:0.72;">loading</div>
      <div style="width:100%;height:10px;border:1px solid rgba(255,255,255,0.18);border-radius:999px;overflow:hidden;background:rgba(255,255,255,0.06);">
        <div id="loading-fill" style="width:0%;height:100%;background:linear-gradient(90deg,#ffffff,#8d8d8d);"></div>
      </div>
    </div>
  </div>
</template>
<template id="no-support-template">
  <div style="position:fixed;inset:0;display:grid;place-items:center;padding:24px;text-align:center;background:#000;color:#fff;">
    <div>
      <div style="font-size:16px;letter-spacing:0.08em;text-transform:lowercase;">this game needs webgl and web audio</div>
    </div>
  </div>
</template>
<template id="main-template">
  <div id="quality-container" style="position:fixed;top:18px;left:18px;z-index:20;display:flex;gap:8px;">
    <button id="quality-medium" type="button" style="border:1px solid rgba(255,255,255,0.2);background:rgba(0,0,0,0.55);color:#fff;padding:10px 14px;border-radius:999px;cursor:pointer;text-transform:lowercase;">medium</button>
    <button id="quality-high" type="button" style="border:1px solid rgba(255,255,255,0.2);background:rgba(0,0,0,0.55);color:#fff;padding:10px 14px;border-radius:999px;cursor:pointer;text-transform:lowercase;">high</button>
  </div>
</template>
<link rel="stylesheet" href="${escapeAttr(sourceBaseUrl)}face.css">
<script src="${escapeAttr(sourceUrl)}"></script>`
  );

const setFrameSource = async () => {
  if (!frameEl || !sourceUrl) return;

  if (loadMode === "ruffle") {
    frameEl.srcdoc = getRuffleDoc();
    return;
  }

  if (loadMode === "script") {
    frameEl.srcdoc = getScriptDoc();
    return;
  }

  if (loadMode === "unity") {
    frameEl.srcdoc = getUnityDoc();
    return;
  }

  if (loadMode === "face") {
    frameEl.srcdoc = getFaceDoc();
    return;
  }

  if (loadMode === "srcdoc") {
    try {
      const res = await fetch(sourceUrl, { cache: "no-cache", mode: "cors" });
      if (!res.ok) throw new Error(`Failed to fetch source (${res.status})`);
      let html = await res.text();
      const baseTag = sourceBaseUrl ? `<base href="${sourceBaseUrl}">` : "";
      if (/<head[^>]*>/i.test(html)) {
        html = html.replace(/<head([^>]*)>/i, `<head$1>${baseTag}`);
      } else {
        html = `${baseTag}${html}`;
      }
      frameEl.srcdoc = html;
      return;
    } catch {
      frameEl.src = sourceUrl;
      return;
    }
  }

  frameEl.src = sourceUrl;
};

let frames = 0;
let sampleStart = performance.now();

const updateFps = (fps) => {
  if (!fpsCounter) return;
  fpsCounter.textContent = `${fps} fps`;
};

const tick = (now) => {
  frames += 1;
  if (now - sampleStart >= 3000) {
    const fps = Math.max(1, Math.round((frames * 1000) / (now - sampleStart)));
    updateFps(fps);
    frames = 0;
    sampleStart = now;
  }
  requestAnimationFrame(tick);
};

updateFps("--");
requestAnimationFrame(tick);
void setFrameSource();

if (backButton) {
  backButton.addEventListener("click", () => {
    window.location.href = libraryUrl;
  });
}
