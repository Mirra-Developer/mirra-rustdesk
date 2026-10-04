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
export MACOSX_DEPLOYMENT_TARGET=12.3
export MIRRA_TEST_APP=1
export PATH="$ROOT/toolchain/native-tools/bin:$CARGO_HOME/bin:$PATH"
exec cargo test --locked --release --lib \
  --features flutter,hwcodec,unix-file-copy-paste,screencapturekit \
  --manifest-path "$CLIENT_DIR/Cargo.toml" auto_id -- --nocapture "$@"
