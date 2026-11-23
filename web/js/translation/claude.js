// Claude provider: uses the artifact runtime's `sample` capability, which runs
// on the viewer's own Claude account. No API key in the page. One request
// returns the contextual translation, lemma, part of speech and the sentence
// translation together.

const WORD_OPEN = '⟦';
const WORD_CLOSE = '⟧';

let samplePromise;
function getSample() {
  if (!samplePromise) samplePromise = window.claude?.use ? window.claude.use('sample').catch(() => null) : Promise.resolve(null);
  return samplePromise;
}

export function buildPrompt({ word, sentence, offset, bookTitle }) {
  const marked = Number.isInteger(offset) && sentence.substr(offset, word.length) === word
    ? `${sentence.slice(0, offset)}${WORD_OPEN}${word}${WORD_CLOSE}${sentence.slice(offset + word.length)}`
    : sentence.replace(word, `${WORD_OPEN}${word}${WORD_CLOSE}`);
  return [
    'You are an English→Bulgarian dictionary for a Bulgarian speaker who is reading an English book and learning vocabulary.',
    bookTitle ? `Book: ${bookTitle}` : '',
    `Sentence (the looked-up word is marked with ${WORD_OPEN} ${WORD_CLOSE}):`,
    marked,
    '',
    'Translate the marked word as it is used in THIS sentence (pick the sense that fits the context, not the most common dictionary sense).',
    'Reply with only a JSON object with these keys:',
    '{',
    '  "lemma": English base form of the word (e.g. "ran" → "run", "mice" → "mouse"). If the word is part of a phrasal verb or fixed expression in this sentence, give the whole expression (e.g. "give up").',
    '  "partOfSpeech": short English label with grammatical detail, e.g. "verb, past tense", "noun, plural", "adjective".',
    '  "translation": Bulgarian translation of the word as used here, in Cyrillic, 1–4 words, inflected to fit the sentence where natural. No explanations.',
    '  "dictionaryTranslation": Bulgarian translation of the lemma in its dictionary form (1–4 words).',
    '  "sentenceTranslation": a natural, faithful Bulgarian translation of the whole sentence.',
    '  "note": one short sentence in Bulgarian only if the word is idiomatic, archaic, a phrasal verb, or has an unusual meaning here; otherwise "".',
    '}',
  ].filter(Boolean).join('\n');
}

export class ClaudeTranslationService {
  id = 'claude';
  name = 'Claude';
  description = 'Runs on your Claude account. Understands context, idioms and phrasal verbs.';

  async isAvailable() { return !!(await getSample()); }

  async translate(req, { signal, quality = 'fast' } = {}) {
    const sample = await getSample();
    if (!sample) throw Object.assign(new Error('Claude is not available in this view.'), { code: 'unavailable' });
    let data;
    try {
      data = await sample.json(buildPrompt(req), {
        signal,
        modelTier: quality === 'best' ? 'default' : 'quick',
        cache: quality === 'best' ? false : true,
      });
    } catch (e) {
      throw Object.assign(new Error(messageFor(e?.code)), { code: e?.code || 'upstream_error' });
    }
    if (!data || typeof data !== 'object' || !data.translation) {
      throw Object.assign(new Error('The translation came back incomplete. Try again.'), { code: 'invalid_json' });
    }
    const str = (v) => (typeof v === 'string' ? v.trim() : '');
    return {
      word: req.word,
      lemma: str(data.lemma) || req.word.toLowerCase(),
      partOfSpeech: str(data.partOfSpeech),
      translation: str(data.translation),
      dictionaryTranslation: str(data.dictionaryTranslation),
      sentenceTranslation: str(data.sentenceTranslation),
      note: str(data.note),
      provider: this.id,
    };
  }
}

function messageFor(code) {
  switch (code) {
    case 'not_granted': return 'Claude access wasn’t allowed for this page. Allow it from the page’s permissions to translate words.';
    case 'rate_limited': return 'Too many lookups right now. Wait a moment and try again.';
    case 'session_expired': return 'Your Claude session expired. Sign in again, then retry.';
    case 'sampling_disabled': return 'Claude isn’t available for this account.';
    case 'cancelled': return 'Cancelled.';
    case 'invalid_json': return 'The translation came back in an unexpected format. Try again.';
    case 'refused': return 'Claude declined to translate this sentence.';
    default: return 'The translation service didn’t respond. Check your connection and try again.';
  }
}
