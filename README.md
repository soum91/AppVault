# AppVault

An iOS backup utility scaffold based on the worse_query container-access technique.

## Features

- Import a user-selected `.ipa` from Files and package it with a JSON manifest.
- Export backups through the iOS share sheet.
- Provide a gated integration seam for app-data container backup using a compatible worse_query build.

## Install source

Add this FlareStore-compatible source URL:

`https://raw.githubusercontent.com/soum91/AppVault/main/repo.json`

The listed 0.1.1 build is an unsigned prerelease and requires signing before installation.

## Limits

Standard iOS apps cannot enumerate or read other apps' private containers. Container backup requires the correct worse_query implementation, matching App Group entitlement, and a compatible device and OS. Backing up app data does not include signing credentials and does not guarantee an app can be reinstalled. Importing an IPA only archives the file the user selected.

## Build

The GitHub Actions workflow uses XcodeGen on macOS to generate the Xcode project, compile an unsigned iOS app, and upload `AppVault-unsigned.ipa` as a workflow artifact.

See [CHANGELOG.md](CHANGELOG.md) for release changes.
