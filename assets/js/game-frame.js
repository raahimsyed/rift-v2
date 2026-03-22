const backButton = document.getElementById("backToLibrary");
const openButton = document.getElementById("openHostedGame");
const titleEl = document.getElementById("gameTitle");
const subEl = document.getElementById("gameSub");
const frameEl = document.getElementById("gameFrame");

const slug = document.body.dataset.gameSlug || "";
const name = document.body.dataset.gameName || slug;
const sourceUrl = document.body.dataset.sourceUrl || "";
const libraryUrl = location.protocol === "file:" ? "./index.html" : "/games/selenite/";

if (titleEl) titleEl.textContent = name.toLowerCase();
if (subEl) subEl.textContent = slug ? `selenite / ${slug}` : "selenite";
if (frameEl && sourceUrl) frameEl.src = sourceUrl;

if (backButton) {
  backButton.addEventListener("click", () => {
    window.location.href = libraryUrl;
  });
}

if (openButton) {
  openButton.addEventListener("click", () => {
    if (sourceUrl) window.open(sourceUrl, "_blank", "noopener,noreferrer");
  });
}
