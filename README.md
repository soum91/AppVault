# AppVault

On-device app-folder backup utility using forcequitOS/worse_query (GPL-3.0). Upstream sources and license are included.

Browse installed application paths or discover application data folders, open directories, and export backups through Files or the share sheet. Readable .app directories export as an IPA with Payload/App.app; data directories export as ZIP.

The signing profile must provide an App Group entitlement. The app discovers the signed groups automatically and reports failures from worse_query. Upstream documents data-container access; Bundle/Application access is attempted but is not guaranteed. App Store executable encryption is preserved.

Build with XcodeGen and Xcode, or use the GitHub Actions workflow. Device access and visual layout require validation on a compatible device.
