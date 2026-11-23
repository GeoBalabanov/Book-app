// Reading themes modeled on Apple Books (Original, Quiet, Paper, Bold, Calm,
// Focus), each with a light and dark variant, plus fonts and settings.
// Apple-only fonts fall back to close equivalents on other platforms.

import { storage } from '../util.js';

const PAPER_TEXTURE_LIGHT = `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2' stitchTiles='stitch'/%3E%3CfeColorMatrix values='0 0 0 0 0.45 0 0 0 0 0.42 0 0 0 0 0.38 0 0 0 .07 0'/%3E%3C/filter%3E%3Crect width='160' height='160' filter='url(%23n)'/%3E%3C/svg%3E")`;
const PAPER_TEXTURE_DARK = `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2' stitchTiles='stitch'/%3E%3CfeColorMatrix values='0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 0 0 0 .05 0'/%3E%3C/filter%3E%3Crect width='160' height='160' filter='url(%23n)'/%3E%3C/svg%3E")`;

export const FONTS = {
  original: { name: 'Original', stack: null },
  newyork: { name: 'New York', stack: '"New York", ui-serif, "Literata", Georgia, serif' },
  athelas: { name: 'Athelas', stack: 'Athelas, "Literata", Georgia, serif' },
  charter: { name: 'Charter', stack: 'Charter, "Bitstream Charter", "Literata", Georgia, serif' },
  georgia: { name: 'Georgia', stack: 'Georgia, "Literata", serif' },
  iowan: { name: 'Iowan', stack: '"Iowan Old Style", "Literata", Georgia, serif' },
  palatino: { name: 'Palatino', stack: 'Palatino, "Palatino Linotype", "Book Antiqua", "Literata", serif' },
  sanfrancisco: { name: 'San Francisco', stack: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Inter", system-ui, sans-serif' },
  seravek: { name: 'Seravek', stack: 'Seravek, "Gill Sans Nova", "Inter", system-ui, sans-serif' },
  times: { name: 'Times New Roman', stack: '"Times New Roman", Times, serif' },
};

// bg, fg, muted text, chrome glass, saved-word accent, lookup highlight
export const THEMES = {
  original: {
    name: 'Original', font: 'newyork', weight: 400,
    light: { bg: '#ffffff', fg: '#121212', muted: 'rgba(0,0,0,.45)', chrome: 'rgba(250,250,250,.78)', btn: 'rgba(120,120,128,.14)', accent: '#e07b00', select: 'rgba(255,170,40,.32)', hairline: 'rgba(0,0,0,.12)' },
    dark: { bg: '#000000', fg: '#e8e8e8', muted: 'rgba(255,255,255,.45)', chrome: 'rgba(22,22,24,.78)', btn: 'rgba(118,118,128,.28)', accent: '#ff9f0a', select: 'rgba(255,159,10,.32)', hairline: 'rgba(255,255,255,.1)' },
  },
  quiet: {
    name: 'Quiet', font: 'newyork', weight: 400,
    light: { bg: '#4a4a4d', fg: '#d4d4d6', muted: 'rgba(255,255,255,.42)', chrome: 'rgba(64,64,67,.82)', btn: 'rgba(255,255,255,.12)', accent: '#ffb340', select: 'rgba(255,179,64,.3)', hairline: 'rgba(255,255,255,.1)' },
    dark: { bg: '#1c1c1e', fg: '#a8a8ad', muted: 'rgba(255,255,255,.35)', chrome: 'rgba(36,36,38,.82)', btn: 'rgba(255,255,255,.1)', accent: '#d9952c', select: 'rgba(217,149,44,.3)', hairline: 'rgba(255,255,255,.08)' },
  },
  paper: {
    name: 'Paper', font: 'charter', weight: 400, texture: true,
    light: { bg: '#f1f0ed', fg: '#1d1c1a', muted: 'rgba(0,0,0,.45)', chrome: 'rgba(236,235,231,.8)', btn: 'rgba(100,95,85,.13)', accent: '#c46a00', select: 'rgba(230,150,40,.3)', hairline: 'rgba(0,0,0,.1)', texture: PAPER_TEXTURE_LIGHT },
    dark: { bg: '#232325', fg: '#d6d4cf', muted: 'rgba(255,255,255,.4)', chrome: 'rgba(40,40,42,.82)', btn: 'rgba(255,255,255,.1)', accent: '#f0a030', select: 'rgba(240,160,48,.3)', hairline: 'rgba(255,255,255,.08)', texture: PAPER_TEXTURE_DARK },
  },
  bold: {
    name: 'Bold', font: 'sanfrancisco', weight: 600,
    light: { bg: '#ffffff', fg: '#000000', muted: 'rgba(0,0,0,.5)', chrome: 'rgba(250,250,250,.8)', btn: 'rgba(120,120,128,.14)', accent: '#d86e00', select: 'rgba(255,170,40,.35)', hairline: 'rgba(0,0,0,.12)' },
    dark: { bg: '#000000', fg: '#ffffff', muted: 'rgba(255,255,255,.5)', chrome: 'rgba(22,22,24,.8)', btn: 'rgba(118,118,128,.28)', accent: '#ff9f0a', select: 'rgba(255,159,10,.35)', hairline: 'rgba(255,255,255,.1)' },
  },
  calm: {
    name: 'Calm', font: 'athelas', weight: 400,
    light: { bg: '#f3e7d0', fg: '#3b2f22', muted: 'rgba(59,47,34,.5)', chrome: 'rgba(238,226,203,.82)', btn: 'rgba(110,85,50,.13)', accent: '#a8580a', select: 'rgba(200,120,30,.28)', hairline: 'rgba(59,47,34,.14)' },
    dark: { bg: '#2c241c', fg: '#ddcbb0', muted: 'rgba(221,203,176,.48)', chrome: 'rgba(48,40,32,.84)', btn: 'rgba(221,203,176,.12)', accent: '#e0a050', select: 'rgba(224,160,80,.28)', hairline: 'rgba(221,203,176,.1)' },
  },
  focus: {
    name: 'Focus', font: 'iowan', weight: 400,
    light: { bg: '#fffbee', fg: '#1b1b1b', muted: 'rgba(0,0,0,.45)', chrome: 'rgba(252,247,232,.82)', btn: 'rgba(120,110,80,.13)', accent: '#c56a00', select: 'rgba(240,160,40,.3)', hairline: 'rgba(0,0,0,.1)' },
    dark: { bg: '#1a1813', fg: '#e6dfcc', muted: 'rgba(230,223,204,.45)', chrome: 'rgba(34,31,25,.84)', btn: 'rgba(230,223,204,.1)', accent: '#f0a840', select: 'rgba(240,168,64,.3)', hairline: 'rgba(230,223,204,.08)' },
  },
};

export const DEFAULT_SETTINGS = {
  theme: 'original',
  appearance: 'auto',   // 'auto' | 'light' | 'dark'
  font: 'original',     // 'original' = the theme's own font
  fontSize: 19,         // px
  lineHeight: 1.5,
  justify: false,
  brightness: 1,        // 0.3..1, dims the page (browsers can't change screen brightness)
};

const KEY = 'lexi.readerSettings';
const listeners = new Set();
let settings = { ...DEFAULT_SETTINGS, ...storage.get(KEY, {}) };

export const readerSettings = {
  get: () => settings,
  set(patch) {
    settings = { ...settings, ...patch };
    storage.set(KEY, settings);
    listeners.forEach((fn) => fn(settings));
  },
  onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); },
};

export function isDark(appearance) {
  if (appearance === 'dark') return true;
  if (appearance === 'light') return false;
  const forced = document.documentElement.getAttribute('data-theme');
  if (forced) return forced === 'dark';
  return window.matchMedia?.('(prefers-color-scheme: dark)').matches ?? false;
}

/** CSS custom properties for the reader root. */
export function themeVars(s = settings) {
  const theme = THEMES[s.theme] || THEMES.original;
  const palette = isDark(s.appearance) ? theme.dark : theme.light;
  const fontKey = s.font === 'original' ? theme.font : s.font;
  return {
    vars: {
      '--r-bg': palette.bg, '--r-fg': palette.fg, '--r-muted': palette.muted, '--r-chrome': palette.chrome,
      '--r-btn': palette.btn, '--r-accent': palette.accent, '--r-select': palette.select, '--r-hairline': palette.hairline,
      '--r-texture': palette.texture || 'none',
      '--r-font': FONTS[fontKey]?.stack || FONTS.newyork.stack,
      '--r-weight': String(theme.weight),
      '--r-size': `${s.fontSize}px`, '--r-line': String(s.lineHeight),
      '--r-align': s.justify ? 'justify' : 'start',
    },
    textured: !!theme.texture,
    dark: isDark(s.appearance),
  };
}
