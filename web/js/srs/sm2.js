// SM-2 spaced repetition (SuperMemo 2, Wozniak 1990) with the four buttons
// mapped to SM-2 quality grades: Again=1, Hard=3, Good=4, Easy=5.
//
//   EF' = EF + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)),  EF >= 1.3
//   q < 3  → repetitions = 0, card comes back in 10 minutes (same session)
//   q >= 3 → interval: 1 day, then 6 days, then round(previous * EF)
// Two small, common adjustments: Hard grows the interval by only 1.2×, and
// Easy gets a 1.3× bonus.

export const GRADES = {
  again: { quality: 1, label: 'Again' },
  hard: { quality: 3, label: 'Hard' },
  good: { quality: 4, label: 'Good' },
  easy: { quality: 5, label: 'Easy' },
};

export const DAY = 24 * 60 * 60 * 1000;
export const RELEARN_DELAY = 10 * 60 * 1000;

/** Review state of a brand-new card: due immediately. */
export function newReviewState(now = Date.now()) {
  return { ease: 2.5, interval: 0, repetitions: 0, lapses: 0, due: now, lastReviewed: null };
}

/**
 * Apply one review. Returns a new state; does not mutate the input.
 * @param {{ease:number, interval:number, repetitions:number, lapses:number, due:number}} state
 * @param {'again'|'hard'|'good'|'easy'} grade
 */
export function review(state, grade, now = Date.now()) {
  const q = GRADES[grade]?.quality;
  if (q === undefined) throw new Error(`Unknown grade: ${grade}`);
  const s = { ...newReviewState(now), ...state };

  let ease = s.ease + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02));
  ease = Math.max(1.3, Math.round(ease * 1000) / 1000);

  if (q < 3) {
    return { ease, interval: 0, repetitions: 0, lapses: s.lapses + 1, due: now + RELEARN_DELAY, lastReviewed: now };
  }

  let interval;
  if (s.repetitions === 0) interval = grade === 'easy' ? 4 : 1;
  else if (s.repetitions === 1) interval = grade === 'hard' ? 3 : 6;
  else if (grade === 'hard') interval = s.interval * 1.2;
  else interval = s.interval * ease;
  if (grade === 'easy' && s.repetitions > 0) interval *= 1.3;
  interval = Math.max(1, Math.round(interval));

  return { ease, interval, repetitions: s.repetitions + 1, lapses: s.lapses, due: startOfDay(now) + interval * DAY + 4 * 60 * 60 * 1000, lastReviewed: now };
}

/** Preview the next interval for each grade (for button captions). */
export function previewIntervals(state, now = Date.now()) {
  return Object.fromEntries(Object.keys(GRADES).map((g) => [g, review(state, g, now).due - now]));
}

export function startOfDay(t) { const d = new Date(t); d.setHours(0, 0, 0, 0); return d.getTime(); }
export function endOfDay(t) { return startOfDay(t) + DAY - 1; }

/** Cards due by the end of today (local time). */
export function isDueToday(state, now = Date.now()) {
  return (state?.due ?? 0) <= endOfDay(now);
}
