// iOS-style bottom sheet (centered card on wide screens).

import { h, icons } from '../util.js';

const stack = [];

export function openSheet({ title = '', content, onClose, label } = {}) {
  const root = document.getElementById('sheet-root');
  const backdrop = h('div', { class: 'sheet-backdrop' });
  const body = h('div', { class: 'sheet-body' }, content || null);
  const titleEl = h('h2', {}, title);
  const closeBtn = h('button', { class: 'sheet-close', 'aria-label': 'Close', html: icons.close });
  const sheet = h('div', { class: 'sheet', role: 'dialog', 'aria-modal': 'true', 'aria-label': label || title || 'Details' },
    h('div', { class: 'sheet-grabber' }),
    h('div', { class: 'sheet-head' }, titleEl, closeBtn),
    body,
  );
  root.append(backdrop, sheet);
  requestAnimationFrame(() => requestAnimationFrame(() => { backdrop.classList.add('open'); sheet.classList.add('open'); }));

  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    stack.splice(stack.indexOf(api), 1);
    backdrop.classList.remove('open');
    sheet.classList.remove('open');
    setTimeout(() => { backdrop.remove(); sheet.remove(); }, 380);
    onClose?.();
  };
  backdrop.addEventListener('click', close);
  closeBtn.addEventListener('click', close);

  // Drag down to dismiss (from the grabber/header, or the body when scrolled to top).
  let startY = null, dy = 0;
  sheet.addEventListener('pointerdown', (e) => {
    if (e.target.closest('button, input, select, a')) return;
    if (!e.target.closest('.sheet-grabber, .sheet-head')) return;
    startY = e.clientY; dy = 0;
    sheet.setPointerCapture(e.pointerId);
    sheet.style.transition = 'none';
  });
  sheet.addEventListener('pointermove', (e) => {
    if (startY == null) return;
    dy = Math.max(0, e.clientY - startY);
    sheet.style.transform = window.innerWidth >= 760 ? `translate(-50%, ${dy}px)` : `translateY(${dy}px)`;
  });
  const end = () => {
    if (startY == null) return;
    startY = null;
    sheet.style.transition = '';
    sheet.style.transform = '';
    if (dy > 90) close();
  };
  sheet.addEventListener('pointerup', end);
  sheet.addEventListener('pointercancel', end);

  const api = { el: sheet, body, close, setTitle: (t) => { titleEl.textContent = t; }, get closed() { return closed; } };
  stack.push(api);
  setTimeout(() => closeBtn.focus({ preventScroll: true }), 50);
  return api;
}

export function closeTopSheet() { const top = stack[stack.length - 1]; if (top) { top.close(); return true; } return false; }
export function hasOpenSheet() { return stack.length > 0; }

document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeTopSheet(); });

/** In-page confirmation (the viewer blocks window.confirm). Resolves true/false. */
export function confirmSheet({ title, message, confirmLabel = 'Delete', danger = true }) {
  return new Promise((resolve) => {
    let answered = false;
    const yes = h('button', { class: `btn block${danger ? ' destructive' : ''}` }, confirmLabel);
    const no = h('button', { class: 'btn secondary block' }, 'Cancel');
    const s = openSheet({
      title,
      content: h('div', { class: 'confirm' }, h('p', {}, message), h('div', { class: 'row-btns' }, yes, no)),
      onClose: () => { if (!answered) resolve(false); },
    });
    yes.onclick = () => { answered = true; resolve(true); s.close(); };
    no.onclick = () => { answered = true; resolve(false); s.close(); };
  });
}
