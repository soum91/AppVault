#!/usr/bin/env python3
"""Regression gate: manual Store 2FA must not fabricate approval sessions."""
from pathlib import Path

root = Path(__file__).resolve().parents[2]
service = (root / "AppVault/StoreService.swift").read_text()
view = (root / "AppVault/BackupHomeView.swift").read_text()
store = (root / "AppVault/DirectAppleStore.swift").read_text()
protocol = (root / "AppVault/StoreProtocol.swift").read_text()
checks = [
    ('manual entry action', 'func showManualCodeEntry()' in service),
    ('manual entry visibility', 'manualCodeEntry = true' in service),
    ('manual entry dismissal', 'func hideManualCodeEntry()' in service),
    ('manual flag clearing', 'manualCodeEntry = false' in service),
    ('six digit validation', 'code.count != 6' in service and '$0.isASCII && $0.isNumber' in service),
    ('opt in code button', 'Button("Use a Verification Code")' in view),
    ('show code callback', 'store.showManualCodeEntry()' in view),
    ('code field on manual OR server challenge', 'store.needsCode || store.manualCodeEntry' in view),
    ('system OTP autofill', 'textContentType(.oneTimeCode)' in view),
    ('submit with code label', 'store.code.isEmpty ? "Sign In" : "Sign In with Code"' in view),
    ('trusted device approval', 'Request Approval on Other Devices' in view),
    ('approval UI only with server-issued session', 'verificationAvailable()' in service and 'canRequestApproval' in view),
    ('approval requires Apple session', 'guard let context = verification else' in store),
    ('recognize Apple challenge', 'AppleVerificationSession.isChallengeResponse' in store),
    ('request actual Apple approval', 'requestTrustedDeviceApproval()' in store),
    ('append manual code only in existing Store protocol', 'password + code' in protocol and 'code.isEmpty ? "1" : "2"' in protocol),
    ('do not append code after session verification', 'sessionVerified ? "" : code' in store),
]
for name, passed in checks:
    if not passed:
        raise AssertionError("2FA contract failed: " + name)
print("Passed", len(checks), "manual code / trusted-device authorization checks")
