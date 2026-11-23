// Books and reading positions. EPUB files and their metadata are kept in this
// browser's IndexedDB; the bundled sample is re-fetched if it is missing.

import { idb } from './idb.js';
import { EpubBook } from '../epub/parser.js';
import { uid, storage } from '../util.js';

export const SAMPLE_ID = 'sample-war-of-the-worlds';
const SAMPLE_URL = 'samples/war-of-the-worlds.epub';

const listeners = new Set();
const notify = () => listeners.forEach((fn) => fn());

/**
 * @typedef {Object} BookMeta
 * @property {string} id
 * @property {string} title
 * @property {string} author
 * @property {Blob|null} cover
 * @property {number} addedAt
 * @property {number|null} lastOpenedAt
 * @property {{chapter:number, fraction:number}|null} location
 * @property {number} progress   0..1 over the whole book
 * @property {number[]|null} textLengths
 * @property {boolean} [sample]
 */

export const library = {
  onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); },

  async list() {
    const rows = (await idb.entries('books')).map(([, v]) => v);
    return rows.sort((a, b) => (b.lastOpenedAt || b.addedAt) - (a.lastOpenedAt || a.addedAt));
  },

  get: (id) => idb.get('books', id),

  async ensureSample() {
    if (storage.get('lexi.sampleRemoved', false) || await idb.get('books', SAMPLE_ID)) return;
    try {
      const blob = await fetchSample();
      await this.addFromBlob(blob, { id: SAMPLE_ID, sample: true, addedAt: 0 });
    } catch (e) {
      console.warn('Sample book unavailable', e);
    }
  },

  /** Parse an EPUB, store it, and return its metadata. Throws EpubError on bad files. */
  async addFromBlob(blob, extra = {}) {
    const book = await EpubBook.open(blob);
    const meta = {
      id: extra.id || uid('b'),
      title: book.metadata.title,
      author: book.metadata.author,
      cover: await book.coverBlob(),
      addedAt: extra.addedAt ?? Date.now(),
      lastOpenedAt: null,
      location: null,
      progress: 0,
      textLengths: await book.computeTextLengths(),
      sample: !!extra.sample,
    };
    book.destroy();
    await idb.put('files', meta.id, blob);
    await idb.put('books', meta.id, meta);
    notify();
    return meta;
  },

  async openFile(id) {
    let blob = await idb.get('files', id);
    if (!blob && id === SAMPLE_ID) {
      blob = await fetchSample();
      await idb.put('files', id, blob);
    }
    if (!blob) throw new Error('This book’s file is no longer stored in this browser. Import it again.');
    return EpubBook.open(blob);
  },

  async saveLocation(id, location, progress) {
    const meta = await idb.get('books', id);
    if (!meta) return;
    meta.location = location;
    meta.progress = progress;
    meta.lastOpenedAt = Date.now();
    await idb.put('books', id, meta);
    notify();
  },

  async touch(id) {
    const meta = await idb.get('books', id);
    if (!meta) return;
    meta.lastOpenedAt = Date.now();
    await idb.put('books', id, meta);
    notify();
  },

  async remove(id) {
    if (id === SAMPLE_ID) storage.set('lexi.sampleRemoved', true);
    await idb.delete('books', id);
    await idb.delete('files', id);
    notify();
  },
};

// The artifact host can't serve .epub files, so the hosted copy of the sample
// is base64 text; the local server serves the .epub directly.
async function fetchSample() {
  const res = await fetch(SAMPLE_URL);
  if (res.ok && !/text\/html/.test(res.headers.get('content-type') || '')) return res.blob();
  const b64 = await fetch(`${SAMPLE_URL}.b64.txt`);
  if (!b64.ok) throw new Error(`Sample book request failed (${b64.status})`);
  const bin = atob((await b64.text()).trim());
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new Blob([bytes], { type: 'application/epub+zip' });
}
