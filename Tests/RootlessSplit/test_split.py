#!/usr/bin/env python3
"""Fail closed if the rootless AppVault package ever bundles Store/WebKit sign-in."""
from pathlib import Path
p = Path(__file__).resolve().parents[2]
project = (p / "project.yml").read_text()
workflow = (p / ".github/workflows/ios-build.yml").read_text()
rootless = (p / "packaging/rootless/DEBIAN/postinst").read_text()
view = (p / "AppVault/Decryption/DecryptionService.swift").read_text()
app = (p / "Decryptor/DecryptorApp.swift").read_text()
checks = {
    "separate rootless target": "  AppVaultDecryptor:" in project,
    "distinct rootless bundle identity": "PRODUCT_BUNDLE_IDENTIFIER: com.soum91.appvault.decryptor" in project,
    "privilege only for rootless package": "ldid -Spackaging/AppVault-jailbreak.entitlements" in workflow and "AppVaultDecryptor.app/AppVaultDecryptor" in workflow,
    "stock IPA preserves stock bundle": "PRODUCT_BUNDLE_IDENTIFIER: com.soum91.appvault\n" in project,
    "rootless target excludes WebKit and Store files": "AppVault/Attestation/" not in project.split("  AppVaultDecryptor:", 1)[1].split("  AppVaultDecrypt:", 1)[0],
    "rootless target includes standalone UI": "path: Decryptor/DecryptorApp.swift" in project,
    "rootless UI starts at decryption not Account": "WindowGroup" in app and "DecryptionView()" in app and "BackupHomeView" not in app,
    "installer migrates rootless icon": 'AppVaultDecryptor.app' in rootless and 'AppVault.app' in rootless,
    "file export still supported": "ShareLink(item: output)" in view,
    "version accessible in decryptor": 'AppVault Decryptor \\(version) (\\(build))' in view,
}
for label, ok in checks.items():
    if not ok: raise AssertionError("Rootless separation regression: " + label)
print("Passed", len(checks), "privilege separation and package migration checks")
