// Offline stand-in for development and tests. Enabled only with ?mock in the URL.

export class MockTranslationService {
  id = 'mock';
  name = 'Demo (offline)';
  description = 'Fake translations for testing the interface without a service.';

  async isAvailable() { return /[?&]mock\b/.test(location.search); }

  async translate(req, { signal } = {}) {
    await new Promise((r, j) => { const t = setTimeout(r, 400); signal?.addEventListener('abort', () => { clearTimeout(t); j(Object.assign(new Error('Cancelled.'), { code: 'cancelled' })); }); });
    const w = req.word.toLowerCase();
    return {
      word: req.word,
      lemma: w.replace(/(ed|ing|s)$/, '') || w,
      partOfSpeech: 'word',
      translation: `«${w}» (демо)`,
      dictionaryTranslation: `${w} (речник)`,
      sentenceTranslation: `[Демо превод] ${req.sentence}`,
      note: '',
      provider: this.id,
    };
  }
}
