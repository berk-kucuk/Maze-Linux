# Hyperframes Composition Brief: Maze Linux (v2)

## Objective
A 28.5 s capability walk for Maze Linux following the user's five-part flow. Pure black, one cyan accent, monospace, no stock visuals, no people, no adjectives.

## Output
- Composition directory: `composition/`
- Rendered video: `brag.mp4`
- Format: landscape — 1920x1080
- Duration: 28.5 s

## Source Material
- Product name: Maze Linux
- Logo: `airootfs/usr/share/plasma/look-and-feel/com.mazelinux.oled/contents/splash/logo.png` → `assets/logo.png`
- Copy that must appear verbatim: see `brag-plan.md` storyboard (hook line, base lines, four feature titles + descriptors, tool list, cloud line, URL)

## Creative Direction
- Tone: deadpan structure, polished restraint; flat technical sentences
- Banned: "revolutionary", "powerful", "flawless", any hype adjective; gradients, glows, particles, scanlines
- Motion: fades and line-by-line printing only; fade-through-black between scenes

## Visual Identity
- Background `#000000`; text `#E6E6E6`; dim `#8C8C8C`; titles `#FFFFFF`; accent `#22D3EE`
- Font: Hack (local TTF, `@font-face` in-file)

## Storyboard
See `brag-plan.md`. Five parts, 28.5 s total.

## Audio
- Bed: `assets/music/cold-bed.wav` (synthesized, 28.5 s), volume lane fade in 1 s / out last 2.5 s
- SFX: `ui/click2.ogg` ticks on printed lines and feature titles; `impact/impactSoft_medium_001.ogg` on both logo landings; all low HF-risk, low volume
- No audio-reactive treatment; no beat sync (no grid)

## Hyperframes Instructions
Standalone monolithic `index.html`; one paused GSAP timeline; local assets; `npx hyperframes check` must pass with 0 errors before render.
