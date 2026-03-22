importScripts("../scram/scramjet.all.js");

const { ScramjetServiceWorker } = $scramjetLoadWorker();
const scramjet = new ScramjetServiceWorker();
const SCRAMJET_CONFIG = {
  prefix: "/browser/service/",
  globals: {
    wrapfn: "$scramjet$wrap",
    wrappropertybase: "$scramjet__",
    wrappropertyfn: "$scramjet$prop",
    cleanrestfn: "$scramjet$clean",
    importfn: "$scramjet$import",
    rewritefn: "$scramjet$rewrite",
    metafn: "$scramjet$meta",
    setrealmfn: "$scramjet$setrealm",
    pushsourcemapfn: "$scramjet$pushsourcemap",
    trysetfn: "$scramjet$tryset",
    templocid: "$scramjet$temploc",
    tempunusedid: "$scramjet$tempunused"
  },
  files: {
    wasm: "/scram/scramjet.wasm.wasm",
    all: "/scram/scramjet.all.js",
    sync: "/scram/scramjet.sync.js"
  },
  flags: {
    serviceworkers: false,
    syncxhr: false,
    strictRewrites: true,
    rewriterLogs: false,
    captureErrors: true,
    cleanErrors: false,
    scramitize: false,
    sourcemaps: true,
    destructureRewrites: false,
    interceptDownloads: false,
    allowInvalidJs: true,
    allowFailedIntercepts: true
  },
  siteFlags: {},
  codec: {
    encode: (value) => value ? encodeURIComponent(value) : value,
    decode: (value) => value ? decodeURIComponent(value) : value
  }
};

const SCRAMJET_DB_NAMES = [
  "$scramjet",
  `${self.location.origin}@$scramjet`
];

const openDb = (name, version, onUpgrade) =>
  new Promise((resolve, reject) => {
    const request = version ? indexedDB.open(name, version) : indexedDB.open(name);
    request.onerror = () => reject(request.error || new Error("IDB open failed"));
    request.onupgradeneeded = () => {
      try {
        onUpgrade?.(request.result);
      } catch (err) {
        reject(err);
      }
    };
    request.onsuccess = () => resolve(request.result);
  });

const deleteDb = (name) =>
  new Promise((resolve) => {
    const request = indexedDB.deleteDatabase(name);
    request.onsuccess = () => resolve(true);
    request.onerror = () => resolve(false);
    request.onblocked = () => resolve(false);
  });

async function ensureScramjetSchema(name) {
  let db = null;
  try {
    db = await openDb(name);
  } catch {
    db = null;
  }

  if (db) {
    const required = ["config", "cookies", "redirectTrackers", "referrerPolicies", "publicSuffixList"];
    const missing = required.some((store) => !db.objectStoreNames.contains(store));
    db.close();
    if (!missing) return;
  }

  await deleteDb(name);

  const fresh = await openDb(name, 1, (upgradeDb) => {
    const required = ["config", "cookies", "redirectTrackers", "referrerPolicies", "publicSuffixList"];
    for (const store of required) {
      if (!upgradeDb.objectStoreNames.contains(store)) upgradeDb.createObjectStore(store);
    }
  });
  try {
    const tx = fresh.transaction("config", "readwrite");
    tx.objectStore("config").put(SCRAMJET_CONFIG, "config");
    await new Promise((resolve, reject) => {
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error || new Error("IDB transaction failed"));
      tx.onabort = () => reject(tx.error || new Error("IDB transaction aborted"));
    });
  } catch {
    // ignore
  }
  fresh.close();
}

let schemaReady = false;
async function ensureSchemaReady() {
  if (schemaReady) return;
  for (const name of SCRAMJET_DB_NAMES) {
    try {
      await ensureScramjetSchema(name);
    } catch {
      // Ignore and let Scramjet try the remaining candidate names.
    }
  }
  scramjet.config = SCRAMJET_CONFIG;
  schemaReady = true;
}

async function handleRequest(event) {
  await ensureSchemaReady();
  if (!scramjet.config) {
    scramjet.config = SCRAMJET_CONFIG;
  }
  if (scramjet.route(event)) return scramjet.fetch(event);
  return fetch(event.request);
}

self.addEventListener("install", (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    await ensureSchemaReady();
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", (event) => {
  event.respondWith(handleRequest(event));
});
