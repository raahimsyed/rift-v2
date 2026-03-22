const isFile = location.protocol === "file:";
const gamesUrl = isFile ? "../index.html" : "/games/";

const root = document.body;
const libraryName = root.dataset.libraryName || "library";
const libraryMeta = root.dataset.libraryMeta || libraryName;

const els = {
  back: document.getElementById("backToGames"),
  search: document.getElementById("librarySearch"),
  grid: document.getElementById("libraryGrid"),
  empty: document.getElementById("libraryEmpty"),
  count: document.getElementById("libraryCount")
};

const escapeHtml = (s) =>
  String(s)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;")
    .replaceAll("'", "&#39;");

const normalize = (s) => String(s || "").trim().toLowerCase();

const fetchJson = async (url) => {
  const res = await fetch(url, { credentials: "same-origin", cache: "no-cache" });
  if (!res.ok) throw new Error(`Failed to fetch ${url} (${res.status})`);
  return res.json();
};

const render = (games, query) => {
  const q = normalize(query);
  const filtered = (games || []).filter((game) => {
    if (!q) return true;
    return normalize(game.name).includes(q) || normalize(game.slug).includes(q);
  });

  if (els.count) {
    els.count.textContent = `${filtered.length} games`;
  }

  if (!filtered.length) {
    els.grid.hidden = true;
    els.empty.hidden = false;
    els.empty.textContent = "no matches.";
    return;
  }

  els.empty.hidden = true;
  els.grid.hidden = false;
  els.grid.innerHTML = filtered.map((game) => {
    const name = escapeHtml(game.name);
    const slug = escapeHtml(game.slug);
    const thumb = escapeHtml(game.thumbnailUrl || "");
    const fallbackClass = thumb ? "" : " is-fallback";
    const thumbMarkup = thumb
      ? `<img class="game-thumb" src="${thumb}" alt="" loading="lazy" referrerpolicy="no-referrer">`
      : "";
    return `
      <button class="game-card" type="button" data-open-local="./${slug}.html">
        <span class="game-thumb-wrap${fallbackClass}">
          ${thumbMarkup}
          <span class="game-ico" aria-hidden="true"><i class="fa-solid fa-gamepad"></i></span>
        </span>
        <span class="game-copy">
          <span class="game-name">${name}</span>
          <span class="game-meta">${escapeHtml(libraryMeta)}</span>
        </span>
      </button>
    `;
  }).join("");
};

const main = async () => {
  if (els.back) {
    els.back.addEventListener("click", () => {
      window.location.href = gamesUrl;
    });
  }

  let games = [];
  try {
    games = await fetchJson("./games.json");
  } catch {
    if (els.empty) {
      els.empty.textContent = `failed to load ${libraryName}/games.json.`;
    }
    return;
  }

  render(games, "");

  if (els.search) {
    els.search.addEventListener("input", () => {
      render(games, els.search.value);
    });
    els.search.focus();
  }

  document.addEventListener("click", (e) => {
    const button = e.target.closest?.("[data-open-local]");
    if (!button) return;
    const href = button.getAttribute("data-open-local");
    if (href) window.location.href = href;
  });

  document.addEventListener("error", (e) => {
    const img = e.target;
    if (!(img instanceof HTMLImageElement) || !img.classList.contains("game-thumb")) return;
    img.closest(".game-thumb-wrap")?.classList.add("is-fallback");
  }, true);
};

main();
