import { h, clear } from '../util.js';
import { openSheet } from '../ui/sheet.js';
import { availableProviders, currentProvider, setPreferredProvider } from '../translation/service.js';
import { vocab } from '../store/vocab.js';

export async function openSettings() {
  const body = h('div', {}, h('p', { class: 'muted' }, 'Checking translation services…'));
  openSheet({ title: 'Settings', content: body });
  const draw = async () => {
    const list = await availableProviders();
    const cur = await currentProvider();
    clear(body);
    body.append(h('div', { class: 'ws-label', style: { margin: '6px 4px 8px' } }, 'Translation service'));
    const group = h('div', { class: 'group', role: 'radiogroup' });
    for (const { provider, available } of list) {
      if (provider.id === 'mock' && !available) continue;
      const row = h('button', { class: 'group-row radio-row', role: 'radio', 'aria-checked': String(cur?.id === provider.id), disabled: !available },
        h('span', {}, provider.name, h('small', {}, available ? provider.description : `Not available here. ${provider.description}`)),
        h('span', { class: 'check' }, '✓'));
      row.onclick = () => { setPreferredProvider(provider.id); draw(); };
      group.append(row);
    }
    body.append(group,
      h('p', { class: 'group-caption' }, 'Each word is sent with its full sentence, so the translation matches how the word is used. Results are cached, so the same word in the same sentence is never translated twice.'),
      h('div', { class: 'ws-label', style: { margin: '6px 4px 8px' } }, 'Saved words'),
      h('div', { class: 'group' }, h('div', { class: 'group-row' }, h('span', {}, 'Stored in'),
        h('span', { class: 'muted' }, vocab.kind === 'cloud' ? 'Your Claude account' : vocab.kind === 'local' ? 'This browser' : 'Connecting…'))),
    );
  };
  draw();
}
