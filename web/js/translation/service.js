// TranslationService: the one interface the UI talks to.
//
// interface TranslationService {
//   id: string;                     // 'claude' | 'deepl' | 'mock' | ...
//   name: string;                   // shown in Settings and under results
//   description: string;
//   isAvailable(): Promise<boolean>;
//   translate(req: LookupRequest, opts?: {signal?: AbortSignal, quality?: 'fast'|'best'}): Promise<LookupResult>;
// }
//
// To add a provider: implement the interface in a new module and add it to
// PROVIDERS below. Nothing else in the app needs to change.

import { hashString, storage } from '../util.js';
import { vocab } from '../store/vocab.js';
import { ClaudeTranslationService } from './claude.js';
import { DeepLTranslationService } from './deepl.js';
import { MockTranslationService } from './mock.js';

/**
 * @typedef {Object} LookupRequest
 * @property {string} word        the tapped word exactly as printed
 * @property {string} sentence    the full sentence it appears in
 * @property {number} offset      index of `word` inside `sentence`
 * @property {string} [bookTitle]
 *
 * @typedef {Object} LookupResult
 * @property {string} word
 * @property {string} lemma               English base form
 * @property {string} partOfSpeech
 * @property {string} translation         Bulgarian for the word as used here
 * @property {string} [dictionaryTranslation]  Bulgarian for the lemma
 * @property {string} [note]
 * @property {string} sentenceTranslation Bulgarian for the whole sentence
 * @property {string} provider            id of the service that answered
 */

export const PROVIDERS = [new ClaudeTranslationService(), new DeepLTranslationService(), new MockTranslationService()];

const PREF_KEY = 'lexi.provider';

export async function availableProviders() {
  const results = await Promise.all(PROVIDERS.map(async (p) => [p, await p.isAvailable().catch(() => false)]));
  return results.map(([p, ok]) => ({ provider: p, available: ok }));
}

export async function currentProvider() {
  const pref = storage.get(PREF_KEY, null);
  const list = await availableProviders();
  return (list.find((x) => x.available && x.provider.id === pref) || list.find((x) => x.available))?.provider || null;
}

export function setPreferredProvider(id) { storage.set(PREF_KEY, id); }

export function cacheKey(providerId, req) {
  return `${providerId}-${hashString(`${req.word.toLowerCase()}|${req.offset}|${req.sentence}`)}`;
}

/**
 * Look a word up with caching. The same provider + word + sentence is never
 * requested twice; `refresh: true` bypasses and overwrites the cache.
 */
export async function lookup(req, { signal, refresh = false, quality = 'fast' } = {}) {
  const provider = await currentProvider();
  if (!provider) {
    const err = new Error('No translation service is available here. Open the app inside Claude, or run the local server with a DeepL key.');
    err.code = 'no_provider';
    throw err;
  }
  const key = cacheKey(provider.id, req);
  if (!refresh) {
    const hit = await vocab.cacheGet(key);
    if (hit?.translation) return { ...hit, cached: true };
  }
  const result = await provider.translate(req, { signal, quality });
  const clean = { ...result, word: req.word, provider: provider.id, cachedAt: Date.now() };
  vocab.cachePut(key, clean);
  return clean;
}
