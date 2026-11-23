import { h, clear, boldSentence, formatRelativeDue } from '../util.js';
import { vocab } from '../store/vocab.js';
import { review, previewIntervals, isDueToday, GRADES, startOfDay, DAY } from '../srs/sm2.js';

let session = null; // { queue: ids[], done, flipped, tally: {again, hard, good, easy} }
let summaryOpen = false; // keep the summary on screen while the last review saves

export function renderFlashcards(root) {
  const page = h('div', { class: 'page' });
  clear(root).append(page);
  const draw = () => (session ? drawStudy(page) : drawHome(page));
  summaryOpen = false;
  const off = vocab.onChange(() => { if (!session && !summaryOpen) draw(); });
  draw();
  return () => { off(); document.removeEventListener('keydown', onKey); document.body.classList.remove('studying'); };
}

/** Card number = order in which the word was saved (an index-card detail). */
function cardNumber(entry) {
  const sorted = [...vocab.all].sort((a, b) => a.addedAt - b.addedAt);
  return sorted.findIndex((e) => e.id === entry.id) + 1;
}

function cite(entry) {
  return entry.bookTitle ? h('span', { class: 'ic-cite' }, entry.bookTitle) : h('span');
}

function drawHome(page) {
  clear(page);
  document.body.classList.remove('studying');
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
  const top = due[0] || next || vocab.all[0];

  const fan = h('div', { class: 'fan', 'aria-hidden': 'true' },
    h('div', { class: 'index-card' }), h('div', { class: 'index-card' }),
    h('div', { class: 'index-card' },
      h('div', { class: 'ic-head' }, h('span', {}, due.length ? 'Up next' : 'Next'), h('span', { class: 'no' }, `No. ${cardNumber(top)}`)),
      h('div', { class: 'word', lang: 'en' }, top.word),
      cite(top)));

  const deck = h('section', { class: 'deck' }, fan,
    h('h2', {}, due.length ? `${due.length} ${due.length === 1 ? 'card' : 'cards'} due today` : 'You’re all caught up'),
    h('div', { class: 'figures' },
      h('div', {}, h('b', {}, String(fresh)), h('span', {}, 'New')),
      h('div', {}, h('b', {}, String(due.length - fresh)), h('span', {}, 'Review')),
      h('div', {}, h('b', {}, String(learned)), h('span', {}, 'Learned'))));
  if (due.length) {
    const start = h('button', { class: 'btn' }, 'Review Now');
    start.onclick = () => { session = { queue: due.map((e) => e.id), done: 0, flipped: false, tally: { again: 0, hard: 0, good: 0, easy: 0 } }; drawStudy(page); };
    deck.append(start);
  } else if (next) {
    deck.append(h('p', { class: 'later' }, `Next review in ${formatRelativeDue(next.srs.due)}`));
  }
  deck.append(weekForecast(now));
  page.append(deck);
}

function weekForecast(now) {
  const today = startOfDay(now);
  const counts = Array.from({ length: 7 }, (_, i) => vocab.all.filter((e) => {
    const d = startOfDay(e.srs?.due ?? now);
    return i === 0 ? d <= today : d === today + i * DAY;
  }).length);
  const max = Math.max(1, ...counts);
  const fmt = new Intl.DateTimeFormat(undefined, { weekday: 'narrow' });
  return h('div', { class: 'week', role: 'img', 'aria-label': `Cards due over the next 7 days: ${counts.join(', ')}` },
    h('span', { class: 'week-label' }, 'Coming up'),
    h('div', { class: 'week-bars' }, counts.map((c, i) => h('div', { class: i === 0 ? 'today' : '' },
      h('i', { style: { height: `${Math.round((c / max) * 44) + 3}px` } }),
      h('span', {}, fmt.format(new Date(today + i * DAY)))))));
}

/** A window of words around the target so long sentences fit on a card. */
function excerpt(entry, radius = 9) {
  const { sentence, word } = entry;
  let off = Number.isInteger(entry.offset) && sentence.substr(entry.offset, word.length) === word ? entry.offset : sentence.indexOf(word);
  if (off < 0) return { text: sentence, offset: undefined };
  const tokens = [...sentence.matchAll(/\S+/g)];
  const idx = tokens.findIndex((t) => off >= t.index && off < t.index + t[0].length);
  if (tokens.length <= radius * 2 + 4 || idx < 0) return { text: sentence, offset: off };
  const a = Math.max(0, idx - radius), b = Math.min(tokens.length, idx + radius + 1);
  const start = tokens[a].index, end = tokens[b - 1].index + tokens[b - 1][0].length;
  const pre = a > 0 ? '… ' : '';
  const text = pre + sentence.slice(start, end).replace(/[,;:]$/, '') + (b < tokens.length ? ' …' : '');
  return { text, offset: off - start + pre.length };
}

let keyHandler = null;
function onKey(e) { keyHandler?.(e); }

function drawSummary(page) {
  const t = session.tally;
  const reviewed = session.done;
  session = null;
  summaryOpen = true;
  document.body.classList.remove('studying');
  const rows = [['Again', t.again], ['Hard', t.hard], ['Good', t.good], ['Easy', t.easy]];
  page.append(h('div', { class: 'nav-row' }), h('section', { class: 'summary' },
    h('div', { class: 'index-card', 'aria-hidden': 'true' },
      h('div', { class: 'ic-head' }, h('span', {}, 'Today’s session'), h('span', { class: 'no' }, new Date().toLocaleDateString(undefined, { day: 'numeric', month: 'short' }))),
      h('div', { class: 'rows' }, rows.map(([k, v]) => h('div', {}, h('span', {}, k), h('b', {}, String(v)))))),
    h('h2', {}, 'Session Complete'),
    h('p', {}, `You reviewed ${reviewed} ${reviewed === 1 ? 'card' : 'cards'}. The ones you found hard will come back sooner.`),
    h('button', { class: 'btn', onclick: () => { summaryOpen = false; drawHome(page); } }, 'Done')));
}

function drawStudy(page) {
  clear(page);
  document.body.classList.add('studying');
  document.removeEventListener('keydown', onKey);
  const entry = vocab.all.find((e) => e.id === session.queue[0]);
  if (!entry) {
    if (session.queue.length) { session.queue.shift(); return drawStudy(page); }
    return drawSummary(page);
  }

  const remaining = session.queue.length;
  const progress = Math.round((session.done / Math.max(1, session.done + remaining)) * 100);
  const isNew = !entry.srs?.lastReviewed;
  const card = h('article', { class: 'card index-card', role: 'button', tabindex: '0', 'aria-label': 'Show answer' });
  const grades = h('div', { class: 'grades', role: 'group', 'aria-label': 'How well did you know it?', hidden: true });
  const hint = h('p', { class: 'grades-hint', hidden: true }, 'How well did you know it?');
  const ex = excerpt(entry);
  const head = (label) => h('div', { class: 'ic-head' }, h('span', {}, label), h('span', { class: 'no' }, `No. ${cardNumber(entry)}`));

  const front = () => {
    clear(card).append(
      head(isNew ? 'New word' : 'Review'),
      h('div', { class: 'card-body' },
        h('div', { class: 'word', lang: 'en' }, entry.word),
        h('div', { class: 'ornament', 'aria-hidden': 'true' }, '· · ·'),
        h('blockquote', { lang: 'en' }, boldSentence(ex.text, entry.word, ex.offset))),
      h('div', { class: 'card-foot' }, cite(entry), h('span', { class: 'tap' }, 'Tap to turn')));
  };
  const back = () => {
    const gram = [entry.partOfSpeech, entry.lemma && entry.lemma.toLowerCase() !== entry.word.toLowerCase() ? `from ${entry.lemma}` : ''].filter(Boolean).join(', ');
    clear(card).append(
      head(entry.word),
      h('div', { class: 'card-body' },
        h('div', { class: 'tr', lang: 'bg' }, entry.translation),
        gram ? h('div', { class: 'gram' }, gram) : null,
        h('div', { class: 'ornament', 'aria-hidden': 'true' }, '· · ·'),
        h('blockquote', { lang: 'en' }, boldSentence(ex.text, entry.word, ex.offset)),
        entry.sentenceTranslation ? h('div', { class: 'bg', lang: 'bg' }, entry.sentenceTranslation) : null),
      h('div', { class: 'card-foot' }, cite(entry), h('span')));
  };
  front();

  const flip = () => {
    if (session.flipped) return;
    session.flipped = true;
    card.style.animation = 'none';
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
      hint.hidden = false;
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
    session.tally[key] += 1;
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
  page.append(h('div', { class: 'study' },
    h('div', { class: 'study-top' }, h('span'), h('span', { class: 'count' }, `${session.done + 1} of ${session.done + remaining}`), end),
    h('div', { class: 'study-bar' }, h('i', { style: { width: `${progress}%` } })),
    h('div', { class: 'card-scene' }, card),
    hint, grades));
}
