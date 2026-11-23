// Minimal promise wrapper over IndexedDB with an in-memory fallback.
// IndexedDB can be missing or throw (private windows, blocked site data,
// some embedded views); in that case data lives only for this page load.

const DB_NAME = 'lexi-reader';
const DB_VERSION = 1;
export const STORES = ['books', 'files', 'kv'];

let dbPromise;
const memory = new Map(STORES.map((s) => [s, new Map()]));
let persistent = true;

function open() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve) => {
    try {
      const req = indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = () => {
        const db = req.result;
        for (const s of STORES) if (!db.objectStoreNames.contains(s)) db.createObjectStore(s);
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => { persistent = false; resolve(null); };
      req.onblocked = () => { persistent = false; resolve(null); };
    } catch {
      persistent = false;
      resolve(null);
    }
  });
  return dbPromise;
}

function wrap(req) {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function tx(store, mode, fn) {
  const db = await open();
  if (!db) return fn(null);
  try {
    const t = db.transaction(store, mode);
    return await fn(t.objectStore(store));
  } catch (e) {
    console.warn('IndexedDB failed, using memory', e);
    persistent = false;
    return fn(null);
  }
}

export const idb = {
  isPersistent: async () => { await open(); return persistent; },
  get: (store, key) => tx(store, 'readonly', (os) => (os ? wrap(os.get(key)) : memory.get(store).get(key))),
  put: (store, key, value) => tx(store, 'readwrite', (os) => (os ? wrap(os.put(value, key)) : void memory.get(store).set(key, value))),
  delete: (store, key) => tx(store, 'readwrite', (os) => (os ? wrap(os.delete(key)) : void memory.get(store).delete(key))),
  /** All [key, value] pairs, optionally only keys starting with `prefix`. */
  entries: (store, prefix = '') => tx(store, 'readonly', async (os) => {
    if (!os) return [...memory.get(store)].filter(([k]) => String(k).startsWith(prefix));
    const range = prefix ? IDBKeyRange.bound(prefix, prefix + '￿') : undefined;
    const [keys, values] = await Promise.all([wrap(os.getAllKeys(range)), wrap(os.getAll(range))]);
    return keys.map((k, i) => [k, values[i]]);
  }),
};
