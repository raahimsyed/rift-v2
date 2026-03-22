const backButton = document.getElementById("backToLibrary");
const fpsCounter = document.getElementById("fpsCounter");
const titleEl = document.getElementById("gameTitle");
const subEl = document.getElementById("gameSub");
const frameEl = document.getElementById("gameFrame");

const slug = document.body.dataset.gameSlug || "";
const name = document.body.dataset.gameName || slug;
const normalizeSourceUrl = (url) => {
  const value = String(url || "").trim();
  const match = value.match(/^https:\/\/cdn\.jsdelivr\.net\/gh\/([^/]+)\/([^@]+)@([^/]+)\/(.+)$/i);
  if (!match) return value;
  const [, owner, repo, ref, path] = match;
  return `https://rawcdn.githack.com/${owner}/${repo}/${ref}/${path}`;
};

const sourceUrl = normalizeSourceUrl(document.body.dataset.sourceUrl || "");
const libraryUrl = location.protocol === "file:" ? "./index.html" : "/games/selenite/";

if (titleEl) titleEl.textContent = name.toLowerCase();
if (subEl) subEl.textContent = slug ? `selenite / ${slug}` : "selenite";
if (frameEl && sourceUrl) frameEl.src = sourceUrl;

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

if (backButton) {
  backButton.addEventListener("click", () => {
    window.location.href = libraryUrl;
  });
}
