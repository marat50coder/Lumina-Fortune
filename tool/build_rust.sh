#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# build_rust.sh — compile prism_core for the 4 Android ABIs
# ─────────────────────────────────────────────────────────────
# Produces:
#   android/app/src/main/jniLibs/arm64-v8a/libprism_core.so
#   android/app/src/main/jniLibs/armeabi-v7a/libprism_core.so
#   android/app/src/main/jniLibs/x86_64/libprism_core.so
#   android/app/src/main/jniLibs/x86/libprism_core.so
#
# Dependencies:
#   • `cargo` + `cargo-ndk`  (install via `cargo install cargo-ndk`)
#   • `rustup target add aarch64-linux-android armv7-linux-androideabi \
#                        x86_64-linux-android i686-linux-android`
#   • Android NDK (resolved from $ANDROID_NDK_HOME or $HOME/Library/Android/sdk/ndk/<ver>)
#
# Run this manually when the Rust sources change. Flutter will
# pick up `.so` files automatically because jniLibs is Gradle's
# default sidecar directory.
# ─────────────────────────────────────────────────────────────

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRATE_DIR="$ROOT/rust/prism_core"
JNI_DIR="$ROOT/android/app/src/main/jniLibs"

# Resolve NDK path.
if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  for candidate in \
      "$HOME/Library/Android/sdk/ndk/28.2.13676358" \
      "$HOME/Library/Android/sdk/ndk/27.0.12077973" \
      "$HOME/Android/Sdk/ndk/28.2.13676358" \
      "$HOME/Android/Sdk/ndk/27.0.12077973"; do
    if [[ -d "$candidate" ]]; then
      export ANDROID_NDK_HOME="$candidate"
      break
    fi
  done
fi

if [[ -z "${ANDROID_NDK_HOME:-}" || ! -d "$ANDROID_NDK_HOME" ]]; then
  echo "✗ ANDROID_NDK_HOME is not set and no NDK was found. Install an NDK via Android Studio and re-run." >&2
  exit 1
fi
echo "→ Using NDK: $ANDROID_NDK_HOME"

mkdir -p "$JNI_DIR/arm64-v8a" \
         "$JNI_DIR/armeabi-v7a" \
         "$JNI_DIR/x86_64" \
         "$JNI_DIR/x86"

cd "$CRATE_DIR"

# `cargo ndk` drops the .so files into the correct per-ABI
# directory names on its own.
cargo ndk \
  -t arm64-v8a \
  -t armeabi-v7a \
  -t x86_64 \
  -t x86 \
  -o "$JNI_DIR" \
  build --release

echo "→ Built jniLibs:"
find "$JNI_DIR" -name 'libprism_core.so' -maxdepth 2 -print -exec ls -lh {} \;

echo "✓ prism_core shared libraries updated."
