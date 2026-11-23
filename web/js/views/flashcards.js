import { h, clear, boldSentence, formatRelativeDue } from '../util.js';
import { vocab } from '../store/vocab.js';
import { review, previewIntervals, isDueToday, GRADES } from '../srs/sm2.js';

let session = null; // { queue: entryIds[], done: number, total: number, flipped: bool }

export function renderFlashcards(root) {
  const page = h('div', { class: 'page' });
  clear(root).append(page);
  const draw = () => (session ? drawStudy(page) : drawHome(page));
  const off = vocab.onChange(() => { if (!session) draw(); });
  draw();
  return () => { off(); document.removeEventListener('keydown', onKey); };
}

function drawHome(page) {
  clear(page);
  document.removeEventListener('keydown', onKey);
  page.append(h('div', { class: 'nav-row' }), h('h1', { class: 'large-title' }, 'Flashcards'));
  if (!vocab.isReady) { page.append(h('p', { class: 'muted' }, vocab.error || 'Loading saved words…')); return; }
  if (!vocab.all.length) {
    page.append(h('div', { class: 'empty' }, h('h3', {}, 'No Cards Yet'),
      h('p', {}, 'Words you save while reading become cards here, each shown in the sentence where you found it.')));
    return;
  }
  const now = Date.now();
  const due = vocab.dueToday(now).sort((a, b) => (a.srs?.due || 0) - (b.srs?.due || 0));
  const fresh = due.filter((e) => !e.srs?.lastReviewed).length;
  const learned = vocab.all.filter((e) => (e.srs?.repetitions || 0) >= 2).length;
  const next = vocab.all.filter((e) => !isDueToday(e.srs, now)).sort((a, b) => a.srs.due - b.srs.due)[0];

  const top = due[0] || next;
  const stack = h('div', { class: 'stack', 'aria-hidden': 'true' },
    h('div', { class: 'sheet-card' }), h('div', { class: 'sheet-card' }),
    h('div', { class: 'sheet-card' }, h('b', { lang: 'en' }, top.word)));

  const parts = [];
  if (fresh) parts.push(`${fresh} new`);
  if (due.length - fresh) parts.push(`${due.length - fresh} to review`);
  parts.push(`${learned} learned`);

  const deck = h('section', { class: 'deck' }, stack,
    h('h2', {}, due.length ? `${due.length} ${due.length === 1 ? 'card' : 'cards'} due today` : 'You’re all caught up'),
    h('p', {}, due.length ? parts.join(' · ') : next ? `Next review in ${formatRelativeDue(next.srs.due)}` : ''));
  if (due.length) {
    const start = h('button', { class: 'btn' }, 'Review Now');
    start.onclick = () => { startSession(due); drawStudy(page); };
    deck.append(start);
  }
  page.append(deck);
}

function startSession(due) {
  session = { queue: due.map((e) => e.id), total: due.length, done: 0, flipped: false };
}

let keyHandler = null;
function onKey(e) { keyHandler?.(e); }

function drawStudy(page) {
  clear(page);
  document.removeEventListener('keydown', onKey);
  const entry = vocab.all.find((e) => e.id === session.queue[0]);
  if (!entry) {
    if (session.queue.length) { session.queue.shift(); return drawStudy(page); }
    const reviewed = session.done;
    session = null;
    page.append(h('div', { class: 'nav-row' }), h('div', { class: 'empty' },
      h('h3', {}, 'Session Complete'),
      h('p', {}, `You reviewed ${reviewed} ${reviewed === 1 ? 'card' : 'cards'}. Cards you found hard will come back sooner.`),
      h('button', { class: 'btn', onclick: () => drawHome(page) }, 'Done')));
    return;
  }

  const remaining = session.queue.length;
  const progress = Math.round((session.done / Math.max(1, session.done + remaining)) * 100);
  const card = h('div', { class: 'card', role: 'button', tabindex: '0', 'aria-label': 'Show answer' });
  const grades = h('div', { class: 'grades', hidden: true });

  const front = () => {
    clear(card).append(
      h('div', { class: 'word', lang: 'en' }, entry.word),
      h('div', { class: 'sentence', lang: 'en' }, boldSentence(entry.sentence, entry.word, entry.offset)),
      h('div', { class: 'hint' }, 'Tap to show the translation'));
  };
  const back = () => {
    const gram = [entry.partOfSpeech, entry.lemma && entry.lemma.toLowerCase() !== entry.word.toLowerCase() ? `base form ${entry.lemma}` : ''].filter(Boolean).join(' · ');
    clear(card).append(
      h('div', { class: 'tr', lang: 'bg' }, entry.translation),
      gram ? h('div', { class: 'pos' }, `${entry.word} — ${gram}`) : h('div', { class: 'pos' }, entry.word),
      h('div', { class: 'rule' }),
      h('div', { class: 'sentence', lang: 'en' }, boldSentence(entry.sentence, entry.word, entry.offset)),
      entry.sentenceTranslation ? h('div', { class: 'sentence-bg', lang: 'bg' }, entry.sentenceTranslation) : null);
  };
  front();

  const flip = () => {
    if (session.flipped) return;
    session.flipped = true;
    card.classList.add('turning');
    setTimeout(() => {
      back();
      card.style.transition = 'none';
      card.style.transform = 'rotateY(-90deg)';
      card.classList.remove('turning');
      card.getBoundingClientRect();
      card.style.transition = 'transform .22s ease-out';
      card.style.transform = '';
      grades.hidden = false;
      card.setAttribute('aria-label', 'Answer');
    }, 200);
  };
  card.addEventListener('click', flip);

  const preview = previewIntervals(entry.srs);
  for (const [key, g] of Object.entries(GRADES)) {
    const b = h('button', { class: `grade ${key}` }, g.label, h('small', {}, formatRelativeDue(Date.now() + preview[key])));
    b.onclick = () => grade(key);
    grades.append(b);
  }
  const grade = (key) => {
    const nextState = review(entry.srs, key);
    session.queue.shift();
    session.done += 1;
    if (key === 'again') session.queue.push(entry.id);
    session.flipped = false;
    vocab.updateReview(entry.id, nextState).catch((e) => console.error('review save failed', e));
    drawStudy(page);
  };

  keyHandler = (e) => {
    if (e.target.closest?.('input, select, textarea')) return;
    if (!session.flipped && (e.key === ' ' || e.key === 'Enter')) { e.preventDefault(); flip(); return; }
    if (session.flipped) {
      const map = { 1: 'again', 2: 'hard', 3: 'good', 4: 'easy', ' ': 'good' };
      if (map[e.key]) { e.preventDefault(); grade(map[e.key]); }
    }
  };
  document.addEventListener('keydown', onKey);

  const end = h('button', { class: 'end', onclick: () => { session = null; drawHome(page); } }, 'Done');
  page.append(h('div', { class: 'nav-row' }), h('div', { class: 'study' },
    h('div', { class: 'study-top' }, h('span'), h('span', { class: 'count' }, `${session.done + 1} of ${session.done + remaining}`), end),
    h('div', { class: 'study-bar' }, h('i', { style: { width: `${progress}%` } })),
    h('div', { class: 'card-scene' }, card),
    grades));
}
