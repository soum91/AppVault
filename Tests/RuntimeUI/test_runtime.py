#!/usr/bin/env python3
"""Regression: keep the iOS 16 WebKit signer visible and preserve safe failure evidence."""
from pathlib import Path

root = Path(__file__).resolve().parents[2]
view = (root / "AppVault/BackupHomeView.swift").read_text()
signer = (root / "AppVault/Attestation/LocalSAPSigner.swift").read_text()
service = (root / "AppVault/StoreService.swift").read_text()
checks = {
    "WebKit signer in foreground overlay": '.overlay(alignment: .center)' in view and 'signing.isPresented, let web = signing.webView' in view,
    "render at meaningful size": 'SigningRuntimeView(web: web)' in view and '.frame(height: 140)' in view,
    "no tiny invisible runtime": '.frame(width: 1, height: 1).opacity(0.01)' not in view,
    "preserve active proxy on memory warnings": 'if self.operationID != nil' in signer and 'memory-warning-active-preserved' in signer,
    "WebKit process termination gets a specific code": 'WEB_CONTENT_EXIT' in signer and 'webViewWebContentProcessDidTerminate' in signer,
    "diagnostic includes safe signer states": 'var diagnosticSummary: String' in signer and 'recentEvents.joined' in signer,
    "report includes runtime diagnostic": 'LocalSAPSigner.shared.diagnosticSummary' in service,
    "no raw JS exception dumps": 'error.localizedDescription' not in signer and 'err.localizedDescription' not in signer,
}
for name, good in checks.items():
    if not good:
        raise AssertionError("AppVault WebKit regression: " + name)
print(f"Passed {len(checks)} WebKit-runtime guards")
