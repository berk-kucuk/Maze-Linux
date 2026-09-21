# Brag Plan: Maze Linux

## What is this app?
Maze Linux is an Arch-based, UEFI-only, hardened KDE Plasma distribution
(btrfs + LUKS, shim → signed Unified Kernel Image, AppArmor/firewalld/OpenSnitch
on by default, nothing leaves the machine) whose distinguishing claim is that it
does not just block a network attack — it tells you *which device, when, and what
it did*.

## The angle
No hype. The whole video is a terminal on an OLED-black screen. The product is
allowed to speak only through its own output: one command, its status report,
and one Maze Guard detection record. The differentiator is stated as a dry
contrast — every other system says "something was blocked"; Maze names the
device. The restraint *is* the confidence.

## Hook (first 2-3 seconds)
A single shell prompt on pure black. Cyan block cursor blinks once. Then
`mazelinux --status` is typed character by character, Enter. Nothing else on
screen. The viewer is already inside the machine.

## Key moments (the middle)
- The `--status` report printing line by line: boot chain
  `shim → signed UKI → kernel`, `btrfs + LUKS`, AppArmor / firewalld /
  OpenSnitch / auditd `active`, `maze-guard watching`, `telemetry none`.
- The dry contrast line, alone on black: *Most systems tell you: "something was blocked."*
- A Maze Guard event record arriving field by field — timestamp, attack type,
  device MAC, vendor, IP, OS, action — with the identifying fields in cyan.

## Outro / punchline
`Maze names the device.` — then the wordmark `MAZE LINUX`, one small line of
facts (`Arch · KDE Plasma · UEFI-only · signed kernel · nothing leaves the machine`)
and the URL. Long hold on black.

## User flow worth showing
1. **Entry** — boot into the live system, open a terminal, run `mazelinux --status`.
2. **Key action** — the report shows the hardened stack is not "available", it is
   *on*: Secure Boot enrolled, disk encrypted, MAC controls on, Maze Guard watching.
3. **Result** — when a device on the network tries an ARP spoof, Maze Guard logs
   who it was (MAC, vendor, IP, OS), when, what it tried, and that evidence was
   written — not a vague "blocked" toast.

(The detection record is an illustrative sample event in the real
`maze-guard` format — MAC/vendor/IP are placeholders.)

## Tone
- Preset: deadpan (structure/pacing) with polished restraint
- Creative direction: cold, technical, OLED black with cyan accent, terminal aesthetic, no startup hype
- Interpretation: one thought per scene, long holds, monospace everything,
  no gradients, no glow blobs, no stock motion. Motion is limited to typing,
  line-by-line printing, and slow crossfades. The only colour is a single cyan
  used for the cursor, the prompt, and the identifying fields of the detection.

## Format: landscape — 1920x1080
## Duration: 21 seconds

## Visual identity (from the project)
- Background: `#000000` (true-black OLED identity used across Plymouth, SDDM, installer branding)
- Accent: `#22D3EE` (cyan — user direction; project itself is black + white)
- Text: `#E6E6E6` primary, `#7A7A7A` dim/secondary
- Display font: Hack (installed locally) → fallback `JetBrains Mono`, `DejaVu Sans Mono`, monospace
- Body font: same monospace family — one typeface for the whole video
- Strongest visual element: the terminal itself — `mazelinux --status` output and a `maze-guard` event record

## Share copy (draft)
Maze Linux: Arch, hardened, UEFI-only, signed kernel, nothing leaves the machine — and when a device on your network attacks you, it tells you which one. Not "something was blocked".

## Audio direction
- Role: intentional near-silence — a cold, barely-there low bed plus sparse motion-matched SFX
- Music: **none of the bundled tracks** ("Happy Beats / Business Moves" is exactly the startup hype the direction forbids). Instead a synthesized cold bed generated with ffmpeg: a low sine (~55 Hz) under band-limited brown noise, at very low level (≈ -30 dBFS), 1 s fade-in, 2 s fade-out under the final hold. Written to `composition/assets/music/cold-bed.wav`.
- Music treatment: starts at 0 s, constant, no swell; fades out over the final 2 s so the video ends in silence.
- Music cue guidance: no bundled preset (synthesized bed has no beat grid). Cues not applicable — use natural timing throughout; readability governs.
- Audio-reactive treatment: none. The bed is featureless by design; nothing should pulse.
- SFX posture: sparse. Keypress ticks for the typed command, a very quiet uniform tick as each status line prints (low HF-risk clicks only), one soft low impact when the detection header lands, one soft impact on the wordmark. Nothing bright, nothing repeated at high frequency.
- Audio-coupled moments: typed command (keypress ticks), line-by-line status print (ticks), detection record (header impact, then quieter ticks per field), wordmark landing (single soft impact).
- Restraint rule: no music beat, no risers, no whoosh, no glitch stingers, no "error" buzzers. If a sound would be noticed as a sound, it is too loud.

## Storyboard

### Scene 1 — Prompt — 3.0s
Pure black. Top-left-ish (comfortable terminal margin, not centred), a prompt in
cyan: `maze@maze:~$ ` followed by a cyan block cursor. Cursor blinks once
(~0.6 s), then `mazelinux --status` types out at human speed (~0.08 s/char,
~1.4 s), short pause, Enter — the cursor drops to the next line.
Sequential/interaction: yes — typing simulated character by character, then Enter.
Audio intent: the room is silent except the keys.
Audio-coupled idea: keypress ticks per character (vary files, low volume); no sound on Enter.
Music: cold bed fades in over the first second.
Transition mood: none (hard continuation — output prints in the same terminal) → Scene 2

### Scene 2 — Status report — 5.0s
The `--status` report prints below the prompt, one line every ~0.35 s, then holds
fully visible for the remaining ~2.5 s. Monospace, aligned columns; labels dim
grey, values light grey; the words `enrolled`, `encrypted`, `active`, `watching`,
`none` in cyan. Lines (verbatim):
```
MAZE LINUX 2026.09        arch x86_64 · kde plasma 6 / wayland
boot        shim → signed UKI → kernel     secure boot   enrolled
disk        btrfs + LUKS                   encryption    on
apparmor    enforcing                      firewalld     active
opensnitch  active                         auditd        active
maze-guard  watching                       maze-cloak    stable mac
telemetry   none                           ai            local only
```
Sequential/interaction: yes — 7 lines arrive one by one, top to bottom.
Audio intent: mechanical, uniform, quiet — a printer, not a drumroll.
Audio-coupled idea: one quiet low-HF-risk tick per line at the exact print time.
Music: bed constant.
Transition mood: slow crossfade to black (0.8 s) → Scene 3

### Scene 3 — The contrast — 4.0s
Black. One sentence, centred, large monospace, light grey:
`Most systems tell you: "something was blocked."`
Fades in over 0.5 s, holds ~3 s. Nothing else. The cursor is gone.
Sequential/interaction: none
Audio intent: empty. The bed alone.
Audio-coupled idea: none
Music: bed constant.
Transition mood: hard cut → Scene 4

### Scene 4 — The detection — 5.0s
Back in the terminal. A Maze Guard event record prints, header first, then one
field every ~0.4 s, then holds ~2 s. The header line is white; the field values
`d4:6d:6d:1a:2b:3c`, `Hewlett-Packard`, `192.168.1.104`, `Windows 10/11` are
cyan. Lines (verbatim, illustrative sample event):
```
[maze-guard] 14:02:17  ARP spoofing — gateway impersonation attempt
  device    d4:6d:6d:1a:2b:3c   Hewlett-Packard
  ip        192.168.1.104
  os        Windows 10/11
  action    blocked · evidence written to /var/lib/maze-guard/attackers/
```
Sequential/interaction: yes — header, then 4 fields one by one.
Audio intent: the one moment with weight. Header lands with a soft low impact; the fields tick in quietly.
Audio-coupled idea: soft impact at header landing; quiet ticks per field.
Music: bed constant.
Transition mood: slow crossfade (0.8 s) → Scene 5

### Scene 5 — Outro — 4.0s
Black. Centred: `Maze names the device.` fades in (0.4 s), holds 1.2 s, then
shrinks/moves up slightly as the wordmark `MAZE LINUX` appears below it in
heavier monospace with wide letter-spacing. Under the wordmark, small and dim:
`Arch · KDE Plasma · UEFI-only · signed kernel · nothing leaves the machine`
and, below that, in cyan: `mazelinux.berkkucukk.com.tr`. Hold to the end.
Sequential/interaction: yes — sentence, then wordmark, then the fact line + URL.
Audio intent: settle. One soft impact on the wordmark, then the bed fades to silence.
Audio-coupled idea: single soft impact on wordmark landing.
Music: bed fades out over the final 2 s.
Transition mood: hold to black (end).

**Music mood for this video:** cold / featureless (synthesized low bed, no beats)
**Audio summary:** keys → quiet mechanical ticks → silence with a low bed → one soft weight on the detection → one soft weight on the name → silence.

Scene durations: 3.0 + 5.0 + 4.0 + 5.0 + 4.0 = **21.0 s**.
