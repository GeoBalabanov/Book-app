import { h, clear, icons, markedSentence, formatRelativeDue, toast } from '../util.js';
import { vocab } from '../store/vocab.js';
import { openWordSheet } from '../ui/word-sheet.js';

const state = { query: '', book: '' };

export function renderVocabulary(root) {
  const page = h('div', { class: 'page' });
  clear(root).append(page);

  const search = h('input', { type: 'search', id: 'vocab-search', placeholder: 'Search words or translations', 'aria-label': 'Search vocabulary', value: state.query, autocomplete: 'off', autocapitalize: 'off', spellcheck: 'false' });
  const bookSel = h('select', { class: 'select', id: 'vocab-book', 'aria-label': 'Filter by book' });
  const listWrap = h('div');
  page.append(
    h('div', { class: 'nav-row' }),
    h('h1', { class: 'large-title' }, 'Vocabulary'),
    h('div', { class: 'toolbar' }, h('label', { class: 'search' }, h('span', { html: icons.search }), search), bookSel),
    listWrap,
  );
  search.addEventListener('input', () => { state.query = search.value; drawList(); });
  bookSel.addEventListener('change', () => { state.book = bookSel.value; drawList(); });

  const drawFilter = () => {
    const books = [...new Set(vocab.all.map((e) => e.bookTitle).filter(Boolean))].sort();
    if (state.book && !books.includes(state.book)) state.book = '';
    clear(bookSel).append(h('option', { value: '' }, 'All Books'), ...books.map((b) => h('option', { value: b, selected: b === state.book }, b)));
    bookSel.hidden = books.length < 1;
  };

  const drawList = () => {
    clear(listWrap);
    if (!vocab.isReady) { listWrap.append(h('p', { class: 'muted' }, vocab.error || 'Loading saved words…')); return; }
    if (vocab.error) listWrap.append(h('p', { class: 'error-box' }, vocab.error));
    const q = state.query.trim().toLowerCase();
    const items = vocab.all.filter((e) => (!state.book || e.bookTitle === state.book)
      && (!q || [e.word, e.lemma, e.translation, e.dictionaryTranslation].some((s) => s?.toLowerCase().includes(q))));
    if (!vocab.all.length) {
      listWrap.append(h('div', { class: 'empty' },
        h('h3', {}, 'No saved words yet'),
        h('p', {}, 'While reading, press and hold a word (or double-click it) to translate it, then tap “Save to flashcards”.')));
      return;
    }
    listWrap.append(h('p', { class: 'count-note' }, items.length === vocab.all.length ? `${items.length} ${items.length === 1 ? 'word' : 'words'}` : `${items.length} of ${vocab.all.length} words`));
    if (!items.length) { listWrap.append(h('div', { class: 'empty' }, h('p', {}, `No words match “${state.query}”.`))); return; }
    const ul = h('ul', { class: 'list' });
    for (const e of items) ul.append(row(e));
    listWrap.append(ul);
  };

  const draw = () => { drawFilter(); drawList(); };
  const off = vocab.onChange(draw);
  draw();
  return () => off();
}

function row(e) {
  const del = h('button', { class: 'row-delete', 'aria-label': `Delete ${e.word}`, tabindex: '-1' }, 'Delete');
  const due = e.srs?.due ? formatRelativeDue(e.srs.due) : '';
  const main = h('div', { class: 'row-main', role: 'button', tabindex: '0', 'aria-label': `${e.word}: ${e.translation}` },
    h('div', { class: 'row-head' }, h('span', { class: 'row-word', lang: 'en' }, e.word), h('span', { class: 'row-tr', lang: 'bg' }, e.translation),
      due ? h('span', { class: 'row-due', title: 'Next review' }, due === 'due' ? 'Due' : `in ${due}`) : null),
    h('div', { class: 'row-sentence', lang: 'en' }, markedSentence(e.sentence, e.word, e.offset)),
    e.bookTitle ? h('div', { class: 'row-meta' }, e.bookTitle) : null,
  );
  const li = h('li', { class: 'row' }, del, main);

  // Swipe left to reveal Delete; a long swipe deletes straight away.
  let sx = null, sy = null, dx = 0, open = false, horizontal = null;
  const setX = (x, anim) => { main.style.transition = anim ? '' : 'none'; main.style.transform = x ? `translateX(${x}px)` : ''; };
  main.addEventListener('pointerdown', (ev) => { if (ev.pointerType === 'mouse') return; sx = ev.clientX; sy = ev.clientY; dx = 0; horizontal = null; });
  main.addEventListener('pointermove', (ev) => {
    if (sx == null) return;
    const mx = ev.clientX - sx, my = ev.clientY - sy;
    if (horizontal == null && Math.hypot(mx, my) > 8) horizontal = Math.abs(mx) > Math.abs(my);
    if (!horizontal) return;
    dx = Math.min(0, (open ? -88 : 0) + mx);
    setX(dx, false);
  });
  const end = () => {
    if (sx == null) return;
    sx = null;
    if (!horizontal) return;
    if (dx < -220) { remove(); return; }
    open = dx < -44;
    setX(open ? -88 : 0, true);
  };
  main.addEventListener('pointerup', end);
  main.addEventListener('pointercancel', end);
  main.addEventListener('click', () => {
    if (horizontal) { horizontal = null; return; }
    if (open) { open = false; setX(0, true); return; }
    openWordSheet({ word: e.word, sentence: e.sentence, offset: e.offset, bookTitle: e.bookTitle }, { entry: e });
  });
  main.addEventListener('keydown', (ev) => {
    if (ev.key === 'Enter') main.click();
    if (ev.key === 'Delete' || ev.key === 'Backspace') remove();
  });
  const remove = async () => {
    li.style.transition = 'opacity .2s'; li.style.opacity = '0';
    await vocab.remove(e.id);
    toast(`Deleted “${e.word}”`);
  };
  del.addEventListener('click', remove);
  return li;
}
