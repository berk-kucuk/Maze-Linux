# Maze Linux

Maze Linux is a lightweight, Arch-based live and install medium built with
[archiso](https://gitlab.archlinux.org/archlinux/archiso). It is derived from
the upstream `releng` profile and rebranded as Maze Linux. The system is
English by default.

## Layout

| Path                     | Purpose                                                        |
| ------------------------ | ------------------------------------------------------------- |
| `profiledef.sh`          | ISO metadata (name, label, publisher) and build options.      |
| `packages.x86_64`        | Packages installed into the live system.                      |
| `pacman.conf`            | Pacman configuration used during the build.                   |
| `airootfs/`              | Files overlaid onto the live root filesystem.                 |
| `efiboot/`               | UEFI boot loader configuration (systemd-boot). Maze is **UEFI-only**. |
| `build.sh`               | Convenience wrapper around `mkarchiso`.                        |
| `maze-logo.png`, `maze-boot-animation/` | Source branding assets (logo + Plymouth theme). |

## Branding: logo and boot splash

The boot splash uses [Plymouth](https://wiki.archlinux.org/title/Plymouth) with
a custom theme:

- **Theme:** `airootfs/usr/share/plymouth/themes/maze/` (a `script`-module theme
  built from `maze-boot-animation/`). `default.plymouth` symlinks to it and
  `airootfs/etc/plymouth/plymouthd.conf` sets `Theme=maze`.
- **initramfs:** the `plymouth` hook is added to
  `airootfs/etc/mkinitcpio.conf.d/archiso.conf` so the theme is embedded in the
  initramfs at build time, and `plymouth` is listed in `packages.x86_64`.
- **Kernel cmdline:** the standard (non-accessibility) boot entries get
  `quiet splash` so the animation is shown; the screen-reader entries are left
  as plain text.
- **Logo:** `maze-logo.png` is installed to `/usr/share/pixmaps/maze-logo.png`
  and is also the theme's `logo.png`.

To change the artwork, edit the files under `maze-boot-animation/` (or the
installed copies under `airootfs/usr/share/plymouth/themes/maze/`) and rebuild.

## Desktop (KDE Plasma on Wayland)

The live ISO boots straight into a full KDE Plasma desktop running on Wayland:

- **Packages:** `plasma-meta` plus a curated app set (Konsole, Dolphin, Kate,
  Gwenview, Okular, Ark, …), Firefox, VLC, the PipeWire audio stack and
  Vulkan/VA-API drivers — see the `KDE Plasma` block in `packages.x86_64`.
- **Display manager:** SDDM (`display-manager.service`) with the default target
  set to `graphical.target`.
- **Autologin:** SDDM logs in the live user automatically to the Plasma Wayland
  session — `airootfs/etc/sddm.conf.d/10-maze-autologin.conf`.
- **Live user:** a passwordless `maze` user (group `wheel`, passwordless sudo via
  `airootfs/etc/sudoers.d/10-maze`) is created at build time by the
  `0600-maze-live-user.hook` pacman hook (Plasma refuses to run as root).
- **Networking:** switched from archiso's `systemd-networkd`/`iwd` to
  `NetworkManager` (Plasma's `plasma-nm` applet), with `systemd-resolved` kept
  as the DNS backend.
- **Wallpaper:** `maze-wallpaper.png` is installed as the Plasma wallpaper
  package `/usr/share/wallpapers/Maze` and set as the default via the
  `0700-maze-wallpaper.hook` build hook (it patches the wallpaper defaults, so
  Plasma still builds its normal panel + desktop, just with the Maze wallpaper).
- **Layout / widgets:** the panel layout (top bar + bottom dock), widgets and
  their configs are seeded from a reference Plasma 6 setup into
  `airootfs/etc/skel/.config/` (`plasma-org.kde.plasma.desktop-appletsrc`,
  `kdeglobals`, `kwinrc`, …); the live user inherits them via `/etc/skel`.
  Third-party pure-QML widgets (latte separator, netspeed, thermal monitor) are
  shipped under `airootfs/etc/skel/.local/share/plasma/plasmoids/`. Host-specific
  paths were rewritten to `/home/maze` and the wallpaper points to `Maze`.

> Note: with the squashfs left uncompressed (`profiledef.sh`), a full KDE image
> is large (~8–10 GB). Switch `airootfs_image_tool_options` to zstd/xz for a
> smaller ISO.

## AUR packages (paru + custom packages)

`paru` and a set of AUR packages (`entropy-shield`, `qlam`, `maze`, `hazedrop`,
`haze`, `linux-chan-ai`, `sentinai`) are **preinstalled** in the ISO, so the live
system works offline. `mkarchiso` can only install from binary repositories, so
the AUR packages are first built into a local repository:

1. `tools/build-aur.sh` clones each package from the AUR with `git` and builds
   it in an **isolated clean chroot** (`./aur/chroot`, via `devtools`), then
   publishes the results into `./localrepo/` (a pacman repo).
2. `pacman.conf` has a `[maze-aur]` entry pointing at `./localrepo/`.
3. `packages.x86_64` lists `paru-bin` and the AUR packages, so `mkarchiso`
   installs them like any other package. `base-devel` + `git` are included too
   so the preinstalled `paru` can build further AUR packages later.

**Host isolation:** all building happens inside the throwaway chroot, so build
dependencies and the AUR packages are *not* installed onto your host — your
host's package set is left untouched. The only host requirement is the build
tools (`sudo pacman -S --needed devtools git`); `sudo` is used solely to manage
the chroot, never to install anything onto the host.

Build order (the AUR step runs as a normal user, the ISO step as root):

```sh
sudo pacman -S --needed devtools git   # one-time: build tools
./tools/build-aur.sh                   # build AUR packages into ./localrepo (NOT as root)
sudo ./build.sh                        # build the ISO (checks the local repo exists)
```

If you move the project directory, update the absolute `Server` path in the
`[maze-aur]` section of `pacman.conf`.

## Build requirements

- Arch Linux (or an Arch-based host)
- The `archiso` package: `sudo pacman -S archiso`
- `sbsigntools` for Secure Boot signing of the ISO: `sudo pacman -S sbsigntools`
- `systemd-ukify` for building the Unified Kernel Image: `sudo pacman -S systemd-ukify`
- Root privileges and a few GB of free disk space

## Building the ISO

```sh
sudo ./build.sh
```

The resulting ISO image is written to `./out/`. Intermediate build artifacts
are placed in `./work/`. Both directories can be safely deleted afterwards.

You can override the directories:

```sh
sudo ./build.sh -w /tmp/maze-work -o /tmp/maze-out
```

## Testing the ISO

Boot the generated image in a virtual machine, for example with QEMU:

```sh
qemu-system-x86_64 -m 4096 -enable-kvm \
    -cdrom out/mazelinux-*.iso \
    -boot d -bios /usr/share/edk2/x64/OVMF.4m.fd
```

To test **with UEFI Secure Boot enabled**, use writable OVMF firmware + vars
copies so the enrolled key persists across reboots:

```sh
cp /usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd /tmp/code.fd
cp /usr/share/edk2/x64/OVMF_VARS.4m.fd /tmp/vars.fd
qemu-system-x86_64 -m 4096 -enable-kvm \
    -machine q35,smm=on -global driver=cfi.pflash01,property=secure,value=on \
    -drive if=pflash,format=raw,unit=0,file=/tmp/code.fd,readonly=on \
    -drive if=pflash,format=raw,unit=1,file=/tmp/vars.fd \
    -cdrom out/mazelinux-*.iso -boot d
```

On the first Secure Boot start, **MokManager** appears: choose
*Enroll key from disk* → select `MOK.cer` on the ISO's EFI partition → enroll →
reboot. The live session then boots with Secure Boot on. `mokutil --sb-state`
inside the live session should report *SecureBoot enabled*.

## Secure Boot

Maze Linux supports UEFI Secure Boot on both the live ISO and the installed
system using a Microsoft-signed **shim** plus a Maze key enrolled as a **MOK**
(Machine Owner Key). Factory and Windows keys are kept — no firmware *Setup
Mode* is required.

```
firmware → shim (Microsoft-signed) → Unified Kernel Image (Maze-signed)
```

The kernel, initramfs and kernel command line are bundled into a single
**Unified Kernel Image** (UKI) PE binary, signed with the Maze key and installed
as `grubx64.efi` — the second stage shim chainloads by that exact name. The
shim **always** verifies its second stage through its own `shim_lock` protocol
(MOK-backed), never via the firmware's `db`. Because the kernel is already
embedded inside the UKI, no separate firmware `LoadImage()` of `vmlinuz` ever
happens. This is what makes the chain portable across every UEFI firmware —
strict ones (MSI, some ASUS, …) that ignore the MOK for loose kernels and only
consult their own `db` no longer reject the boot with
*Security Policy Violation*.

- **Live ISO** — signed at build time with the shared Maze ISO key in
  `keys/secureboot/` (generated once by `tools/gen-sb-keys.sh`; `build.sh`
  patches `mkarchiso` to inject shim and build + sign the UKI). Boot it
  once and enroll `MOK.cer` via MokManager as described above.
- **Installed system** — enable the **Secure Boot** toggle in the installer's
  *Bootloader* menu (on by default on UEFI with systemd-boot + UKI). The
  installer generates a **per-machine** key (its private half never leaves that
  machine), signs systemd-boot and the unified kernel image, and copies the
  certificate to the ESP as `MOK.cer`. A pacman hook re-signs automatically after
  kernel and systemd updates. On the first boot the bootloader is not trusted
  yet, so MokManager appears: choose **Enroll key from disk → MOK.cer → Continue
  → Yes**, then reboot. **No password** — enrollment requires physical presence
  instead (the same flow as the live ISO). Details are written to
  `/var/lib/maze-secureboot/ENROLLMENT.txt`.

If you prefer not to use Secure Boot, simply disable it in firmware (the ISO and
the installed system boot normally either way), or turn the installer toggle off.

## Checking an installed system

Every Maze install ships `maze-doctor` (part of `maze-tools`). It is read-only —
it inspects and reports, never repairs — and every finding prints the command
that fixes it:

```sh
sudo maze-doctor
```

It walks the whole boot chain (shim → grubx64.efi → UKI → kernel, signatures and
MOK enrolment included), the installed kernels and their DKMS modules, every
Maze package and its files, branding, the kernel command line and initramfs
hooks, pacman configuration, leftovers from the live medium, storage, filesystem
integrity, snapshots, services, the security posture and recent kernel errors.

`--deep` additionally verifies every installed file on the system against its
package (slow). `--no-color` gives plain text suitable for a bug report — that
output is the most useful thing to attach when asking for help.

Two more tools ship next to it (also in `maze-tools`):

```sh
sudo maze-audit --deep        # did the install leave the machine the way the source intends?
sudo maze-exercise            # kernel-update rehearsal, daemon restarts, then maze-audit
```

`maze-audit` checks the machine against what `deploy-to-target.sh`, the
package presets and `packages.x86_64` promise — every live-medium file that
must be gone, every kernel parameter, the boot chain down to the hooks inside
the sealed initrd, the service set, the btrfs layout; `--deep` adds the LUKS
header, the MOK list, tmpfiles/sysusers compliance and more. `maze-exercise`
changes state on purpose: it reinstalls the recovery kernel to drive the whole
hook chain, restarts the Maze daemons, optionally suspends (`--suspend`), and
audits afterwards. Both are read from the source tree as
`MazeLinux/tools/{audit,exercise}-installed-system.sh`.

## Installing Maze Linux

> **UEFI is required.** Maze's boot stack (systemd-boot + Unified Kernel Image +
> shim Secure Boot) is UEFI-only and has no BIOS/legacy bootloader path, so a
> legacy-BIOS / CSM install cannot complete (it fails at the bootloader step).
> Boot the live medium in **UEFI mode** — disable CSM / Legacy Boot in firmware
> setup if needed. `maze-calamares` detects a BIOS boot and refuses up front with
> this instruction rather than failing late during partitioning.

On the booted live medium, connect to the internet and launch the graphical
installer — click **Install Maze Linux** in the panel/dock, or run:

```sh
maze-calamares
```

Maze uses **[Calamares](https://calamares.io/)** as its installer, in an
**offline / `unpackfs`** model: the baked live system is copied to the target
(no `pacstrap`), then Maze's own **`deploy-to-target.sh`** finalises the install
(branding, Plymouth, kernel params, Secure Boot / MOK signing, AUR apps,
security services). All Maze-specific install logic lives in that one script,
which is wired into Calamares as a `shellprocess` module — so the live ISO and
the installed system stay in sync from a single source.

- **Config & branding:** `airootfs/etc/calamares/` (`settings.conf` + `modules/`)
  and `airootfs/usr/share/calamares/branding/maze/` (true-black OLED + white).
- **Launcher:** `airootfs/usr/local/bin/maze-calamares` (XWayland + pkexec) and
  `maze-calamares.desktop` (pinned in the live panel/dock).
- **Bootloader:** systemd-boot (UEFI-only; installs fail in legacy BIOS mode);
  boots straight into Maze (`timeout 0`, so the splash comes up immediately).
- Calamares is not in the official repos, so it is built from the **AUR** by
  `tools/build-aur.sh` into the local repo and baked into the live ISO
  (live-medium only).

See **`MD-Files/CALAMARES.md`** for the full module list and the VM
debug runbook.

```sh
# edit Maze's install logic / Calamares config, then rebuild
$EDITOR airootfs/usr/share/maze/install/deploy-to-target.sh
$EDITOR airootfs/etc/calamares/...
sudo ./build.sh
```
