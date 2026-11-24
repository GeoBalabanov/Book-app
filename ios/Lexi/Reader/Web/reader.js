// Paginated EPUB reader inside the WKWebView. Ported from web/js/reader/reader.js.
// One chapter is laid out at a time with CSS columns; each "page" is one
// viewport-wide step of the column strip (two columns on wide screens, e.g.
// iPad landscape). Native code drives it through window.Lexi and gets events
// through the "lexi" message handler.
(() => {
  'use strict';

  const root = document.getElementById('reader');
  const viewport = document.getElementById('viewport');
  const content = document.getElementById('content');

  const post = (msg) => { try { window.webkit.messageHandlers.lexi.postMessage(msg); } catch (e) { /* not in app */ } };
  window.addEventListener('error', (e) => post({ type: 'log', message: `${e.message} (${e.filename}:${e.lineno})` }));
  window.addEventListener('unhandledrejection', (e) => post({ type: 'log', message: `Unhandled: ${e.reason}` }));
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  const debounce = (fn, ms) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };

  const state = {
    base: '',          // URL prefix of the unzipped book, e.g. /book/<folder>/
    spine: [],         // chapter paths
    lengths: [],       // chapter text lengths, for whole-book progress
    total: 1,
    chapter: 0,
    page: 0,
    pages: 1,
    g: null,
    crossing: false,
  };

  // ---------- Paths & chapter rendering ----------

  function resolvePath(base, rel) {
    if (/^[a-z]+:/i.test(rel)) return rel;
    const [pathPart, frag] = rel.split('#');
    const parts = base ? base.split('/').slice(0, -1) : [];
    for (const seg of pathPart.split('/')) {
      if (seg === '..') parts.pop();
      else if (seg && seg !== '.') parts.push(seg);
    }
    let out = parts.join('/');
    try { out = decodeURIComponent(out); } catch (e) { /* keep raw */ }
    return frag !== undefined ? `${out}#${frag}` : out;
  }

  const fileURL = (path) => state.base + path.split('/').map(encodeURIComponent).join('/');

  function parseXhtml(text) {
    const strict = new DOMParser().parseFromString(text, 'application/xhtml+xml');
    if (!strict.getElementsByTagName('parsererror').length) return strict;
    return new DOMParser().parseFromString(text, 'text/html');
  }

  const BLOCKED_TAGS = new Set(['script', 'style', 'link', 'iframe', 'object', 'embed', 'form', 'input', 'button', 'textarea', 'select', 'meta', 'base', 'audio', 'video', 'source', 'noscript', 'head', 'title']);

  /** A sanitized, display-ready fragment for one spine item (same rules as the web parser). */
  async function renderChapter(index) {
    const href = state.spine[index];
    const res = await fetch(fileURL(href));
    if (!res.ok) throw new Error(`Missing ${href}`);
    const src = parseXhtml(await res.text());
    const body = src.getElementsByTagName('body')[0] || src.documentElement;
    const frag = document.createDocumentFragment();

    const copy = (node, parent) => {
      if (node.nodeType === 3) { parent.append(document.createTextNode(node.data)); return; }
      if (node.nodeType !== 1) return;
      const tag = node.localName.toLowerCase();
      if (BLOCKED_TAGS.has(tag)) return;
      const isSvg = node.namespaceURI === 'http://www.w3.org/2000/svg';
      const el = isSvg ? document.createElementNS('http://www.w3.org/2000/svg', node.localName) : document.createElement(tag === 'body' ? 'div' : tag);
      for (const attr of [...node.attributes]) {
        const name = attr.localName.toLowerCase();
        if (name.startsWith('on') || name === 'style' || name === 'srcset') continue;
        if (name === 'id') { el.setAttribute('id', `epub-${index}-${attr.value}`); continue; }
        if (name === 'class' && !isSvg) { el.setAttribute('class', attr.value); continue; }
        if (!isSvg && tag === 'a' && name === 'href') {
          el.setAttribute('data-href', attr.value.startsWith('#') ? `${href}${attr.value}` : resolvePath(href, attr.value));
          el.setAttribute('role', 'link');
          continue;
        }
        if ((tag === 'img' && name === 'src') || (isSvg && name === 'href' && node.localName === 'image')) {
          const url = fileURL(resolvePath(href, attr.value));
          if (isSvg) { el.setAttributeNS('http://www.w3.org/1999/xlink', 'href', url); el.setAttribute('href', url); } else el.setAttribute('src', url);
          continue;
        }
        if (['alt', 'title', 'colspan', 'rowspan', 'lang', 'dir'].includes(name) || isSvg) {
          try { el.setAttribute(attr.name.replace(/^xlink:/, ''), attr.value); } catch (e) { /* invalid attr name */ }
        }
      }
      for (const child of node.childNodes) copy(child, el);
      parent.append(el);
    };
    for (const child of body.childNodes) copy(child, frag);
    return frag;
  }

  // ---------- Theme & layout ----------

  function applyTheme(vars, textured) {
    for (const [k, v] of Object.entries(vars)) root.style.setProperty(k, v);
    document.documentElement.style.setProperty('--r-bg', vars['--r-bg']);
    root.classList.toggle('paper', !!textured);
    const wide = window.innerWidth >= 900;
    root.style.setProperty('--r-margin-x', wide ? 'max(56px, calc((100vw - 1180px) / 2))' : 'clamp(22px, 6.5vw, 44px)');
    root.style.setProperty('--r-margin-top', '58px');
    root.style.setProperty('--r-margin-bottom', '40px');
  }

  function geometry() {
    const W = viewport.clientWidth;
    const H = viewport.clientHeight;
    const cols = W >= 760 ? 2 : 1;
    const G = cols === 2 ? 64 : 48;
    const colW = (W - (cols - 1) * G) / cols;
    return { W, H, cols, G, colW, step: W + G };
  }

  function layout() {
    const g = geometry();
    state.g = g;
    const c = content.style;
    c.width = `${g.W}px`;
    c.columnWidth = `${g.colW}px`;
    c.columnGap = `${g.G}px`;
    c.columnCount = 'auto';
    root.style.setProperty('--r-page-h', `${g.H}px`);
    const ncols = Math.max(1, Math.round((content.scrollWidth + g.G) / (g.colW + g.G)));
    state.pages = Math.max(1, Math.ceil(ncols / g.cols));
  }

  /** The text position at the top of the current page, used to stay in place across relayouts. */
  function anchor() {
    const r = viewport.getBoundingClientRect();
    const x = r.left + 4, y = r.top + 4;
    const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT);
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
      if (!n.data.trim()) continue;
      const range = document.createRange();
      range.selectNodeContents(n);
      for (const rect of range.getClientRects()) {
        if (rect.right > x && rect.left < r.right && rect.bottom > y) {
          for (let i = 0; i < n.data.length; i += 8) {
            range.setStart(n, i); range.setEnd(n, Math.min(n.data.length, i + 1));
            const cr = range.getBoundingClientRect();
            if (cr.left >= r.left - 2 && cr.left < r.right) return { node: n, offset: i };
          }
          return { node: n, offset: 0 };
        }
      }
    }
    return null;
  }

  function pageOfAnchor(a) {
    if (!a || !a.node.isConnected) return null;
    const range = document.createRange();
    range.setStart(a.node, a.offset);
    range.setEnd(a.node, Math.min(a.node.data.length, a.offset + 1));
    return pageOfRect(range.getBoundingClientRect());
  }

  function pageOfRect(rect) {
    const base = content.getBoundingClientRect().left; // already translated
    const x = rect.left - base;
    return Math.max(0, Math.min(state.pages - 1, Math.floor((x + 1) / state.g.step)));
  }

  const relayout = debounce(() => {
    if (!state.g) return;
    const a = anchor();
    layout();
    const p = pageOfAnchor(a);
    goPage(p ?? Math.min(state.page, state.pages - 1), false);
  }, 120);

  // ---------- Chapters & pages ----------

  async function loadChapter(index, { fraction = 0, toEnd = false, fragment = null } = {}) {
    index = Math.max(0, Math.min(state.spine.length - 1, index));
    let frag;
    try {
      frag = await renderChapter(index);
    } catch (e) {
      frag = document.createElement('p');
      frag.textContent = 'This section could not be displayed.';
    }
    state.chapter = index;
    content.replaceChildren(frag);
    content.style.transform = 'translateX(0)';
    for (const img of content.querySelectorAll('img')) {
      if (!img.complete) img.addEventListener('load', relayout, { once: true });
    }
    layout();
    let page = toEnd ? state.pages - 1 : Math.floor(fraction * state.pages + 1e-6);
    if (fragment) {
      const el = content.querySelector(`[id="epub-${index}-${CSS.escape(fragment)}"]`);
      if (el) page = pageOfRect(el.getBoundingClientRect());
    }
    goPage(Math.max(0, Math.min(state.pages - 1, page)), false);
    post({ type: 'chapterLoaded', chapter: index });
  }

  function goPage(p, animate = true) {
    state.page = Math.max(0, Math.min(state.pages - 1, p));
    content.classList.toggle('animating', animate);
    content.style.transform = `translateX(${-state.page * state.g.step}px)`;
    reportLocation();
  }

  async function next() {
    if (state.page < state.pages - 1) return goPage(state.page + 1);
    if (state.chapter < state.spine.length - 1) return crossChapter(state.chapter + 1, false);
    bounce(-1);
  }

  async function prev() {
    if (state.page > 0) return goPage(state.page - 1);
    if (state.chapter > 0) return crossChapter(state.chapter - 1, true);
    bounce(1);
  }

  async function crossChapter(index, toEnd) {
    if (state.crossing) return;
    state.crossing = true;
    const dir = toEnd ? 1 : -1;
    const out = -state.page * state.g.step + dir * state.g.step;
    content.classList.add('animating');
    content.style.transform = `translateX(${out}px)`;
    await wait(200);
    await loadChapter(index, { toEnd });
    const target = -state.page * state.g.step;
    content.classList.remove('animating');
    content.style.transform = `translateX(${target - dir * state.g.step}px)`;
    content.getBoundingClientRect();
    content.classList.add('animating');
    content.style.transform = `translateX(${target}px)`;
    state.crossing = false;
  }

  function bounce(dir) {
    const base = -state.page * state.g.step;
    content.classList.add('animating');
    content.style.transform = `translateX(${base + dir * 30}px)`;
    setTimeout(() => { content.style.transform = `translateX(${base}px)`; }, 160);
  }

  function bookProgress() {
    const before = state.lengths.slice(0, state.chapter).reduce((a, b) => a + b, 0);
    const within = state.pages > 1 ? state.page / (state.pages - 1) : 1;
    return Math.min(1, (before + within * (state.lengths[state.chapter] || 0)) / state.total);
  }

  function locationFromProgress(p) {
    let acc = 0;
    const target = p * state.total;
    for (let i = 0; i < state.lengths.length; i++) {
      if (acc + state.lengths[i] >= target) return { chapter: i, fraction: (target - acc) / state.lengths[i] };
      acc += state.lengths[i];
    }
    return { chapter: state.lengths.length - 1, fraction: 0.999 };
  }

  function reportLocation() {
    post({
      type: 'location',
      chapter: state.chapter,
      page: state.page,
      pages: state.pages,
      fraction: state.pages > 0 ? state.page / state.pages : 0,
      progress: bookProgress(),
    });
  }

  // ---------- Input ----------

  // Touches are recognised natively (UIKit gesture recognizers on the web view)
  // and forwarded here, so WebKit's own selection and callouts never interfere.
  function bindEvents() {
    window.addEventListener('resize', relayout);
    document.fonts?.ready?.then(relayout);
  }

  const drag = { active: false };

  function dragStart() {
    if (state.crossing || !state.g) return;
    drag.active = true;
    content.classList.remove('animating');
  }

  function dragMove(dx) {
    if (!drag.active) return;
    let off = dx;
    const atStart = state.page === 0 && state.chapter === 0;
    const atEnd = state.page === state.pages - 1 && state.chapter === state.spine.length - 1;
    if ((off > 0 && atStart) || (off < 0 && atEnd)) off *= 0.3;
    content.style.transform = `translateX(${-state.page * state.g.step + off}px)`;
  }

  /** dx in points, vx in points per millisecond. */
  function dragEnd(dx, vx) {
    if (!drag.active) return;
    drag.active = false;
    const fast = Math.abs(vx) > 0.35;
    if (dx < -60 || (fast && dx < -20)) next();
    else if (dx > 60 || (fast && dx > 20)) prev();
    else goPage(state.page);
  }

  function tap(x, y) {
    if (state.crossing) return;
    const target = document.elementFromPoint(x, y);
    const link = target?.closest?.('[data-href]');
    if (link && content.contains(link)) { followLink(link.getAttribute('data-href')); return; }
    const w = window.innerWidth;
    if (x < w * 0.22) prev();
    else if (x > w * 0.78) next();
    else post({ type: 'toggleChrome' });
  }

  async function followLink(href) {
    if (/^https?:/i.test(href)) { post({ type: 'openURL', url: href }); return; }
    const [file, frag] = href.split('#');
    const idx = state.spine.indexOf(file);
    if (idx < 0) return;
    await loadChapter(idx, { fragment: frag || null });
  }

  // ---------- Native API ----------

  window.Lexi = {
    async open(cfg) {
      state.base = cfg.base;
      state.spine = cfg.spine;
      state.lengths = cfg.lengths;
      state.total = cfg.lengths.reduce((a, b) => a + b, 0) || 1;
      applyTheme(cfg.vars, cfg.textured);
      bindEvents();
      // The web view can start loading before it is on screen; wait for a real size
      // (and the reading font) so the saved position maps to the right page.
      for (let i = 0; i < 60 && viewport.clientWidth < 50; i++) await wait(50);
      try { await Promise.race([document.fonts.ready, wait(800)]); } catch (e) { /* ignore */ }
      await loadChapter(cfg.chapter || 0, { fraction: cfg.fraction || 0 });
      post({ type: 'ready' });
    },
    setTheme(vars, textured, layoutChange) {
      applyTheme(vars, textured);
      if (layoutChange) relayout();
    },
    goTo(chapter, fragment) { return loadChapter(chapter, { fragment: fragment || null }); },
    goToProgress(p) { const loc = locationFromProgress(p); return loadChapter(loc.chapter, { fraction: loc.fraction }); },
    locationLabel(p) { return locationFromProgress(p).chapter; },
    next, prev, tap, dragStart, dragMove, dragEnd,
  };

  post({ type: 'loaded' });
})();
