import { h, clear, markedSentence, formatRelativeDue } from '../util.js';
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
  page.append(h('div', { class: 'nav-row' }), h('h1', { class: 'large-title' }, 'Flashcards'));
  if (!vocab.isReady) { page.append(h('p', { class: 'muted' }, vocab.error || 'Loading saved words…')); return; }
  const now = Date.now();
  const due = vocab.dueToday(now);
  const fresh = due.filter((e) => !e.srs?.lastReviewed).length;
  const later = vocab.all.filter((e) => !isDueToday(e.srs, now)).sort((a, b) => a.srs.due - b.srs.due);
  const learned = vocab.all.filter((e) => (e.srs?.repetitions || 0) >= 2).length;

  if (!vocab.all.length) {
    page.append(h('div', { class: 'empty' }, h('h3', {}, 'No cards yet'),
      h('p', {}, 'Words you save while reading become flashcards here. Each card shows the word in its original sentence.')));
    return;
  }
  const start = h('button', { class: 'pill-btn', disabled: !due.length }, due.length ? 'Start Review' : 'All caught up');
  start.onclick = () => { startSession(due); drawStudy(page); };
  page.append(h('section', { class: 'due-hero' },
    h('div', { class: 'due-num' }, String(due.length)),
    h('div', { class: 'due-label' }, `${due.length === 1 ? 'card' : 'cards'} due today`),
    h('div', { class: 'due-stats' },
      h('span', {}, `${fresh} new`), h('span', {}, `${due.length - fresh} to review`),
      h('span', {}, `${learned} learned`), h('span', {}, `${vocab.all.length} total`)),
    h('div', {}, start)));
  if (!due.length && later[0]) {
    page.append(h('p', { class: 'footnote' }, `Next card is due in ${formatRelativeDue(later[0].srs.due)}.`));
  }
}

function startSession(due) {
  const ordered = [...due].sort((a, b) => (a.srs?.due || 0) - (b.srs?.due || 0));
  session = { queue: ordered.map((e) => e.id), total: ordered.length, done: 0, flipped: false };
}

let keyHandler = null;
function onKey(e) { keyHandler?.(e); }

function drawStudy(page) {
  clear(page);
  document.removeEventListener('keydown', onKey);
  const entry = vocab.all.find((e) => e.id === session.queue[0]);
  if (!entry) {
    // Skip cards deleted meanwhile, or finish.
    if (session.queue.length) { session.queue.shift(); return drawStudy(page); }
    const reviewed = session.done;
    session = null;
    page.append(h('div', { class: 'nav-row' }), h('div', { class: 'empty' },
      h('h3', {}, 'Session complete'),
      h('p', {}, `You reviewed ${reviewed} ${reviewed === 1 ? 'card' : 'cards'}. Cards you found hard will come back sooner.`),
      h('button', { class: 'pill-btn', onclick: () => drawHome(page) }, 'Done')));
    return;
  }

  const quit = h('button', { class: 'text-btn', onclick: () => { session = null; drawHome(page); } }, 'End');
  const progress = Math.round((session.done / Math.max(1, session.done + session.queue.length)) * 100);
  const front = h('div', { class: 'face front' },
    h('div', { class: 'big', lang: 'en' }, entry.word),
    h('div', { class: 'sentence', lang: 'en' }, markedSentence(entry.sentence, entry.word, entry.offset)),
    h('div', { class: 'hint' }, 'Tap to show translation'));
  const back = h('div', { class: 'face back' },
    h('div', { class: 'tr', lang: 'bg' }, entry.translation),
    h('div', { class: 'pos' }, [entry.lemma && entry.lemma.toLowerCase() !== entry.word.toLowerCase() ? entry.lemma : '', entry.partOfSpeech].filter(Boolean).join(' · ')),
    h('div', { class: 'sentence', lang: 'en' }, markedSentence(entry.sentence, entry.word, entry.offset)),
    h('div', { class: 'sentence-bg', lang: 'bg' }, entry.sentenceTranslation || ''));
  const card = h('div', { class: `card${session.flipped ? ' flipped' : ''}`, role: 'button', tabindex: '0', 'aria-label': 'Flip card' }, front, back);
  const grades = h('div', { class: 'grades', hidden: !session.flipped });
  const flip = () => {
    if (session.flipped) return;
    session.flipped = true;
    card.classList.add('flipped');
    grades.hidden = false;
  };
  card.addEventListener('click', flip);

  const preview = previewIntervals(entry.srs);
  for (const [key, g] of Object.entries(GRADES)) {
    const b = h('button', { class: `grade ${key}` }, g.label, h('small', {}, formatRelativeDue(Date.now() + preview[key])));
    b.onclick = () => grade(key);
    grades.append(b);
  }
  const grade = async (key) => {
    const next = review(entry.srs, key);
    session.queue.shift();
    session.done += 1;
    if (key === 'again') session.queue.push(entry.id); // see it again this session
    session.flipped = false;
    vocab.updateReview(entry.id, next).catch((e) => console.error('review save failed', e));
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

  page.append(h('div', { class: 'nav-row' }), h('div', { class: 'study' },
    h('div', { class: 'study-top' }, h('span', {}, `${session.done} reviewed · ${session.queue.length} left`), quit),
    h('div', { class: 'study-bar' }, h('i', { style: { width: `${progress}%` } })),
    h('div', { class: 'card-scene' }, card),
    grades));
}
