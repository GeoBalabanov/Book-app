import { h, clear, icons, toast } from '../util.js';
import { library } from '../store/library.js';
import { openReader } from '../reader/reader.js';
import { openSheet, confirmSheet } from '../ui/sheet.js';
import { openSettings } from './settings.js';

const coverUrls = new Map();
function coverUrl(book) {
  if (!book.cover) return null;
  const k = book.id;
  if (!coverUrls.has(k)) coverUrls.set(k, URL.createObjectURL(book.cover));
  return coverUrls.get(k);
}

const PALETTE = ['#7a3b2e', '#2f4858', '#5b4b8a', '#33673b', '#8a5a19', '#1f4e79', '#6d2e46'];
function cover(book) {
  const url = coverUrl(book);
  if (url) return h('div', { class: 'cover' }, h('img', { src: url, alt: '', loading: 'lazy', draggable: 'false' }));
  const color = PALETTE[[...book.id].reduce((a, c) => a + c.charCodeAt(0), 0) % PALETTE.length];
  return h('div', { class: 'cover generated', style: { background: `linear-gradient(160deg, ${color}, #111)` } },
    h('b', {}, book.title), h('span', {}, book.author || ''));
}

function statusText(book) {
  if (!book.progress) return { text: 'NEW', cls: 'status new' };
  if (book.progress >= 0.995) return { text: 'Finished', cls: 'status' };
  return { text: `${Math.max(1, Math.round(book.progress * 100))}%`, cls: 'status' };
}

export async function renderLibrary(root) {
  const fileInput = h('input', { type: 'file', accept: '.epub,application/epub+zip', id: 'import-epub', class: 'sr-only', multiple: true });
  fileInput.addEventListener('change', async () => {
    const files = [...fileInput.files];
    fileInput.value = '';
    for (const f of files) {
      toast(`Importing “${f.name}”…`, 4000);
      try {
        const meta = await library.addFromBlob(f);
        toast(`Added “${meta.title}”`);
      } catch (e) {
        console.error(e);
        toast(e.message || `“${f.name}” couldn’t be imported.`, 4000);
      }
    }
  });

  const page = h('div', { class: 'page' });
  clear(root).append(page, fileInput);

  const draw = async () => {
    const books = await library.list();
    clear(page);
    page.append(
      h('div', { class: 'nav-row' },
        h('button', { class: 'icon-btn', 'aria-label': 'Settings', html: icons.gear, onclick: openSettings }),
        h('button', { class: 'icon-btn', 'aria-label': 'Import EPUB', html: icons.plus, onclick: () => fileInput.click() })),
      h('h1', { class: 'large-title' }, 'Library'),
    );

    const current = books.find((b) => b.lastOpenedAt && b.progress < 0.995) || books[0];
    if (current) {
      const pct = Math.round((current.progress || 0) * 100);
      page.append(
        h('h2', { class: 'section-title' }, current.lastOpenedAt ? 'Continue Reading' : 'Start Reading'),
        h('button', { class: 'continue', onclick: () => openReader(current.id), 'aria-label': `Open ${current.title}` },
          cover(current),
          h('div', { class: 'continue-meta' },
            h('span', { class: 'kicker' }, current.lastOpenedAt ? `${pct}% read` : 'Sample book'),
            h('h3', {}, current.title),
            h('span', { class: 'author' }, current.author || ''),
            h('div', { class: 'progress-line' }, h('div', { class: 'progress-track' }, h('i', { style: { width: `${pct}%` } })), `${pct}%`),
          )),
      );
    }

    page.append(h('h2', { class: 'section-title' }, 'All Books', h('small', {}, `${books.length} ${books.length === 1 ? 'book' : 'books'}`)));
    const grid = h('div', { class: 'grid' });
    for (const b of books) {
      const st = statusText(b);
      const more = h('button', { class: 'more-btn', 'aria-label': `More actions for ${b.title}`, html: icons.more });
      more.onclick = () => bookActions(b);
      grid.append(h('div', { class: 'book' },
        h('button', { class: 'book-open', onclick: () => openReader(b.id), 'aria-label': `Open ${b.title}` }, cover(b), h('span', { class: 'book-title-sm' }, b.title)),
        h('div', { class: 'book-foot' }, h('span', { class: st.cls }, st.text), more)));
    }
    grid.append(h('button', { class: 'import-tile', onclick: () => fileInput.click() }, h('span', { html: icons.book }), 'Import EPUB'));
    page.append(grid);
    page.append(h('p', { class: 'footnote' }, 'Books you import are stored in this browser only. Your saved words sync with your Claude account when the app runs inside Claude.'));
  };

  const off = library.onChange(draw);
  await draw();
  return () => off();
}

function bookActions(book) {
  const remove = h('button', { class: 'pill-btn secondary', style: { color: 'var(--danger)', width: '100%' } }, 'Remove from Library');
  const sheet = openSheet({
    title: book.title,
    content: h('div', { class: 'confirm' },
      h('p', {}, [book.author, book.progress ? `${Math.round(book.progress * 100)}% read` : 'Not started'].filter(Boolean).join(' · ')),
      remove),
  });
  remove.onclick = async () => {
    sheet.close();
    if (await confirmSheet({ title: 'Remove book?', message: `“${book.title}” will be removed from this browser. Saved words from it stay in your vocabulary.`, confirmLabel: 'Remove' })) {
      await library.remove(book.id);
      toast('Book removed');
    }
  };
}
