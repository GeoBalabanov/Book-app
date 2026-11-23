// Lightweight EPUB 2/3 parser: JSZip for the container, DOMParser for XML.
// Reads container.xml → OPF (metadata, manifest, spine) → nav.xhtml or NCX.

const NS = {
  opf: 'http://www.idpf.org/2007/opf',
  dc: 'http://purl.org/dc/elements/1.1/',
  xhtml: 'http://www.w3.org/1999/xhtml',
  ops: 'http://www.idpf.org/2007/ops',
};

export class EpubError extends Error {}

function parseXml(text, type = 'application/xml') {
  const doc = new DOMParser().parseFromString(text, type);
  if (doc.getElementsByTagName('parsererror').length) return null;
  return doc;
}

/** Parse (X)HTML leniently: strict XHTML first, then the HTML parser. */
function parseXhtml(text) {
  return parseXml(text, 'application/xhtml+xml') || new DOMParser().parseFromString(text, 'text/html');
}

function byLocalName(root, name) {
  return [...root.getElementsByTagName('*')].filter((el) => el.localName === name);
}

export function resolvePath(base, rel) {
  if (/^[a-z]+:/i.test(rel)) return rel;
  const [pathPart, frag] = rel.split('#');
  const parts = base ? base.split('/').slice(0, -1) : [];
  for (const seg of pathPart.split('/')) {
    if (seg === '..') parts.pop();
    else if (seg && seg !== '.') parts.push(seg);
  }
  let out = parts.join('/');
  try { out = decodeURIComponent(out); } catch { /* keep raw */ }
  return frag !== undefined ? `${out}#${frag}` : out;
}

const BLOCKED_TAGS = new Set(['script', 'style', 'link', 'iframe', 'object', 'embed', 'form', 'input', 'button', 'textarea', 'select', 'meta', 'base', 'audio', 'video', 'source', 'noscript', 'head', 'title']);

export class EpubBook {
  constructor(zip) {
    this.zip = zip;
    this.urlCache = new Map();
    this.textLengths = null;
  }

  static async open(data) {
    if (typeof JSZip === 'undefined') throw new EpubError('The ZIP library did not load. Check your connection and reload.');
    let zip;
    try { zip = await JSZip.loadAsync(data); } catch { throw new EpubError('This file is not a valid EPUB (it could not be unzipped).'); }
    const book = new EpubBook(zip);
    await book.#load();
    return book;
  }

  async text(path) {
    const f = this.zip.file(path) || this.zip.file(decodeURI(path));
    if (!f) throw new EpubError(`Missing file in EPUB: ${path}`);
    return f.async('string');
  }

  async #load() {
    const container = parseXml(await this.text('META-INF/container.xml'));
    const rootfile = container && byLocalName(container, 'rootfile')[0];
    if (!rootfile) throw new EpubError('This EPUB has no package document.');
    this.opfPath = rootfile.getAttribute('full-path');
    const opf = parseXml(await this.text(this.opfPath));
    if (!opf) throw new EpubError('The EPUB package document is malformed.');

    // Metadata
    const meta = byLocalName(opf, 'metadata')[0] || opf;
    const dc = (name) => byLocalName(meta, name).map((e) => e.textContent.trim()).filter(Boolean);
    this.metadata = {
      title: dc('title')[0] || 'Untitled',
      author: dc('creator').join(', '),
      language: dc('language')[0] || 'en',
      identifier: dc('identifier')[0] || '',
    };

    // Manifest
    this.manifest = new Map();
    for (const item of byLocalName(opf, 'item')) {
      const href = resolvePath(this.opfPath, item.getAttribute('href') || '');
      this.manifest.set(item.getAttribute('id'), {
        id: item.getAttribute('id'),
        href,
        mediaType: item.getAttribute('media-type') || '',
        properties: (item.getAttribute('properties') || '').split(/\s+/),
      });
    }
    const hrefToItem = new Map([...this.manifest.values()].map((i) => [i.href, i]));

    // Spine
    const spineEl = byLocalName(opf, 'spine')[0];
    this.spine = byLocalName(spineEl || opf, 'itemref')
      .map((ref) => this.manifest.get(ref.getAttribute('idref')))
      .filter((it) => it && /html|xml/.test(it.mediaType));
    if (!this.spine.length) throw new EpubError('This EPUB has no readable chapters.');
    this.spineIndexByHref = new Map(this.spine.map((it, i) => [it.href, i]));

    // Cover
    const coverMetaId = byLocalName(meta, 'meta').find((m) => m.getAttribute('name') === 'cover')?.getAttribute('content');
    const coverItem = [...this.manifest.values()].find((i) => i.properties.includes('cover-image'))
      || (coverMetaId && this.manifest.get(coverMetaId))
      || [...this.manifest.values()].find((i) => /image\//.test(i.mediaType) && /cover/i.test(i.id + i.href));
    this.coverHref = coverItem && /image\//.test(coverItem.mediaType) ? coverItem.href : null;

    // Table of contents
    this.toc = [];
    const navItem = [...this.manifest.values()].find((i) => i.properties.includes('nav'));
    const ncxItem = this.manifest.get(spineEl?.getAttribute('toc')) || [...this.manifest.values()].find((i) => i.mediaType === 'application/x-dtbncx+xml');
    try {
      if (navItem) this.toc = await this.#parseNav(navItem.href);
      if (!this.toc.length && ncxItem) this.toc = await this.#parseNcx(ncxItem.href);
    } catch (e) { console.warn('TOC parse failed', e); }
    if (!this.toc.length) {
      this.toc = this.spine.map((it, i) => ({ label: `Section ${i + 1}`, href: it.href, spineIndex: i, level: 0 }));
    }
    void hrefToItem;
  }

  #tocEntry(label, href, level) {
    const [file, fragment] = href.split('#');
    const spineIndex = this.spineIndexByHref.get(file);
    if (spineIndex === undefined) return null;
    return { label: label.replace(/\s+/g, ' ').trim() || 'Untitled', href, fragment: fragment || null, spineIndex, level };
  }

  async #parseNav(path) {
    const doc = parseXhtml(await this.text(path));
    const navs = byLocalName(doc, 'nav');
    const nav = navs.find((n) => (n.getAttributeNS(NS.ops, 'type') || n.getAttribute('epub:type') || '').includes('toc')) || navs[0];
    if (!nav) return [];
    const out = [];
    const walk = (ol, level) => {
      for (const li of [...ol.children].filter((c) => c.localName === 'li')) {
        const a = [...li.children].find((c) => c.localName === 'a' || c.localName === 'span');
        if (a && a.getAttribute('href')) {
          const e = this.#tocEntry(a.textContent, resolvePath(path, a.getAttribute('href')), level);
          if (e) out.push(e);
        }
        const sub = [...li.children].find((c) => c.localName === 'ol');
        if (sub) walk(sub, level + 1);
      }
    };
    const ol = byLocalName(nav, 'ol')[0];
    if (ol) walk(ol, 0);
    return out;
  }

  async #parseNcx(path) {
    const doc = parseXml(await this.text(path));
    if (!doc) return [];
    const out = [];
    const walk = (parent, level) => {
      for (const np of [...parent.children].filter((c) => c.localName === 'navPoint')) {
        const label = byLocalName(np, 'text')[0]?.textContent || '';
        const src = byLocalName(np, 'content')[0]?.getAttribute('src');
        if (src) {
          const e = this.#tocEntry(label, resolvePath(path, src), level);
          if (e) out.push(e);
        }
        walk(np, level + 1);
      }
    };
    const navMap = byLocalName(doc, 'navMap')[0];
    if (navMap) walk(navMap, 0);
    return out;
  }

  async coverBlob() {
    if (!this.coverHref) return null;
    const f = this.zip.file(this.coverHref);
    if (!f) return null;
    const item = [...this.manifest.values()].find((i) => i.href === this.coverHref);
    return new Blob([await f.async('uint8array')], { type: item?.mediaType || 'image/jpeg' });
  }

  async resourceUrl(path) {
    if (this.urlCache.has(path)) return this.urlCache.get(path);
    const f = this.zip.file(path);
    if (!f) return null;
    const item = [...this.manifest.values()].find((i) => i.href === path);
    const url = URL.createObjectURL(new Blob([await f.async('uint8array')], { type: item?.mediaType || '' }));
    this.urlCache.set(path, url);
    return url;
  }

  /** Character counts per spine item; used for whole-book progress. */
  async computeTextLengths() {
    if (this.textLengths) return this.textLengths;
    const lengths = [];
    for (const it of this.spine) {
      try {
        const doc = parseXhtml(await this.text(it.href));
        const body = byLocalName(doc, 'body')[0] || doc.documentElement;
        lengths.push(Math.max(1, (body.textContent || '').replace(/\s+/g, ' ').length));
      } catch { lengths.push(1); }
    }
    this.textLengths = lengths;
    return lengths;
  }

  /**
   * Build a sanitized, display-ready fragment for one spine item. Scripts,
   * styles, forms and event handlers are dropped; images point at blob URLs;
   * links keep their target in data-href so the reader can route them.
   */
  async renderChapter(index) {
    const item = this.spine[index];
    const src = parseXhtml(await this.text(item.href));
    const body = byLocalName(src, 'body')[0] || src.documentElement;
    const frag = document.createDocumentFragment();
    const pending = [];

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
          el.setAttribute('data-href', attr.value.startsWith('#') ? `${item.href}${attr.value}` : resolvePath(item.href, attr.value));
          el.setAttribute('role', 'link');
          continue;
        }
        if ((tag === 'img' && name === 'src') || (isSvg && name === 'href' && node.localName === 'image')) {
          const path = resolvePath(item.href, attr.value);
          pending.push(this.resourceUrl(path).then((url) => {
            if (!url) return;
            if (isSvg) el.setAttributeNS('http://www.w3.org/1999/xlink', 'href', url), el.setAttribute('href', url);
            else el.setAttribute('src', url);
          }));
          continue;
        }
        if (['alt', 'title', 'colspan', 'rowspan', 'lang', 'dir'].includes(name) || isSvg) {
          try { el.setAttribute(attr.name.replace(/^xlink:/, ''), attr.value); } catch { /* invalid attr name */ }
        }
      }
      for (const child of node.childNodes) copy(child, el);
      parent.append(el);
    };
    for (const child of body.childNodes) copy(child, frag);
    await Promise.all(pending);
    return frag;
  }

  destroy() {
    for (const url of this.urlCache.values()) URL.revokeObjectURL(url);
    this.urlCache.clear();
  }
}
