# Running Maze Linux in a Virtual Machine

Maze Linux ships as a bootable live ISO — you can run it in a virtual machine without installing anything. The live environment is the full system: all security services, Ollama, OpenSnitch, the Maze desktop, and every pre-installed app are active. Nothing is stripped down.

> **Note:** Some security features behave differently in a VM. AppArmor and firewalld run normally, but MAC randomization applies to the virtual NIC (not your physical adapter). OpenSnitch will prompt on first launch as usual.

---

## Requirements

| | Minimum | Recommended |
|---|---|---|
| RAM | 4 GB allocated to VM | 8 GB+ (needed if you want to run Ollama) |
| CPU | 2 cores, 64-bit | 4+ cores with hardware virtualization |
| Disk | None (live mode) | — |
| Host OS | Linux, Windows, macOS | — |

Maze ships with **zram** compressed swap, which helps when RAM is tight — but local AI models (`llama3`, etc.) need headroom. If you plan to use Ollama inside the VM, allocate at least 8 GB.

---

## QEMU / KVM (Linux — Recommended)

QEMU with KVM gives near-native performance and is the best way to test Maze on Linux.

**Install QEMU:**

```bash
# Maze Linux / Arch
sudo pacman -S qemu-full

# Fedora
sudo dnf install qemu-kvm

# Debian / Ubuntu
sudo apt install qemu-system-x86
```

**Boot the ISO:**

```bash
qemu-system-x86_64 \
  -enable-kvm \
  -m 6G \
  -cpu host \
  -smp 4 \
  -cdrom mazelinux-*.iso \
  -boot d \
  -vga virtio \
  -display gtk
```

- `-enable-kvm` — hardware acceleration (Linux hosts only, requires `kvm` kernel modules loaded)
- `-m 6G` — 6 GB is a comfortable amount for the full desktop + security stack
- `-cpu host` — exposes your real CPU flags to the VM; improves compatibility with some Maze tools

Press `Ctrl+Alt+G` to release keyboard/mouse from the QEMU window.

---

## VirtualBox

1. Download and install [VirtualBox](https://www.virtualbox.org/wiki/Downloads).
2. Click **New** → name it "Maze Linux" → Type: **Linux** → Version: **Arch Linux (64-bit)**.
3. Set RAM to at least **4096 MB** (6144 MB recommended).
4. Skip creating a virtual disk — live mode needs none.
5. Go to **Settings → Storage** → attach the Maze Linux ISO to the optical drive.
6. Go to **Settings → Display** → set Video Memory to **128 MB**, enable **3D Acceleration**.
7. Click **Start**.

> VirtualBox uses software rendering unless Guest Additions are installed. The desktop will work, but may feel sluggish compared to QEMU/KVM. Wayland compositing effects may be reduced.

---

## VMware Workstation / Fusion

1. Create a new VM → **Use ISO image** → select the Maze Linux ISO.
2. Guest OS: **Linux** → **Other Linux 6.x kernel 64-bit**.
3. RAM: 4 GB minimum, 6–8 GB recommended.
4. Click **Finish** and start the VM.

---

## What works in the live VM

| Feature | Works in VM? |
|---|---|
| KDE Plasma desktop | Yes |
| AppArmor / firewalld | Yes |
| OpenSnitch | Yes (will prompt on first connections) |
| ClamAV / QLAM | Yes |
| Entropy Shield (Tor + I2P) | Yes |
| MAC randomization | Yes (applies to virtual NIC) |
| Ollama / local AI | Yes — needs enough RAM allocated |
| GPU acceleration (Ollama) | No — VM GPU passthrough is not supported out of the box |
| Guided installer | Yes — you can install to a virtual disk from live mode |

---

## Tips

- **Screen resolution:** If the display is small, open **System Settings → Display & Monitor** and set your preferred resolution.
- **Clipboard sharing:** In VirtualBox, enable **Shared Clipboard** under Settings → General → Advanced. In QEMU, use `-device virtio-serial -chardev spicevmchannel` with a SPICE display.
- **Want to install?** Once you're satisfied with the live session, click **Install Maze Linux** in the dock and follow the [Installation Guide](/wiki/Installation).
