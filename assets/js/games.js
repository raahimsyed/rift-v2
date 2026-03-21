const isFile = location.protocol === "file:";
const riftUrl = isFile ? "../rift/index.html" : "/rift/";

const els = {
  back: document.getElementById("backToRift"),
  search: document.getElementById("gamesSearch"),
  sourceList: document.getElementById("sourceList"),
  gamesGrid: document.getElementById("gamesGrid"),
  gamesEmpty: document.getElementById("gamesEmpty")
};

const escapeHtml = (s) =>
  String(s)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;")
    .replaceAll("'", "&#39;");

const fetchJson = async (url) => {
  const res = await fetch(url, { credentials: "same-origin", cache: "no-cache" });
  if (!res.ok) throw new Error(`Failed to fetch ${url} (${res.status})`);
  return res.json();
};

const normalize = (s) => String(s || "").trim().toLowerCase();

const renderSources = (sources, q) => {
  if (!els.sourceList) return;
  const query = normalize(q);

  const filtered = (sources || []).filter((src) => {
    if (!query) return true;
    return (
      normalize(src.name).includes(query) ||
      normalize(src.url).includes(query) ||
      normalize(src.note).includes(query)
    );
  });

  if (!filtered.length) {
    els.sourceList.innerHTML = `<div class="empty">no sources match.</div>`;
    return;
  }

  els.sourceList.innerHTML = filtered.map((src) => {
    const name = escapeHtml(src.name || "source");
    const url = escapeHtml(src.url || "#");
    const note = escapeHtml(src.note || "");
    const tag = escapeHtml(src.tag || "library");

    return `
      <article class="source-card">
        <div class="source-head">
          <div class="source-name">${name}</div>
          <div class="source-meta">${tag}</div>
        </div>
        ${note ? `<div class="source-meta">${note}</div>` : ""}
        <div class="source-actions">
          <button class="pill" type="button" data-open="${url}">
            <i class="fa-solid fa-up-right-from-square" aria-hidden="true"></i>
            open
          </button>
          <button class="pill" type="button" data-copy="${url}">
            <i class="fa-solid fa-copy" aria-hidden="true"></i>
            copy
          </button>
        </div>
      </article>
    `;
  }).join("");
};

const main = async () => {
  if (els.back) {
    els.back.addEventListener("click", () => {
      window.location.href = riftUrl;
    });
  }

  let sources = [];
  try {
    sources = await fetchJson("./sources.json");
  } catch (err) {
    if (els.sourceList) {
      els.sourceList.innerHTML = `<div class="empty">failed to load sources.json.</div>`;
    }
  }

  renderSources(sources, "");

  if (els.search) {
    els.search.addEventListener("input", () => {
      renderSources(sources, els.search.value);
    });
  }

  document.addEventListener("click", async (e) => {
    const open = e.target.closest?.("[data-open]");
    if (open) {
      const url = open.getAttribute("data-open");
      if (url) window.open(url, "_blank", "noopener,noreferrer");
      return;
    }

    const copy = e.target.closest?.("[data-copy]");
    if (copy) {
      const url = copy.getAttribute("data-copy") || "";
      try {
        await navigator.clipboard.writeText(url);
      } catch {
        // No-op if clipboard is blocked; user can still open.
      }
    }
  });

  // Games list will be wired once you send the library manifests.
  if (els.gamesGrid && els.gamesEmpty) {
    els.gamesGrid.hidden = true;
    els.gamesEmpty.hidden = false;
  }
};

main();

