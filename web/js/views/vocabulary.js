import { h, clear, icons, boldSentence, toast } from '../util.js';
import { vocab } from '../store/vocab.js';
import { openWordSheet } from '../ui/word-sheet.js';

const state = { query: '', book: '' };

export function renderVocabulary(root) {
  const page = h('div', { class: 'page' });
  clear(root).append(page);

  const search = h('input', { type: 'search', id: 'vocab-search', placeholder: 'Search', 'aria-label': 'Search vocabulary', value: state.query, autocomplete: 'off', autocapitalize: 'off', spellcheck: 'false' });
  const bookSel = h('select', { class: 'menu-select', id: 'vocab-book', 'aria-label': 'Filter by book' });
  const caption = h('span', { class: 'list-caption' });
  const listWrap = h('div');
  page.append(
    h('div', { class: 'nav-row' }),
    h('h1', { class: 'large-title' }, 'Vocabulary'),
    h('label', { class: 'search' }, h('span', { html: icons.search }), search),
    h('div', { class: 'filter-row' }, caption, bookSel),
    listWrap,
  );
  search.addEventListener('input', () => { state.query = search.value; drawList(); });
  bookSel.addEventListener('change', () => { state.book = bookSel.value; drawList(); });

  const drawFilter = () => {
    const books = [...new Set(vocab.all.map((e) => e.bookTitle).filter(Boolean))].sort();
    if (state.book && !books.includes(state.book)) state.book = '';
    clear(bookSel).append(h('option', { value: '' }, 'All Books'), ...books.map((b) => h('option', { value: b, selected: b === state.book }, b)));
    bookSel.hidden = books.length < 2;
  };

  const drawList = () => {
    clear(listWrap);
    caption.textContent = '';
    if (!vocab.isReady) { listWrap.append(h('p', { class: 'muted' }, vocab.error || 'Loading saved words…')); return; }
    if (vocab.error) listWrap.append(h('p', { class: 'error-box' }, vocab.error));
    const q = state.query.trim().toLowerCase();
    const items = vocab.all.filter((e) => (!state.book || e.bookTitle === state.book)
      && (!q || [e.word, e.lemma, e.translation, e.dictionaryTranslation].some((s) => s?.toLowerCase().includes(q))));
    if (!vocab.all.length) {
      listWrap.append(h('div', { class: 'empty' },
        h('h3', {}, 'No Saved Words'),
        h('p', {}, 'While reading, touch and hold a word to look it up, then tap Save to Flashcards.')));
      return;
    }
    caption.textContent = items.length === vocab.all.length ? `${items.length} ${items.length === 1 ? 'Word' : 'Words'}` : `${items.length} of ${vocab.all.length} Words`;
    if (!items.length) { listWrap.append(h('div', { class: 'empty' }, h('p', {}, `No results for “${state.query}”`))); return; }
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
  const main = h('div', { class: 'row-main', role: 'button', tabindex: '0', 'aria-label': `${e.word}: ${e.translation}` },
    h('div', { class: 'row-line' }, h('span', { class: 'row-word', lang: 'en' }, e.word), h('span', { class: 'row-tr', lang: 'bg' }, e.translation)),
    h('div', { class: 'row-sentence', lang: 'en' }, boldSentence(e.sentence, e.word, e.offset)),
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
