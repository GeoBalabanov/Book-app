# Lexi Reader for iOS: build plan

Native SwiftUI port of the web app in `web/`. The web app is the approved
reference for **behavior and design**. Open it locally with
`cd web && node server.mjs`, then visit http://localhost:5173/?mock.

## Requirements (from the owner)
- Library: cover grid, "Continue Reading" at the top, EPUB import from the Files picker. Sample book included (`web/samples/war-of-the-worlds.epub`).
- Reader: paginated with horizontal page turns; tap the center to show or hide controls; progress bar; contents list; reading position saved per book.
- Themes like Apple Books (Original, Quiet, Paper, Bold, Calm, Focus, each with light and dark variants). An "Aa" panel with font size, font, line spacing and brightness. Settings are global.
- Tap or long-press a word to open a sheet showing:
  - the Bulgarian translation **in this sentence's context**
  - the sentence with the word highlighted
  - the sentence translated into Bulgarian
  - part of speech and base form
  - a "Save to flashcards" button
- Translation sits behind a `TranslationService` protocol, implemented with DeepL; the API key lives in a git-ignored config file. Translations are cached so the same word + sentence is never requested twice.
- SwiftData vocabulary store with these fields: word, lemma, translation, sentence, sentence translation, book title, date added, review data. Saved words are underlined in the reader.
- Vocabulary tab: search, filter by book, swipe to delete.
- Flashcards tab:
  - front: word + sentence; back: translation + sentence translation
  - flip animation; Again/Hard/Good/Easy rating
  - SM-2 scheduling; "X cards due today"
- Tabs: Library · Vocabulary · Flashcards. SwiftUI + SwiftData, MVVM, no third-party UI libraries.

## Decisions already made
- **Project:** `ios/Lexi.xcodeproj`, app name **Lexi**. iOS 17+ deployment target, Xcode 16+. Use folder-synchronized groups so new files are included automatically.
- **EPUB:**
  - Unzip with the **ZIPFoundation** SwiftPM package (non-UI, well maintained).
  - Write a small custom parser that reads container.xml → OPF (metadata, manifest, spine, cover) → nav.xhtml or NCX. Port it from `web/js/epub/parser.js`.
- **Rendering:**
  - One `WKWebView` per chapter. CSS multi-column pagination with one page per step, two columns on iPad landscape.
  - Use the reader CSS from `web/app.css` (`.reader-content` rules) and the theme values from `web/js/reader/themes.js`.
  - A JS bridge (`WKScriptMessageHandler`) reports the long-pressed word, its sentence and its offset. Detect sentences with `Intl.Segmenter`; see `web/js/reader/selection.js`.
  - Saved-word underlines use the CSS Custom Highlight API.
- **Translation flow:**
  - Port the DeepL logic from `web/js/translation/deepl.js` and `deepl-core.js`.
  - Translate the sentence with the word wrapped in `<w>…</w>` and `tag_handling=xml`. The tagged span is the in-context word translation; the full output is the sentence translation.
  - If DeepL drops the tag, fall back to translating the word alone with `context=<sentence>`.
  - Get lemma and part of speech on device with `NaturalLanguage` (`NLTagger`, `.lexicalClass` + `.lemma`).
  - Cache results in SwiftData, keyed by provider + word + offset + sentence.
- **API key:**
  - `ios/Config/Secrets.xcconfig` holds `DEEPL_API_KEY = …` and is git-ignored. Commit `Secrets.example.xcconfig`.
  - The value is exposed through Info.plist and read at runtime.
  - Free keys end in `:fx` and use api-free.deepl.com.
- **SRS:** port `web/js/srs/sm2.js` exactly, including its unit tests in `web/tests/sm2.test.mjs`.
- **Design:** match the approved web app.
  - Monochrome Apple-style chrome (SF Pro for the interface, New York for book text).
  - Reader controls: close button top-left, menu button bottom-right (Contents, Themes & Settings).
  - Themes & Settings is a bottom panel: A/A size buttons, appearance toggle, 3×2 theme tiles, Customize.
  - The Look Up sheet is styled like Apple's dictionary sheet.
  - Flashcards are **paper index cards**: warm paper with grain, a ruled header with "New word" and "No. N", the word in large serif, the sentence excerpt quoted, and the book title as a citation. The deck screen shows a fanned stack, a 7-day forecast and a session summary card.

## Build order
Each step must build and run in the Simulator before moving on. Commit after each step.
1. Reader + themes, including the library and the sample book.
2. Word selection + translation.
3. Saving words + the Vocabulary tab.
4. Flashcards + SRS.

Finally, report what's done, what's missing, and how to add the DeepL key.
