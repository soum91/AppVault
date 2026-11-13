#!/usr/bin/env python3
"""Fail closed if AppVault's installed-version display or release gate regresses."""
import json
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parents[1]
errors = []
def require(condition, message):
    if not condition:
        errors.append(message)

contract = json.loads((root / "version-ui-contract.json").read_text())
require(contract.get("schemaVersion") == 1, "Unsupported contract schema")
for target in contract.get("platforms", []):
    require(target.get("platform") == "ios", "Unexpected target platform")
    source = (root / target["settingsView"]).read_text()
    project = (root / target["project"]).read_text()
    require('Section("Installed Version")' in source, "Installed Version section missing")
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        require(re.search(r'Bundle\.main\.object\(forInfoDictionaryKey:\s*"' + key + r'"\)', source) is not None,
                f"Runtime bundle metadata read missing: {key}")
    require('Text("AppVault \\(version) (\\(build))")' in source,
            "Installed version/build not visibly displayed")
    require("MARKETING_VERSION:" in project and "CURRENT_PROJECT_VERSION:" in project,
            "Packaging version/build settings missing")
workflow = (root / ".github/workflows/ios-build.yml").read_text()
require("python3 scripts/check_version_ui.py" in workflow, "Release preflight not invoked")
require("continue-on-error: true" not in workflow, "Version preflight must block")
if errors:
    print("\n".join("ERROR: " + e for e in errors), file=sys.stderr)
    sys.exit(1)
print("AppVault installed-version contract passed")
