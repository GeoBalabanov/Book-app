# Lexi for iOS

Native SwiftUI port of the web app in `../web` (the reference for behaviour
and design). iOS 17+, Xcode 16+. The only third-party dependency is
ZIPFoundation, pulled in by Swift Package Manager.

## Run it

1. Open `ios/Lexi.xcodeproj` in Xcode.
2. Pick an iPhone or iPad simulator and press Run. The sample book
   (*The War of the Worlds*) is added on first launch.

From the command line:

```sh
xcodebuild -project ios/Lexi.xcodeproj -scheme Lexi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project ios/Lexi.xcodeproj -scheme Lexi \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

To run on a real device, set your development team under Signing &
Capabilities. The bundle ID is `com.georgibalabanov.lexi`.

## DeepL key

Without a key, lookups use clearly labelled demo translations, so the whole
app works offline. To get real translations:

1. Copy `ios/Config/Secrets.example.xcconfig` to `ios/Config/Secrets.xcconfig`
   (this file is git-ignored).
2. Put your key in it:
   ```
   DEEPL_API_KEY = 0123abcd-…:fx
   ```
   Free keys end in `:fx` and go to `api-free.deepl.com`; other keys go to
   `api.deepl.com`. The app picks the host from the key.
3. Clean the build folder (Product › Clean Build Folder) and run again.

The value goes from `Secrets.xcconfig` to Info.plist (`DeepLAPIKey`) and is
read at runtime by `TranslationProviders`. Remember the key ends up inside
the app bundle, so don't ship a build with a personal key to other people.

## Layout

```
Lexi/
  App/            app entry, tabs (Library · Vocabulary · Flashcards)
  EPUB/           container.xml → OPF → nav/NCX parser (port of web/js/epub/parser.js)
  Library/        library screen, EPUB import and storage
  Reader/         reader screen, themes, Look Up sheet, web-view bridge
  Reader/Web/     reader.html/js/css: CSS-column pagination, word + sentence
                  detection, highlights (ports of web/js/reader/*)
  Translation/    TranslationService protocol, DeepL, demo provider, NLTagger, cache
  Vocabulary/     saved-word list
  Flashcards/     SM-2 (port of web/js/srs/sm2.js), deck, study and summary screens
  Models/         SwiftData models: Book, SavedWord (CachedTranslation lives in Translation/)
LexiTests/        unit tests, incl. ports of web/tests/sm2.test.mjs and deepl.test.mjs
```

### How the reader works

- Each book is unzipped once on import, into Application Support/Books/<id>.
- One `WKWebView` shows one chapter at a time. A `lexi://` URL scheme handler
  serves the reader page, the bundled fonts and the book's files.
- Taps, swipes and long-presses are handled natively (WebKit's own text
  selection is turned off) and passed to the page's `window.Lexi` API. The
  page reports back through the `lexi` message handler: location, lookup word
  and sentence, and chrome toggles.
- The reading position is saved as a point in the chapter's text, so it
  survives font, theme and rotation changes.

### Adding a translation provider

Implement `TranslationService` (`id`, `attribution`, `translate(_:)`) and
return it from `TranslationProviders.current`. Caching, the Look Up sheet and
saving work unchanged.
