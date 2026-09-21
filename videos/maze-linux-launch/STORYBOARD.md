---
format: 1920x1080
duration: 25s
message: "Nothing leaves the machine."
arc: Hook (pain) → Brand → Feature-Benefit Cascade → Climax → Brand_Outro
audience: privacy- and security-minded Linux users; Arch users evaluating a hardened daily driver
mode: collaborative
music: none
language: en
---

## Video direction

- **Palette (frame.md roles):** ground `ink-black` #000000 on every frame — true OLED black, never lifted. Text `cream` #FFFFFF. Muted `cream-muted` #8A9194, hint `cream-hint` #3E4547, hairlines `border-dark` #1A2022. `fire-orange` = #00E5FF cyan is the ONLY hue and is rationed to one element per frame (rule stub, status dots, kicker, caret, the 06 alarm). No gradients into another colour; the single sanctioned bloom is 06's radial cyan at ≤12%.
- **Type (frame.md roles):** JetBrains Mono on every role — `@font-face` from `assets/fonts/JetBrainsMono-{300,400,500,600,700}.woff2`. Statement lines = `quote-text` role (400, −0.02em); feature words = `h2` (500); kickers/labels = `label` (500, 0.14em, uppercase); URL = `lead` (400, muted). Sentence case. Hard cap: ≤4 words visible at any instant (settled muted names in 08 count toward it).
- **Depth model (brief):** two planes on every frame that has a ground element — back plane `filter: blur(8px)` + `scale(1.04)` at ≤45% opacity (the drifting grid), front plane crisp. `→ depth-of-field-blur` (static two-plane form). The grid: 1px `border-dark` lines, 154px cells, drifting up-left at (−12px/s, −12px/s) as a finite translate tween.
- **Camera (brief override of the back-half rule):** the user requires that NO frame is ever fully static — every frame carries one continuous, very low-amplitude camera move for its full duration: a push-in of ~2.5–3% total scale or a lateral pan of ~1.5% width, `power3.inOut`, ONE tween end-to-end, never restarting. The amplitude sits below the sightline-disruption threshold; treat it as the film's constant breath, not a per-scene move. `→ multi-phase-camera` (single-phase form).
- **Motion grammar:** all eases `power3.inOut` (brief); `power3.out` allowed only on text entrances where inOut reads sluggish; NO linear anywhere except the caret blink square wave. Text enters from 24px below + opacity 0→1, per-word/per-line stagger 0.06s — the brief's numbers override `waterfall-entry`'s binary-opacity default. Reveals are paced across each frame's duration on the `on_screen` cue order; nothing dumps at t=0.
- **Rhythm / holds:** breaths (01, 02, 04, 07, 08) reveal across their first ~60% and hold a read for the rest under the constant camera breath; fast beats (03, 05, 06) reveal continuously — no hold. 09 holds from 1.6s.
- **Handoffs:** the drifting grid is one continuous element across 01→02 and 07→08→09: same cell size, same drift vector; `handoff_out`/`handoff_in` give its exact offset at each seam. Every other seam is a deliberate clean cut.
- **Caption band:** captions disabled (no VO) but every frame keeps the bottom 17% clear of primary content — kickers sit in the top third or at the 74% line at the lowest.
- **Negative list:** no Inter, no second hue, no gradients (except 06's bloom), no shadows/radius, no CRT/scanline/glitch pastiche, no particles, no infinite loops, no `Math.random`, no CSS transitions/keyframes; no slideshow (dump-then-freeze) and no screensaver (independent floating). No real cursors or browser chrome. No sentences beyond the three the user wrote.

## Locked

- Sheet v1 confirmed as-is on 2026-09-20: placement, hierarchy and copy of all nine frames.
- Build dresses these layouts (motion + real assets); it never redraws them.

## Frame 1 — Remembers

- scene: Pure black; one line surfaces from below, word by word, under a barely-visible drifting grid
- voiceover: ""
- on_screen: "Your machine remembers everything."
- duration: 3.2s
- poster: 2.2s
- transition_in: cut
- status: built
- src: compositions/frames/01-remembers.html
- type: hook
- persuasion: Pain validation
- beat: unease
- asset_candidates:
- blueprint: kinetic-type-beats (Adapt)
- focal: (typography)
- roles: (none — typography-only)
- camera: push-in, scale 1.00 → 1.025 over 0.0–3.2s
- handoff_out: grid — cell 154px, 1px #1A2022, back plane blur(8px) scale(1.04) opacity 0.35; offset at 3.2s = (−38px, −38px), drifting (−12px/s, −12px/s), opacity 0.35 constant. Line "Your machine remembers everything." — centered, quote-text role, opacity 1, camera scale 1.025 at the cut, still.

Adapt: keep the signature — the words ARE the motion; one line built word-by-word, no swap. Single statement, then a held read.
Scene 1 (0.0–0.6s): black. Only the back-plane grid exists — blurred, 35%, offset (0,0) at t=0 and already drifting up-left; the push-in has begun. Centered, layered-depth; nothing else on screen.
Scene 2 (0.6–1.5s): "Your" · "machine" · "remembers" · "everything." rise from 24px below with 0.06s stagger, opacity 0→1, into one centered two-line block (~50% of frame width) — quote-text role, white. `→ waterfall-entry` (brief offsets)
Scene 3 (1.5–3.2s): held read. The line is still; only the constant push-in and the grid drift continue. Exit is the crossfade into 02.

narrativeRole: The hook — names the pain in the viewer's own language. Everything after is the answer to this line.
keyMessage: Your default OS keeps a record of you.

## Frame 2 — Logo

- scene: The Maze mark scales in slowly from a soft-blur back plane to a crisp front plane; cyan hairline rule stub underlines it
- voiceover: ""
- on_screen: "(logo)"
- duration: 2.8s
- poster: 2.0s
- transition_in: crossfade 0.6s
- status: animated
- src: compositions/frames/02-logo.html
- type: product_intro
- persuasion: Authority by restraint
- beat: intrigue → calm
- asset_candidates: assets/maze-logo.png — white maze mark + MAZE LINUX wordmark, transparent PNG (stand-in for maze-logo-4k.png)
- blueprint: logo-assemble-lockup (Adapt)
- focal: assets/maze-logo.png
- roles: maze-logo = cutout (hero, centered, ~30% of frame width at rest)
- camera: push-in, scale 1.00 → 1.03 over 0.0–2.8s (the logo's own scale-in rides on top)
- handoff_in: grid — identical element to 01's: cell 154px, blur(8px) scale(1.04) opacity 0.35; offset at 0.0s = (−38px, −38px), drifting (−12px/s, −12px/s). No text carried in (01's line leaves with the crossfade).
- handoff_out: none — hard cut into 03; the grid does not continue.

Adapt: keep the signature — the mark comes to exist on screen — as a slow blur-to-crisp scale-in instead of an assembly. No orbiting parts, no letter cascade.
Scene 1 (0.0–1.6s): the logo emerges dead-center from the back plane: opacity 0→1, scale 0.92→1.0, blur 8px→0 — one long power3.inOut tween, so it rises out of the depth into focus. `→ depth-of-field-blur` (two-plane rack; a plain fromTo scale 0.92→1 rides on it — no overshoot). Grid keeps drifting behind.
Scene 2 (1.2–1.8s): the cyan rule stub (36×2) draws left→right beneath the wordmark — the frame's one cyan element — a plain scaleX 0→1 fromTo, origin left.
Scene 3 (1.8–2.8s): held read under the constant push-in. Nothing else moves.

narrativeRole: Product intro — the answer arrives as an identity, not a claim. Wordless premium sting.
keyMessage: Maze Linux.

## Frame 3 — Foundation

- scene: Three hard-cut typographic beats — LUKS2 / Secure Boot UKI / nftables — each a single large word-group with one geometric glyph (lock square · shield chevron · lattice) and a tiny cyan label
- voiceover: ""
- on_screen: "LUKS2" → "Secure Boot UKI" → "nftables"
- duration: 2.4s
- poster: 1.3s
- transition_in: cut
- status: built
- src: compositions/frames/03-foundation.html
- type: feature_showcase
- persuasion: Rule of three
- beat: confidence
- asset_candidates:
- blueprint: kinetic-type-beats (Reproduce — hard-cut word-swap form)
- focal: (typography + geometry)
- roles: (none — typography-only; the glyphs are placeholders for the user's later screen recordings)
- camera: three restarted push-ins, one per beat — each beat 1.00 → 1.03 across its own 0.8s; the restart is masked by the hard cut

Scene 1 (0.0–0.8s): hard cut to BEAT 1. Triptych framing (three equal columns split by 1px hairlines), only the LEFT column lit: a 1px hint-grey square with an inner 1px white square (the lock glyph) draws itself, "LUKS2" rises from 24px below (h2 role, white), cyan label "disk" rises 0.06s later. The other two columns hold their word as ghost text at 28% opacity (no glyph). `→ svg-path-draw` + `waterfall-entry` (beat swaps are plain `tl.set` state changes at 0.8s and 1.6s)
Scene 2 (0.8–1.6s): hard cut to BEAT 2 — instant state swap, no fade: CENTER column lit — shield glyph (two vertical hairlines bridged by one white rule) draws, "Secure Boot" / "UKI" rise as two lines, label "boot". Left column drops to 28% ghost.
Scene 3 (1.6–2.4s): hard cut to BEAT 3 — RIGHT column lit — a 1px lattice (4×4 hint-grey grid) draws in, "nftables" rises, label "network". Center drops to 28%. Beat 3 runs into the cut to 04.

narrativeRole: First evidence — the hardened base, stated as three tokens at fast-cut tempo (~0.8s each). Placeholder for the user's future screen recordings.
keyMessage: Encrypted disk, signed boot, firewall by default.

## Frame 4 — Panic Mode

- scene: The frame goes dark in a hard brightness collapse; a cyan "PANIC MODE" label, then "Network severed." then "RAM wiped." land one after the other on near-black
- voiceover: ""
- on_screen: "Panic Mode" → "Network severed." → "RAM wiped."
- duration: 3.0s
- poster: 2.2s
- transition_in: cut
- status: animated
- src: compositions/frames/04-panic-mode.html
- type: feature_showcase
- persuasion: Show-don't-tell proof
- beat: tension → control
- asset_candidates:
- blueprint: kinetic-type-beats (Adapt)
- focal: (typography)
- roles: (none — typography-only)
- camera: push-in, scale 1.00 → 1.03 over 0.0–3.0s

Adapt: keep the signature — a statement builds across beats, each its own move. Add the brightness collapse as the entrance beat.
Scene 1 (0.0–0.25s): the frame opens LIT — a crisp front-plane grid at 60% opacity (154px cells, hint-grey lines), reading as a live screen — and collapses to black in 0.25s: opacity 0.6→0 on power3.in, plus the grid scale snaps 1.0→0.985 (a brightness drop, not a fade) — two plain fromTo tweens.
Scene 2 (0.5–0.9s): kicker "PANIC MODE" (label role, cyan, tracked) rises at the 30% line. The frame's one cyan element.
Scene 3 (1.0–1.4s): "Network severed." rises from 24px below into center (quote-text role, white).
Scene 4 (1.8–2.2s): "RAM wiped." rises directly beneath it; as it lands, "Network severed." settles to `cream-muted` (opacity to 0.55) so only one line is white. `→ waterfall-entry`
Scene 5 (2.2–3.0s): held read under the push-in.

narrativeRole: Breathing beat with drama — one keypress and the machine goes silent. The blackout IS the feature.
keyMessage: One action, everything cut.

## Frame 5 — Forensics Mode

- scene: A geometric RAM-only boot: a row of memory cells fills with cyan ticks left→right while a disk outline beneath it is struck through and fades; label "RAM-only boot"
- voiceover: ""
- on_screen: "Forensics Mode" · "RAM-only boot"
- duration: 2.0s
- poster: 1.4s
- transition_in: cut
- status: animated
- src: compositions/frames/05-forensics-mode.html
- type: feature_showcase
- persuasion: Feature-to-benefit translation
- beat: clarity
- asset_candidates:
- blueprint: grid-card-assemble (Adapt)
- focal: (geometry)
- roles: (none — typography + geometry)
- camera: lateral pan left→right, x 0 → −1.5% of width over 0.0–2.0s

Adapt: keep the signature — items self-assemble in a staggered cascade — as eight memory cells ticking on. Add the struck disk as the counter-image.
Scene 1 (0.0–0.3s): kicker "FORENSICS MODE" (label role, cyan) rises top-left at the 6% margin. Eight empty 1px hint-grey cells sit centered as a row (~45% of frame width) — present from t=0, unlit.
Scene 2 (0.3–1.3s): the cells tick cyan left→right — a cyan bar fills inside each at 0.12s intervals (scaleX 0→1, power3.out). The kicker settles to hint-grey as the first cell lights, so cyan stays one element. `→ stat-bars-and-fills` (stagger fill)
Scene 3 (0.9–1.3s): "RAM-only boot" rises beneath the row (h3 role, white).
Scene 4 (1.2–1.8s): a 1px disk outline (wide rectangle) beneath the label is struck through — a hairline draws across it at −8° — and the outline fades to 20%. `→ svg-path-draw` (strike stroke)
Scene 5 (1.8–2.0s): runs into the cut; no hold.

narrativeRole: Fast cut — the system can run leaving no trace on disk.
keyMessage: Boot from memory, write nothing.

## Frame 6 — Deception

- scene: A quiet lattice of dark nodes; one node is touched, a cyan alarm ring expands from it and the whole frame pulses once with a cyan bloom; "HONEYPOT TRIGGERED" label, then "Deception Technology"
- voiceover: ""
- on_screen: "Honeypot triggered" → "Deception Technology"
- duration: 2.4s
- poster: 1.5s
- transition_in: cut
- status: built
- src: compositions/frames/06-deception.html
- type: feature_showcase
- persuasion: Negative contrast (the intruder loses)
- beat: alert → power
- asset_candidates:
- blueprint: compose
- focal: (geometry)
- roles: (none — geometry + typography)
- camera: push-in, scale 1.00 → 1.03 over 0.0–2.4s

Compose: no blueprint fits "one node trips the wire".
Scene 1 (0.0–0.4s): a sparse lattice of nine small hint-grey squares (0.6% of frame width) at the sketch's positions, each entering opacity 0→0.6 on an index-derived 0.04s stagger; three hairline connectors between neighbours draw on. `→ waterfall-entry` (opacity form) + `svg-path-draw`
Scene 2 (0.4–1.0s): the CENTRE node flips to cyan and scales 1→1.6; two concentric 1px cyan rings expand from it (scale 0→1 at 22% and 8% of frame width, opacity 1→0 on power3.out, the outer lagging the inner by 0.15s); a radial cyan bloom pulses in behind at 12% and decays to 0 by 1.4s — the film's only bloom. `→ ambient-glow-bloom` (single pass) + `spring-pop-entrance`
Scene 3 (0.7–1.1s): kicker "HONEYPOT TRIGGERED" (label role, cyan) rises at the 74% line.
Scene 4 (1.6–2.0s): the kicker hard-cut swaps to "Deception Technology" set as an h2 line (white, sentence case) — instant state swap, no fade. `→ discrete-text-sequence`
Scene 5 (2.0–2.4s): runs into the blur-crossfade; rings have fully decayed by 1.8s so the seam carries only the lattice + line.

narrativeRole: Fast cut with the video's single loud moment — cyan is spent here as an alarm.
keyMessage: Intruders trip the wire, not you.

## Frame 7 — Hardware Privacy

- scene: Five line icons in a row — Camera · Microphone · Bluetooth · WiFi · USB — each switches off in turn (icon dims, a cyan status dot goes dark, a hairline strike crosses it); label "Hardware Privacy Controller"
- voiceover: ""
- on_screen: "Hardware Privacy Controller" + five icons
- duration: 3.0s
- poster: 2.4s
- transition_in: blur-crossfade 0.5s
- status: built
- src: compositions/frames/07-hardware-privacy.html
- type: feature_showcase
- persuasion: Show-don't-tell proof
- beat: control
- asset_candidates:
- blueprint: grid-card-assemble (Adapt)
- focal: (icons)
- roles: (none — five 1px-stroke line icons hand-drawn as inline SVG: camera, microphone, bluetooth, wifi, usb)
- camera: push-in, scale 1.00 → 1.025 over 0.0–3.0s
- handoff_out: grid — cell 154px, back plane blur(8px) scale(1.04) opacity 0.35; offset at 3.0s = (−36px, −36px), drifting (−12px/s, −12px/s). Icon row centered at 50%/52%, all five OFF (stroke hint-grey, dot at 25%, strike drawn), camera scale 1.025, opacity 1, still.

Adapt: keep the signature — items self-assemble in a cascade — then invert it: the cascade is the switch-OFF. Five line icons in one centered row (~55% of frame width), each with a cyan status dot and a hint label beneath.
Scene 1 (0.0–0.5s): the back-plane grid fades up (blurred, 35%, drifting, offset (0,0) at t=0). Kicker "HARDWARE PRIVACY CONTROLLER" (label role, hint-grey — cyan is spent on the dots) rises at the 20% line.
Scene 2 (0.4–0.9s): the five icons rise from 24px below with 0.06s stagger, all LIT — white strokes, cyan dots, labels Camera · Mic · Bluetooth · WiFi · USB in hint. `→ waterfall-entry`
Scene 3 (0.9–2.65s): switch-off cascade, one every 0.35s, left→right: the icon stroke dims white→hint, the cyan dot goes dark (opacity 1→0.25), a hairline strike draws across the icon at −30° (scaleX 0→1). Camera 0.9s · Mic 1.25s · Bluetooth 1.6s · WiFi 1.95s · USB 2.3s. `→ svg-icon-enrichment` + `svg-path-draw` + `dynamic-content-sequencing`
Scene 4 (2.65–3.0s): held read — all five off, under the push-in.

narrativeRole: Breathing beat — the physical kill-switch idea, one device at a time.
keyMessage: Every sensor has an off.

## Frame 8 — Nothing leaves

- scene: A thin square outline (the machine) holds center; four names — Haze Protocol · HazeDrop · Entropy Shield · Ollama — surface inside it one at a time and settle to muted; then they clear and "Nothing leaves the machine." lands alone
- voiceover: ""
- on_screen: "Haze Protocol" → "HazeDrop" → "Entropy Shield" → "Ollama" → "Nothing leaves the machine."
- duration: 3.4s
- poster: 2.9s
- transition_in: crossfade 0.6s
- status: built
- src: compositions/frames/08-nothing-leaves.html
- type: benefit_highlight
- persuasion: Value stacking → thesis
- beat: inevitability
- asset_candidates:
- blueprint: fixed-anchor-cycle (Adapt)
- focal: (typography + geometry)
- roles: (none — typography-only; the square is the placeholder for the user's later screen recordings)
- camera: push-in, scale 1.00 → 1.03 over 0.0–3.4s
- handoff_in: grid — identical element to 07's: cell 154px, blur(8px) scale(1.04) opacity 0.35; offset at 0.0s = (−36px, −36px), drifting (−12px/s, −12px/s). Nothing else carried in.
- handoff_out: grid — offset at 3.4s = (−77px, −77px), same drift, opacity 0.35. Square outline (46% × 26% of frame, 1px #8A9194) centered at 50%/50%, opacity 1, camera scale 1.03, still — 09's logo lands inside its footprint.

Adapt: keep the signature — one element stays PINNED while the region inside it cycles states. The anchor is the square outline (the machine); the cycle is the four names surfacing; the emphasis beat is the thesis line.
Scene 1 (0.0–0.5s): the square outline draws itself — one continuous 1px muted-grey stroke from the top-left corner around — centered, ~46% of frame width. `→ svg-path-draw`
Scene 2 (0.5–1.9s): inside the square, top-left, the four names surface one at a time at 0.35s intervals, each rising 24px + opacity as a label-role line (uppercase, tracked): "HAZE PROTOCOL" 0.5s · "HAZEDROP" 0.85s · "ENTROPY SHIELD" 1.2s · "OLLAMA" 1.55s. Each lands white and, as the next arrives, settles to hint-grey — only the newest is white. `→ waterfall-entry` + `dynamic-content-sequencing`
Scene 3 (1.9–2.3s): the four names fade to 0 together (opacity, power3.inOut), clearing the square.
Scene 4 (2.3–2.9s): "Nothing leaves the machine." rises from 24px below into the square's centre (quote-text role, white) — the four words 0.06s apart. The cyan rule stub draws beneath it at 2.7s — the frame's one cyan element.
Scene 5 (2.9–3.4s): held read under the push-in; exit is the crossfade into 09.

narrativeRole: Climax — the four tools that keep traffic, files and AI inside the box, then the thesis line. Placeholder for future screen recordings.
keyMessage: Nothing leaves the machine.

## Frame 9 — Outro

- scene: Logo settles center with a continuous slow push-in; the URL mazelinux.berkkucukk.com.tr types beneath it in muted mono, a cyan cursor blinks once and holds
- voiceover: ""
- on_screen: "(logo)" + "mazelinux.berkkucukk.com.tr"
- duration: 2.8s
- poster: 2.2s
- transition_in: crossfade 0.8s
- status: built
- src: compositions/frames/09-outro.html
- type: branding
- persuasion: Risk-free next step
- beat: peace of mind
- asset_candidates: assets/maze-logo.png — white maze mark + MAZE LINUX wordmark, transparent PNG (stand-in for maze-logo-4k.png)
- blueprint: logo-assemble-lockup (Adapt — end-card extension)
- focal: assets/maze-logo.png
- roles: maze-logo = cutout (hero, centered at 50%/44%, ~30% of frame width); typewriter (registry component `typewriter`) = supporting, the URL line
- camera: push-in, scale 1.00 → 1.03 over 0.0–2.8s — continuous; this frame must never stop moving
- handoff_in: grid — identical element to 08's: cell 154px, blur(8px) scale(1.04) opacity 0.35; offset at 0.0s = (−77px, −77px), drifting (−12px/s, −12px/s). The logo enters already at opacity 1 inside the footprint 08's square held, so the crossfade reads as the box becoming the mark.

Adapt: keep the signature — the lockup resolves and extends to a URL end card. No assembly; the logo is present from t=0 (the crossfade IS its entrance).
Scene 1 (0.0–0.8s): logo held centered, crisp, under the push-in; grid drifts behind. Nothing else.
Scene 2 (0.8–1.6s): "mazelinux.berkkucukk.com.tr" types beneath the logo character by character behind a cyan block caret (lead role, muted) — `typewriter` registry component, installed and skinned to frame.md tokens. The caret is the frame's one cyan element. `→ discrete-text-sequence` + `context-sensitive-cursor`
Scene 3 (1.6–2.8s): held. The caret blinks exactly twice (square wave, finite) then holds solid; the push-in runs to the last frame. The film ends on this hold — no exit motion.

narrativeRole: Brand outro — identity + one place to go.
keyMessage: mazelinux.berkkucukk.com.tr
