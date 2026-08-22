# Headstart — design canvas

Source of truth for the app's UI. Each `.dc.html` is one artboard; `canvas.json` lays them out.

Published canvas: https://claude.ai/code/artifact/6692b71e-794c-451a-a1ce-0c10715d9a82

## Tokens
| Role | Value |
|---|---|
| Base background | `#15171B` |
| Card | `#1E2126` |
| Raised / control | `#262A30` |
| Line | `#31363D` |
| Text primary | `#F2F4F7` |
| Text secondary | `#A8B0BA` |
| Text tertiary | `#6D7681` |
| Go (driver acts) | `#3AD693` — oklch(.78 .15 155) |
| Headstart (walk out now) | `#F0A13C` — oklch(.78 .15 65) |
| Delayed (stay inside) | `#EF6F52` — oklch(.70 .15 25) |

Type: **Archivo** (400/500/600/700), fallback `system-ui, "Helvetica Neue", Arial`. Countdowns and clock times use `font-variant-numeric: tabular-nums`.
Radii: 12–14 px controls, 16–22 px cards, 26 px sheets. Controls 56 px tall; nothing interactive under 44 px.

## Rules the design encodes
- The **receiver owns the headstart value**; the driver cannot set it for them.
- Only the walk-out alert is time-sensitive (own sound, breaks through focus). Everything else stays quiet.
- Every screen states the privacy position in plain words; nothing is shared until the driver taps.
- No fake status bars or keyboards — the OS draws those.

## Regenerating
```bash
cd design
node "<design skill dir>/seed-canvas.mjs" \
  --template "<design skill dir>/payload.template.html" \
  --out headstart-app-design.html --title "Headstart App Design" \
  $(for f in *.dc.html; do printf -- "--artboard $f "; done) --canvas canvas.json
```
Then republish `headstart-app-design.html` to the same artifact URL.

## Placeholders to replace before launch
- **Sara** — stand-in name for the paired person.
- The QR square on `PairInvite.dc.html` is a drawn pattern, not a scannable code.
