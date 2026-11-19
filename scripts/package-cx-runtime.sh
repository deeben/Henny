#!/bin/bash
#
#  package-cx-runtime.sh
#  Henny
#
#  Packages a CrossOver-source Wine engine (built with wine-cx-sikarugir, which
#  outputs a Sikarugir "wswine.bundle") plus Apple's D3DMetal into the
#  Libraries.tar.xz that Henny downloads, and writes HennyWineVersion.plist.
#
#  CrossOver's loader finds ntdll.so through realpath(bin/wine), so bin/wine
#  stays a symlink and bin/wine64 (what Henny runs) points at it. The loader
#  is ad-hoc signed with no entitlements: CrossOver's audio-input/camera
#  entitlements made Battle.net's Chromium renderer crash under Henny.
#
#  Usage:
#    scripts/package-cx-runtime.sh \
#      --engine  <WS12WineCX*.tar.xz>             from wine-cx-sikarugir/dist
#      --gptk    <Game Porting Toolkit .dmg>      e.g. 3.0, the version CrossOver ships
#      --version 11.30.0                          runtime version, any x.y.z
#      [--extras <folder with DXVK/, winetricks, verbs.txt>]
#                                                 default: Whisky's Libraries folder
#      [--r2-bucket henny]                        upload with wrangler if given
#
#  Output: build/runtime-cx/Libraries.tar.xz and build/runtime-cx/HennyWineVersion.plist
#

set -euo pipefail

ENGINE="" GPTK_DMG="" VERSION="" R2_BUCKET=""
EXTRAS="$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --engine) ENGINE="$2"; shift 2 ;;
        --gptk) GPTK_DMG="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --extras) EXTRAS="$2"; shift 2 ;;
        --r2-bucket) R2_BUCKET="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

[[ -n "$ENGINE" && -n "$GPTK_DMG" && -n "$VERSION" ]] || {
    sed -n '15,23p' "$0"; exit 1; }
[[ "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || {
    echo "--version must look like 1.2.3" >&2; exit 1; }
MAJOR=${BASH_REMATCH[1]} MINOR=${BASH_REMATCH[2]} PATCH=${BASH_REMATCH[3]}

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/runtime-cx"
WORK="$(mktemp -d)"
trap 'hdiutil detach -quiet "$WORK/gptk-eval" 2>/dev/null || true; hdiutil detach -quiet "$WORK/gptk" 2>/dev/null || true; chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
LIB="$WORK/Libraries"
mkdir -p "$LIB" "$OUT"

echo "==> Wine engine"
mkdir -p "$WORK/engine"
tar -xJf "$ENGINE" -C "$WORK/engine"
[[ -d "$WORK/engine/wswine.bundle/lib/wine" ]] || { echo "No wswine.bundle in $ENGINE" >&2; exit 1; }
mv "$WORK/engine/wswine.bundle" "$LIB/Wine"
[[ -L "$LIB/Wine/bin/wine" ]] || { echo "bin/wine must be a symlink for CrossOver's loader" >&2; exit 1; }
ln -s wine "$LIB/Wine/bin/wine64"
# 0008 corrupts the macOS QoS TSD slot and makes cfprefsd crash (see wine-cx-sikarugir/patches/disabled)
if grep -qa WINE_FIBER_GS_MIRROR "$LIB/Wine/lib/wine/x86_64-windows/kernelbase.dll"; then
    echo "warning: engine still has the fiber %gs mirror patch (0008); Henny sets WINE_FIBER_GS_MIRROR=0" >&2
fi

echo "==> DXVK, winetricks and verbs.txt from $EXTRAS"
for item in DXVK winetricks verbs.txt; do
    [[ -e "$EXTRAS/$item" ]] || { echo "Missing $EXTRAS/$item" >&2; exit 1; }
    ditto "$EXTRAS/$item" "$LIB/$item"
done
chmod -R u+w "$LIB/DXVK" "$LIB/winetricks" "$LIB/verbs.txt"

echo "==> D3DMetal from the Game Porting Toolkit"
mkdir -p "$WORK/gptk" "$WORK/gptk-eval"
# `yes` is killed by SIGPIPE once hdiutil stops reading; don't let pipefail treat that as failure.
{ yes || true; } | hdiutil attach -quiet -nobrowse -readonly -mountpoint "$WORK/gptk" "$GPTK_DMG"
REDIST="$(find "$WORK/gptk" -type d -path '*/redist/lib' -print -quit)"
# GPTK 3 and later nest redist/lib inside "Evaluation environment for Windows games *.dmg".
if [[ -z "$REDIST" ]]; then
    EVAL_DMG="$(find "$WORK/gptk" -maxdepth 1 -name 'Evaluation environment*.dmg' -print -quit)"
    [[ -n "$EVAL_DMG" ]] && { yes || true; } | hdiutil attach -quiet -nobrowse -readonly \
        -mountpoint "$WORK/gptk-eval" "$EVAL_DMG"
    REDIST="$(find "$WORK/gptk-eval" -type d -path '*/redist/lib' -print -quit)"
fi
[[ -d "$REDIST" ]] || { echo "No redist/lib folder in the GPTK image" >&2; exit 1; }
ditto "$REDIST" "$LIB/Wine/lib"
echo "    D3DMetal $(defaults read "$LIB/Wine/lib/external/D3DMetal.framework/Resources/Info" CFBundleShortVersionString)"

echo "==> Signing the Wine loader"
xattr -cr "$LIB"
LOADER="$LIB/Wine/lib/wine/x86_64-unix/wine"
codesign -f -s - "$LOADER"

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
tar --no-xattrs --no-mac-metadata -cJf "$OUT/Libraries.tar.xz" -C "$WORK" Libraries
(cd "$OUT" && shasum -a 256 Libraries.tar.xz) | tee "$OUT/Libraries.tar.xz.sha256"
du -h "$OUT/Libraries.tar.xz"
SIZE_MB=$(( $(stat -f %z "$OUT/Libraries.tar.xz") / 1048576 ))

echo "==> Smoke test (wine --version under Rosetta)"
CHECK="$WORK/check"
mkdir -p "$CHECK/tmp"
tar -xJf "$OUT/Libraries.tar.xz" -C "$CHECK"
TMPDIR="$CHECK/tmp" arch -x86_64 "$CHECK/Libraries/Wine/bin/wine64" --version

if [[ -n "$R2_BUCKET" ]]; then
    if (( SIZE_MB >= 300 )); then
        echo "Archive is ${SIZE_MB} MiB, over wrangler's 300 MiB limit." >&2
        exit 1
    fi
    echo "==> Uploading to R2 bucket $R2_BUCKET"
    for f in Libraries.tar.xz Libraries.tar.xz.sha256 HennyWineVersion.plist; do
        npx --yes wrangler r2 object put "$R2_BUCKET/Wine/$f" --file "$OUT/$f" --remote
    done
fi
