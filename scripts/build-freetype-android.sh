#!/usr/bin/env bash
# Cross-build a minimal static FreeType for Android, for linking into the
# Vinculum JNI `.so` (issue #92, docs/ANDROID.md).
#
# Vinculum only needs face loading, the sfnt MATH table, glyph advances/ink
# extents, and outline decomposition — no PNG/zlib/harfbuzz/brotli/bzip2 — so
# this builds FreeType with all of those OFF, keeping the archive small and
# dependency-free. The result (`libfreetype.a`, per ABI, built `-fPIC` so it can
# be linked into a shared library) is fed to `swift build` via
# `-Xcc -I<inc> -Xlinker -L<lib>`; the C ABI target statically links it, so the
# shipped `.so` is self-contained (no separate libfreetype.so on device).
#
# Verified working on a Linux x86_64 host with Docker (swift:6.2 image), the
# Swift 6.2.0-RELEASE toolchain, and finagolfin's swift-6.2 Android SDK. The
# toolchain and the Android SDK MUST be the same exact Swift version — the
# floating `swift:6.2` docker tag drifts (it is 6.2.4 now) while the SDK is fixed
# at 6.2.0, and Swift modules only import into the exact compiler version.
#
# Usage:
#   SWIFT_TOOLCHAIN=/path/to/swift-6.2-RELEASE-ubuntu24.04 \
#   ANDROID_SYSROOT=/path/to/.../android-<n>-sysroot \
#   FT_VERSION=2.13.3 ABI=arm64-v8a \
#   scripts/build-freetype-android.sh <out-dir>
set -euo pipefail

OUT="${1:?usage: build-freetype-android.sh <out-dir>}"
FT_VERSION="${FT_VERSION:-2.13.3}"
ABI="${ABI:-arm64-v8a}"
API="${API:-24}"
TOOLCHAIN="${SWIFT_TOOLCHAIN:?set SWIFT_TOOLCHAIN to the Swift toolchain root (contains usr/bin/clang)}"
SYSROOT="${ANDROID_SYSROOT:?set ANDROID_SYSROOT to the Swift Android SDK sysroot}"

# ABI → clang target triple + the arch subdir the SDK's compiler-rt/unwind live under.
case "$ABI" in
  arm64-v8a)   TRIPLE="aarch64-linux-android${API}"; RTARCH="aarch64" ;;
  x86_64)      TRIPLE="x86_64-linux-android${API}";  RTARCH="x86_64"  ;;
  armeabi-v7a) TRIPLE="armv7a-linux-androideabi${API}"; RTARCH="arm"  ;;
  *) echo "unknown ABI: $ABI (arm64-v8a | x86_64 | armeabi-v7a)"; exit 1 ;;
esac

CLANG="$TOOLCHAIN/usr/bin/clang"
RESDIR="$SYSROOT/usr/lib/swift/clang"   # holds libclang_rt.builtins-<arch>-android.a + <arch>/libunwind.a

# The SDK ships compiler-rt/libunwind under the old NDK layout; point clang at
# them, force lld (bfd can't link Android), and build PIC for the shared lib.
export CC="$CLANG --target=$TRIPLE --sysroot=$SYSROOT -fuse-ld=lld -resource-dir=$RESDIR -L$RESDIR/lib/linux/$RTARCH -fPIC"
export CC_BUILD="${CC_BUILD:-gcc}"      # FreeType builds a native tool during the build
export AR="$TOOLCHAIN/usr/bin/llvm-ar"
export RANLIB="$TOOLCHAIN/usr/bin/llvm-ranlib"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cd "$work"
curl -sL "https://download.savannah.gnu.org/releases/freetype/freetype-${FT_VERSION}.tar.gz" -o ft.tar.gz
tar xzf ft.tar.gz && cd "freetype-${FT_VERSION}"

./configure --host="${TRIPLE%${API}}" --enable-static --disable-shared \
  --with-zlib=no --with-bzip2=no --with-png=no --with-harfbuzz=no --with-brotli=no

make -j"$(nproc)"

mkdir -p "$OUT/lib/$ABI" "$OUT/include"
cp objs/.libs/libfreetype.a "$OUT/lib/$ABI/"
cp -r include/* "$OUT/include/"
echo "built $OUT/lib/$ABI/libfreetype.a for $TRIPLE"
