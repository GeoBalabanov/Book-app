import { test } from 'node:test';
import assert from 'node:assert/strict';
import { newReviewState, review, isDueToday, DAY, RELEARN_DELAY, startOfDay } from '../js/srs/sm2.js';

const NOW = new Date('2026-03-10T12:00:00').getTime();
const days = (s) => Math.round((startOfDay(s.due) - startOfDay(NOW)) / DAY);

test('new card is due immediately', () => {
  const s = newReviewState(NOW);
  assert.equal(s.ease, 2.5);
  assert.ok(isDueToday(s, NOW));
});

test('Good: 1 day, then 6 days, then interval × ease', () => {
  let s = review(newReviewState(NOW), 'good', NOW);
  assert.equal(s.interval, 1); assert.equal(s.repetitions, 1); assert.equal(s.ease, 2.5);
  assert.equal(days(s), 1);
  s = review(s, 'good', NOW);
  assert.equal(s.interval, 6);
  s = review(s, 'good', NOW);
  assert.equal(s.interval, 15); // round(6 × 2.5)
  assert.ok(!isDueToday(s, NOW));
});

test('Again resets repetitions, lowers ease, returns in 10 minutes', () => {
  let s = review(review(newReviewState(NOW), 'good', NOW), 'good', NOW);
  s = review(s, 'again', NOW);
  assert.equal(s.repetitions, 0);
  assert.equal(s.interval, 0);
  assert.equal(s.lapses, 1);
  assert.equal(s.due, NOW + RELEARN_DELAY);
  assert.ok(Math.abs(s.ease - 1.96) < 1e-9); // 2.5 - 0.54
});

test('Hard lowers ease by 0.14 and grows slowly; Easy raises ease by 0.1', () => {
  const h = review(newReviewState(NOW), 'hard', NOW);
  assert.ok(Math.abs(h.ease - 2.36) < 1e-9);
  const e = review(newReviewState(NOW), 'easy', NOW);
  assert.ok(Math.abs(e.ease - 2.6) < 1e-9);
  assert.equal(e.interval, 4);
});

test('ease never drops below 1.3', () => {
  let s = newReviewState(NOW);
  for (let i = 0; i < 20; i++) s = review(s, 'again', NOW);
  assert.equal(s.ease, 1.3);
});
