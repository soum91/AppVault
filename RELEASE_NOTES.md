# AppVault 0.3.1 (6)

- Fix the app-data backup failure on Apple's protected .com.apple.mobile_container_manager.metadata.plist by copying Documents and Library rather than the whole container.
- Exclude Library/Caches, tmp and container-management files; record exclusions and copied file/byte counts in backup-manifest.json.
- Continue to abort on unreadable user data or symbolic links; remove incomplete ZIP output on archive failure.
- Add host regression fixtures covering protected metadata, preserved data, exclusions, unreadable user files and symbolic links.

Evidence: AppVault/AppDataCopy.swift, BackupService.swift and Tests/main.swift in this release.
Validation: host fixtures and device compilation run in GitHub Actions before publication. The reported physical-device metadata failure has not been retested on the user's device. This remains app-data ZIP backup; installed IPA extraction on iOS 27.0.1 remains unsupported.
