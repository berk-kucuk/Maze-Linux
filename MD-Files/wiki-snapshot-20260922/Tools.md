# Tools & Apps

Every application that ships with Maze Linux is listed here. Tools are grouped by category.

---

## Maze-Built Tools

These utilities were developed specifically for Maze Linux.

### maze-control-center

An OLED-styled PySide6 dashboard showing the live state of your system at a glance.

- Tabs for Security, Privacy, AI, and Maintenance.
- Shows whether AppArmor, the firewall, fail2ban, auditd, and Maze Guard are active.
- Shows MAC randomization status and current interface MACs.
- Shows whether Ollama is running and which models are available.
- All privileged actions are shown as **copyable terminal commands** — nothing runs automatically.

```bash
maze-control-center
```

---

### maze-welcome

A first-boot greeter that opens once after install to orient new users. Self-removes its autostart entry after first launch.

---

### Install Maze Linux (Calamares)

The guided graphical installer, launched from the icon on the live desktop.
It handles partitioning, LUKS encryption, users and the signed boot chain.
See the [Installation Guide](Installation).

---

### QLAM

A modern antivirus GUI built on top of **ClamAV**. Provides:

- On-demand directory and file scanning.
- Virus definition database updates.
- Scan history and quarantine management.

Launch from the application menu or run `qlam`.

---

### Entropy Shield

A one-click anonymity layer. Activates **Tor + DNSCrypt-proxy + I2P** simultaneously, routing all traffic through the anonymity stack with a single command.

```bash
entropy-shield --help
```

---

### Haze

A **Tor-based onion messenger** using the Haze Protocol — a Maze-native encrypted messaging system that routes all communication over the Tor network. Messages never pass through a central server.

```bash
haze --help
```

---

### HazeDrop

**Anonymous file and text transfer over Tor.** Send files or text snippets without revealing either party's IP address. The transfer happens entirely over Tor hidden services.

```bash
hazedrop --help
```

---

### sentinai

An AI-assisted security monitoring tool. Analyzes system events and surfaces anomalies.

```bash
sentinai
```

---

### linux-chan-ai

The Maze **local model manager and chat interface**. Provides a terminal UI for managing Ollama models (pull, delete, list) and chatting with any installed model. All inference runs locally via Ollama — no data leaves your machine.

```bash
linux-chan-ai
```

---

### Maze Cloak

Randomises your network adapter's MAC address, and can rotate it on a schedule.
Even networks you never join cannot track your device across visits.

Enable it, and set the rotation interval, from Maze Control Center's Privacy
tab. See the [Privacy Reference](Privacy).

---

### change-mac-now

A one-shot script that immediately randomizes the MAC address on all physical network interfaces and prints the new addresses.

```bash
change-mac-now
```

---

## Browsers

### Firefox

The default browser. Ships with a hardened profile: telemetry off, tracking and fingerprint protection on, DNS-over-HTTPS enabled. No configuration needed.

### Brave

Privacy-focused Chromium-based browser with built-in ad blocking and Brave Shields. Good alternative when Firefox compatibility is an issue.

### Mullvad Browser

Based on Tor Browser's hardened engine but designed to use with a VPN. Minimal fingerprinting surface.

### Tor Browser

Routes all traffic through the Tor anonymity network. Use for maximum anonymity. Launch via `torbrowser-launcher` which fetches and verifies the official bundle.

---

## Communication & Messaging

### Session

An end-to-end encrypted private messenger with no phone number required. Decentralized network, no central servers storing metadata.

### Discord

The popular voice/text/community platform. Included for convenience.

### Thunderbird

Full-featured email client with PGP/S-MIME support via the built-in OpenPGP manager.

---

## Productivity

### ONLYOFFICE

A full office suite compatible with Microsoft Office formats (.docx, .xlsx, .pptx). Available via Flatpak.

### Joplin

An open-source, end-to-end encrypted note-taking app with Markdown support and optional sync (Nextcloud, Joplin Cloud, self-hosted).

### KDE Apps

| App | Purpose |
|-----|---------|
| Dolphin | File manager with split-pane, tabs, and Btrfs integration |
| Kate | Advanced text editor with split view and LSP support |
| Okular | PDF and document viewer |
| Gwenview | Image viewer |
| Ark | Archive manager (zip, tar, 7z, rar) |
| KCalc | Scientific calculator |
| KFind | File search |
| KWallet Manager | Credential/secret storage |
| Filelight | Disk usage visualization |
| KDE Partition Manager | Disk and partition management |
| KDE Connect | Phone ↔ desktop integration |

---

## Security Tools

### ClamAV + QLAM

ClamAV 1.4.1 is the open-source antivirus engine. QLAM is the Maze GUI on top. On-access scanning and scheduled definition updates are configured out of the box.

```bash
sudo freshclam          # update definitions
sudo clamscan -r /home  # CLI scan
```

### rkhunter

Rootkit detection scanner. Run periodically:

```bash
sudo rkhunter --update
sudo rkhunter --check
```

### lynis

Security auditing tool that scores your system configuration and suggests improvements:

```bash
sudo lynis audit system
```

### Wireshark

Full GUI network protocol analyzer. Your user is in the `wireshark` group by default so you can capture without `sudo`.

### nmap

Network scanner for host discovery and port scanning:

```bash
nmap -sV 192.168.1.0/24
```

### aircrack-ng

Wi-Fi security testing suite (monitor mode, packet capture, WPA handshake testing). Use only on networks you own or are authorized to test.

### Maze Guard (OpenSnitch)

Interactive application firewall. Prompts you whenever an application attempts an outbound connection. Rules are stored in `/etc/opensnitchd/rules/`.

---

## Privacy Tools

### DNSCrypt-proxy

Encrypts DNS queries. Preconfigured with a no-logs resolver. Starts automatically at boot.

```bash
systemctl status dnscrypt-proxy
```

Config: `/etc/dnscrypt-proxy/dnscrypt-proxy.toml`

### Tor + OnionShare

- `tor` — the Tor daemon. Runs as a SOCKS5 proxy on port 9050.
- `onionshare` — securely share files or host a hidden web service over Tor.

### Mullvad VPN

The Mullvad VPN client is preconfigured. Accepts anonymous payment and keeps no logs. WireGuard and OpenVPN protocols supported.

### ProtonVPN

A GUI client for the ProtonVPN service (subscription required). WireGuard and OpenVPN protocols supported.

### WireGuard

The modern VPN protocol. Set up custom connections with:

```bash
sudo wg-quick up /etc/wireguard/wg0.conf
```

### macchanger

The underlying MAC address randomization tool. Used by the `mac-changer.service` systemd service that runs at every boot.

---

## Multimedia

### VLC

Universal media player supporting nearly every format.

### Spotify

The official Spotify client via `spotify-launcher`.

### PipeWire

The audio stack — handles audio and video routing. Replaces PulseAudio and JACK with a single compatible layer. Configured automatically.

---

## System Utilities

### btop

A modern, interactive resource monitor showing CPU, memory, disk, and network usage in the terminal.

```bash
btop
```

### fastfetch

Displays a Maze-branded system summary at shell startup.

```bash
fastfetch
```

### Btrfs Assistant

GUI tool for managing Btrfs subvolumes and snapper snapshots.

### Bitwarden

Open-source password manager with browser extension and desktop app.

### FileZilla

Full-featured FTP/SFTP/FTPS client.

### Distrobox

Run containers that use another distro's package manager while sharing your home directory and display:

```bash
distrobox create --name ubuntu --image ubuntu:24.04
distrobox enter ubuntu
```

### fwupd

Firmware update client for BIOS, UEFI, NVMe, and peripheral firmware from the Linux Vendor Firmware Service (LVFS).

---

## Virtualization

### QEMU + libvirt + virt-manager

A complete virtualization stack:

- **QEMU** — fast hardware emulation and KVM acceleration.
- **libvirt** — management daemon and API.
- **virt-manager** — full GUI for creating and managing VMs.
- **OVMF/edk2** — UEFI firmware for VMs.

Your user is pre-added to the `kvm` and `libvirt` groups at install time.

---

## Development

### paru

The AUR helper. Wraps `pacman` and lets you install from both official repos and the AUR:

```bash
paru -S <package>   # install
paru -Syu           # system update including AUR
paru -Ss <keyword>  # search
```

### base-devel

The full Arch build toolchain: `gcc`, `make`, `binutils`, `fakeroot`, `patch`, etc. Required to compile AUR packages.

### Python + pip

Python 3 with `pip` and `python-setuptools` preinstalled. The Maze tools themselves are written in Python.

### Node.js

Node.js is preinstalled for JavaScript and TypeScript development:

```bash
node --version
npm install
```

### Rust (rustup)

The Rust toolchain is managed via `rustup`:

```bash
rustup show
cargo new my-project
```

### Go

The Go toolchain is preinstalled:

```bash
go version
go build ./...
```

### Flatpak + Flathub

Sandboxed app distribution. Flathub remote is configured out of the box. Install additional apps via `flatpak install flathub <id>` or through KDE Discover.
