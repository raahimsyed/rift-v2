const title = document.getElementById("riftTitle");
if (title) {
  const text = title.textContent || "";
  title.textContent = "";
  for (const ch of text) {
    const span = document.createElement("span");
    span.className = ch === " " ? "letter space" : "letter";
    span.textContent = ch;
    title.appendChild(span);
  }
}

const COUNTS = {
  games: "0 games",
  browser: "0 sites",
  music: "0 playlists",
  cloud_gaming: "0 providers",
  library: "0 saved"
};

document.querySelectorAll("[data-count]").forEach((el) => {
  const key = el.getAttribute("data-count");
  if (!key) return;
  if (COUNTS[key] != null) el.textContent = COUNTS[key];
});

