#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CLIENT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ROOT=${MIRRA_WORKSPACE:-"$SCRIPT_DIR/workspace"}
export CARGO_HOME="$ROOT/toolchain/cargo"
export RUSTUP_HOME="$ROOT/toolchain/rustup"
export VCPKG_ROOT="$ROOT/toolchain/vcpkg"
export VCPKG_INSTALLED_ROOT="$ROOT/native"
export LIBCLANG_PATH=/Library/Developer/CommandLineTools/usr/lib
export PUB_CACHE="$ROOT/toolchain/pub-cache"
export RUST_LOG=info
export PATH="$ROOT/toolchain/flutter/bin/cache/dart-sdk/bin:$ROOT/toolchain/native-tools/bin:$CARGO_HOME/bin:$PATH"
cd "$ROOT/toolchain/bridge-dart"
dart pub get
cd "$CLIENT_DIR"
flutter_rust_bridge_codegen \
  --rust-input ./src/flutter_ffi.rs \
  --dart-output ./flutter/lib/generated_bridge.dart \
  --c-output ./flutter/macos/Runner/bridge_generated.h \
  --llvm-path /Library/Developer/CommandLineTools/usr \
  --dart-root "$ROOT/toolchain/bridge-dart" \
  --skip-add-mod-to-lib --no-build-runner
