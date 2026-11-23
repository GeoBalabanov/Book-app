// Paginated EPUB reader. One chapter is laid out at a time with CSS columns;
// each "page" is one viewport-wide step of the column strip (two columns side
// by side on wide screens, like Apple Books in landscape).

import { h, clear, debounce, icons, toast } from '../util.js';
import { library } from '../store/library.js';
import { vocab } from '../store/vocab.js';
import { readerSettings, themeVars, THEMES, FONTS, isDark } from './themes.js';
import { wordAtPoint, setLookupHighlight, underlineSaved } from './selection.js';
import { openSheet, hasOpenSheet, closeTopSheet } from '../ui/sheet.js';
import { openWordSheet } from '../ui/word-sheet.js';

const LONG_PRESS_MS = 430;

let active = null;

export async function openReader(bookId, { onClose } = {}) {
  if (active) await active.close();
  const meta = await library.get(bookId);
  if (!meta) { toast('That book is no longer in your library.'); return; }
  const r = new Reader(meta, onClose);
  active = r;
  await r.start();
}

class Reader {
  constructor(meta, onClose) {
    this.meta = meta;
    this.onCloseCb = onClose;
    this.chapter = 0;
    this.page = 0;
    this.pages = 1;
    this.chromeVisible = true;
    this.unsubs = [];
    this.buildDom();
  }

  buildDom() {
    this.content = h('div', { class: 'reader-content', lang: 'en' });
    this.viewport = h('div', { class: 'reader-viewport' }, this.content);
    this.loading = h('div', { class: 'reader-loading' }, 'Opening book…');
    this.dim = h('div', { class: 'reader-dim' });
    this.titleEl = h('div', { class: 'reader-title' }, this.meta.title);
    const close = h('button', { class: 'r-round', 'aria-label': 'Back to Library', html: icons.close, onclick: () => this.close() });
    this.top = h('div', { class: 'reader-top' }, close, this.titleEl, h('span'));
    this.scrub = h('input', { type: 'range', min: '0', max: '1000', step: '1', id: 'reader-scrub', 'aria-label': 'Book position' });
    this.pageInfo = h('div', { class: 'page-info' });
    this.bottom = h('div', { class: 'reader-bottom' }, h('div', { class: 'scrub' }, this.scrub), this.pageInfo);
    this.menuBtn = h('button', { class: 'r-round', 'aria-label': 'Reading menu', 'aria-expanded': 'false', html: icons.menu, onclick: () => this.toggleMenu() });
    this.fab = h('div', { class: 'reader-fab' }, this.menuBtn);
    this.root = h('div', { class: 'reader', role: 'region', 'aria-label': `Reading ${this.meta.title}` },
      this.viewport, this.loading, this.dim, this.top, this.bottom, this.fab);
    document.getElementById('reader-root').append(this.root);
    document.getElementById('app').setAttribute('aria-hidden', 'true');
    this.applyTheme();
  }

  async start() {
    try {
      this.epub = await library.openFile(this.meta.id);
    } catch (e) {
      this.loading.textContent = e.message || 'This book could not be opened.';
      return;
    }
    this.lengths = this.meta.textLengths || await this.epub.computeTextLengths();
    this.total = this.lengths.reduce((a, b) => a + b, 0) || 1;
    this.bindEvents();
    const loc = this.meta.location;
    await this.loadChapter(loc?.chapter ?? 0, { fraction: loc?.fraction ?? 0 });
    this.loading.remove();
    library.touch(this.meta.id);
    this.setChrome(!loc);
    document.fonts?.ready?.then(() => this.relayout());
  }

  // ---------- Theme & layout ----------

  applyTheme() {
    const s = readerSettings.get();
    const { vars, textured } = themeVars(s);
    for (const [k, v] of Object.entries(vars)) this.root.style.setProperty(k, v);
    this.root.classList.toggle('paper', textured);
    this.dim.style.opacity = String(Math.max(0, Math.min(0.7, 1 - s.brightness)));
    const wide = window.innerWidth >= 900;
    this.root.style.setProperty('--r-margin-x', wide ? 'max(56px, calc((100vw - 1180px) / 2))' : 'clamp(22px, 6.5vw, 44px)');
    this.root.style.setProperty('--r-margin-top', '58px');
    this.root.style.setProperty('--r-margin-bottom', '40px');
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.content = vars['--r-bg'];
  }

  geometry() {
    const W = this.viewport.clientWidth;
    const H = this.viewport.clientHeight;
    const cols = W >= 760 ? 2 : 1;
    const G = cols === 2 ? 64 : 48;
    const colW = (W - (cols - 1) * G) / cols;
    return { W, H, cols, G, colW, step: W + G };
  }

  layout() {
    const g = this.geometry();
    this.g = g;
    const c = this.content.style;
    c.width = `${g.W}px`;
    c.columnWidth = `${g.colW}px`;
    c.columnGap = `${g.G}px`;
    c.columnCount = 'auto';
    this.root.style.setProperty('--r-page-h', `${g.H}px`);
    const ncols = Math.max(1, Math.round((this.content.scrollWidth + g.G) / (g.colW + g.G)));
    this.pages = Math.max(1, Math.ceil(ncols / g.cols));
  }

  /** The text position at the top of the current page, used to stay in place across relayouts. */
  anchor() {
    const r = this.viewport.getBoundingClientRect();
    const x = r.left + 4, y = r.top + 4;
    const walker = document.createTreeWalker(this.content, NodeFilter.SHOW_TEXT);
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
      if (!n.data.trim()) continue;
      const range = document.createRange();
      range.selectNodeContents(n);
      for (const rect of range.getClientRects()) {
        if (rect.right > x && rect.left < r.right && rect.bottom > y) {
          // Narrow to the first character on this page.
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

  pageOfAnchor(a) {
    if (!a || !a.node.isConnected) return null;
    const range = document.createRange();
    range.setStart(a.node, a.offset);
    range.setEnd(a.node, Math.min(a.node.data.length, a.offset + 1));
    return this.pageOfRect(range.getBoundingClientRect());
  }

  pageOfRect(rect) {
    const base = this.content.getBoundingClientRect().left; // already translated
    const x = rect.left - base;
    return Math.max(0, Math.min(this.pages - 1, Math.floor((x + 1) / this.g.step)));
  }

  relayout = debounce(() => {
    const a = this.anchor();
    this.applyTheme();
    this.layout();
    const p = this.pageOfAnchor(a);
    this.goPage(p ?? Math.min(this.page, this.pages - 1), false);
  }, 120);

  // ---------- Chapters & pages ----------

  async loadChapter(index, { fraction = 0, toEnd = false, fragment = null } = {}) {
    index = Math.max(0, Math.min(this.epub.spine.length - 1, index));
    let frag;
    try {
      frag = await this.epub.renderChapter(index);
    } catch (e) {
      console.error(e);
      frag = h('p', {}, 'This section could not be displayed.');
    }
    this.chapter = index;
    clear(this.content).append(frag);
    this.content.style.transform = 'translateX(0)';
    for (const img of this.content.querySelectorAll('img')) {
      if (!img.complete) img.addEventListener('load', () => this.relayout(), { once: true });
    }
    this.layout();
    let page = toEnd ? this.pages - 1 : Math.floor(fraction * this.pages + 1e-6);
    if (fragment) {
      const el = this.content.querySelector(`[id="epub-${index}-${CSS.escape(fragment)}"]`);
      if (el) page = this.pageOfRect(el.getBoundingClientRect());
    }
    this.goPage(Math.max(0, Math.min(this.pages - 1, page)), false);
    this.refreshUnderlines();
    this.updateTitle();
  }

  goPage(p, animate = true) {
    this.page = Math.max(0, Math.min(this.pages - 1, p));
    this.content.classList.toggle('animating', animate);
    this.content.style.transform = `translateX(${-this.page * this.g.step}px)`;
    this.updateInfo();
    this.saveLocation();
  }

  async next() {
    if (this.page < this.pages - 1) return this.goPage(this.page + 1);
    if (this.chapter < this.epub.spine.length - 1) return this.crossChapter(this.chapter + 1, false);
    this.bounce(-1);
  }

  async prev() {
    if (this.page > 0) return this.goPage(this.page - 1);
    if (this.chapter > 0) return this.crossChapter(this.chapter - 1, true);
    this.bounce(1);
  }

  async crossChapter(index, toEnd) {
    if (this.crossing) return;
    this.crossing = true;
    const dir = toEnd ? 1 : -1;
    const out = -this.page * this.g.step + dir * this.g.step;
    this.content.classList.add('animating');
    this.content.style.transform = `translateX(${out}px)`;
    await wait(200);
    await this.loadChapter(index, { toEnd });
    const target = -this.page * this.g.step;
    this.content.classList.remove('animating');
    this.content.style.transform = `translateX(${target - dir * this.g.step}px)`;
    this.content.getBoundingClientRect();
    this.content.classList.add('animating');
    this.content.style.transform = `translateX(${target}px)`;
    this.crossing = false;
  }

  bounce(dir) {
    const base = -this.page * this.g.step;
    this.content.classList.add('animating');
    this.content.style.transform = `translateX(${base + dir * 30}px)`;
    setTimeout(() => { this.content.style.transform = `translateX(${base}px)`; }, 160);
  }

  bookProgress() {
    const before = this.lengths.slice(0, this.chapter).reduce((a, b) => a + b, 0);
    const within = this.pages > 1 ? this.page / (this.pages - 1) : 1;
    return Math.min(1, (before + within * (this.lengths[this.chapter] || 0)) / this.total);
  }

  locationFromProgress(p) {
    let acc = 0;
    const target = p * this.total;
    for (let i = 0; i < this.lengths.length; i++) {
      if (acc + this.lengths[i] >= target) return { chapter: i, fraction: (target - acc) / this.lengths[i] };
      acc += this.lengths[i];
    }
    return { chapter: this.lengths.length - 1, fraction: 0.999 };
  }

  chapterTitle() {
    let label = '';
    for (const t of this.epub.toc) if (t.spineIndex <= this.chapter) label = t.label; else break;
    return label;
  }

  updateTitle() { this.titleEl.textContent = this.meta.title; }

  updateInfo() {
    const left = this.pages - 1 - this.page;
    this.pageInfo.textContent = left === 0 ? 'Last page in chapter' : `${left} ${left === 1 ? 'page' : 'pages'} left in chapter`;
    this.pageInfo.textContent = this.chromeVisible ? `${this.pageInfo.textContent} · ${Math.round(this.bookProgress() * 100)}%` : this.pageInfo.textContent;
    if (!this.scrubbing) {
      this.scrub.value = String(Math.round(this.bookProgress() * 1000));
      this.scrub.style.setProperty('--pct', `${this.bookProgress() * 100}%`);
    }
  }

  saveLocation = debounce(() => {
    const fraction = this.pages > 0 ? this.page / this.pages : 0;
    library.saveLocation(this.meta.id, { chapter: this.chapter, fraction }, this.bookProgress(), this.chapterTitle());
  }, 500);

  refreshUnderlines() { underlineSaved(this.content, vocab.savedForms()); }

  // ---------- Chrome, menus ----------

  setChrome(visible) {
    this.chromeVisible = visible;
    this.root.classList.toggle('chrome-hidden', !visible);
    if (!visible) this.closeAa();
    if (this.g) this.updateInfo();
  }

  openToc() {
    this.closeAa();
    const list = h('ul', { class: 'toc' });
    let current = null;
    for (const t of this.epub.toc) if (t.spineIndex <= this.chapter) current = t;
    for (const t of this.epub.toc) {
      const isPart = /^part\b/i.test(t.label);
      const btn = h('button', { class: `lvl${Math.min(2, t.level)}${isPart ? ' part' : ''}`, 'aria-current': t === current ? 'true' : 'false' },
        h('span', {}, t.label));
      btn.onclick = async () => {
        sheet.close();
        await this.loadChapter(t.spineIndex, { fragment: t.fragment });
        this.setChrome(false);
      };
      list.append(h('li', {}, btn));
    }
    const sheet = openSheet({ title: this.meta.title, content: list });
    setTimeout(() => list.querySelector('[aria-current="true"]')?.scrollIntoView({ block: 'center' }), 60);
  }

  /** Close whichever overlay (menu or settings panel) is open. */
  closeAa() {
    if (!this.aa) return;
    this.aa.remove();
    this.aa = null;
    this.menuBtn.setAttribute('aria-expanded', 'false');
  }

  #overlay(el) {
    this.closeAa();
    el.addEventListener('pointerdown', (e) => e.stopPropagation());
    el.addEventListener('pointerup', (e) => e.stopPropagation());
    this.aa = el;
    this.root.append(el);
  }

  toggleMenu() {
    if (this.aa?.classList.contains('r-menu')) { this.closeAa(); return; }
    const pct = Math.round(this.bookProgress() * 100);
    const item = (label, icon, fn) => h('button', { onclick: () => { this.closeAa(); fn(); } }, h('span', {}, label), h('span', { html: icon }));
    const menu = h('div', { class: 'r-menu', role: 'menu', 'aria-label': 'Reading menu' },
      h('div', { class: 'menu-progress' }, h('b', {}, this.chapterTitle() || this.meta.title), h('span', {}, `${pct}% of book`)),
      item('Contents', icons.list, () => this.openToc()),
      item('Themes & Settings', icons.textformat, () => this.openAa()),
    );
    this.#overlay(menu);
    this.menuBtn.setAttribute('aria-expanded', 'true');
  }

  openAa(view = 'main') {
    const panel = h('div', { class: 'r-panel', role: 'dialog', 'aria-label': 'Themes & Settings' });
    const set = (patch, layoutChange) => {
      readerSettings.set(patch);
      if (layoutChange) this.relayout(); else this.applyTheme();
      render();
    };
    const head = (title, withBack) => h('div', { class: 'panel-head' },
      withBack ? h('button', { class: 'back', 'aria-label': 'Back', html: icons.back, onclick: () => { view = 'main'; render(); } }) : null,
      h('h2', {}, title),
      h('button', { class: 'sheet-close', 'aria-label': 'Close', html: icons.close, onclick: () => this.closeAa() }));
    const seg = (items, cur, onPick) => h('div', { class: 'seg', role: 'group' },
      items.map(([v, label]) => h('button', { 'aria-pressed': String(v === cur), onclick: () => onPick(v) }, label)));

    const render = () => {
      const st = readerSettings.get();
      clear(panel);
      if (view === 'main') {
        const modes = ['auto', 'light', 'dark'];
        const modeIcon = { auto: icons.auto, light: icons.sun, dark: icons.moon }[st.appearance];
        const modeLabel = { auto: 'Appearance: match device', light: 'Appearance: light', dark: 'Appearance: dark' }[st.appearance];
        const dark = isDark(st.appearance);
        panel.append(
          head('Themes & Settings'),
          h('div', { class: 'ctrl-row' },
            h('div', { class: 'capsule' },
              h('button', { class: 'a-small', 'aria-label': 'Smaller text', disabled: st.fontSize <= 14, onclick: () => set({ fontSize: Math.max(14, st.fontSize - 1) }, true) }, 'A'),
              h('button', { class: 'a-large', 'aria-label': 'Larger text', disabled: st.fontSize >= 32, onclick: () => set({ fontSize: Math.min(32, st.fontSize + 1) }, true) }, 'A')),
            h('div', { class: 'capsule mode-btn' },
              h('button', { 'aria-label': modeLabel, title: modeLabel, html: modeIcon, onclick: () => set({ appearance: modes[(modes.indexOf(st.appearance) + 1) % 3] }, false) }))),
          h('div', { class: 'themes' }, Object.entries(THEMES).map(([key, t]) => {
            const p = dark ? t.dark : t.light;
            const tile = h('button', { class: 'theme-tile', 'aria-pressed': String(st.theme === key), 'aria-label': `${t.name} theme` },
              h('b', {}, 'Aa'), h('span', {}, t.name));
            tile.style.setProperty('--t-bg', p.bg);
            tile.style.setProperty('--t-fg', p.fg);
            tile.style.setProperty('--t-font', FONTS[t.font].stack);
            tile.style.setProperty('--t-weight', String(t.weight));
            if (p.texture) tile.style.backgroundImage = p.texture;
            tile.onclick = () => set({ theme: key, font: 'original' }, true);
            return tile;
          })),
          h('button', { class: 'customize', onclick: () => { view = 'customize'; render(); } }, h('span', { html: icons.sliders }), 'Customize'),
        );
      } else {
        const bright = h('input', { type: 'range', min: '0.3', max: '1', step: '0.01', value: String(st.brightness), 'aria-label': 'Brightness', id: 'aa-brightness' });
        bright.oninput = () => { readerSettings.set({ brightness: Number(bright.value) }); this.applyTheme(); };
        const themeFont = FONTS[(THEMES[st.theme] || THEMES.original).font];
        panel.append(
          head('Customize', true),
          h('div', { class: 'panel-group' },
            h('div', { class: 'panel-row' }, h('span', { html: icons.sunSmall }), bright, h('span', { html: icons.sunLarge }))),
          h('div', { class: 'panel-group' },
            h('div', { class: 'panel-row' }, h('span', {}, 'Line spacing'), seg([[1.35, 'Tight'], [1.5, 'Normal'], [1.75, 'Loose']], st.lineHeight, (v) => set({ lineHeight: v }, true))),
            h('div', { class: 'panel-row' }, h('span', {}, 'Justify text'), seg([[false, 'Off'], [true, 'On']], st.justify, (v) => set({ justify: v }, true)))),
          h('div', { class: 'panel-group font-list', role: 'group', 'aria-label': 'Font' }, Object.entries(FONTS).map(([key, f]) =>
            h('button', { class: 'font-opt', 'aria-pressed': String(st.font === key), style: { fontFamily: f.stack || themeFont.stack }, onclick: () => set({ font: key }, true) },
              key === 'original' ? `Original (${themeFont.name})` : f.name))),
        );
      }
    };
    render();
    this.#overlay(panel);
  }

  // ---------- Input ----------

  bindEvents() {
    const vp = this.root;
    let start = null, timer = null, dragging = false, pressed = false;

    const down = (e) => {
      if (e.button > 0 || this.crossing) return;
      if (e.target.closest('.reader-top, .reader-bottom .scrub, .reader-fab, .r-menu, .r-panel')) return;
      start = { x: e.clientX, y: e.clientY, t: performance.now(), id: e.pointerId };
      dragging = false; pressed = false;
      clearTimeout(timer);
      timer = setTimeout(() => {
        if (!start || dragging) return;
        pressed = true;
        this.lookupAt(start.x, start.y);
      }, LONG_PRESS_MS);
    };
    const move = (e) => {
      if (!start || e.pointerId !== start.id || pressed) return;
      const dx = e.clientX - start.x, dy = e.clientY - start.y;
      if (!dragging && Math.hypot(dx, dy) > 10) {
        clearTimeout(timer);
        if (Math.abs(dx) > Math.abs(dy)) {
          dragging = true;
          this.closeAa();
          try { vp.setPointerCapture(e.pointerId); } catch { /* ignore */ }
          this.content.classList.remove('animating');
        } else { start = null; return; }
      }
      if (dragging) {
        let off = dx;
        const atStart = this.page === 0 && this.chapter === 0, atEnd = this.page === this.pages - 1 && this.chapter === this.epub.spine.length - 1;
        if ((off > 0 && atStart) || (off < 0 && atEnd)) off *= 0.3;
        this.content.style.transform = `translateX(${-this.page * this.g.step + off}px)`;
      }
    };
    const up = (e) => {
      clearTimeout(timer);
      if (!start || e.pointerId !== start.id) { start = null; return; }
      const s = start; start = null;
      if (pressed) return;
      const dx = e.clientX - s.x;
      const dt = performance.now() - s.t;
      if (dragging) {
        const fast = Math.abs(dx) / dt > 0.35;
        if (dx < -60 || (fast && dx < -20)) this.next();
        else if (dx > 60 || (fast && dx > 20)) this.prev();
        else this.goPage(this.page);
        return;
      }
      if (e.type === 'pointercancel') return;
      this.tap(e.clientX, e.clientY, e.target);
    };
    vp.addEventListener('pointerdown', down);
    vp.addEventListener('pointermove', move);
    vp.addEventListener('pointerup', up);
    vp.addEventListener('pointercancel', up);
    vp.addEventListener('contextmenu', (e) => e.preventDefault());
    vp.addEventListener('dblclick', (e) => { if (!e.target.closest('.reader-top, .reader-bottom, .reader-fab, .r-menu, .r-panel')) this.lookupAt(e.clientX, e.clientY); });

    this.scrub.addEventListener('input', () => {
      this.scrubbing = true;
      const loc = this.locationFromProgress(Number(this.scrub.value) / 1000);
      const t = [...this.epub.toc].reverse().find((x) => x.spineIndex <= loc.chapter);
      this.pageInfo.textContent = `${t ? `${t.label} · ` : ''}${Math.round(Number(this.scrub.value) / 10)}%`;
      this.scrub.style.setProperty('--pct', `${Number(this.scrub.value) / 10}%`);
    });
    this.scrub.addEventListener('change', async () => {
      const loc = this.locationFromProgress(Number(this.scrub.value) / 1000);
      await this.loadChapter(loc.chapter, { fraction: loc.fraction });
      this.scrubbing = false;
      this.updateInfo();
    });

    const key = (e) => {
      if (hasOpenSheet() || e.target.closest?.('input, select, textarea')) return;
      if (['ArrowRight', 'PageDown', ' '].includes(e.key)) { e.preventDefault(); this.next(); }
      else if (['ArrowLeft', 'PageUp'].includes(e.key)) { e.preventDefault(); this.prev(); }
      else if (e.key === 'Escape' && this.aa) this.closeAa();
    };
    document.addEventListener('keydown', key);
    this.unsubs.push(() => document.removeEventListener('keydown', key));

    const onResize = () => this.relayout();
    window.addEventListener('resize', onResize);
    this.unsubs.push(() => window.removeEventListener('resize', onResize));
    const mq = window.matchMedia?.('(prefers-color-scheme: dark)');
    const onScheme = () => { this.applyTheme(); if (this.aa) { this.closeAa(); this.openAa(); } };
    mq?.addEventListener?.('change', onScheme);
    this.unsubs.push(() => mq?.removeEventListener?.('change', onScheme));
    this.unsubs.push(vocab.onChange(() => this.refreshUnderlines()));
  }

  tap(x, y, target) {
    if (this.aa) { this.closeAa(); return; }
    const link = target.closest?.('[data-href]');
    if (link && this.content.contains(link)) { this.followLink(link.getAttribute('data-href')); return; }
    const w = window.innerWidth;
    if (x < w * 0.22) this.prev();
    else if (x > w * 0.78) this.next();
    else this.setChrome(!this.chromeVisible);
  }

  async followLink(href) {
    if (/^https?:/i.test(href)) { window.open(href, '_blank', 'noopener'); return; }
    const [file, frag] = href.split('#');
    const idx = this.epub.spineIndexByHref.get(file);
    if (idx === undefined) return;
    await this.loadChapter(idx, { fragment: frag || null });
  }

  lookupAt(x, y) {
    const hit = wordAtPoint(x, y, this.content);
    if (!hit) return;
    this.closeAa();
    navigator.vibrate?.(8);
    setLookupHighlight(hit.range);
    openWordSheet({ word: hit.word, sentence: hit.sentence, offset: hit.offset, bookTitle: this.meta.title, bookId: this.meta.id }, {
      onClose: () => setLookupHighlight(null),
    });
  }

  async close() {
    while (closeTopSheet()) { /* close open sheets */ }
    this.saveLocation.flush?.();
    this.unsubs.forEach((u) => u());
    this.root.remove();
    this.epub?.destroy();
    setLookupHighlight(null);
    try { CSS.highlights?.delete('lexi-saved'); } catch { /* ignore */ }
    document.getElementById('app').removeAttribute('aria-hidden');
    if (active === this) active = null;
    this.onCloseCb?.();
  }
}

function wait(ms) { return new Promise((r) => setTimeout(r, ms)); }
