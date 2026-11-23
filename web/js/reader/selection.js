// Find the word under a point, the sentence around it, and maintain the
// CSS Custom Highlights used for the lookup highlight and saved-word underlines.

const BLOCK = 'p, li, h1, h2, h3, h4, h5, h6, blockquote, dd, dt, td, th, figcaption, pre, div, section';
const WORD_CHAR = /[\p{L}\p{M}\p{N}]/u;
const JOINER = /['’\-]/;

/** Text nodes of `block` with their start offsets in the concatenated text. */
function indexText(block) {
  const nodes = [];
  let text = '';
  const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT);
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    nodes.push({ node: n, start: text.length });
    text += n.data;
  }
  return { nodes, text };
}

function locate(nodes, abs) {
  for (let i = nodes.length - 1; i >= 0; i--) {
    if (abs >= nodes[i].start) return { node: nodes[i].node, offset: Math.min(abs - nodes[i].start, nodes[i].node.data.length) };
  }
  return null;
}

function caretFromPoint(x, y) {
  if (document.caretPositionFromPoint) {
    const p = document.caretPositionFromPoint(x, y);
    return p && { node: p.offsetNode, offset: p.offset };
  }
  if (document.caretRangeFromPoint) {
    const r = document.caretRangeFromPoint(x, y);
    return r && { node: r.startContainer, offset: r.startOffset };
  }
  return null;
}

function rangeContainsPoint(range, x, y, slop = 4) {
  for (const r of range.getClientRects()) {
    if (x >= r.left - slop && x <= r.right + slop && y >= r.top - slop && y <= r.bottom + slop) return true;
  }
  return false;
}

const segmenter = typeof Intl !== 'undefined' && Intl.Segmenter ? new Intl.Segmenter('en', { granularity: 'sentence' }) : null;

function sentenceBounds(text, index) {
  // Source HTML wraps lines with newlines, which the segmenter treats as
  // paragraph breaks. Replace each whitespace char with a space (same length).
  text = text.replace(/\s/g, ' ');
  if (segmenter) {
    for (const seg of segmenter.segment(text)) {
      if (index >= seg.index && index < seg.index + seg.segment.length) return [seg.index, seg.index + seg.segment.length];
    }
  }
  // Fallback: split on . ! ? followed by space + capital/quote.
  let start = 0;
  const re = /[.!?]["'’”)]*\s+(?=["'‘“(]?[A-Z])/g;
  for (let m = re.exec(text); m; m = re.exec(text)) {
    const end = m.index + m[0].length;
    if (end > index) return [start, end];
    start = end;
  }
  return [start, text.length];
}

/**
 * @returns {{word:string, sentence:string, offset:number, range:Range}|null}
 */
export function wordAtPoint(x, y, root) {
  const caret = caretFromPoint(x, y);
  if (!caret || caret.node.nodeType !== 3 || !root.contains(caret.node)) return null;
  const block = caret.node.parentElement.closest(BLOCK) || root;
  if (!root.contains(block)) return null;
  const { nodes, text } = indexText(block);
  const nodeInfo = nodes.find((n) => n.node === caret.node);
  if (!nodeInfo) return null;
  let i = nodeInfo.start + caret.offset;
  if (!WORD_CHAR.test(text[i] || '') && WORD_CHAR.test(text[i - 1] || '')) i -= 1;
  if (!WORD_CHAR.test(text[i] || '')) return null;

  let s = i, e = i + 1;
  while (s > 0 && (WORD_CHAR.test(text[s - 1]) || (JOINER.test(text[s - 1]) && WORD_CHAR.test(text[s - 2] || '')))) s--;
  while (e < text.length && (WORD_CHAR.test(text[e]) || (JOINER.test(text[e]) && WORD_CHAR.test(text[e + 1] || '')))) e++;
  const word = text.slice(s, e);
  if (!/\p{L}/u.test(word)) return null;

  const a = locate(nodes, s), b = locate(nodes, e);
  const range = document.createRange();
  range.setStart(a.node, a.offset);
  range.setEnd(b.node, b.offset);
  if (!rangeContainsPoint(range, x, y)) return null;

  const [ss, se] = sentenceBounds(text, s);
  const raw = text.slice(ss, se);
  const sentence = raw.replace(/\s+/g, ' ').trim();
  const prefix = raw.slice(0, s - ss).replace(/\s+/g, ' ').replace(/^\s+/, '');
  return { word, sentence, offset: prefix.length, range };
}

const hasHighlights = typeof CSS !== 'undefined' && CSS.highlights && typeof Highlight !== 'undefined';

export function setLookupHighlight(range) {
  if (!hasHighlights) return;
  if (range) CSS.highlights.set('lexi-lookup', new Highlight(range));
  else CSS.highlights.delete('lexi-lookup');
}

/** Underline every occurrence of a saved form inside `root`. */
export function underlineSaved(root, forms) {
  if (!hasHighlights) return;
  if (!forms.size || !root) { CSS.highlights.delete('lexi-saved'); return; }
  const ranges = [];
  const re = /[\p{L}][\p{L}\p{M}'’\-]*/gu;
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    re.lastIndex = 0;
    for (let m = re.exec(n.data); m; m = re.exec(n.data)) {
      const w = m[0].replace(/['’\-]+$/, '');
      if (forms.has(w.toLowerCase())) {
        const r = document.createRange();
        r.setStart(n, m.index);
        r.setEnd(n, m.index + w.length);
        ranges.push(r);
      }
    }
  }
  CSS.highlights.set('lexi-saved', new Highlight(...ranges));
}
