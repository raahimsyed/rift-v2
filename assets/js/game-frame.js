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
const normalizeSourceUrl = (url) => {
  const value = String(url || "").trim();
  const match = value.match(/^https:\/\/cdn\.jsdelivr\.net\/gh\/([^/]+)\/([^@]+)@([^/]+)\/(.+)$/i);
  if (!match) return value;
  const [, owner, repo, ref, path] = match;
  return `https://rawcdn.githack.com/${owner}/${repo}/${ref}/${path}`;
};

const sourceUrl = normalizeSourceUrl(document.body.dataset.sourceUrl || "");
const libraryUrl = location.protocol === "file:" ? "./index.html" : `/games/${librarySlug}/`;

if (titleEl) titleEl.textContent = name.toLowerCase();
if (subEl) subEl.textContent = slug ? `${libraryName} / ${slug}` : libraryName;

const setFrameSource = async () => {
  if (!frameEl || !sourceUrl) return;

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
