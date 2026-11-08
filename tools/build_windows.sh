#!/usr/bin/env bash
# Reproducible TinserBox Windows x64 build (runs on Linux).
# Requires: Godot 4.3 (set GODOT=/path/to/godot), python3 + Pillow, mingw-w64, nsis, zip, curl, wine
# (wine runs rcedit, which Godot uses to set the exe icon and version info).
#   sudo apt install mingw-w64 nsis zip wine64 && pip install pillow
# Produces dist/TinserBox_Portable_Win64.zip and dist/TinserBox_Setup_Win64.exe.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
VERSION="1.0.0"
APP="$ROOT/build/windows/TinserBox"
DIST="$ROOT/dist"
TEMPLATES="$HOME/.local/share/godot/export_templates/4.3.stable"
TPZ="https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_export_templates.tpz"

rm -rf "$ROOT/build/windows" && mkdir -p "$APP" "$DIST"
# Remove previous artifacts so a failed build never leaves an older installer looking current.
rm -f "$DIST/TinserBox_Setup_Win64.exe" "$DIST/TinserBox_Portable_Win64.zip"
touch "$ROOT/build/.gdignore" "$DIST/.gdignore"

# 1. Windows export template (only that file is fetched from the ~1 GB template archive).
if [ ! -f "$TEMPLATES/windows_release_x86_64.exe" ]; then
  python3 -I "$ROOT/tools/fetch_zip_member.py" "$TPZ" "$TEMPLATES" templates/windows_release_x86_64.exe templates/version.txt
fi

# 2. Icon (icon.png / icon.ico).
python3 "$ROOT/tools/make_icon.py"

# 3. Media-key helper (Windows System Media Transport Controls).
x86_64-w64-mingw32-windres "$ROOT/tools/media_keys/TinserBoxMedia.rc" -O coff -o "$ROOT/build/windows/media_res.o"
x86_64-w64-mingw32-g++ -O2 -s -static -mwindows -o "$APP/TinserBoxMedia.exe" \
  "$ROOT/tools/media_keys/main.cpp" "$ROOT/build/windows/media_res.o" -lws2_32 -lruntimeobject -lole32 -luuid -lmfplat -lmfreadwrite -lmfuuid

# 4. Godot export (single exe with embedded pck; music/backgrounds stay external).
RCEDIT="$HOME/.local/share/rcedit/rcedit-x64.exe"
[ -f "$RCEDIT" ] || curl -sSLf --create-dirs -o "$RCEDIT" https://github.com/electron/rcedit/releases/download/v2.0.0/rcedit-x64.exe
"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
sed -i "s|^export/windows/rcedit = .*|export/windows/rcedit = \"$RCEDIT\"|; s|^export/windows/wine = .*|export/windows/wine = \"$(command -v wine)\"|" \
  "$HOME/.config/godot/editor_settings-4.3.tres"
"$GODOT" --headless --path "$ROOT" --export-release "Windows Desktop" "$APP/TinserBox.exe"

# 5. External user folders with the bundled songs/backgrounds, plus docs.
mkdir -p "$APP/music" "$APP/backgrounds"
find "$ROOT/music" -maxdepth 1 -type f \( -iname '*.mp3' -o -iname '*.ogg' -o -iname '*.wav' \) -exec cp {} "$APP/music/" \;
find "$ROOT/backgrounds" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -exec cp {} "$APP/backgrounds/" \;
cp "$ROOT/tools/README.txt" "$APP/README.txt"

# 6. Portable zip.
rm -f "$DIST/TinserBox_Portable_Win64.zip"
(cd "$(dirname "$APP")" && zip -qr -9 "$DIST/TinserBox_Portable_Win64.zip" TinserBox)

# 7. Installer.
LC_ALL=C.UTF-8 makensis -V2 -DVERSION="$VERSION" -DSRC="$APP" -DICON="$ROOT/icon.ico" \
  -DOUT="$DIST/TinserBox_Setup_Win64.exe" "$ROOT/tools/installer.nsi"

ls -la "$DIST"
echo "Latest installer: $DIST/TinserBox_Setup_Win64.exe ($(date -r "$DIST/TinserBox_Setup_Win64.exe" '+%Y-%m-%d %H:%M:%S'))"
