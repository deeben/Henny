#!/bin/bash
#
#  build-runtime.sh
#  Henny
#
#  Packages a Wine build, Apple's D3DMetal (from the Game Porting Toolkit)
#  and DXVK into the Libraries.tar.xz that Henny downloads on first launch,
#  writes HennyWineVersion.plist, and optionally uploads both to Cloudflare R2.
#
#  Run on a Mac. Nothing here is downloaded automatically from Apple: you
#  supply the GPTK disk image yourself after accepting Apple's license.
#  Check that license before making the result publicly downloadable.
#
#  Usage:
#    scripts/build-runtime.sh \
#      --wine   <wine .tar.xz/.tar.gz or URL>     e.g. a Gcenx macOS Wine build
#      --gptk   <Game Porting Toolkit .dmg>       from developer.apple.com
#      --dxvk   <DXVK-macOS .tar.gz or URL>       optional
#      --version 1.0.0                            runtime version, any x.y.z
#      [--r2-bucket henny-runtime]                upload with wrangler if given
#
#  Output: build/runtime/Libraries.tar.xz and build/runtime/HennyWineVersion.plist
#

set -euo pipefail

WINE_SRC="" GPTK_DMG="" DXVK_SRC="" VERSION="" R2_BUCKET=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --wine) WINE_SRC="$2"; shift 2 ;;
        --gptk) GPTK_DMG="$2"; shift 2 ;;
        --dxvk) DXVK_SRC="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --r2-bucket) R2_BUCKET="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

[[ -n "$WINE_SRC" && -n "$GPTK_DMG" && -n "$VERSION" ]] || {
    sed -n '14,22p' "$0"; exit 1; }
[[ "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || {
    echo "--version must look like 1.2.3" >&2; exit 1; }
MAJOR=${BASH_REMATCH[1]} MINOR=${BASH_REMATCH[2]} PATCH=${BASH_REMATCH[3]}

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/runtime"
WORK="$(mktemp -d)"
trap 'hdiutil detach -quiet "$WORK/gptk-eval" 2>/dev/null || true; hdiutil detach -quiet "$WORK/gptk" 2>/dev/null || true; rm -rf "$WORK"' EXIT
LIB="$WORK/Libraries"
mkdir -p "$LIB" "$OUT"

fetch() {  # fetch <path-or-url> <dest>
    if [[ "$1" =~ ^https?:// ]]; then curl -fL --progress-bar -o "$2" "$1"; else cp "$1" "$2"; fi
}

echo "==> Wine"
fetch "$WINE_SRC" "$WORK/wine.tar"
mkdir -p "$WORK/wine-x"
tar -xf "$WORK/wine.tar" -C "$WORK/wine-x"
# Gcenx builds unpack to e.g. "Wine Devel.app/Contents/Resources/wine"; find the folder with bin/wine*.
WINE_DIR="$(dirname "$(dirname "$(find "$WORK/wine-x" -type f \( -name wine64 -o -name wine \) -path '*/bin/*' | head -1)")")"
[[ -d "$WINE_DIR/bin" ]] || { echo "Couldn't find bin/wine in the Wine archive" >&2; exit 1; }
cp -R "$WINE_DIR" "$LIB/Wine"
# Henny launches bin/wine64. Wine 9+ "new WoW64" builds only ship bin/wine.
if [[ ! -e "$LIB/Wine/bin/wine64" && -e "$LIB/Wine/bin/wine" ]]; then
    ln -s wine "$LIB/Wine/bin/wine64"
    echo "    linked bin/wine64 -> wine"
fi

echo "==> D3DMetal from the Game Porting Toolkit"
{ yes || true; } | hdiutil attach -quiet -nobrowse -readonly -mountpoint "$WORK/gptk" "$GPTK_DMG"
REDIST="$(find "$WORK/gptk" -type d -path '*/redist/lib' -print -quit)"
# GPTK 4 nests redist/lib inside "Evaluation environment for Windows games *.dmg".
if [[ -z "$REDIST" ]]; then
    EVAL_DMG="$(find "$WORK/gptk" -maxdepth 1 -name 'Evaluation environment*.dmg' | head -1)"
    if [[ -n "$EVAL_DMG" ]]; then
        { yes || true; } | hdiutil attach -quiet -nobrowse -readonly -mountpoint "$WORK/gptk-eval" "$EVAL_DMG"
        REDIST="$(find "$WORK/gptk-eval" -type d -path '*/redist/lib' -print -quit)"
    fi
fi
[[ -d "$REDIST" ]] || { echo "No redist/lib folder in the GPTK image" >&2; exit 1; }
# redist/lib holds external/D3DMetal.framework, external/libd3dshared.dylib and
# wine/x86_64-windows/{d3d11,d3d12,dxgi,...}.dll; they overlay Wine's own lib folder.
ditto "$REDIST" "$LIB/Wine/lib"

if [[ -n "$DXVK_SRC" ]]; then
    echo "==> DXVK"
    fetch "$DXVK_SRC" "$WORK/dxvk.tar"
    mkdir -p "$WORK/dxvk-x"
    tar -xf "$WORK/dxvk.tar" -C "$WORK/dxvk-x"
    DXVK_DIR="$(dirname "$(find "$WORK/dxvk-x" -type d -name x64 | head -1)")"
    mkdir -p "$LIB/DXVK"
    cp -R "$DXVK_DIR/x64" "$DXVK_DIR/x32" "$LIB/DXVK/"
fi

echo "==> winetricks"
curl -fsSL -o "$LIB/winetricks" \
    https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
chmod +x "$LIB/winetricks"

echo "==> Version plist"
cat > "$LIB/HennyWineVersion.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>version</key>
    <dict>
        <key>major</key><integer>$MAJOR</integer>
        <key>minor</key><integer>$MINOR</integer>
        <key>patch</key><integer>$PATCH</integer>
        <key>preRelease</key><string></string>
        <key>build</key><string></string>
    </dict>
</dict>
</plist>
PLIST
plutil -lint "$LIB/HennyWineVersion.plist" >/dev/null
cp "$LIB/HennyWineVersion.plist" "$OUT/HennyWineVersion.plist"

echo "==> Packing (xz, takes a few minutes)"
# xz keeps the archive small enough for wrangler's 300 MiB upload limit.
# macOS tar auto-detects the compression when Henny extracts it.
# Files unpacked from a browser download carry com.apple.quarantine, and macOS tar
# would store it in the archive, making Gatekeeper block every Wine binary for users.
xattr -cr "$LIB"
tar --no-xattrs --no-mac-metadata -cJf "$OUT/Libraries.tar.xz" -C "$WORK" Libraries
(cd "$OUT" && shasum -a 256 Libraries.tar.xz) | tee "$OUT/Libraries.tar.xz.sha256"
du -h "$OUT/Libraries.tar.xz"
SIZE_MB=$(( $(stat -f %z "$OUT/Libraries.tar.xz") / 1048576 ))

if [[ -n "$R2_BUCKET" ]]; then
    if (( SIZE_MB >= 300 )); then
        echo "Archive is ${SIZE_MB} MiB, over wrangler's 300 MiB limit." >&2
        echo "Upload build/runtime/* to $R2_BUCKET/Wine/ with rclone instead (see R2 docs)." >&2
        exit 1
    fi
    echo "==> Uploading to R2 bucket $R2_BUCKET"
    for f in Libraries.tar.xz Libraries.tar.xz.sha256 HennyWineVersion.plist; do
        npx --yes wrangler r2 object put "$R2_BUCKET/Wine/$f" --file "$OUT/$f" --remote
    done
    echo "Set HennyWineInstaller.runtimeBaseURL to <your bucket's public URL>/Wine/"
fi
