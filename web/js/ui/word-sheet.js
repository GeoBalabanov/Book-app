// The lookup sheet: word, in-context Bulgarian translation, sentence with the
// word highlighted, sentence translation, base form + part of speech, Save.

import { h, clear, markedSentence, toast } from '../util.js';
import { openSheet, confirmSheet } from './sheet.js';
import { lookup, currentProvider } from '../translation/service.js';
import { vocab } from '../store/vocab.js';

/**
 * @param {{word:string, sentence:string, offset:number, bookTitle?:string, bookId?:string}} req
 * @param {{onClose?:Function, entry?:object}} opts  `entry`: show a saved word without a lookup
 */
export function openWordSheet(req, { onClose, entry } = {}) {
  const container = h('div', { class: 'ws' });
  const sheet = openSheet({ title: entry ? 'Saved word' : 'Translate', content: container, onClose: () => { ctl?.abort(); onClose?.(); }, label: `Translation of ${req.word}` });
  let ctl = null;
  let result = null;

  const render = (state) => {
    clear(container);
    const head = h('div', { class: 'ws-word' }, h('h3', { lang: 'en' }, req.word));
    if (state.result?.lemma || state.result?.partOfSpeech) {
      const bits = [];
      if (state.result.lemma && state.result.lemma.toLowerCase() !== req.word.toLowerCase()) bits.push(`base form: ${state.result.lemma}`);
      if (state.result.partOfSpeech) bits.push(state.result.partOfSpeech);
      if (bits.length) head.append(h('span', { class: 'ws-pos' }, bits.join(' · ')));
    }
    container.append(head);

    if (state.loading) {
      container.append(h('div', { class: 'skeleton', style: { height: '30px', width: '55%' } }));
    } else if (state.error) {
      container.append(h('div', { class: 'error-box', role: 'alert' }, state.error),
        h('div', { class: 'ws-actions' }, h('button', { class: 'pill-btn secondary', onclick: () => run(false) }, 'Try again')));
    } else if (state.result) {
      container.append(h('div', { class: 'ws-tr', lang: 'bg' }, state.result.translation));
      if (state.result.dictionaryTranslation && state.result.dictionaryTranslation !== state.result.translation) {
        container.append(h('div', { class: 'ws-dict', lang: 'bg' }, `${state.result.lemma}: ${state.result.dictionaryTranslation}`));
      }
      if (state.result.note) container.append(h('div', { class: 'ws-note', lang: 'bg' }, state.result.note));
    }

    container.append(h('div', { class: 'ws-block' },
      h('span', { class: 'ws-label' }, 'In the book'),
      h('div', { class: 'sentence', lang: 'en' }, markedSentence(req.sentence, req.word, req.offset)),
    ));
    const sentBlock = h('div', { class: 'ws-block' }, h('span', { class: 'ws-label' }, 'Sentence in Bulgarian'));
    if (state.loading) sentBlock.append(h('div', { class: 'skeleton' }), h('div', { class: 'skeleton', style: { width: '70%' } }));
    else if (state.result?.sentenceTranslation) sentBlock.append(h('div', { class: 'sentence-bg', lang: 'bg' }, state.result.sentenceTranslation));
    if (state.loading || state.result?.sentenceTranslation) container.append(sentBlock);

    if (entry) {
      container.append(h('div', { class: 'ws-provider' }, h('span', {}, `From ${entry.bookTitle || 'a book'} · saved ${new Date(entry.addedAt).toLocaleDateString()}`)));
      const del = h('button', { class: 'pill-btn secondary', style: { color: 'var(--danger)' } }, 'Delete word');
      del.onclick = async () => {
        if (await confirmSheet({ title: 'Delete word?', message: `“${entry.word}” and its review history will be removed.` })) {
          await vocab.remove(entry.id); sheet.close(); toast('Word deleted');
        }
      };
      container.append(h('div', { class: 'ws-actions' }, del));
      return;
    }

    if (state.result) {
      const existing = vocab.find(req.word, req.sentence);
      const saved = existing && existing.sentence === req.sentence;
      const save = h('button', { class: 'pill-btn', disabled: saved }, saved ? 'Saved to flashcards ✓' : 'Save to flashcards');
      save.onclick = async () => {
        save.disabled = true; save.textContent = 'Saving…';
        try {
          await vocab.add({
            word: req.word, lemma: state.result.lemma, partOfSpeech: state.result.partOfSpeech,
            translation: state.result.translation, dictionaryTranslation: state.result.dictionaryTranslation || '',
            note: state.result.note || '', sentence: req.sentence, offset: req.offset,
            sentenceTranslation: state.result.sentenceTranslation, bookId: req.bookId || '', bookTitle: req.bookTitle || '',
          });
          save.textContent = 'Saved to flashcards ✓';
          toast(`Saved “${req.word}”`);
        } catch (e) {
          console.error(e);
          save.disabled = false; save.textContent = 'Save to flashcards';
          toast(e?.code === 'quota_exceeded' ? 'Storage is full. Delete some words first.' : 'Couldn’t save the word. Try again.');
        }
      };
      container.append(h('div', { class: 'ws-actions' }, save));
      const foot = h('div', { class: 'ws-provider' }, h('span', {}, `${providerName(state.result.provider)}${state.result.cached ? ' · cached' : ''}`));
      if (state.result.provider === 'claude') {
        foot.append(h('button', { onclick: () => run(true) }, 'Check with a stronger model'));
      }
      container.append(foot);
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
      if (!sheet.closed) render({ error: e?.message || 'Translation failed.', result: null });
    }
  };

  if (entry) {
    render({ result: { ...entry, provider: null } });
  } else {
    run(false);
  }
  return sheet;
}

function providerName(id) {
  return { claude: 'Translated by Claude', deepl: 'Translated by DeepL', mock: 'Demo translation' }[id] || '';
}

export { currentProvider };
