#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CLIENT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ROOT=${MIRRA_WORKSPACE:-"$SCRIPT_DIR/workspace"}
export PUB_CACHE="$ROOT/toolchain/pub-cache"
export PATH="$ROOT/toolchain/flutter/bin:$PATH"
cd "$CLIENT_DIR/flutter"
flutter test --no-pub test/connection_routing_test.dart
dart analyze lib/desktop/connection_routing test/connection_routing_test.dart
