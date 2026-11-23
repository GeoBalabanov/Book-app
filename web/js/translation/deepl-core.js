// Pure helpers for the DeepL provider (no DOM, no network) so they can be
// unit-tested in Node.

/** Wrap the word at `offset` in <w>…</w>, escaping the rest for XML tag handling. */
export function markSentence(sentence, word, offset) {
  const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  let i = Number.isInteger(offset) && sentence.substr(offset, word.length) === word ? offset : sentence.indexOf(word);
  if (i < 0) return null;
  return `${esc(sentence.slice(0, i))}<w>${esc(word)}</w>${esc(sentence.slice(i + word.length))}`;
}

const unesc = (s) => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');

/**
 * Split DeepL's tagged output into the in-context word translation and the
 * plain sentence translation. Returns word: null when the tag was dropped or
 * came back empty.
 */
export function parseTagged(text) {
  const m = /<w>([\s\S]*?)<\/w>/.exec(text);
  const word = m ? unesc(m[1]).replace(/[.,;:!?"“”«»]+$/g, '').trim() : '';
  const sentence = unesc(text.replace(/<\/?w>/g, '')).replace(/\s+/g, ' ').trim();
  return { word: word || null, sentence };
}

/** DeepL Free keys end in ":fx" and use a different host. */
export function deeplHost(key) {
  return /:fx$/.test(key.trim()) ? 'https://api-free.deepl.com' : 'https://api.deepl.com';
}
