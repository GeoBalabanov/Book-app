// Look Up sheet: the word, its Bulgarian meaning in this sentence, grammar,
// the sentence with the word in bold, the sentence in Bulgarian, and Save.

import { h, clear, boldSentence, toast } from '../util.js';
import { openSheet, confirmSheet } from './sheet.js';
import { lookup } from '../translation/service.js';
import { vocab } from '../store/vocab.js';

/**
 * @param {{word:string, sentence:string, offset:number, bookTitle?:string, bookId?:string}} req
 * @param {{onClose?:Function, entry?:object}} opts  `entry`: show a saved word without a lookup
 */
export function openWordSheet(req, { onClose, entry } = {}) {
  const container = h('div', { class: 'lu' });
  let ctl = null;
  let result = null;
  const sheet = openSheet({
    title: entry ? 'Saved Word' : 'Look Up', content: container, label: `Translation of ${req.word}`,
    onClose: () => { ctl?.abort(); onClose?.(); },
  });

  const render = (state) => {
    clear(container);
    const r = state.result;
    const head = h('div', { class: 'lu-head' }, h('h3', { class: 'lu-word', lang: 'en' }, req.word));
    const gram = [];
    if (r?.partOfSpeech) gram.push(h('i', {}, r.partOfSpeech));
    if (r?.lemma && r.lemma.toLowerCase() !== req.word.toLowerCase()) gram.push(`base form ${r.lemma}`);
    if (gram.length) head.append(h('div', { class: 'lu-gram' }, gram.flatMap((g, i) => (i ? [' · ', g] : [g]))));

    if (state.loading) {
      head.append(h('div', { class: 'lu-tr' }, h('div', { class: 'skeleton', style: { height: '28px', width: '50%' } })));
    } else if (state.error) {
      head.append(h('p', { class: 'error-box', role: 'alert' }, state.error),
        h('button', { class: 'btn secondary small', onclick: () => run(false) }, 'Try Again'));
    } else if (r) {
      head.append(h('div', { class: 'lu-tr', lang: 'bg' }, r.translation));
      if (r.dictionaryTranslation && r.dictionaryTranslation !== r.translation) {
        head.append(h('div', { class: 'lu-dict', lang: 'bg' }, `${r.lemma || req.word}: ${r.dictionaryTranslation}`));
      }
      if (r.note) head.append(h('p', { class: 'lu-note', lang: 'bg' }, r.note));
    }
    container.append(head);

    const sec = h('div', { class: 'lu-section' },
      h('span', { class: 'lu-label' }, entry?.bookTitle || req.bookTitle || 'In the book'),
      h('p', { class: 'lu-sentence', lang: 'en', style: { margin: 0 } }, boldSentence(req.sentence, req.word, req.offset)));
    if (state.loading) sec.append(h('div', { class: 'skeleton' }), h('div', { class: 'skeleton', style: { width: '65%' } }));
    else if (r?.sentenceTranslation) sec.append(h('p', { class: 'lu-sentence bg', lang: 'bg', style: { margin: 0 } }, r.sentenceTranslation));
    container.append(sec);

    const actions = h('div', { class: 'lu-actions' });
    if (entry) {
      const del = h('button', { class: 'btn destructive block' }, 'Delete Word');
      del.onclick = async () => {
        if (await confirmSheet({ title: 'Delete Word?', message: `“${entry.word}” and its review history will be removed.` })) {
          await vocab.remove(entry.id); sheet.close(); toast('Word deleted');
        }
      };
      actions.append(del, h('div', { class: 'lu-foot' }, h('span', {}, `Saved ${new Date(entry.addedAt).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })}`)));
      container.append(actions);
      return;
    }
    if (r) {
      const existing = vocab.find(req.word, req.sentence);
      const saved = existing && existing.sentence === req.sentence;
      const save = h('button', { class: 'btn block', disabled: saved }, saved ? 'Saved to Flashcards' : 'Save to Flashcards');
      save.onclick = async () => {
        save.disabled = true; save.textContent = 'Saving…';
        try {
          await vocab.add({
            word: req.word, lemma: r.lemma, partOfSpeech: r.partOfSpeech,
            translation: r.translation, dictionaryTranslation: r.dictionaryTranslation || '',
            note: r.note || '', sentence: req.sentence, offset: req.offset,
            sentenceTranslation: r.sentenceTranslation, bookId: req.bookId || '', bookTitle: req.bookTitle || '',
          });
          save.textContent = 'Saved to Flashcards';
        } catch (e) {
          console.error(e);
          save.disabled = false; save.textContent = 'Save to Flashcards';
          toast(e?.code === 'quota_exceeded' ? 'Storage is full. Delete some words first.' : 'Couldn’t save the word. Try again.');
        }
      };
      const foot = h('div', { class: 'lu-foot' }, h('span', {}, providerName(r.provider)));
      if (r.provider === 'claude') foot.append(h('button', { onclick: () => run(true) }, 'Ask a stronger model'));
      actions.append(save, foot);
      container.append(actions);
    }
  };

  const run = async (best) => {
    ctl?.abort();
    ctl = new AbortController();
    render({ loading: true, result: best ? result : null });
    try {
      result = await lookup(req, { signal: ctl.signal, refresh: best, quality: best ? 'best' : 'fast' });
      if (!sheet.closed) render({ result });
    } catch (e) {
      if (e?.code === 'cancelled' || e?.name === 'AbortError') return;
      if (!sheet.closed) render({ error: e?.message || 'Translation failed.' });
    }
  };

  if (entry) render({ result: { ...entry, provider: null } });
  else run(false);
  return sheet;
}

function providerName(id) {
  return { claude: 'Translated by Claude', deepl: 'Translated by DeepL', mock: 'Demo translation' }[id] || '';
}
