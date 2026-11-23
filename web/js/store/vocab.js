// Saved words and the translation cache.
//
// Two interchangeable backends:
//  - CloudBackend: the artifact's `db` capability, under the viewer's private
//    `data/users/<id>/` subtree. Survives reloads and syncs across devices.
//  - LocalBackend: IndexedDB in this browser (used when the page runs outside
//    a Claude viewer, e.g. the local dev server).

import { idb } from './idb.js';
import { uid } from '../util.js';
import { newReviewState, isDueToday } from '../srs/sm2.js';

/**
 * @typedef {Object} VocabEntry
 * @property {string} id
 * @property {string} word              surface form as it appeared ("ran")
 * @property {string} lemma             base form ("run")
 * @property {string} partOfSpeech
 * @property {string} translation       Bulgarian, as used in the sentence
 * @property {string} [dictionaryTranslation] Bulgarian for the lemma
 * @property {string} [note]
 * @property {string} sentence
 * @property {number} [offset]          index of the word in `sentence`
 * @property {string} sentenceTranslation
 * @property {string} [bookId]
 * @property {string} bookTitle
 * @property {number} addedAt
 * @property {{ease:number, interval:number, repetitions:number, lapses:number, due:number, lastReviewed:number|null}} srs
 */

class LocalBackend {
  kind = 'local';
  #cb = null;
  async #all() { return (await idb.entries('kv', 'vocab:')).map(([, v]) => v); }
  async #emit() { this.#cb?.(await this.#all()); }
  subscribe(cb) { this.#cb = cb; this.#emit(); return () => { this.#cb = null; }; }
  async put(entry) { await idb.put('kv', `vocab:${entry.id}`, entry); this.#emit(); }
  async patch(id, partial) {
    const cur = await idb.get('kv', `vocab:${id}`);
    if (cur) await idb.put('kv', `vocab:${id}`, { ...cur, ...partial });
    this.#emit();
  }
  async remove(id) { await idb.delete('kv', `vocab:${id}`); this.#emit(); }
  cacheGet(key) { return idb.get('kv', `cache:${key}`); }
  cachePut(key, value) { return idb.put('kv', `cache:${key}`, value); }
  async drain() { return this.#all(); }
}

class CloudBackend {
  kind = 'cloud';
  constructor(db, userId) {
    const root = db.doc(`data/users/${userId}/lexi`);
    this.vocabCol = root.collection('vocab');
    this.cacheCol = root.collection('cache');
  }
  subscribe(cb, onError) {
    return this.vocabCol.onSnapshot(
      (snap) => cb(snap.docs.map((d) => ({ ...d.data(), id: d.id }))),
      (e) => onError?.(e),
    );
  }
  put(entry) { const { id, ...body } = entry; return this.vocabCol.doc(id).set(JSON.parse(JSON.stringify(body))); }
  patch(id, partial) { return this.vocabCol.doc(id).update(JSON.parse(JSON.stringify(partial))); }
  remove(id) { return this.vocabCol.doc(id).delete(); }
  async cacheGet(key) {
    try { const s = await this.cacheCol.doc(key).get(); return s.exists ? s.data() : undefined; } catch { return undefined; }
  }
  async cachePut(key, value) {
    try { await this.cacheCol.doc(key).set(JSON.parse(JSON.stringify(value))); } catch (e) { console.warn('cache write failed', e); }
  }
}

async function pickBackend() {
  const local = new LocalBackend();
  if (!window.claude?.use) return local;
  try {
    const [db, user] = await Promise.all([window.claude.use('db'), window.claude.use('user')]);
    const id = db && user ? await user.id() : null;
    if (!db || !id) return local;
    const cloud = new CloudBackend(db, id);
    // Move anything saved locally (before the cloud store answered) into the cloud.
    for (const e of await local.drain()) {
      try { await cloud.put(e); await local.remove(e.id); } catch { break; }
    }
    return cloud;
  } catch (e) {
    console.warn('db unavailable, using local storage', e);
    return local;
  }
}

const listeners = new Set();
let backend = null;
let entries = [];
let ready = false;
let loadError = null;

const readyPromise = pickBackend().then((b) => {
  backend = b;
  const timer = setTimeout(() => { if (!ready) { loadError = 'Your saved words can’t be reached yet.'; emit(); } }, 10000);
  b.subscribe((list) => {
    clearTimeout(timer);
    entries = list.sort((a, c) => c.addedAt - a.addedAt);
    ready = true; loadError = null;
    emit();
  }, (e) => {
    clearTimeout(timer);
    loadError = `Saved words are unavailable (${e.code || 'error'}).`;
    ready = true;
    emit();
  });
  return b;
});

function emit() { listeners.forEach((fn) => fn(entries)); }

export const vocab = {
  ready: readyPromise,
  get isReady() { return ready; },
  get error() { return loadError; },
  get kind() { return backend?.kind ?? 'pending'; },
  get all() { return entries; },
  onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); },

  find(word, sentence) {
    const w = word.toLowerCase();
    return entries.find((e) => e.word.toLowerCase() === w && e.sentence === sentence)
      || entries.find((e) => e.word.toLowerCase() === w || e.lemma?.toLowerCase() === w);
  },

  /** Lowercased forms to underline in the reader (surface words and lemmas). */
  savedForms() {
    const set = new Set();
    for (const e of entries) {
      if (e.word) set.add(e.word.toLowerCase());
      if (e.lemma && !e.lemma.includes(' ')) set.add(e.lemma.toLowerCase());
    }
    return set;
  },

  dueToday(now = Date.now()) { return entries.filter((e) => isDueToday(e.srs, now)); },

  async add(data) {
    const b = await readyPromise;
    const entry = { ...data, id: uid('w'), addedAt: Date.now(), srs: newReviewState() };
    entries = [entry, ...entries]; emit(); // optimistic
    await b.put(entry);
    return entry;
  },

  async updateReview(id, srs) {
    const b = await readyPromise;
    entries = entries.map((e) => (e.id === id ? { ...e, srs } : e)); emit();
    await b.patch(id, { srs });
  },

  async remove(id) {
    const b = await readyPromise;
    entries = entries.filter((e) => e.id !== id); emit();
    await b.remove(id);
  },

  async cacheGet(key) { const b = await readyPromise; return b.cacheGet(key); },
  async cachePut(key, value) { const b = await readyPromise; return b.cachePut(key, value); },
};
