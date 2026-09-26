# Installation Guide

> **Current release:** Labyrinth — 2026-06-21 — x86\_64 — Linux 6.9.8-arch1 · KDE Plasma 6.7.0

Maze Linux ships as a bootable ISO. Write it to a USB drive, boot live to try the system, then run the guided installer to put it on your disk.

---

## Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 64-bit (x86\_64), 2 cores | 4+ cores |
| RAM | 4 GB | 8 GB+ (16 GB for local AI) |
| Storage | 40 GB | 100 GB+ SSD |
| Firmware | **UEFI required** (no BIOS/Legacy) | UEFI + Secure Boot |
| EFI partition | 512 MB | **1 GB+** (two kernel images) |
| Internet | Optional for install | Recommended |

---

## 1. Download the ISO

Get the latest `mazelinux-YYYY.MM.DD-x86_64.iso` from the [Maze Linux website](https://mazelinux.berkkucukk.com.tr/#download).

---

## 2. Write the ISO to USB

**On Linux:**

```bash
sudo dd if=mazelinux-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Replace `/dev/sdX` with your USB device — verify with `lsblk` before running. This is destructive.

**On Windows:** use [Rufus](https://rufus.ie) in **DD image** mode.

**On macOS:** use `dd` with `/dev/diskN` instead of `/dev/sdX`, or use [Balena Etcher](https://etcher.balena.io).

---

## 3. Boot the Live Environment

1. Plug in the USB and reboot.
2. Enter your firmware boot menu (usually **F2**, **F12**, **Delete**, or **Esc** at POST).
3. Select your USB drive.
4. Choose **Maze Linux** from the GRUB menu.

The system boots to a full **KDE Plasma 6.7** desktop on Wayland. This is the real system — not a stripped-down live mode. You can try every app and test all hardware before committing to an install.

---

## 4. Connect to the Internet (optional)

Use the **NetworkManager** tray applet to connect to Wi-Fi or plug in Ethernet. An internet connection lets the installer fetch remaining updates, but is not required — all packages are already on the ISO.

---

## 5. Run the Installer

Click the **Install Maze Linux (Calamares)** icon on the live desktop.

The guided installer walks you through:

| Step | What to configure |
|------|------------------|
| Language / locale | System language, keyboard layout, timezone |
| Disk | Target drive, partition scheme, optional LUKS2 encryption |
| Filesystem | btrfs (recommended — enables automatic snapshots) |
| Encryption | LUKS2 full-disk encryption (optional, guided mode) |
| Bootloader | systemd-boot + signed Unified Kernel Image |
| Users | Root password, your user account and password |
| Desktop | KDE Plasma is pre-selected |
| Security | AppArmor, firewall, fail2ban, auditd, Maze Guard toggles |
| Additional packages | Optional extra software |

### Recommended disk layout

Choose **btrfs** for the root partition. It is what makes the automatic
before/after-update snapshots work — see [Snapshots & Rollback](Snapshots).

Tick the **encryption** box: LUKS2 full-disk encryption is available in guided
mode and is strongly recommended.

> **Give the EFI partition room.** Maze stores each kernel as a single signed
> image of about 90 MB and keeps two of them. 512 MB is tight; **1 GB or more**
> is comfortable. See [Kernel Management](Kernels).

---

## 6. Reboot

When the installer finishes, click **Reboot** and remove the USB when prompted.

> **On the first reboot a blue screen appears** saying *"Verification failed"*
> or *"MOK Management"*. **This is not an error.** It is the one-time approval
> of your machine's own signing key, and it takes four keystrokes — see
> [First Boot / MOK](FirstBoot). Do not disable Secure Boot to skip it.

On first login the **Maze Welcome** app opens automatically to orient you to the system.

---

## Unattended / Pre-seeded Install

For automated deployments, copy the example config files:

```bash
cp /etc/maze-installer/maze.json.example /etc/maze-installer/maze.json
cp /etc/maze-installer/creds.json.example /etc/maze-installer/creds.json
```

Edit them to match your target system, then run the installer in unattended
mode.

> **Note:** the guided installer is now **Calamares**. If you rely on the
> unattended flow, check `maze-installer --help` on the live ISO for the
> current invocation before scripting against it.

---

## Known Issues (Labyrinth release)

- **Secure Boot is not supported.** Disable Secure Boot in your firmware settings before booting.
- **Btrfs subvolume layouts** are not supported in the installer. Use ext4 or XFS for root.
- **AMD GPU + Ollama** — GPU acceleration requires ROCm 6.1+. Older AMD GPUs fall back to CPU inference automatically.
- **Some NVIDIA laptops** may show a blank screen on first boot. Reboot, edit the GRUB entry, and add `nomodeset` to the kernel command line.

---

## Troubleshooting

**Black screen on boot** — try the non-quiet boot entry in GRUB (remove `quiet splash`). On some NVIDIA laptops, also add `nomodeset`.

**Wi-Fi not detected** — Broadcom cards need the `broadcom-wl` driver which is included on the ISO:

```bash
sudo modprobe wl
```

**Installer crashes** — check the installer log:

```bash
cat /tmp/archinstall.log
journalctl -xe
```

**UEFI Secure Boot** — Maze does not ship signed bootloader binaries. Disable Secure Boot in firmware settings.
