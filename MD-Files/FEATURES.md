# Maze Linux — Features

> **Maze Linux** is a security‑ and privacy‑focused, AI‑ready Linux distribution
> built on Arch Linux. It ships a complete, hardened KDE Plasma (Wayland) desktop
> that works out of the box — no assembly required.

**Tagline ideas:** *“Arch, hardened and ready.” · “Privacy, security and AI — out of the box.” · “The complete Arch desktop.”*

---

## What is Maze Linux?

Maze Linux takes the power and freedom of Arch Linux and removes the part that
stops most people from using it: the hours of manual setup. It is **not a
minimal base** — it is a *complete* desktop you can boot, test live, and install,
with security, privacy and AI tooling already configured and turned on.

Three pillars define the project:

- 🛡️ **Security by default** — hardening and defensive tooling enabled from first boot.
- 🕵️ **Privacy by default** — anonymity tools, MAC randomization, private apps preconfigured.
- 🤖 **AI‑ready** — local LLM runtime and AI utilities included, plus a full dev toolchain.

---

## Maze Linux vs. stock Arch Linux

| Area | Stock Arch Linux | Maze Linux |
| --- | --- | --- |
| Out‑of‑the‑box state | Minimal base, no GUI | Complete KDE Plasma **Wayland** desktop |
| Installation | Manual / generic `archinstall` | Branded, **OLED‑themed Calamares** graphical installer (offline `unpackfs`) |
| Desktop & apps | None — you install everything | Curated apps preinstalled & configured |
| Security | You configure it yourself | AppArmor, firewalld, fail2ban, auditd, OpenSnitch **on by default** |
| Secure Boot | Manual key management | **UEFI Secure Boot out of the box** — shim + per‑machine MOK, kernel auto‑re‑signed on every update |
| Privacy | You configure it yourself | Tor, Mullvad, MAC randomization, private apps preconfigured |
| AI tooling | None | Ollama + AI utilities + dev toolchain included |
| Live ISO | Console rescue environment | Full desktop — the real system, testable live |
| Branding | Generic Arch | Maze identity: boot splash, theme, wallpaper, installer |
| Antivirus | None | ClamAV + **QLAM** GUI |
| Mirrors / repos | Manual | Reflector mirror ranking + multilib + Flathub + firmware updates (fwupd) |
| First‑run experience | None | Animated **Maze Welcome** app on the first boot after install |

**The short version:** stock Arch gives you a toolbox. Maze gives you a finished,
hardened workstation you can use immediately — while keeping Arch’s rolling
release, AUR access and full control.

---

## Complete KDE Plasma desktop (Wayland)

- Full **KDE Plasma 6 on Wayland**, not a stripped‑down spin.
- **SDDM** display manager with autologin into the live session.
- A **preconfigured desktop layout** — thin top status bar + bottom dock — with
  curated widgets (system monitor, network speed, weather, thermal, clock,
  app launcher) and a polished dark color scheme.
- A clean dock containing **only installed applications** plus a one‑click
  **Install Maze Linux** launcher.
- **PipeWire** audio stack, **NetworkManager** networking, Bluetooth, power
  profiles, and Vulkan/VA‑API graphics drivers (Intel/AMD/Nouveau + software
  fallback) for smooth performance in VMs and on real hardware.

## Security by default

Hardening and defensive tools are installed **and enabled** from first boot:

- **AppArmor** mandatory access control (enabled via kernel command line + service).
- **firewalld** with sensible service rules.
- **fail2ban** protecting SSH (systemd‑journal backend).
- **auditd** system auditing.
- **OpenSnitch** — interactive application firewall that asks before any app
  makes an outbound connection.
- **ClamAV** antivirus engine with the **QLAM** modern GUI.
- **rkhunter** and **lynis** for rootkit detection and security auditing.
- **Hardened SSH** defaults (no root login, limited auth attempts, no agent/TCP/X11
  forwarding). The SSH server is not enabled by default.
- **OpenSnitch** interactive application firewall (autostarts on the desktop), plus
  **firewalld**, **AppArmor** and **auditd** — all selectable in the installer's
  **Security** section.
- **Kernel & network hardening** — sensible `sysctl` defaults applied from first
  boot (hidden kernel pointers, restricted `dmesg`/`ptrace`, eBPF hardening,
  anti‑spoofing and ICMP/redirect protections).
- **UEFI Secure Boot** — works on both the live ISO and the installed system via
  a Microsoft‑signed **shim** that chainloads a Maze‑signed **Unified Kernel
  Image** (kernel + initramfs + cmdline bundled into one PE binary). Because the
  kernel is embedded in the UKI, the firmware never `LoadImage()`s a loose
  `vmlinuz`, so the chain is portable across every UEFI firmware — strict ones
  (MSI, some ASUS, …) that ignore the MOK for loose kernels and only consult
  their own `db` no longer reject the boot with *Security Policy Violation*. The
  key is enrolled once as a **MOK**, so factory and Windows keys are preserved
  (no firmware *Setup Mode*). The installed system uses a **per‑machine** key and
  re‑signs the kernel automatically on every update via a pacman hook.
  Toggleable in the installer.
- **Maze Control Center** — an OLED dashboard that shows the live state of every
  security service, MAC randomisation, the AI runtime and system maintenance,
  with one‑click copyable commands for any action.
- **Compressed RAM swap (zram)** for responsiveness under memory pressure.
- **Automatic, rollbackable upgrades** — when Btrfs snapshots are chosen in the
  installer, **snapper** + **snap‑pac** take a snapshot before and after every
  `pacman` transaction, with **grub‑btrfs** boot entries to roll back.

## Privacy by default

- **Hardened Firefox** out of the box — telemetry, Studies, Pocket and sponsored
  content disabled, tracking/fingerprinting/cryptomining protection and
  DNS‑over‑HTTPS on, Maze homepage.
- **MAC address randomization** — automatic and native via NetworkManager
  (`stable` per‑network MACs: your real hardware address is never exposed and
  you can't be tracked across networks, without the captive‑portal/DHCP
  breakage that per‑connection random causes). `change-mac-now` rotates to a
  fresh MAC on demand.
- **Tor**, **Tor Browser** and **OnionShare** for anonymous browsing/sharing.
- **Mullvad Browser**, **Proton VPN**, **WireGuard**, **OpenVPN**.
- **Session** private messenger.
- Network analysis tooling: **Wireshark**, **aircrack‑ng**, **nmap**.

## AI‑ready

- **Ollama** — run large language models locally, fully offline.
- **Upscayl** — AI image upscaling.
- Maze’s own AI utilities (**sentinai**, **linux‑chan‑ai**).
- Complete build toolchain (**base‑devel**, **git**, **Python**, **paru**) so you
  can pull and build AI projects from the AUR or source immediately.

## Maze’s own tools

Maze ships a suite of in‑house utilities developed for the distribution:

- **`mazelinux`** — the embedded command‑line companion. `mazelinux --welcome`
  greets you with a one‑glance, live‑state summary (identity, desktop, security
  services, anonymity, local AI); `--status` prints the full security / privacy
  / AI / system report, `--security` / `--privacy` / `--ai` / `--system` drill
  into one area, and `--json` emits it all machine‑readably. No GUI, no network
  calls — it reuses the same `maze_status` probes as the desktop apps.
- **QLAM** — a modern antivirus GUI powered by ClamAV.
- **entropy‑shield**, **sentinai**, **haze**, **hazedrop**, **linux‑chan‑ai**,
  **maze** — Maze’s own security and AI tooling, preinstalled and ready.

*(These ship preinstalled and offline; descriptions can be expanded on the website.)*

## Curated software suite

A genuinely usable desktop the moment you boot:

- **Browsers:** Firefox (default), Mullvad Browser, Tor Browser.
- **Productivity:** ONLYOFFICE, Joplin, KDE apps (Dolphin, Kate, Okular,
  Gwenview, Ark, …).
- **Communication & media:** Discord, Session, VLC.
- **Utilities:** Bitwarden, FileZilla, btop, fastfetch, KDE Partition Manager,
  Btrfs Assistant, Distrobox.

## Developer & virtualization

- **Virtualization is installed on demand, not preinstalled.** Run
  `maze-install-vmware` (or launch it from the application menu) and paru builds
  **VMware Workstation** + open-vm-tools from the AUR and enables its services.
  The KVM stack is one command away if you prefer it:
  `sudo pacman -S qemu-desktop libvirt virt-manager edk2-ovmf`. Nothing
  virtualization-related ships by default — qemu-full alone was ~2 GB of image
  size with no use in a live session.
- **Distrobox** for running other distros’ toolchains in containers.
- **multilib** enabled and **Flatpak + Flathub** preconfigured.
- **paru** AUR helper preinstalled — the full AUR is one command away.

## A live ISO that is the real thing

Many distros ship a cut‑down live environment. Maze’s **live ISO is the full
system**: the same hardened, AI‑ready KDE desktop, with the same apps and
services, so you can evaluate everything before installing — even offline,
because the AUR packages are **prebuilt into the image**.

## Branding & polish

- A coherent **true-black OLED identity** across the whole boot-to-desktop chain:
  - Custom **Plymouth** boot splash animation with the Maze logo.
  - **Maze OLED SDDM** login/greeter theme: pure-black, centred login card,
    live clock, session picker and power controls.
  - **Maze OLED Plasma splash** (login → desktop) with the logo and a progress bar.
  - A packaged **Maze OLED global theme** (Plasma look‑and‑feel) built on Breeze
    with the **Carl** dark colour scheme and the Maze splash — selectable and set
    as default.
- Maze **default wallpaper**, application‑launcher icon, **breeze-dark icons**
  and system branding, plus an **on‑brand pac‑man pacman progress bar**.
- Custom **os‑release**, hostname and boot‑menu identity.
- **Zsh + Oh My Zsh** as the default shell with a custom theme and a branded
  **fastfetch** greeting.

## Guided installer

- **maze‑calamares** — a branded **[Calamares](https://calamares.io/)** graphical
  installer, themed to match the rest of the system, launched in one click from
  the desktop/dock.
- **Maze OLED installer branding** — the installer shares the desktop's
  true‑black OLED identity (branded slideshow, pure‑black + white palette) via
  `airootfs/usr/share/calamares/branding/maze/`.
- **Offline / `unpackfs` install** — the baked live system is copied to the
  target (no `pacstrap`), so the install is fast and the installed system is
  identical to the live ISO. Maze's own `deploy-to-target.sh` then finalises
  everything (branding, Plymouth, kernel params, security services, AUR apps)
  from a single source of truth shared with the live medium.
- **Streamlined flow** — KDE Plasma is the one supported desktop, so there is no
  desktop‑environment picker; sane Maze defaults are applied automatically.
- **UEFI Secure Boot** — a per‑machine MOK is generated and the bootloader and
  kernel are signed during install (on by default on UEFI; see *Security by
  default*).
- **Boots straight into Maze** — systemd-boot with `timeout 0`, so the splash
  appears immediately with no menu wait. Maze is **UEFI-only** (no BIOS/legacy
  boot): the whole stack — systemd-boot, Unified Kernel Images and Secure Boot —
  is UEFI-native, so the live ISO ships no BIOS bootmode.

## Under the hood (engineering)

- Built with **archiso** for reproducible, official‑tooling ISO builds.
- AUR packages (including the Maze tools and curated apps) are compiled in an
  **isolated clean chroot** and published to a local repo, then baked into the
  ISO — so the build **never pollutes the host system** and the result works
  **offline**.
- Robust build pipeline: private mount‑namespace builds, safe work‑directory
  cleanup, and resilient AUR building (optional apps that fail to build are
  skipped instead of breaking the whole image).

---

## Why Maze? (one‑liners for the site)

- **Arch, without the assembly.** A complete, hardened desktop on first boot.
- **Secure and private by default** — not as an afterthought.
- **AI on your machine** — local models, no cloud required.
- **Try it for real** — the live ISO is the full system, even offline.
- **Still Arch underneath** — rolling release, AUR, total control.
