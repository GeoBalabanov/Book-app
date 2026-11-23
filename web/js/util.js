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
  close: '<svg viewBox="0 0 12 12"><path d="M2 2l8 8M10 2l-8 8" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
  back: '<svg viewBox="0 0 20 20"><path d="M12.5 3.5L6 10l6.5 6.5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  list: '<svg viewBox="0 0 20 20"><path d="M7 5h10M7 10h10M7 15h10" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><circle cx="3.5" cy="5" r="1.2" fill="currentColor"/><circle cx="3.5" cy="10" r="1.2" fill="currentColor"/><circle cx="3.5" cy="15" r="1.2" fill="currentColor"/></svg>',
  plus: '<svg viewBox="0 0 20 20"><path d="M10 4v12M4 10h12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
  gear: '<svg viewBox="0 0 20 20"><circle cx="10" cy="10" r="2.6" fill="none" stroke="currentColor" stroke-width="1.7"/><path d="M10 2.5v2M10 15.5v2M2.5 10h2M15.5 10h2M4.7 4.7l1.4 1.4M13.9 13.9l1.4 1.4M4.7 15.3l1.4-1.4M13.9 6.1l1.4-1.4" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>',
  more: '<svg viewBox="0 0 20 6" width="18" height="6"><circle cx="3" cy="3" r="2" fill="currentColor"/><circle cx="10" cy="3" r="2" fill="currentColor"/><circle cx="17" cy="3" r="2" fill="currentColor"/></svg>',
  search: '<svg viewBox="0 0 18 18"><circle cx="7.5" cy="7.5" r="5.5" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M11.6 11.6L16 16" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
  sunSmall: '<svg viewBox="0 0 20 20"><circle cx="10" cy="10" r="3" fill="currentColor"/><path d="M10 3v1.5M10 15.5V17M3 10h1.5M15.5 10H17" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>',
  sunLarge: '<svg viewBox="0 0 20 20"><circle cx="10" cy="10" r="4" fill="currentColor"/><path d="M10 1.5v2.5M10 16v2.5M1.5 10H4M16 10h2.5M4 4l1.8 1.8M14.2 14.2L16 16M4 16l1.8-1.8M14.2 5.8L16 4" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
  book: '<svg viewBox="0 0 40 40"><path d="M8 8h10a4 4 0 0 1 4 4v20a3 3 0 0 0-3-3H8zM32 8H22a4 4 0 0 0-4 4" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linejoin="round"/><path d="M28 22v10M23 27h10" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg>',
};
