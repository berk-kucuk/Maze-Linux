# Brag Plan: Maze Linux (v2 — user-specified flow)

## What is this app?
Maze Linux — an Arch-based, UEFI-only, hardened KDE Plasma distribution: LUKS2
full-disk encryption, Secure Boot with a signed Unified Kernel Image, an nftables
network layer, and a set of in-house privacy tools that never touch the cloud.

## The angle
The user's flow, verbatim in structure: a dry statement of the problem ("Your
machine remembers everything."), the logo, the base layer, four short feature
scenes, the integrated tool list with one emphasis line, close. No stock
imagery, no people, no adjectives. Every sentence is a fact stated flatly.

## Hook (first 2-3 seconds)
Black. One centred monospace line: `Your machine remembers everything.`
Holds, fades. The white Maze logo (from the OLED splash theme) fades in alone.

## Key moments (the middle)
- Base layer printed as three terminal lines: LUKS2 / Secure Boot · signed UKI / nftables.
- Four feature cards, one per scene, title + one flat descriptor line:
  Panic Mode, Forensics Mode, Deception Technology, Hardware Privacy Controller.
- Tool list printed line by line, then one cyan line: `None of them connect to the cloud.`

## Outro / punchline
Logo + `mazelinux.berkkucukk.com.tr`. Hold.

## User flow worth showing
Not a UI flow this time — the user asked for a capability walk. The product
is shown through its own vocabulary (mode names, tool names, exact mechanisms).

## Tone
- Preset: deadpan structure, polished restraint
- Creative direction: pure black, single cyan accent, monospace, no stock visuals, no people; short flat technical sentences; banned words: revolutionary / powerful / flawless and their kin
- Interpretation: one thought per scene; fade-through-black; the only motion is fades and line-by-line printing

## Format: landscape — 1920x1080
## Duration: 28.5 seconds (user asked for 20–30 s)

## Visual identity (from the project)
- Background: `#000000`
- Accent: `#22D3EE`
- Text: `#E6E6E6` / dim `#8C8C8C` / white `#FFFFFF` for titles
- Font: Hack (local TTF)
- Logo: `airootfs/usr/share/plasma/look-and-feel/com.mazelinux.oled/contents/splash/logo.png` (white, 320px, transparent)

## Share copy (draft)
Your machine remembers everything. Maze Linux: LUKS2, signed UKI, nftables — and a set of privacy tools that never connect to the cloud.

## Audio direction
- Role: intentional near-silence — synthesized cold bed + sparse ticks
- Music: `assets/music/cold-bed.wav` (ffmpeg-synthesized, 28.5 s; no bundled track — they are upbeat corporate beats)
- Music treatment: fade in 1 s, hold, fade out over the last 2.5 s
- Music cue guidance: unavailable by design (no beat grid); natural timing
- Audio-reactive treatment: none
- SFX posture: sparse — quiet tick per printed line, soft low impact when the logo lands (twice), a quiet tick on each feature title
- Restraint rule: no risers, no whooshes, no stingers

## Storyboard

### Scene 1 — Hook → logo — 4.5s (0.0–4.5)
Black. `Your machine remembers everything.` fades in at 0.3 (0.5 s), holds to 2.6, fades out (0.4 s). Logo fades in at 3.1 (0.5 s), holds to 4.5.
Sequential/interaction: sentence, then logo.
Audio: bed fades in; soft impact when the logo lands.
Transition: fade to black → Scene 2

### Scene 2 — Base — 5.0s (4.5–9.5)
Terminal block, top-left. Dim header `base`, then three lines print at 0.45 s intervals:
`LUKS2        full-disk encryption`
`Secure Boot  signed Unified Kernel Image`
`nftables     network layer`
Labels white, values light grey; hold to 9.1, fade out.
Sequential: yes — three lines. Audio: tick per line.
Transition: fade to black → Scene 3

### Scenes 3a–3d — Features — 4 × 2.6s (9.5–19.9)
Each: centred. Title in white (64 px), fades in with a quiet tick; 0.5 s later a dim descriptor line (34 px). Hold; fade out in the last 0.35 s.
- Panic Mode — `kill network · wipe RAM · lock screen`
- Forensics Mode — `RAM-only boot · nothing written to disk`
- Deception Technology — `honeypot tripped → alarm, lockdown`
- Hardware Privacy Controller — `webcam · mic · Bluetooth · Wi-Fi · USB — off at kernel level`
Transition: fade to black between each.

### Scene 4 — Integrated tools — 5.1s (19.9–25.0)
Terminal block. Dim header `integrated`, then five lines at 0.4 s intervals:
`Haze Protocol` / `Haze Chat` / `HazeDrop` / `Entropy Shield` / `Ollama       local AI`
Then, after a beat, in cyan: `None of them connect to the cloud.` Hold; fade out.
Sequential: yes. Audio: tick per line; nothing on the cyan line (silence is the emphasis).
Transition: fade to black → Scene 5

### Scene 5 — Close — 3.5s (25.0–28.5)
Logo fades in (soft impact), then `mazelinux.berkkucukk.com.tr` in cyan below it. Hold. Bed fades to silence.

Scene durations: 4.5 + 5.0 + 10.4 + 5.1 + 3.5 = **28.5 s**.
