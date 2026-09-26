# After Install

The first time you boot into your installed Maze Linux system, the **Maze Welcome** app opens automatically. It introduces key features and self-removes its autostart entry so it only appears once.

---

## 1. Maze Welcome App

The Welcome app launches on first boot and walks you through:

- What Maze Linux is and what's preconfigured.
- Links to this wiki and the community.
- Quick-start actions: update system, open Control Center, and more.

It will not appear again after you close it on first boot.

---

## 2. Update the System

```bash
sudo pacman -Syu
```

Maze uses Arch Linux's rolling release model. Updates are incremental and frequent — run this regularly.

---

## 3. Open Maze Control Center

The **Maze Control Center** is your central dashboard. Launch it from the application menu or run:

```bash
maze-control-center
```

It shows the live status of every security service, MAC randomization state, the Ollama AI runtime, and system maintenance info. Each action is displayed as a copyable terminal command — nothing runs without you explicitly executing it.

---

## 4. Check Security Services

All of the following are enabled and running from first boot. Confirm they are active:

```bash
systemctl status apparmor
systemctl status firewalld
systemctl status fail2ban
systemctl status auditd
systemctl status opensnitchd
```

**Maze Guard** will prompt you the first time any application tries to make a network connection. Choose to allow or deny per-app and per-destination.

---

## 5. Set Up Flatpak Apps (Optional)

Flathub is already configured as a Flatpak remote. Install additional apps from KDE Discover or the terminal:

```bash
flatpak install flathub <app-id>
flatpak update
```

---

## 6. AUR Access with paru

`paru` is the preinstalled AUR helper. Install any AUR package with:

```bash
paru -S <package-name>
```

`paru` searches both official repos and the AUR, compiles from source in an isolated environment, and installs the result.

---

## 7. Configure Firefox

Firefox ships with a hardened default profile:

- Telemetry, Studies, Pocket, and sponsored content are disabled.
- Tracking protection, fingerprinting protection, and cryptomining protection are on.
- DNS-over-HTTPS is enabled.

No configuration needed — it is already private. To use a different DNS-over-HTTPS provider, go to **Settings → Privacy & Security → DNS over HTTPS**.

---

## 8. Set Up Ollama (Local AI)

Ollama 0.3 is installed and starts on boot automatically. Pull your first model:

```bash
ollama pull llama3
```

Check the service status:

```bash
systemctl status ollama
```

See the [AI & Development](AI-Dev) page for model recommendations and GPU acceleration details.

---

## 9. DNSCrypt-proxy

DNSCrypt-proxy is preconfigured with a no-logs resolver, encrypting your DNS queries and preventing DNS leaks. It starts automatically. Check the status:

```bash
systemctl status dnscrypt-proxy
```

The configuration lives in `/etc/dnscrypt-proxy/dnscrypt-proxy.toml`. You can switch resolvers or add custom ones there.

---

## 10. Firmware Updates

`fwupd` is preinstalled. Check for and install firmware updates:

```bash
fwupdmgr refresh
fwupdmgr update
```

---

## 11. Virtualization

QEMU, libvirt, and virt-manager are preinstalled. Your user is already in the `libvirt` and `kvm` groups. Enable the service:

```bash
sudo systemctl enable --now libvirtd
```

Then open **Virt Manager** from the application menu.

---

## 12. Change the Default Shell (Optional)

Zsh with Oh My Zsh is the default shell. If you prefer bash:

```bash
chsh -s /bin/bash
```

---

## Key Directories

| Path | Purpose |
|------|---------|
| `/etc/maze-installer/` | Installer config templates |
| `/usr/local/bin/` | Maze custom scripts and tools |
| `/usr/local/lib/maze/` | Maze Python libraries (maze\_status, maze\_ui) |
| `/etc/sysctl.d/maze-hardening.conf` | Kernel hardening parameters |
| `/etc/opensnitchd/` | OpenSnitch rules |
| `/etc/fail2ban/` | fail2ban jail configuration |
| `/etc/dnscrypt-proxy/` | DNSCrypt-proxy resolver config |
