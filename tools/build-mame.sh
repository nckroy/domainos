#!/usr/bin/env bash
# Build an Apollo-only MAME 0.289 with this repo's patches applied.
#
#   tools/build-mame.sh           -> build/mame-apollo (binary named "apollo")
#
# Why: MAME's pcap network backend (the only one on macOS) hands received
# frames to the emulated Ethernet chip without padding or FCS, so the
# Apollo's i82586 rejects every incoming frame. patches/ fixes that.
# run.sh and tools/headless.sh use build/mame-apollo when it exists.
#
# Needs: Xcode command line tools, brew install pkgconf glm rapidjson sdl3
#        flac jpeg-turbo portaudio portmidi pugixml sqlite utf8proc zstd
# Takes ~20-40 min and a few GB under build/.

set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
ver=0289
sha=0929cc749afabcef892900e10dd90bd8b05f94a7dde8f367ac6a5d2082589f84   # Homebrew's
tarball="$here/build/dl/mame$ver.tar.gz"
src="$here/build/src/mame-mame$ver"

mkdir -p "$here/build/dl" "$here/build/src"
if [[ ! -f "$tarball" ]]; then
  curl -sSfL -o "$tarball" "https://github.com/mamedev/mame/archive/refs/tags/mame$ver.tar.gz"
fi
echo "$sha  $tarball" | shasum -a 256 -c -

if [[ ! -d "$src" ]]; then
  tar -xzf "$tarball" -C "$here/build/src"
fi
for p in "$here"/patches/mame$ver-*.patch; do
  if patch -d "$src" -p1 -R --dry-run -s < "$p" >/dev/null 2>&1; then
    echo "already applied: $(basename "$p")"
  else
    patch -d "$src" -p1 < "$p"
  fi
done

# Homebrew's build environment adds its include/lib paths automatically; do
# that by hand. sqlite is keg-only and must come before the macOS SDK's, which
# lacks sqlite3_enable_load_extension.
brew_prefix="$(brew --prefix)"
sqlite="$(brew --prefix sqlite)"
export CPATH="$sqlite/include:$brew_prefix/include${CPATH:+:$CPATH}"
export LIBRARY_PATH="$sqlite/lib:$brew_prefix/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
export PKG_CONFIG_PATH="$sqlite/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

# Same options as Homebrew's mame formula, limited to the Apollo driver.
cd "$src"
make -j"$(sysctl -n hw.ncpu)" \
  SUBTARGET=apollo SOURCES=src/mame/apollo/apollo.cpp REGENIE=1 \
  PYTHON_EXECUTABLE="$(command -v python3)" \
  OSD=sdl3 USE_LIBSDL=1 NOWERROR=1 \
  USE_SYSTEM_LIB_EXPAT=1 USE_SYSTEM_LIB_ZLIB=1 USE_SYSTEM_LIB_ASIO=0 \
  USE_SYSTEM_LIB_FLAC=1 USE_SYSTEM_LIB_GLM=1 USE_SYSTEM_LIB_JPEG=1 \
  USE_SYSTEM_LIB_PORTAUDIO=1 USE_SYSTEM_LIB_PORTMIDI=1 USE_SYSTEM_LIB_PUGIXML=1 \
  USE_SYSTEM_LIB_RAPIDJSON=0 USE_SYSTEM_LIB_SQLITE3=1 USE_SYSTEM_LIB_UTF8PROC=1 \
  USE_SYSTEM_LIB_ZSTD=1

install -m 755 "$src/apollo" "$here/build/mame-apollo"
echo "built $here/build/mame-apollo"
