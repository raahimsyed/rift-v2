importScripts("../scram/scramjet.all.js");

const { ScramjetServiceWorker } = $scramjetLoadWorker();
const scramjet = new ScramjetServiceWorker();

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
  schemaReady = true;
}

async function handleRequest(event) {
  await ensureSchemaReady();
  await scramjet.loadConfig();
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
