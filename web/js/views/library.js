import { h, clear, icons, toast } from '../util.js';
import { library } from '../store/library.js';
import { openReader } from '../reader/reader.js';
import { openSheet, confirmSheet } from '../ui/sheet.js';
import { openSettings } from './settings.js';

const coverUrls = new Map();
function coverUrl(book) {
  if (!book.cover) return null;
  if (!coverUrls.has(book.id)) coverUrls.set(book.id, URL.createObjectURL(book.cover));
  return coverUrls.get(book.id);
}

// Muted cloth colors for books without a cover image.
const CLOTH = ['#3b4a5a', '#5a3b3b', '#3f5446', '#4a4560', '#5b4a35', '#2f3a40'];
function cover(book) {
  const url = coverUrl(book);
  if (url) return h('div', { class: 'cover-slot' }, h('img', { src: url, alt: '', draggable: 'false' }));
  const color = CLOTH[[...book.id].reduce((a, c) => a + c.charCodeAt(0), 0) % CLOTH.length];
  return h('div', { class: 'cover-slot' }, h('div', { class: 'cover-gen', style: { '--gen': color } }, h('b', {}, book.title), h('span', {}, book.author || '')));
}

function statusOf(book) {
  if (!book.progress) return h('span', { class: 'status new' }, 'NEW');
  if (book.progress >= 0.995) return h('span', { class: 'status' }, 'Finished');
  return h('span', { class: 'status' }, `${Math.max(1, Math.round(book.progress * 100))}%`);
}

export async function renderLibrary(root) {
  const fileInput = h('input', { type: 'file', accept: '.epub,application/epub+zip', id: 'import-epub', class: 'sr-only', multiple: true });
  fileInput.addEventListener('change', async () => {
    const files = [...fileInput.files];
    fileInput.value = '';
    for (const f of files) {
      toast(`Importing ${f.name}…`, 4000);
      try {
        const meta = await library.addFromBlob(f);
        toast(`Added “${meta.title}”`);
      } catch (e) {
        console.error(e);
        toast(e.message || `${f.name} couldn’t be imported.`, 4000);
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
        h('button', { class: 'glyph-btn', 'aria-label': 'Import EPUB', title: 'Import EPUB', html: icons.plus, onclick: () => fileInput.click() }),
        h('button', { class: 'glyph-btn', 'aria-label': 'Settings', title: 'Settings', html: icons.gear, onclick: openSettings })),
      h('h1', { class: 'large-title' }, 'Library'),
    );

    if (!books.length) {
      page.append(h('div', { class: 'empty' },
        h('h3', {}, 'Your library is empty'),
        h('p', {}, 'Import an EPUB from Files to start reading.'),
        h('button', { class: 'btn', onclick: () => fileInput.click() }, 'Import EPUB')));
      return;
    }

    const current = books.find((b) => b.lastOpenedAt && b.progress < 0.995) || books[0];
    const started = !!current.lastOpenedAt;
    const pct = Math.round((current.progress || 0) * 100);
    page.append(
      h('div', { class: 'section-head' }, h('h2', {}, started ? 'Continue Reading' : 'Start Reading')),
      h('div', { class: 'hero' },
        h('button', { class: 'hero-open', onclick: () => openReader(current.id), 'aria-label': `Open ${current.title}` }, cover(current)),
        h('div', { class: 'hero-meta' },
          h('span', { class: 'eyebrow' }, started && current.chapterLabel ? current.chapterLabel : current.author || ''),
          h('h3', {}, current.title),
          started ? h('span', { class: 'author' }, current.author || '') : null,
          started ? h('div', { class: 'meter' }, h('div', { class: 'meter-track' }, h('i', { style: { width: `${Math.max(pct, 1)}%` } })), `${pct}%`) : null,
          h('button', { class: 'btn small', onclick: () => openReader(current.id) }, started ? 'Continue' : 'Read'))),
    );

    page.append(h('div', { class: 'section-head' }, h('h2', {}, 'All Books'), h('span', {}, `${books.length} ${books.length === 1 ? 'Book' : 'Books'}`)));
    const grid = h('div', { class: 'grid' });
    for (const b of books) {
      const more = h('button', { class: 'more-btn', 'aria-label': `More actions for ${b.title}`, html: icons.more });
      more.onclick = () => bookActions(b);
      grid.append(h('div', { class: 'book' },
        h('button', { class: 'book-open', onclick: () => openReader(b.id), 'aria-label': `Open ${b.title}` }, cover(b)),
        h('div', { class: 'book-foot' }, statusOf(b), more)));
    }
    page.append(grid);
    page.append(h('p', { class: 'footnote' }, 'Imported books are kept in this browser. Saved words follow your Claude account.'));
  };

  const off = library.onChange(draw);
  await draw();
  return () => off();
}

function bookActions(book) {
  const remove = h('button', { class: 'btn destructive block' }, 'Remove from Library');
  const read = h('button', { class: 'btn secondary block' }, book.progress ? 'Continue Reading' : 'Read');
  const sheet = openSheet({
    title: book.title,
    content: h('div', { class: 'confirm' },
      h('p', {}, [book.author, book.progress ? `${Math.round(book.progress * 100)}% read` : 'Not started'].filter(Boolean).join(' · ')),
      h('div', { class: 'row-btns' }, read, remove)),
  });
  read.onclick = () => { sheet.close(); openReader(book.id); };
  remove.onclick = async () => {
    sheet.close();
    if (await confirmSheet({ title: 'Remove Book?', message: `“${book.title}” will be removed from this browser. Words you saved from it stay in Vocabulary.`, confirmLabel: 'Remove' })) {
      await library.remove(book.id);
      toast('Book removed');
    }
  };
}
