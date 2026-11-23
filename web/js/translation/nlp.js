// Lemma + part of speech for providers that don't return them (DeepL).
// Loads `compromise` (MIT, ~250 KB) from jsDelivr on first use.

let nlpPromise;
function loadNlp() {
  if (window.nlp) return Promise.resolve(window.nlp);
  if (!nlpPromise) {
    nlpPromise = new Promise((resolve) => {
      const s = document.createElement('script');
      s.src = 'https://cdn.jsdelivr.net/npm/compromise@14.14.4/builds/compromise.js';
      s.onload = () => resolve(window.nlp || null);
      s.onerror = () => resolve(null);
      document.head.append(s);
    });
  }
  return nlpPromise;
}

const TAG_LABELS = [
  ['PhrasalVerb', 'phrasal verb'], ['Modal', 'modal verb'], ['Auxiliary', 'auxiliary verb'],
  ['PastTense', 'verb, past tense'], ['Gerund', 'verb, -ing form'], ['PresentTense', 'verb, present tense'],
  ['Infinitive', 'verb'], ['Participle', 'verb, participle'], ['Verb', 'verb'],
  ['Plural', 'noun, plural'], ['ProperNoun', 'proper noun'], ['Pronoun', 'pronoun'], ['Noun', 'noun'],
  ['Comparable', 'adjective'], ['Superlative', 'adjective, superlative'], ['Comparative', 'adjective, comparative'], ['Adjective', 'adjective'],
  ['Adverb', 'adverb'], ['Preposition', 'preposition'], ['Conjunction', 'conjunction'], ['Determiner', 'determiner'],
  ['Value', 'number'], ['Expression', 'interjection'],
];

export async function analyzeWord(sentence, word, offset) {
  const nlp = await loadNlp();
  if (!nlp) return { lemma: word.toLowerCase(), partOfSpeech: '' };
  try {
    const doc = nlp(sentence);
    const terms = doc.terms().json();
    // Pick the term whose text matches, nearest to the tapped offset.
    let best = null, bestDist = Infinity, pos = 0;
    for (const t of terms) {
      const text = t.terms?.[0]?.text ?? t.text;
      const idx = sentence.indexOf(text, pos);
      if (idx >= 0) pos = idx + text.length;
      if (text.toLowerCase() === word.toLowerCase()) {
        const d = Math.abs(idx - (offset ?? idx));
        if (d < bestDist) { best = t.terms?.[0] ?? t; bestDist = d; }
      }
    }
    const tags = new Set(best?.tags || []);
    const label = TAG_LABELS.find(([tag]) => tags.has(tag))?.[1] || '';
    let lemma = word.toLowerCase();
    const one = nlp(word);
    if (tags.has('Verb')) lemma = one.verbs().toInfinitive().text() || lemma;
    else if (tags.has('Plural')) lemma = one.nouns().toSingular().text() || lemma;
    else if (tags.has('Comparative') || tags.has('Superlative')) lemma = one.adjectives().json()[0]?.adjective?.adjective || lemma;
    return { lemma: lemma.toLowerCase(), partOfSpeech: label };
  } catch {
    return { lemma: word.toLowerCase(), partOfSpeech: '' };
  }
}
