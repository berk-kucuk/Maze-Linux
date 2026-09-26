# Maze Linux Wiki

Maze Linux is a security-, privacy- and AI-focused desktop built on Arch Linux. It ships a complete, hardened KDE Plasma 6 Wayland desktop with security tools, anonymity software, and a local AI runtime already configured and enabled — ready from first boot.

## Start here

- [Installation Guide](Installation) — write the ISO, boot live, install
- [First Boot / MOK](FirstBoot) — **the blue screen on first reboot is not an error**
- [After Install](After-Install) — first steps once the installer finishes

## When something goes wrong

- [Won't Boot?](Recovery) — five steps, top to bottom
- [Diagnostics](Diagnostics) — `maze-doctor`, `maze-boot-check`
- [Kill Switches](Hardware) — "why isn't my camera working?"

## Keeping the system healthy

- [Updating](Updating) — what happens on every `pacman -Syu`
- [Snapshots & Rollback](Snapshots) — undo a bad update
- [Kernel Management](Kernels) — the recovery kernel

## Reference

- [Tools & Apps](Tools) — every built-in app explained
- [Maze Connect](MazeConnect) — phone ↔ desktop
- [Security Reference](Security) — what's running and why
- [Privacy Reference](Privacy) — anonymity stack and MAC randomization
- [Secure Boot](SecureBoot) — the signing chain in detail
- [AI & Development](AI-Dev) — Ollama, local LLMs and the dev toolchain
- [FAQ](FAQ) — common questions
- [Known Limitations](Limitations) — what Maze does *not* do

## Quick facts

| | |
|---|---|
| Base | Arch Linux (rolling release) |
| Desktop | KDE Plasma 6.7 · Wayland · SDDM |
| Architecture | x86\_64 · **UEFI only** (no BIOS/Legacy) |
| Release | 2026-06-21 "Labyrinth" |
| ISO size | ~4.7 GB |
| License | GPLv3 |

## System requirements

| | Minimum | Recommended |
|---|---|---|
| Boot | **UEFI required** | UEFI + Secure Boot |
| CPU | x86\_64 | — |
| RAM | 4 GB | 8 GB+ (16 GB for local AI) |
| Disk | 40 GB | 100 GB+ |
| ESP | 512 MB | **1 GB+** (room for two kernel images) |

## What's pre-enabled

| Layer | Tool |
|-------|------|
| Mandatory access control | AppArmor |
| Host firewall | firewalld / nftables |
| Network attack detection | Maze Guard |
| Antivirus | ClamAV + QLAM |
| Brute-force protection | fail2ban |
| Audit logging | auditd |
| MAC randomization | Maze Cloak |
| Encrypted DNS | DNSCrypt-proxy |
| Local AI runtime | Ollama |
| Anonymity layer | Entropy Shield (Tor + I2P + DNSCrypt) |
| Automatic snapshots | snap-pac + btrfs |
| Signed boot chain | Secure Boot + signed Unified Kernel Image |

USB device blocking (USBGuard) is installed but **off by default** — you turn
it on in Maze Hardware. See [Kill Switches](Hardware).

## Getting help

Open an [issue on GitHub](https://github.com/berk-kucuk/Maze-Linux/issues) for bugs or feature requests. Attach the output of `sudo maze-doctor` — it answers most questions on its own.
