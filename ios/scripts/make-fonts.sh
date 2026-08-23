#!/usr/bin/env bash
# Generate the four static Archivo faces the app bundles.
#
# Why this exists: plan Task 2 Step 3 says "open fonts.google.com -> Get font ->
# Download all". That endpoint is browser-gated (curl returns an HTML page, not a
# zip) and google/fonts only ships the VARIABLE face `Archivo[wdth,wght].ttf`,
# which Task 2 correctly forbids: `Font.custom` on iOS renders only a variable
# font's default instance, so every weight would come out Regular.
#
# So we download the variable face from google/fonts and pin it to four static
# instances with fontTools' instancer, rewriting the name records and
# OS/2.usWeightClass so the PostScript names are exactly what
# ThemeTests/TypographyTests asserts:
#   Archivo-Regular / Archivo-Medium / Archivo-SemiBold / Archivo-Bold
#
# Idempotent. Safe to re-run. Output: ios/Headstart/Fonts/*.ttf + OFL.txt
set -euo pipefail

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FONTS_DIR="$IOS_DIR/Headstart/Fonts"
mkdir -p "$FONTS_DIR"

PY="${HS_PYTHON:-}"
if [ -z "$PY" ]; then
  for cand in /Library/Frameworks/Python.framework/Versions/3.10/bin/python3 python3; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import fontTools' >/dev/null 2>&1; then
      PY="$cand"; break
    fi
  done
fi
if [ -z "$PY" ]; then
  echo "make-fonts.sh: no python3 with fontTools found. Set HS_PYTHON=/path/to/python3" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

VF_URL='https://raw.githubusercontent.com/google/fonts/main/ofl/archivo/Archivo%5Bwdth%2Cwght%5D.ttf'
OFL_URL='https://raw.githubusercontent.com/google/fonts/main/ofl/archivo/OFL.txt'

echo "make-fonts.sh: downloading Archivo variable face"
curl -sSL --fail -o "$WORK/Archivo[wdth,wght].ttf" "$VF_URL"
curl -sSL --fail -o "$WORK/OFL.txt"                "$OFL_URL"

# The OFL requires the copyright notice to travel with the fonts.
cp "$WORK/OFL.txt" "$FONTS_DIR/OFL.txt"

HS_VF="$WORK/Archivo[wdth,wght].ttf" HS_OUT="$FONTS_DIR" "$PY" - <<'PY'
import os, sys
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

vf_path = os.environ["HS_VF"]
out_dir = os.environ["HS_OUT"]

WEIGHTS = [("Regular", 400), ("Medium", 500), ("SemiBold", 600), ("Bold", 700)]

MAC, WIN = (1, 0, 0), (3, 1, 0x409)

def set_name(font, name_id, value):
    for plat, enc, lang in (MAC, WIN):
        font["name"].setName(value, name_id, plat, enc, lang)

for subfamily, wght in WEIGHTS:
    font = TTFont(vf_path)
    instantiateVariableFont(font, {"wght": wght, "wdth": 100},
                            inplace=True, updateFontNames=False)
    set_name(font, 1, "Archivo")                      # family
    set_name(font, 2, subfamily)                      # subfamily
    set_name(font, 4, f"Archivo {subfamily}")         # full name
    set_name(font, 6, f"Archivo-{subfamily}")         # PostScript name
    font["OS/2"].usWeightClass = wght
    # Typographic (preferred) names, if present, would otherwise still advertise
    # the variable family and confuse CoreText's face matching.
    for nid in (16, 17):
        rec = font["name"].getDebugName(nid)
        if rec is not None:
            set_name(font, 16, "Archivo")
            set_name(font, 17, subfamily)
    dest = os.path.join(out_dir, f"Archivo-{subfamily}.ttf")
    font.save(dest)
    font.close()
    print(f"  wrote {dest}")

# Assertions: no fvar left, PostScript name exact, weight class exact.
failures = []
for subfamily, wght in WEIGHTS:
    dest = os.path.join(out_dir, f"Archivo-{subfamily}.ttf")
    f = TTFont(dest)
    if "fvar" in f:
        failures.append(f"{dest}: still has an fvar table (not a static instance)")
    ps = f["name"].getDebugName(6)
    if ps != f"Archivo-{subfamily}":
        failures.append(f"{dest}: PostScript name is {ps!r}, expected 'Archivo-{subfamily}'")
    if f["OS/2"].usWeightClass != wght:
        failures.append(f"{dest}: usWeightClass is {f['OS/2'].usWeightClass}, expected {wght}")
    f.close()
if failures:
    for line in failures:
        print("ASSERTION FAILED:", line, file=sys.stderr)
    sys.exit(1)
print("make-fonts.sh: all four faces verified (no fvar, exact PostScript names, exact weight class)")
PY

ls -la "$FONTS_DIR"
