#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CLIENT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ROOT=${MIRRA_WORKSPACE:-"$SCRIPT_DIR/workspace"}
export PUB_CACHE="$ROOT/toolchain/pub-cache"
export PATH="$ROOT/toolchain/flutter/bin:$PATH"
cd "$CLIENT_DIR/flutter"
flutter pub get
dart run build_runner build --delete-conflicting-outputs
ROUTING_DEFINES=$(printf '%s' 'MIRRA_ROUTING_UI=true' | /usr/bin/base64)
flutter assemble --no-version-check \
  -dTargetPlatform=darwin -dDarwinArchs=arm64 -dTargetFile=lib/main.dart \
  -dBuildMode=release -dTreeShakeIcons=false \
  --DartDefines="$ROUTING_DEFINES" \
  --output="$ROOT/ui-build" release_macos_bundle_flutter_assets
