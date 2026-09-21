# Hyperframes Composition Brief: Maze Linux

## Objective
Create a short, cold, terminal-aesthetic brag video for Maze Linux. No startup hype.

## Output
- Composition directory: `brag-output/composition/`
- Rendered video: `brag-output/brag.mp4`
- Format: landscape — 1920x1080
- Duration: 21 seconds

## Source Material
- Project root: `MazeLinux/` (archiso profile for the distro)
- Primary files read: `README.md`, `MD-Files/FEATURES.md`, `MD-Files/WEB-VE-WIKI-ICERIGI.md`, `profiledef.sh`, `airootfs/etc/motd`, `airootfs/etc/maze/sentinel.conf`
- Product name: Maze Linux
- Tagline / strongest claim: it does not say "something was blocked" — it tells you which device, when, and what it did
- Key UI or visual moment to recreate: a terminal — the `mazelinux --status` report and a `maze-guard` detection record
- Copy that must appear verbatim:
  - `mazelinux --status`
  - the 7-line status report from `brag-plan.md` Scene 2
  - `Most systems tell you: "something was blocked."`
  - the 5-line `[maze-guard]` record from `brag-plan.md` Scene 4
  - `Maze names the device.`
  - `MAZE LINUX`
  - `Arch · KDE Plasma · UEFI-only · signed kernel · nothing leaves the machine`
  - `mazelinux.berkkucukk.com.tr`

## Creative Direction
- Tone preset: deadpan (structure) + polished (restraint)
- Creative direction: cold, technical, OLED black with cyan accent, terminal aesthetic, no startup hype
- Interpretation: one thought per scene; long holds; monospace only; no gradients, glows, particles or stock motion; motion = typing, line-by-line printing, slow crossfades; cyan is the only colour and is rationed to cursor, prompt, status values and the identifying fields of the detection
- Angle: the product is only allowed to speak through its own terminal output. The differentiator is a dry contrast: everyone else says "blocked"; Maze names the device.
- Hook: shell prompt on black, cyan block cursor blinks once, `mazelinux --status` types out, Enter
- Outro / punchline: `Maze names the device.` → `MAZE LINUX` wordmark → fact line + URL → hold
- Avoid:
  - Generic SaaS language
  - Abstract filler visuals
  - Unrelated visual redesign
  - Any glow/bloom/scanline/CRT pastiche — this is a modern OLED terminal, not retro

## Visual Identity
- Background: `#000000`
- Text: `#E6E6E6` (primary), `#7A7A7A` (labels / secondary)
- Accent: `#22D3EE`
- Display font: Hack (local TTF shipped in `assets/fonts/`, `@font-face` declared in-file)
- Body font: Hack
- Visual references from the project: true-black OLED identity (Plymouth / SDDM / installer branding), `mazelinux --status` CLI, Maze Guard attacker record

## Storyboard
Use the storyboard in `brag-output/brag-plan.md` as the creative contract.

Scene summary:
1. Prompt — 3.0s — prompt + cursor blink, `mazelinux --status` typed, Enter
2. Status report — 5.0s — 7 lines print one by one, hold
3. The contrast — 4.0s — one centred sentence on black
4. The detection — 5.0s — `[maze-guard]` header + 4 fields print, hold
5. Outro — 4.0s — sentence → wordmark → fact line + URL, hold

## Audio
- Audio role: intentional near-silence — synthesized cold low bed + sparse motion-matched SFX
- Audio arc: keys → quiet uniform ticks → bed alone → one soft weight (detection) → one soft weight (wordmark) → silence
- Music: `assets/music/cold-bed.wav` (ffmpeg-synthesized: 55 Hz sine + low-passed brown noise, ≈ -30 dBFS). The bundled "Happy Beats / Business Moves" tracks are deliberately not used — they are the startup hype the direction forbids.
- Music treatment: volume lane fade-in 0→1 over 1 s, hold, fade-out to 0 over the last 2 s (19→21 s)
- Music cue guidance: unavailable by design (featureless bed, no beat grid); natural timing throughout
- Audio-reactive treatment: none
- Audio-coupled moments:
  - Scene 1 typing — keypress ticks per character (randomised across `keyboard/keypress-*.wav`, low volume)
  - Scene 2 status lines — one low-HF-risk tick per printed line at the print time
  - Scene 4 header — one soft low impact at landing; quiet ticks per field
  - Scene 5 wordmark — one soft impact at landing
- SFX selection guidance: only low high-frequency-risk files; nothing bright, nothing sustained; if a sound would be noticed as a sound it is too loud
- SFX analysis guidance: `<skill-dir>/assets/sfx/sfx-analysis.md` (skill-dir = `~/.claude/plugins/cache/brag/brag/0.2.2/skills/brag`)
- Exact SFX choice: Hyperframes chooses filenames, timestamps, density, and volume from the implemented animation
- Audio files: copy chosen music and SFX into `brag-output/composition/assets/`

## Hyperframes Instructions
Load `hyperframes-core`, `hyperframes-animation`, `hyperframes-creative`, `hyperframes-keyframes`, `hyperframes-cli`. /brag is its own workflow — no intent interview, no generic launch-video route.

Requirements:
- Show at least one real UI/copy element from the project (the CLI report and the maze-guard record).
- Keep all text readable; every printed line holds ≥ 0.8 s; sentences hold ≥ 0.3 s/word.
- 21 s total.
- Include the cold bed and the sparse SFX above.
- Keep the timeline alive throughout (blinking caret / staged reveals) so `check` does not flag `sweep_static`.
- Local assets only (fonts, audio). GSAP from CDN is acceptable per the core skeleton.
- Run `npx hyperframes check` before render.
