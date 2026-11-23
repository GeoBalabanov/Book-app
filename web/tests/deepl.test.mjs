import { test } from 'node:test';
import assert from 'node:assert/strict';
import { markSentence, parseTagged, deeplHost } from '../js/translation/deepl-core.js';

test('markSentence wraps the word at the given offset and escapes XML', () => {
  assert.equal(markSentence('Tom & the bank by the bank.', 'bank', 22), 'Tom &amp; the bank by the <w>bank</w>.');
  assert.equal(markSentence('He ran home.', 'ran', 99), 'He <w>ran</w> home.');
  assert.equal(markSentence('Nothing here.', 'absent', 0), null);
});

test('parseTagged extracts the word and the clean sentence', () => {
  const r = parseTagged('Той <w>изтича</w> към къщи &amp; спря.');
  assert.equal(r.word, 'изтича');
  assert.equal(r.sentence, 'Той изтича към къщи & спря.');
  assert.equal(parseTagged('Без таг.').word, null);
});

test('deeplHost picks the free endpoint for :fx keys', () => {
  assert.equal(deeplHost('abc:fx'), 'https://api-free.deepl.com');
  assert.equal(deeplHost('abc'), 'https://api.deepl.com');
});
