# ExoCalc — planned

## Next release 1.3.3 (after testing)
- [ ] Mac: verify click on a green result copies it (window-level click monitor)
- [ ] Publish Mac + Windows: click to copy, ⌘/Ctrl-click expression, fuel economy, flow rate and pipe speed,
      sq/cubic units, mW/MW and b/B, case-ambiguity hints

## Sync between devices
- [ ] Mac + iPhone/iPad via iCloud (sheet, history, settings; rates are not synced) — after the Apple Developer membership is paid
  - First sync / conflicts: history = union by date (duplicates collapsed);
    sheet = the most recently edited one, lines of the other sheet go to history marked "from <device>, <date>";
    settings = most recently changed. Same rule for offline edits on two devices later. No line-by-line merging.
- [ ] Later, if Windows is needed: own server, no registration, end-to-end encrypted.
      One device creates a sync code (QR / 24 characters); the code gives both the ID (hash) and the key (HKDF).
      The server stores only encrypted blobs and never sees the key.

## Later
- [ ] iPhone/iPad: history of calculations with search and clear
- [ ] iPhone/iPad: widget / Shortcuts action
- [ ] iPhone/iPad: TestFlight / App Store (needs Apple Developer membership, $99/yr)
- [ ] Mac: notarization once the Apple Developer membership is active
