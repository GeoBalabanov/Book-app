// DeepL provider. Browsers can't call the DeepL API directly (no CORS, and the
// key must stay secret), so requests go through the local dev server
// (web/server.mjs), which adds the key from web/.env.
//
// Flow: one request translates the sentence with the word wrapped in <w>…</w>
// (tag_handling=xml). The tagged span is the word's in-context translation;
// the whole output is the sentence translation. If DeepL drops the tag, a
// second request translates the word alone with the sentence as `context`.
// Lemma and part of speech come from the on-device `compromise` NLP library.

import { markSentence, parseTagged } from './deepl-core.js';
import { analyzeWord } from './nlp.js';

const API = 'api/deepl';

export class DeepLTranslationService {
  id = 'deepl';
  name = 'DeepL';
  description = 'Needs the local server with your DeepL API key in web/.env.';
  #status = null;

  async isAvailable() {
    if (this.#status === null) {
      this.#status = fetch(`${API}/status`).then((r) => (r.ok ? r.json() : null)).then((j) => !!j?.configured).catch(() => false);
    }
    return this.#status;
  }

  async #call(body, signal) {
    const res = await fetch(`${API}/translate`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal,
    });
    if (!res.ok) {
      const msg = res.status === 403 ? 'DeepL rejected the API key. Check web/.env.'
        : res.status === 456 ? 'Your DeepL quota for this month is used up.'
        : res.status === 429 ? 'Too many DeepL requests. Wait a moment and try again.'
        : `DeepL request failed (${res.status}).`;
      throw Object.assign(new Error(msg), { code: `http_${res.status}` });
    }
    const json = await res.json();
    return json.translations.map((t) => t.text);
  }

  async translate(req, { signal } = {}) {
    const base = { source_lang: 'EN', target_lang: 'BG' };
    const marked = markSentence(req.sentence, req.word, req.offset);
    let wordTr = null;
    let sentenceTr = '';
    if (marked) {
      const [out] = await this.#call({ ...base, text: [marked], tag_handling: 'xml', context: req.bookTitle ? `From the book "${req.bookTitle}".` : undefined }, signal);
      ({ word: wordTr, sentence: sentenceTr } = parseTagged(out));
    } else {
      [sentenceTr] = await this.#call({ ...base, text: [req.sentence] }, signal);
    }
    const nlp = await analyzeWord(req.sentence, req.word, req.offset);
    const lemma = nlp.lemma || req.word.toLowerCase();
    const extra = [];
    if (!wordTr) extra.push(req.word);
    if (lemma.toLowerCase() !== req.word.toLowerCase()) extra.push(lemma);
    let dict = '';
    if (extra.length) {
      const outs = await this.#call({ ...base, text: extra, context: req.sentence }, signal);
      if (!wordTr) wordTr = outs.shift();
      dict = outs[0] || '';
    }
    return {
      word: req.word,
      lemma,
      partOfSpeech: nlp.partOfSpeech,
      translation: wordTr,
      dictionaryTranslation: dict,
      sentenceTranslation: sentenceTr,
      note: '',
      provider: this.id,
    };
  }
}
