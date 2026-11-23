// Small DOM and data helpers shared across the app.

/** Create an element. Text children are set as text nodes, never as HTML. */
export function h(tag, props = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(props || {})) {
    if (v == null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
    else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2).toLowerCase(), v);
    else if (k === 'html') el.innerHTML = v; // only ever used with static, trusted markup (icons)
    else if (v === true) el.setAttribute(k, '');
    else el.setAttribute(k, String(v));
  }
  append(el, children);
  return el;
}

function append(el, children) {
  for (const c of children.flat(Infinity)) {
    if (c == null || c === false) continue;
    el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
}

export function clear(el) { while (el.firstChild) el.firstChild.remove(); return el; }

export function uid(prefix = '') {
  const r = crypto.getRandomValues(new Uint32Array(2));
  return prefix + Date.now().toString(36) + r[0].toString(36) + r[1].toString(36).slice(0, 4);
}

/** 53-bit FNV-1a style hash → base36 string. Stable across sessions; used for cache keys. */
export function hashString(str) {
  let h1 = 0xdeadbeef ^ str.length, h2 = 0x41c6ce57 ^ str.length;
  for (let i = 0; i < str.length; i++) {
    const ch = str.charCodeAt(i);
    h1 = Math.imul(h1 ^ ch, 2654435761);
    h2 = Math.imul(h2 ^ ch, 1597334677);
  }
  h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
  h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
  return (4294967296 * (2097151 & h2) + (h1 >>> 0)).toString(36);
}

export function debounce(fn, ms) {
  let t;
  const d = (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms); };
  d.flush = (...args) => { clearTimeout(t); fn(...args); };
  d.cancel = () => clearTimeout(t);
  return d;
}

export const storage = {
  get(key, fallback) {
    try { const v = localStorage.getItem(key); return v == null ? fallback : JSON.parse(v); } catch { return fallback; }
  },
  set(key, value) {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* private mode etc. */ }
  },
};

let toastTimer;
export function toast(message, ms = 2200) {
  const el = document.getElementById('toast');
  if (!el) return;
  el.textContent = message;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, ms);
}

/** Render a sentence with the word at `offset` wrapped in <mark>. */
export function markedSentence(sentence, word, offset) {
  const frag = document.createDocumentFragment();
  let i = Number.isInteger(offset) && sentence.substr(offset, word.length) === word ? offset : -1;
  if (i < 0) {
    const m = new RegExp(`(^|[^\\p{L}])(${escapeRegExp(word)})(?![\\p{L}])`, 'iu').exec(sentence);
    i = m ? m.index + m[1].length : -1;
  }
  if (i < 0) { frag.append(sentence); return frag; }
  frag.append(sentence.slice(0, i), h('mark', {}, sentence.slice(i, i + word.length)), sentence.slice(i + word.length));
  return frag;
}

export function escapeRegExp(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }

export function formatRelativeDue(due, now = Date.now()) {
  const ms = due - now;
  if (ms <= 0) return 'due';
  const min = ms / 60000;
  if (min < 60) return `${Math.max(1, Math.round(min))}m`;
  const hrs = min / 60;
  if (hrs < 24) return `${Math.round(hrs)}h`;
  const days = hrs / 24;
  if (days < 30) return `${Math.round(days)}d`;
  const months = days / 30;
  if (months < 12) return `${Math.round(months)}mo`;
  return `${(days / 365).toFixed(1)}y`;
}

export const icons = {
  close: '<svg viewBox="0 0 12 12"><path d="M2 2l8 8M10 2l-8 8" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
  back: '<svg viewBox="0 0 20 20"><path d="M12.5 3.5L6 10l6.5 6.5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  menu: '<svg viewBox="0 0 20 20"><path d="M7 5.5h10M7 10h10M7 14.5h10" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><circle cx="3.4" cy="5.5" r="1.25" fill="currentColor"/><circle cx="3.4" cy="10" r="1.25" fill="currentColor"/><circle cx="3.4" cy="14.5" r="1.25" fill="currentColor"/></svg>',
  list: '<svg viewBox="0 0 20 20"><path d="M7 5.5h10M7 10h10M7 14.5h10" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><circle cx="3.4" cy="5.5" r="1.2" fill="currentColor"/><circle cx="3.4" cy="10" r="1.2" fill="currentColor"/><circle cx="3.4" cy="14.5" r="1.2" fill="currentColor"/></svg>',
  textformat: '<svg viewBox="0 0 22 20"><path d="M1.5 16l4.5-12 4.5 12M3.1 12h5.8" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/><path d="M19.5 9.2v6.8M19.5 12.6c0-2-1.3-3.4-3.1-3.4s-3.1 1.5-3.1 3.5 1.3 3.5 3.1 3.5 3.1-1.4 3.1-3.6z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
  sliders: '<svg viewBox="0 0 20 20"><path d="M3 6h8M15 6h2M3 14h2M9 14h8" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><circle cx="13" cy="6" r="2" fill="none" stroke="currentColor" stroke-width="1.7"/><circle cx="7" cy="14" r="2" fill="none" stroke="currentColor" stroke-width="1.7"/></svg>',
  moon: '<svg viewBox="0 0 20 20"><path d="M16.5 12.3A7 7 0 0 1 7.7 3.5a7 7 0 1 0 8.8 8.8z" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/></svg>',
  sun: '<svg viewBox="0 0 20 20"><circle cx="10" cy="10" r="3.3" fill="none" stroke="currentColor" stroke-width="1.7"/><path d="M10 1.8v2M10 16.2v2M1.8 10h2M16.2 10h2M4.2 4.2l1.4 1.4M14.4 14.4l1.4 1.4M4.2 15.8l1.4-1.4M14.4 5.6l1.4-1.4" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>',
  auto: '<svg viewBox="0 0 20 20"><circle cx="10" cy="10" r="7.2" fill="none" stroke="currentColor" stroke-width="1.7"/><path d="M10 2.8a7.2 7.2 0 0 1 0 14.4z" fill="currentColor"/></svg>',
  plus: '<svg viewBox="0 0 20 20"><path d="M10 3.5v13M3.5 10h13" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></svg>',
  gear: '<svg viewBox="0 0 20 20"><circle cx="10" cy="10" r="7.3" fill="none" stroke="currentColor" stroke-width="1.7"/><circle cx="6.3" cy="10" r="1.15" fill="currentColor"/><circle cx="10" cy="10" r="1.15" fill="currentColor"/><circle cx="13.7" cy="10" r="1.15" fill="currentColor"/></svg>',
  more: '<svg viewBox="0 0 20 6" width="17" height="5"><circle cx="3" cy="3" r="1.9" fill="currentColor"/><circle cx="10" cy="3" r="1.9" fill="currentColor"/><circle cx="17" cy="3" r="1.9" fill="currentColor"/></svg>',
  search: '<svg viewBox="0 0 18 18"><circle cx="7.5" cy="7.5" r="5.5" fill="none" stroke="currentColor" stroke-width="1.9"/><path d="M11.6 11.6L16 16" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/></svg>',
  sunSmall: '<svg viewBox="0 0 20 20"><circle cx="10" cy="10" r="2.6" fill="currentColor"/><path d="M10 4v1.2M10 14.8V16M4 10h1.2M14.8 10H16" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>',
  sunLarge: '<svg viewBox="0 0 20 20"><circle cx="10" cy="10" r="3.6" fill="currentColor"/><path d="M10 1.5v2.3M10 16.2v2.3M1.5 10h2.3M16.2 10h2.3M4 4l1.6 1.6M14.4 14.4L16 16M4 16l1.6-1.6M14.4 5.6L16 4" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
};

/** Sentence with the word at `offset` wrapped in <b> (used in lists and cards). */
export function boldSentence(sentence, word, offset) {
  const frag = markedSentence(sentence, word, offset);
  const m = frag.querySelector?.('mark');
  if (m) { const b = document.createElement('b'); b.textContent = m.textContent; m.replaceWith(b); }
  return frag;
}
