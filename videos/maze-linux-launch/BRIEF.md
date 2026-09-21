---
workflow: product-launch-video
flow: automation
storyboard: yes
message: "Nothing leaves the machine."
destination: website-youtube
aspect: 1920x1080
language: en
audience: privacy- and security-minded Linux users; Arch users evaluating a hardened daily driver
length: 25s
angle: reveal
narration: no
music: none
capture: no-capture
style_preset: broadside
---

## Intent

A 25-second launch film for Maze Linux — an Arch-based, privacy- and security-focused
distribution. Visual language: Apple product film. OLED black (#000) ground, a single
accent (#00E5FF cyan), JetBrains Mono typography (explicitly not Inter). No narration;
music will be added by the user later. On-screen text only — at most 4 words visible at
once, never a sentence. Rhythm alternates 1.5–2s fast cuts with 3–4s breathing beats.
The user wrote the scene list; this run builds exactly those nine scenes.

## Assets

- ../../work/x86_64/airootfs/usr/share/pixmaps/maze-logo.png — stand-in logo (669×373,
  white mark + wordmark on transparent). The user will later drop `assets/maze-logo-4k.png`
  in its place; scenes 2 and 9 reference the logo by the staged path `assets/maze-logo.png`.

## Customizations

- Scene list (user-authored, fixed order):
  1. Black, one line appears: "Your machine remembers everything."
  2. Logo — slow scale-in.
  3. LUKS2 · Secure Boot UKI · nftables — three consecutive fast cuts.
  4. Panic Mode: screen darkens, "Network severed. RAM wiped."
  5. Forensics Mode: RAM-only boot visualisation.
  6. Deception Technology: honeypot trigger, cyan alarm.
  7. Hardware Privacy Controller: five icons switch off one by one.
  8. Haze Protocol · HazeDrop · Entropy Shield · Ollama — "Nothing leaves the machine."
  9. Logo + mazelinux.berkkucukk.com.tr
- Every frame moves: no scene is ever fully static — a slow push-in or pan runs continuously.
- All transitions GSAP, easing power3.inOut. No linear easing anywhere.
- Text enters from 24px below + opacity, stagger 0.06s.
- Depth: back layer blur(8px) scale(1.04); front layer sharp.
- No footage for now — scenes 3 and 8 use animated typography and geometric composition;
  the user will add screen recordings later.

## Notes

- Colours: ground #000000, accent #00E5FF only. No secondary hues, no gradients into other colours.
- Type: JetBrains Mono for everything (display and body).
- Max 4 words on screen at once; no sentence construction (except the two quoted lines the
  user wrote verbatim for scenes 1 and 4 — they're the copy, keep them as written).
- Audio: no VO; `music: none` for now — user supplies a track later. Project is marked silent.
- Logo: `assets/maze-logo-4k.png` does not exist yet; the 669×373 pixmap stands in.
- Language of on-screen copy: English (the user's scene copy is English; the brief itself was Turkish).
