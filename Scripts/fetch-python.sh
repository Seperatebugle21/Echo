#!/bin/bash
#
# Downloads BeeWare's iOS Python.xcframework (CPython 3.13) into
# Python/Python.xcframework. Run this before `xcodegen generate`.
#
# yt-dlp needs Python 3.11 or newer; kewlbear/Python-iOS only ships 3.10.
# To upgrade, change the build tag and the checksum below together
# (https://github.com/beeware/Python-Apple-support/releases).

set -euo pipefail

PYTHON_VERSION="3.13"
SUPPORT_BUILD="b18"
SHA256="d06acf2a9c7964a8689566353a0e707402eff822037de5e29ba0e16040f7047d"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Python"
STAMP="$DEST/.version"
WANTED="$PYTHON_VERSION-$SUPPORT_BUILD"

if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$WANTED" ] \
    && [ -d "$DEST/Python.xcframework" ]; then
    echo "Python $WANTED already present."
    exit 0
fi

ARCHIVE="Python-$PYTHON_VERSION-iOS-support.$SUPPORT_BUILD.tar.gz"
URL="https://github.com/beeware/Python-Apple-support/releases/download/$PYTHON_VERSION-$SUPPORT_BUILD/$ARCHIVE"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading $URL"
curl --fail --location --retry 3 --silent --show-error \
    --output "$TMP/$ARCHIVE" "$URL"

echo "$SHA256  $TMP/$ARCHIVE" | shasum -a 256 -c -

mkdir -p "$TMP/extract"
tar -xzf "$TMP/$ARCHIVE" -C "$TMP/extract"

rm -rf "$DEST/Python.xcframework"
mkdir -p "$DEST"
mv "$TMP/extract/Python.xcframework" "$DEST/Python.xcframework"
echo "$WANTED" > "$STAMP"

echo "Installed Python $WANTED in $DEST/Python.xcframework"
