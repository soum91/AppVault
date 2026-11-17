#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PIN=b352566155a667d8aaeabaa7ecec4966080f92ab
WORK="$ROOT/build/ipatool-source"
mkdir -p "$ROOT/build" "$ROOT/NativeLibraries"
git clone https://github.com/majd/ipatool.git "$WORK"
git -C "$WORK" checkout --detach "$PIN"
# Upstream's reproducible iOS build supplies the pinned Unicorn source, digest,
# and W^X patch. Change only the output mode to an in-process C archive.
cp -R "$ROOT/NativeIPATool" "$WORK/appvaultbridge"
python3 - "$WORK/tools/build-ios.sh" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text()
s=s.replace('go build -ldflags="-X github.com/majd/ipatool/v2/cmd.version=$VERSION" -o "$OUTPUT" .', 'go build -buildmode=c-archive -o "$OUTPUT" ./appvaultbridge\ncp "$BUILD_DIR/build/libunicorn.a" "$ROOT/../libunicorn.a"\ncp "$BUILD_DIR/unicorn-2.1.4/COPYING" "$ROOT/../unicorn-COPYING.txt"')
s=s.replace('ldid -S"$ROOT/resources/ios-entitlements.plist" "$OUTPUT"','')
p.write_text(s)
PY
(cd "$WORK" && go test ./appvaultbridge)
bash "$WORK/tools/build-ios.sh" "$ROOT/NativeLibraries/libAppVaultIPATool.a"
cp "$ROOT/build/libunicorn.a" "$ROOT/NativeLibraries/libunicorn.a"
cp "$WORK/LICENSE" "$ROOT/AppVault/ipatool-LICENSE.txt"

cp "$ROOT/build/unicorn-COPYING.txt" "$ROOT/AppVault/unicorn-COPYING.txt"
