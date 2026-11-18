#!/usr/bin/env python3
"""Fail closed if the rootless AppVault package ever links WebKit, and keep its in-process sign-in and decryption."""
from pathlib import Path
p = Path(__file__).resolve().parents[2]
project = (p / "project.yml").read_text()
workflow = (p / ".github/workflows/ios-build.yml").read_text()
rootless = (p / "packaging/rootless/DEBIAN/postinst").read_text()
view = (p / "AppVault/Decryption/DecryptionService.swift").read_text()
app = (p / "Decryptor/DecryptorApp.swift").read_text()
home = (p / "AppVault/BackupHomeView.swift").read_text()
decryptor = project.split("  AppVaultDecryptor:", 1)[1].split("  AppVaultDecrypt:", 1)[0]
import re
unguarded_webkit = [
    str(f.relative_to(p)) for f in (p / "AppVault").rglob("*.swift")
    if re.search(r"(?<!#if !APPVAULT_ROOTLESS\n)import WebKit", f.read_text())
]
checks = {
    "separate rootless target": "  AppVaultDecryptor:" in project,
    "distinct rootless bundle identity": "PRODUCT_BUNDLE_IDENTIFIER: com.soum91.appvault.decryptor" in project,
    "privilege only for rootless package": "ldid -Spackaging/AppVault-jailbreak.entitlements" in workflow and "AppVaultDecryptor.app/AppVaultDecryptor" in workflow,
    "stock IPA preserves stock bundle": "PRODUCT_BUNDLE_IDENTIFIER: com.soum91.appvault\n" in project,
    "rootless target compiles WebKit out": 'APPVAULT_ROOTLESS' in decryptor and not unguarded_webkit,
    "rootless binary is checked for WebKit linkage": "must not link WebKit" in workflow and "otool -L" in workflow,
    "rootless target allows loopback signer traffic": "NSAllowsLocalNetworking: true" in decryptor,
    "rootless target includes its own app entry": "path: Decryptor/DecryptorApp.swift" in project and "- AppVaultApp.swift" in decryptor,
    "rootless UI offers sign-in and installed-app export": "WindowGroup { BackupHomeView() }" in app and "DecryptionView()" in home,
    "installer migrates rootless icon": 'AppVaultDecryptor.app' in rootless and 'AppVault.app' in rootless,
    "file export still supported": "ShareLink(item: output)" in view,
    "version accessible in decryptor": 'AppVault Decryptor \\(version) (\\(build))' in view,
}
for label, ok in checks.items():
    if not ok: raise AssertionError("Rootless separation regression: " + label)
print("Passed", len(checks), "privilege separation and package migration checks")
