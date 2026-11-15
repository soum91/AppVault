# AppVault 0.3.0 (5)

- Replace automatic ascending full-volume container scans with a 20-second descending search for the LaunchServices database. Resume unsuccessful searches from a saved cursor.
- Read app names and data paths using the GPL-3.0 WQFiles database parser; reuse the remembered database location.
- Check for a usable signed App Group and validate fsgetpath against an app-owned probe before searching.
- Show checked-ID counts and elapsed time, and support cancellation.
- Add selectable discovery diagnostics with verified clipboard copy, native share and Files export.
- Remove the App Bundle shortcut and explicitly document that installed IPA extraction on iOS 27.0.1 is unsupported by this access method.

Evidence: changes to AppVault/Discovery, BackupService.swift and BackupHomeView.swift in this release commit.
Limitations: compilation and archive metadata can be verified by CI. App-container discovery, backup, clipboard, Share and Files export have not been tested on a signed physical device by the maintainer in this session. No claim of working installed-IPA extraction is made.
