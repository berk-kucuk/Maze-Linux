# FAQ

---

## General

### What is Maze Linux?

Maze Linux is a security- and privacy-focused Linux distribution built on Arch Linux. It ships a complete, hardened KDE Plasma 6 desktop on Wayland that works immediately after installation — with security tools, privacy software, and a local AI runtime already configured and enabled.

### Is Maze Linux beginner-friendly?

Maze targets users who want the power of Arch Linux without the manual setup required to harden and configure it. Basic Linux familiarity (terminal usage, understanding of packages) is helpful, but you do not need to know how to configure AppArmor or write firewall rules — everything is done for you.

If you are brand new to Linux, Maze is more approachable than vanilla Arch, but less hand-holding than Ubuntu or Fedora. The [After Install](After-Install) page walks you through the first steps.

### Is Maze Linux based on Arch?

Yes. Maze uses the official Arch Linux package repositories and the rolling release model. Every package from the standard Arch repos is available. The AUR is accessible via `paru`.

### Does Maze have its own package manager?

No. Maze uses `pacman` (Arch's package manager) and `paru` (AUR helper). You can also use Flatpak for sandboxed apps. There is no separate Maze package manager.

### Is the live ISO the real system?

Yes. Unlike many distributions that ship a stripped-down live environment, the Maze live ISO runs the full desktop with all apps and services. You can try everything — including Ollama, Maze Guard, and the security tools — before committing to an install.

---

## Installation

### Do I need an internet connection to install?

No. All packages are baked into the ISO. You can install completely offline. An internet connection is recommended so the installer can fetch any critical updates, but it is not required.

### My Wi-Fi is not detected

Broadcom Wi-Fi cards require the `broadcom-wl` driver. It is included on the ISO. Open Konsole and run:

```bash
sudo modprobe wl
```

For Intel Wi-Fi, the firmware is included via `linux-firmware`. If your card is still not detected, run `lspci | grep -i net` to identify your hardware.

### Secure Boot prevents booting

Maze is designed to run **with Secure Boot enabled** — you should not need to
turn it off.

Maze generates a signing key unique to your machine and seals the kernel,
initramfs and command line into a signed Unified Kernel Image. On the first
reboot after installation, your firmware asks you to approve that key once, on
a blue *MOK Management* screen. That screen is expected — see
[First Boot / MOK](FirstBoot).

If the installed system still will not start with Secure Boot on, run
`sudo maze-boot-check` (from the [recovery kernel](Recovery) if necessary); it
checks the whole chain and `--repair` fixes what it finds.

### The installer crashed

Check the installer log:

```bash
cat /tmp/archinstall.log
journalctl -xe
```

Open an issue on the Maze Linux GitHub with the log content.

### Can I dual-boot with Windows?

Yes. Choose **Manual Partitioning** in the installer, leave the Windows EFI and C: partitions untouched, and install Maze to a separate partition or drive. The Maze GRUB bootloader will detect Windows and add it to the boot menu. Note: disable Secure Boot first.

---

## Updates and Packages

### How do I update the system?

```bash
sudo pacman -Syu
```

Run this regularly. To include AUR packages:

```bash
paru -Syu
```

### I broke something after an update. How do I roll back?

A btrfs snapshot is taken automatically before and after every `pacman`
transaction, so you can see exactly what changed and undo it:

```bash
sudo snapper -c root status 42..0        # what changed
sudo snapper -c root undochange 42..0    # undo it
```

Full system rollback needs one extra setup step and is not yet reliable on
every machine — see [Snapshots & Rollback](Snapshots).

If the machine will not boot at all, use the recovery kernel:
[Won't Boot?](Recovery)

You can also downgrade a single package from the pacman cache:

```bash
sudo pacman -U /var/cache/pacman/pkg/<package-old-version>.pkg.tar.zst
```

### How do I install apps not in the official repos?

Use the AUR with `paru`:

```bash
paru -S <package-name>
```

Or use Flatpak for sandboxed apps:

```bash
flatpak install flathub <app-id>
```

### What is the maze-aur local repository?

The Maze ISO includes a local pacman repository (`maze-aur`) containing prebuilt AUR packages: `entropy-shield`, `qlam`, `haze`, `hazedrop`, `linux-chan-ai`, `sentinai`, `brave-bin`, `mullvad-browser-bin`, `session-desktop-bin`, `joplin-bin`, `upscayl-bin`, and `paru`. These are available offline because they were compiled before the ISO was built.

After install, `paru` can update these packages from the AUR normally.

---

## Security

### Are the security tools enabled by default?

Yes. AppArmor, the firewall, fail2ban, auditd, and MAC randomization are all active from first boot. Maze Guard autostarts on the desktop.

### Maze Guard keeps asking me about the same app

Maze Guard prompts once per new connection type (app + destination + port). Click **Allow** and choose **Save** or **Apply to all** to create a persistent rule. After a few days of use it learns your habits and stops prompting.

Rules are saved in `/etc/opensnitchd/rules/` and persist across reboots.

### Can I disable a security service?

Yes. You are in full control:

```bash
sudo systemctl disable --now apparmor    # disable and stop
sudo systemctl stop opensnitchd          # stop without disabling
```

The Maze Control Center shows all services and gives you copyable commands to manage them.

### Is the SSH server running?

No. The SSH server is installed but **not enabled by default**. Enable it only when you need it:

```bash
sudo systemctl enable --now sshd
```

Disable again when not in use:

```bash
sudo systemctl disable --now sshd
```

### How do I run a virus scan?

Open **QLAM** from the application menu for a graphical scan, or use the command line:

```bash
sudo freshclam          # update definitions first
sudo clamscan -r /home/yourusername
```

---

## Privacy

### Is my MAC address randomized automatically?

Yes. The `mac-changer` systemd service runs at every boot and randomizes the MAC address of all physical network interfaces. NetworkManager is also configured to use random MACs per network connection.

To change your MAC immediately without rebooting:

```bash
change-mac-now
```

### Does Firefox send telemetry?

No. The Maze Firefox profile disables all telemetry, crash reporting, data collection, Pocket, sponsored content, and Studies. This is set in the default profile and requires no manual configuration.

### How do I browse anonymously?

Use **Tor Browser** (`torbrowser-launcher`) for maximum anonymity. It routes all traffic through the Tor network and is pre-hardened against fingerprinting.

For everyday private browsing, Firefox with the Maze hardened profile and DNS-over-HTTPS is a good baseline.

For a VPN, install and configure **ProtonVPN** or import a **WireGuard** configuration file.

---

## AI

### How do I run an AI model locally?

Ollama 0.3 is already running as a systemd service. Just pull a model and start chatting:

```bash
ollama pull llama3
ollama run llama3
```

Or use `linux-chan-ai` for a terminal UI that manages models and chat in one place. No account, no cloud, no data sharing required.

### Do AI models work offline?

Yes — once downloaded, models run entirely locally with no internet connection needed. The initial `ollama pull` requires internet to download the model weights.

### My system runs out of RAM with large models

Use a smaller model. `phi3` (~2.3 GB) runs well on 8 GB RAM. `llama3` (~4.7 GB) needs at least 8 GB with other apps closed, ideally 16 GB.

Maze ships with **zram** (compressed RAM swap), which helps when you approach your memory limit. Check memory usage with `btop`.

### Does Ollama use my GPU?

Yes, automatically when a compatible GPU is present. For Nvidia (CUDA):

```bash
sudo pacman -S nvidia nvidia-utils
```

For AMD, GPU acceleration requires **ROCm 6.1+**. Older AMD GPUs fall back to CPU inference automatically.

---

## Desktop and Appearance

### Can I change the desktop theme?

Yes. Go to **System Settings → Appearance → Global Theme**. The **Maze OLED** theme is the default. You can install and apply any KDE Plasma theme.

### The panel layout looks wrong after I changed Global Theme

Switching Global Theme from System Settings may reset the panel layout. If this happens, log out and back in — the Maze skel defaults are applied on first login.

### How do I add widgets to the panel?

Right-click the desktop or panel → **Add Widgets**. The Maze panel includes a system monitor, network speed, weather, thermal monitor, clock, and app launcher by default.

---

## Miscellaneous

### How is Maze different from Arch Linux?

| Arch Linux | Maze Linux |
|------------|-----------|
| Text-only installer | Graphical installer (Calamares) |
| No GUI after install | Full KDE Plasma desktop |
| You configure security | Security stack pre-enabled |
| You set up privacy | Privacy tools pre-configured |
| No AI tooling | Ollama + AI utilities |
| No branding | Maze OLED theme, splash, GRUB |

The underlying system is identical: same packages, same package manager, same AUR. Maze is Arch with all the assembly done for you.

### The first boot showed a blue screen — is my system broken?

No. That is the one-time security key approval. See
[First Boot / MOK](FirstBoot).

### Do I need to turn Secure Boot off?

No. Maze is designed to run **with Secure Boot enabled**.

### Is any of my data sent anywhere?

No. A default install sends nothing — no telemetry, no usage statistics. The
built-in Maze AI runs models locally via Ollama. The two optional apps that can
reach the cloud (SentinAI, Linux Chan AI) are not installed by default and warn
you on first use. See [Privacy Reference](Privacy).

### What if an update breaks my system?

Every update takes a snapshot and verifies the boot chain before you shut down.
If it will not boot, start the recovery kernel — see [Won't Boot?](Recovery).

### Can I install in BIOS/Legacy mode?

No. Maze is UEFI-only; the security chain depends on it.

### Are penetration-testing tools included?

Not by default. You can add the BlackArch repository:

```bash
sudo maze-enable-blackarch
```

### Why isn't my camera working?

Most likely a hardware kill switch is enabled. Run `sudo maze-doctor` — it says
so explicitly. See [Kill Switches](Hardware).

### How do I report a bug?

Open an issue on the [Maze Linux GitHub repository](https://github.com/berk-kucuk/Maze-Linux/issues). Include:

- Your Maze Linux version (`cat /etc/os-release`)
- What you were trying to do
- What happened instead
- Relevant log output (`journalctl -xe`, `/tmp/archinstall.log`, etc.)

### How do I contribute?

The Maze Linux source is on GitHub. Pull requests, bug reports, wiki contributions, and testing on real hardware are all welcome.
