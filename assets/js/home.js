// Tiny comets (low intensity). Respects reduced motion.
(() => {
  const prefersReduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (prefersReduce) return;

  const canvas = document.getElementById("cometCanvas");
  if (!canvas) return;
  const ctx = canvas.getContext("2d", { alpha: true });
  if (!ctx) return;

  let dpr = Math.max(1, Math.min(2, window.devicePixelRatio || 1));
  const state = {
    w: 0,
    h: 0,
    comets: [],
    nextSpawnAt: 0,
    lastT: performance.now()
  };

  const resize = () => {
    dpr = Math.max(1, Math.min(2, window.devicePixelRatio || 1));
    const w = Math.floor(window.innerWidth * dpr);
    const h = Math.floor(window.innerHeight * dpr);
    canvas.width = w;
    canvas.height = h;
    state.w = w;
    state.h = h;
    // Clear to avoid stretching artifacts after resize.
    ctx.clearRect(0, 0, w, h);
  };

  const rand = (a, b) => a + Math.random() * (b - a);
  const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];

  const scheduleNext = (now) => {
    // "Every now and then": roughly 1.2s to 4.0s, with a bit of randomness.
    state.nextSpawnAt = now + rand(1200, 4000);
  };

  const spawnComet = (now) => {
    if (state.comets.length >= 2) return;
    const w = state.w, h = state.h;

    // Always fly top-left -> bottom-right, starting slightly off-screen.
    // Spawn from either the top edge or left edge so it feels natural.
    const start = pick(["top", "left"]);
    let x, y;
    if (start === "top") {
      x = rand(-0.15 * w, 0.65 * w);
      y = -rand(60, 220);
    } else {
      x = -rand(60, 220);
      y = rand(-0.15 * h, 0.65 * h);
    }

    const angle = (Math.PI / 4) + rand(-0.22, 0.22); // ~45deg with jitter
    const speed = rand(640, 1320) * dpr; // pixels/sec in canvas space
    const vx = Math.cos(angle) * speed;
    const vy = Math.sin(angle) * speed;

    const width = rand(0.8, 2.8) * dpr;
    const headR = rand(1.2, 3.4) * dpr;

    state.comets.push({
      x, y,
      px: x, py: y,
      vx, vy,
      age: 0,
      life: rand(850, 1650), // ms
      width,
      headR
    });

    scheduleNext(now);
  };

  const step = (now) => {
    const dt = Math.min(34, now - state.lastT); // clamp for tab switches
    state.lastT = now;

    // Fade previous frame slightly to create trails without washing the screen gray.
    ctx.globalCompositeOperation = "source-over";
    ctx.fillStyle = "rgba(0, 0, 0, 0.16)";
    ctx.fillRect(0, 0, state.w, state.h);

    if (now >= state.nextSpawnAt) spawnComet(now);

    for (let i = state.comets.length - 1; i >= 0; i--) {
      const c = state.comets[i];
      c.age += dt;
      c.px = c.x;
      c.py = c.y;
      c.x += (c.vx * dt) / 1000;
      c.y += (c.vy * dt) / 1000;

      const t = Math.max(0, 1 - c.age / c.life);
      const alpha = 0.85 * t;

      // Trail segment
      ctx.strokeStyle = `rgba(255, 255, 255, ${0.48 * alpha})`;
      ctx.lineWidth = c.width;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(c.px, c.py);
      ctx.lineTo(c.x, c.y);
      ctx.stroke();

      // Head
      ctx.fillStyle = `rgba(255, 255, 255, ${alpha})`;
      ctx.beginPath();
      ctx.arc(c.x, c.y, c.headR, 0, Math.PI * 2);
      ctx.fill();

      const off =
        c.x < -200 || c.x > state.w + 200 ||
        c.y < -200 || c.y > state.h + 200 ||
        c.age > c.life;

      if (off) state.comets.splice(i, 1);
    }

    requestAnimationFrame(step);
  };

  window.addEventListener("resize", resize, { passive: true });
  resize();
  scheduleNext(performance.now());
  requestAnimationFrame(step);
})();

const splitTitle = (el) => {
  if (!el || el.dataset.splitDone === "1") return;
  const text = el.textContent || "";
  el.textContent = "";
  for (const ch of text) {
    const span = document.createElement("span");
    span.className = ch === " " ? "letter space" : "letter";
    span.textContent = ch;
    el.appendChild(span);
  }
  el.dataset.splitDone = "1";
};

document.querySelectorAll("[data-split]").forEach(splitTitle);

const sessionsRoot = document.getElementById("sessions");
const sessionTemplate = document.getElementById("sessionTemplate");
const blurTimers = new WeakMap();

const getActiveSessionId = () => Number(document.body.dataset.activeSession || "1");
const setActiveSessionId = (id) => { document.body.dataset.activeSession = String(id); };

const getSessionEl = (id) => sessionsRoot?.querySelector(`.session-view[data-session="${id}"]`) || null;
const getActiveSessionEl = () => getSessionEl(getActiveSessionId());

const findSuggestionsForInput = (input) => {
  const wrap = input?.closest(".search-wrap");
  return wrap ? wrap.querySelector(".suggestions") : null;
};

const showSuggestionsForInput = (input) => {
  const sug = findSuggestionsForInput(input);
  if (sug) sug.hidden = false;
};

const hideSuggestionsForInput = (input) => {
  const sug = findSuggestionsForInput(input);
  if (sug) sug.hidden = true;
};

const getActiveSearchInput = () => getActiveSessionEl()?.querySelector(".search-input") || null;

if (sessionsRoot) {
  sessionsRoot.addEventListener("focusin", (e) => {
    const input = e.target.closest?.(".search-input");
    if (!input) return;
    const t = blurTimers.get(input);
    if (t) clearTimeout(t);
    showSuggestionsForInput(input);
  });

  sessionsRoot.addEventListener("click", (e) => {
    const input = e.target.closest?.(".search-input");
    if (input) {
      const t = blurTimers.get(input);
      if (t) clearTimeout(t);
      showSuggestionsForInput(input);
      return;
    }

    const btn = e.target.closest?.(".suggestions [data-value]");
    if (!btn) return;
    const value = btn.getAttribute("data-value") || "";
    if (routeKeyword(value)) return;
    const session = btn.closest(".session-view");
    const sessionInput = session?.querySelector(".search-input");
    if (!sessionInput) return;
    sessionInput.value = value;
    hideSuggestionsForInput(sessionInput);
    sessionInput.focus();
  });

  sessionsRoot.addEventListener("mousedown", (e) => {
    if (e.target.closest?.(".suggestions")) e.preventDefault();
  });

  sessionsRoot.addEventListener("focusout", (e) => {
    const input = e.target.closest?.(".search-input");
    if (!input) return;
    const timer = setTimeout(() => hideSuggestionsForInput(input), 120);
    blurTimers.set(input, timer);
  });
}

const topSearchBtn = document.getElementById("topSearchBtn");
const topMenu = document.getElementById("topMenu");

const setTopMenuOpen = (open) => {
  if (!topMenu || !topSearchBtn) return;
  topMenu.hidden = !open;
  topSearchBtn.setAttribute("aria-expanded", open ? "true" : "false");
};

if (topSearchBtn && topMenu) {
  topSearchBtn.addEventListener("click", () => {
    setTopMenuOpen(topMenu.hidden);
  });

  document.addEventListener("click", (e) => {
    if (topMenu.hidden) return;
    const within = topMenu.contains(e.target) || topSearchBtn.contains(e.target);
    if (!within) setTopMenuOpen(false);
  });

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") setTopMenuOpen(false);
  });
}

const setActiveTab = (tabId) => {
  setActiveSessionId(tabId);

  document.querySelectorAll("[role='tab'][data-tab]").forEach((btn) => {
    btn.setAttribute("aria-selected", btn.getAttribute("data-tab") === String(tabId) ? "true" : "false");
  });

  sessionsRoot?.querySelectorAll(".session-view").forEach((view) => {
    view.hidden = view.getAttribute("data-session") !== String(tabId);
  });

  const input = getActiveSearchInput();
  if (input) hideSuggestionsForInput(input);
};

const ensureSession = (id) => {
  if (!sessionsRoot || !sessionTemplate) return null;
  const existing = getSessionEl(id);
  if (existing) return existing;
  const frag = sessionTemplate.content.cloneNode(true);
  const section = frag.querySelector(".session-view");
  if (!section) return null;
  section.setAttribute("data-session", String(id));
  const t = section.querySelector("[data-split]");
  splitTitle(t);
  sessionsRoot.appendChild(section);
  return section;
};

const tab1 = document.getElementById("tab-1");
if (tab1) tab1.addEventListener("click", () => setActiveTab(1));

const addBtn = document.getElementById("addRiftTab");
let nextTabId = 2;
if (addBtn) {
  addBtn.addEventListener("click", () => {
    const tablist = addBtn.closest("[role='tablist']");
    if (!tablist) return;

    const id = nextTabId++;
    ensureSession(id);

    const btn = document.createElement("button");
    btn.className = "tab";
    btn.type = "button";
    btn.id = `tab-${id}`;
    btn.setAttribute("role", "tab");
    btn.setAttribute("data-tab", String(id));
    btn.setAttribute("aria-selected", "false");
    btn.textContent = `rift ${id}`;
    btn.addEventListener("click", () => setActiveTab(id));
    tablist.insertBefore(btn, addBtn);
    setActiveTab(id);
  });
}

// Top-right menu should target the active session's search box.
if (topMenu) {
  topMenu.addEventListener("click", (e) => {
    const btn = e.target.closest("[data-value]");
    if (!btn) return;
    const input = getActiveSearchInput();
    if (!input) return;
    const value = btn.getAttribute("data-value") || "";
    if (routeKeyword(value)) {
      setTopMenuOpen(false);
      return;
    }
    input.value = value;
    showSuggestionsForInput(input);
    input.focus();
    setTopMenuOpen(false);
  });
}

// Initialize: show session 1 only.
setActiveSessionId(1);
setActiveTab(1);

// Navigate to /rift with a slide-down transition, but keep the URL unchanged
// by swapping the document via document.write (no iframe, no overlay app view).
const homeApp = document.getElementById("homeApp");
const navCurtain = document.getElementById("navCurtain");
const prefersReduceNav = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const riftUrl = (location.protocol === "file:") ? "./rift/index.html" : "/rift/";
const gamesUrl = (location.protocol === "file:") ? "./games/index.html" : "/games/";
let navInFlight = false;

const swapToRiftDocument = async () => {
  const res = await fetch(riftUrl, { credentials: "same-origin", cache: "no-cache" });
  if (!res.ok) throw new Error(`Failed to load ${riftUrl} (${res.status})`);
  const html = await res.text();
  document.open();
  document.write(html);
  document.close();
};

const enterRift = async () => {
  if (navInFlight) return;
  navInFlight = true;

  if (!prefersReduceNav) {
    document.body.classList.add("is-navigating");
  } else {
    // Reduced motion: skip animation but still show a clean cut.
    if (navCurtain) navCurtain.style.transform = "translateY(0)";
    if (homeApp) homeApp.style.opacity = "0";
  }

  // Let the animation read before we swap documents.
  const delay = prefersReduceNav ? 20 : 340;
  setTimeout(async () => {
    try {
      await swapToRiftDocument();
    } catch (err) {
      // If fetch fails (common on file://), fall back to a normal navigation.
      window.location.href = riftUrl;
    }
  }, delay);
};

const animateThenNavigate = (url) => {
  if (navInFlight) return;
  navInFlight = true;

  if (!prefersReduceNav) {
    document.body.classList.add("is-navigating");
  } else {
    if (navCurtain) navCurtain.style.transform = "translateY(0)";
    if (homeApp) homeApp.style.opacity = "0";
  }

  const delay = prefersReduceNav ? 20 : 340;
  setTimeout(() => {
    window.location.href = url;
  }, delay);
};

const routeKeyword = (raw) => {
  const value = String(raw || "").trim().toLowerCase();
  if (!value) return false;

  if (value === "games" || value === "game") {
    animateThenNavigate(gamesUrl);
    return true;
  }

  if (value === "rift" || value === "enter" || value === "enter the rift") {
    enterRift();
    return true;
  }

  return false;
};

document.addEventListener("click", (e) => {
  const btn = e.target.closest?.(".enter-btn");
  if (!btn) return;
  enterRift();
});

document.addEventListener("click", (e) => {
  const navBtn = e.target.closest?.(".side-nav .icon-btn");
  if (!navBtn) return;

  const label = (navBtn.getAttribute("aria-label") || "").trim().toLowerCase();
  if (label === "games") {
    animateThenNavigate(gamesUrl);
  }
});

document.addEventListener("keydown", (e) => {
  if (e.key !== "Enter") return;
  const input = e.target.closest?.(".search-input");
  if (!input) return;
  routeKeyword(input.value);
});
