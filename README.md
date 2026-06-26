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
| `efiboot/`, `grub/`, `syslinux/` | Boot loader configurations (UEFI + BIOS).             |
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
firmware → shim (Microsoft-signed) → systemd-boot (Maze-signed) → UKI/kernel (Maze-signed)
```

- **Live ISO** — signed at build time with the shared Maze ISO key in
  `keys/secureboot/` (generated once by `tools/gen-sb-keys.sh`; `build.sh`
  patches `mkarchiso` to inject shim and sign systemd-boot + the kernel). Boot it
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

## Installing Maze Linux

On the booted live medium, connect to the internet and run the guided
installer:

```sh
maze-install
```

`maze-install` is a branded front-end around our **customized fork of
archinstall** (see `airootfs/usr/local/bin/maze-install`). It is the single
entry point we customize over time. Customization data lives in
`/etc/maze-installer/`:

| File                            | Purpose                                         |
| ------------------------------- | ----------------------------------------------- |
| `maze.json`                     | Passed to `archinstall --config` (optional).    |
| `creds.json`                    | Passed to `archinstall --creds` (optional).     |
| `*.example`                     | Templates to copy and edit.                     |

A complete config + creds enables an unattended install (`maze-install
--silent`); a partial config just pre-fills the menu. This data-file layout
lets a future GUI front-end generate the configs and then call `maze-install`.

### Customized archinstall fork

We ship a customized fork of [archinstall](https://github.com/archlinux/archinstall)
instead of the stock TUI:

- **Source (editable):** `src/archinstall/` — full upstream clone (base: 4.3)
  with Maze Linux changes (installer title, default hostname `maze`, bootloader
  entry labels "Maze Linux (...)").
- **Vendored overlay:** `airootfs/opt/maze-archinstall/archinstall/` — the copy
  that ends up in the ISO.
- **Execution:** `maze-install` runs the fork via
  `PYTHONPATH=/opt/maze-archinstall python3 -m archinstall`, so it overrides the
  packaged `archinstall`. The distro `archinstall` package is kept in
  `packages.x86_64` only to provide the Python dependencies.
- **Themed TUI:** the installer is a [Textual](https://textual.textualize.io/)
  app styled to match Maze's true-black **OLED** desktop — all CSS is inline in
  `airootfs/opt/maze-archinstall/archinstall/tui/components.py` (one block per
  screen plus the global theme in `_AppInstance`). Menus render as a
  **configuration checklist** — `✓` for a step that already has a value, `●` for
  a required step that still needs one — with an accented **▸ Install** action, a
  guidance line under the title bar and a live **Details** panel describing the
  highlighted step. KDE Plasma is the only desktop profile, so the desktop picker
  is skipped and you go straight to Maze's app/security sub-selections.

Customization workflow:

The installer that ships in the ISO is the overlay copy under
`airootfs/opt/maze-archinstall/` — edit it directly, then rebuild. (`src/archinstall`
is only a stale upstream reference for diffing; it is NOT vendored into the build.)

```sh
# 1. edit the installer that the build actually ships
$EDITOR airootfs/opt/maze-archinstall/archinstall/...
# 2. rebuild
sudo ./build.sh
```
