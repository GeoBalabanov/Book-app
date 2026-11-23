import { library } from './store/library.js';
import { vocab } from './store/vocab.js';
import { renderLibrary } from './views/library.js';
import { renderVocabulary } from './views/vocabulary.js';
import { renderFlashcards } from './views/flashcards.js';

const TABS = { library: renderLibrary, vocabulary: renderVocabulary, flashcards: renderFlashcards };
const root = document.getElementById('tab-root');
let cleanup = null;
let currentTab = null;

function tabFromHash() {
  const t = location.hash.replace('#', '');
  return TABS[t] ? t : 'library';
}

async function show(tab) {
  if (tab === currentTab) return;
  currentTab = tab;
  cleanup?.();
  cleanup = null;
  for (const a of document.querySelectorAll('.tab')) {
    if (a.dataset.tab === tab) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current');
  }
  root.scrollTop = 0;
  cleanup = await TABS[tab](root);
}

function updateBadge() {
  const n = vocab.isReady ? vocab.dueToday().length : 0;
  const b = document.getElementById('due-badge');
  b.textContent = n > 99 ? '99+' : String(n);
  b.hidden = n === 0;
}

window.addEventListener('hashchange', () => show(tabFromHash()));
document.getElementById('tabbar').addEventListener('click', (e) => {
  const a = e.target.closest('.tab');
  if (!a) return;
  e.preventDefault();
  const tab = a.dataset.tab;
  try { history.replaceState(null, '', `#${tab}`); } catch { /* sandboxed */ }
  show(tab);
});
vocab.onChange(updateBadge);
setInterval(updateBadge, 60 * 1000);

await library.ensureSample();
await show(tabFromHash());
