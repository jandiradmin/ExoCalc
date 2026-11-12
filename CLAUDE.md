# ExoCalc — notes for Claude Code

Notepad calculator (Numi-like) for macOS, Windows and iPhone/iPad. Owner: Yan (answer in Russian, short numbered steps).

## Layout
- `Sources/ExoCalcCore/` — shared engine (Swift, Foundation only): Lexer, Parser (evaluates while parsing), Units, Rates, DateTime, Strings (ru/en/uk via `tr(key, args)`), Examples (welcome sheet + help examples).
- `Sources/ExoCalc/` — macOS app (AppKit + SwiftUI). Results column is `ResultOverlay` above the scroll view; result clicks are caught by a window-level event monitor in `CalcWindowController`. `Updater.swift` — GitHub Releases check + in-place install.
- `Sources/exocalc-cli/` — CLI and `--selftest` (SelfTest.swift: all engine cases).
- `iOS/` — iPhone/iPad app (SwiftUI + UITextView, own digits keypad `NumPad`, `KeyBar`). Project is generated: `cd iOS && xcodegen generate`. Team RU5B5M38AJ (free personal team: reinstall every 7 days).
- `windows/` — Tauri 2 app. `src/engine.js` is a JS port of the Swift engine, `src/data.js` holds units/strings tables (keep in sync with Swift by hand), `tests/selftest.mjs` mirrors SelfTest.swift.

## Rules
- Any engine change goes into BOTH Swift (`Sources/ExoCalcCore`) and JS (`windows/src/engine.js`, `data.js`), plus a test case in BOTH SelfTest.swift and selftest.mjs.
- New UI strings: add to `Strings.swift` AND `windows/src/data.js` (order: ru, en, uk).

## Build and test
```
./build.sh --install                      # Mac app → /Applications, runs selftest (native arch; UNIVERSAL=1 for arm64+x86_64)
.build/release/exocalc-cli --selftest
cd windows && node tests/selftest.mjs     # JS engine tests
cd iOS && xcodebuild -project ExoCalc-iOS.xcodeproj -scheme ExoCalc-iOS -destination 'id=00008150-000054D23CF0401C' -derivedDataPath /tmp/exo-ios-dev -allowProvisioningUpdates build
xcrun devicectl device install app --device 00008150-000054D23CF0401C /tmp/exo-ios-dev/Build/Products/Debug-iphoneos/ExoCalc.app
```

## Release (Mac + Windows)
1. Bump version in `Resources/Info.plist` (CFBundleShortVersionString, CFBundleVersion), `windows/package.json`, `windows/package-lock.json` (top), `windows/src-tauri/tauri.conf.json`, `windows/src-tauri/Cargo.toml`, `windows/src-tauri/Cargo.lock` (package `exocalc`).
2. Commit, `git tag vX.Y.Z && git push origin vX.Y.Z`, `gh release create vX.Y.Z --verify-tag --notes-file …` (notes in en/uk/ru).
3. GitHub Actions attach `ExoCalc-macOS.zip` (macos.yml, universal, macOS 12+) and the Windows `.exe`/`.msi` + `latest.json` (windows.yml).

## Updates
- Windows: tauri-plugin-updater, endpoint `releases/latest/download/latest.json`, signed with the key in GitHub secret `TAURI_SIGNING_PRIVATE_KEY` (copy on the Mac: `~/.exocalc-keys/`). Losing the key breaks auto-update for installed copies.
- Mac: `Updater.swift` reads the GitHub API, downloads `ExoCalc-macOS.zip`, swaps the bundle after quit and relaunches.

## Plans
See `TODO.md` (iCloud sync after Apple Developer membership, iOS history, widget).
