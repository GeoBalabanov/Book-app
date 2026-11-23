# Lexi Reader

A reading app for English books that translates unknown words into Bulgarian
**in context** and turns them into spaced-repetition flashcards.

This is the **web version** (built first so it can be used before the native
iOS app). The iOS SwiftUI app will follow the same structure.

## Features

- **Library**: cover grid, Continue Reading, EPUB import, sample book included
  (*The War of the Worlds*, H. G. Wells, public domain, via Project Gutenberg / Feedbooks).
- **Reader**: paginated with horizontal page turns (swipe, tap the edges, or
  use the arrow keys). Two pages side by side on wide screens. Tap the center to
  show or hide the controls. Contents list, a book-wide progress scrubber, and
  your place saved per book.
- **Themes (Aa menu)**: Original, Quiet, Paper, Bold, Calm, Focus, each with a
  light and dark variant (Auto/Light/Dark). Also brightness, font size, font,
  line spacing and justification. Settings apply to all books.
- **Tap to translate**: press and hold a word (double-click on desktop) to see:
  - the Bulgarian translation as used in that sentence
  - the sentence with the word highlighted, and the sentence in Bulgarian
  - base form and part of speech
  - a *Save to flashcards* button

  Saved words get a subtle underline in the reader.
- **Vocabulary**: search, filter by book, swipe left to delete.
- **Flashcards**: card flip, Again / Hard / Good / Easy buttons, SM-2
  scheduling, and an "X cards due today" count.

## Structure

```
web/
  index.html            page markup (hosted as a Claude artifact, or by server.mjs)
  app.css               iOS-style shell + reader styles
  js/app.js             tabs and startup
  js/epub/parser.js     EPUB 2/3 parser (JSZip + DOMParser): OPF, spine, nav/NCX, cover
  js/reader/            pagination (CSS columns), gestures, themes, word/sentence detection
  js/translation/       TranslationService interface + Claude, DeepL, demo providers
  js/store/             IndexedDB (books), vocabulary + translation cache
  js/srs/sm2.js         SM-2 scheduler
  js/views/             Library, Vocabulary, Flashcards, Settings
  server.mjs            local dev server + DeepL proxy (no dependencies)
  tests/                node --test unit tests (SM-2, DeepL parsing)
```

### Why a custom EPUB parser
Readium's web toolkit is large, and word lookup, saved-word underlines and the
Apple Books look all need direct control of the rendered text anyway. A small
parser (container.xml → OPF → nav/NCX) plus CSS-column pagination covers
reflowable books well. Fixed-layout EPUBs are not supported.

### Translation flow
1. Find the word under your finger and its full sentence (`Intl.Segmenter`).
2. Check the cache: provider + word + offset + sentence. A cache hit returns at once.
3. Otherwise ask the active `TranslationService`:
   - **Claude** (the default inside Claude): one request returns the contextual
     translation, lemma, part of speech, the lemma's dictionary translation, an
     optional note, and the sentence translation. It runs on your Claude account,
     so no key is needed.
   - **DeepL** (local server): translates the sentence with the word wrapped in
     `<w>…</w>` (`tag_handling=xml`). The tagged span is the word's in-context
     translation. If DeepL drops the tag, it makes a second request with
     `context=<sentence>`. Lemma and part of speech come from `compromise`.
4. Save the result to the cache.

To add a provider, implement `isAvailable()` and `translate()` (see
`js/translation/service.js`) and add it to `PROVIDERS`.

## Running locally

```sh
cd web
cp .env.example .env        # paste your DeepL key (Free keys end in :fx)
node server.mjs             # http://localhost:5173
```
Open `http://localhost:5173/?mock` for fake translations without a key.
Run the tests with `node --test web/tests/*.test.mjs`.

`web/.env` is git-ignored. The key stays on the server and is never sent to the browser.
