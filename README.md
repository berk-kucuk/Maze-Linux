# Maze Linux

Maze Linux is an Arch-based distribution focused on security, privacy and local
AI, with a monochrome KDE Plasma (Wayland) desktop and a full UEFI Secure Boot
chain. This repository is the [archiso](https://gitlab.archlinux.org/archlinux/archiso)
profile that builds the Maze live / install ISO. The system is English by default.

![Maze Linux desktop](https://mazelinux.berkkucukk.com.tr/screenshots/desktop.webp)

Website and downloads: <https://mazelinux.berkkucukk.com.tr>

## What's in the ISO

- **Desktop:** KDE Plasma 6 on Wayland, SDDM, a top bar + bottom dock layout,
  PipeWire, NetworkManager with `systemd-resolved`.
- **Maze apps and config** from the signed `[mazelinux]` repository, pulled in
  by `maze-meta`: branding, Plasma config, hardening, `maze-guard`,
  `entropy-shield`, `qlam`, `hazedrop`, `haze`, `maze-ai`, `maze-connect`,
  `maze-cloak`, `maze-snapshots`, `maze-tools`, `maze-secureboot`.
- **Security and privacy:** Tor / Tor Browser, OnionShare, WireGuard, firewalld,
  AppArmor, audit, OpenSnitch, USBGuard, ClamAV, Lynis, rkhunter.
- **AI:** Ollama for local models.
- **Everything else:** Firefox, Steam, Flatpak, distrobox, `paru`, and
  `base-devel` + `git` for building AUR packages.

See `packages.x86_64` for the full list.

## Repository layout

| Path               | Purpose                                                                 |
| ------------------ | ----------------------------------------------------------------------- |
| `profiledef.sh`    | ISO metadata, boot mode (UEFI / systemd-boot only), squashfs options, file permissions. |
| `packages.x86_64`  | Packages installed into the live system.                                |
| `pacman.conf`      | Pacman configuration used during the build (`[maze-aur]`, `[mazelinux]`, official repos). |
| `airootfs/`        | Files overlaid onto the live root filesystem (live user, autologin, build hooks, skel). |
| `efiboot/`         | systemd-boot entries for the live medium.                               |
| `build.sh`         | Wrapper around `mkarchiso`: shim, signed UKI, Secure Boot signing.      |
| `tools/`           | AUR builder, Secure Boot key generator, VM / QEMU test tooling.         |
| `keys/secureboot/` | The **public** Maze ISO certificate (`Maze.crt` / `Maze.cer`). The private key is never committed. |
| `MD-Files/`        | Design notes and runbooks.                                              |

Branding (logo, Plymouth theme, wallpapers), the Plasma layout and the installer
are **not** in this tree. They ship as packages from `[mazelinux]`
(`maze-branding`, `maze-plasma-config`, `maze-installer`, …), so installed
systems get fixes through `pacman -Syu` and the ISO simply installs them.

## Package sources

`pacman.conf` combines three sources:

1. **`[maze-aur]`** (`./localrepo`, listed first): packages that are only on the
   AUR, built locally by `tools/build-aur.sh`. These are `shim-signed`
   (required), plus `paru`, `calamares`, `obfs4proxy`, `upscayl-bin` and a few
   other optional apps. Because it comes first, it also works as a **staging
   area**: a package dropped here overrides the published `[mazelinux]` version
   in the next ISO build.
2. **`[mazelinux]`** (<https://mazerepo.berkkucukk.com.tr/packages>): Maze's own
   packages, signed with the `mazelinux-keyring` key.
3. **Official Arch repositories**, including `multilib`.

The AUR packages are built in an **isolated clean chroot** (`./aur/chroot`, via
`devtools`), so nothing gets installed on your host. If an optional package
fails to build, `build-aur.sh` comments it out in `packages.x86_64`
(`#MAZE-SKIP#`) and the ISO build carries on.

## Building the ISO

Requirements: an Arch (or Arch-based) host, root access, several GB of free disk
space, and:

```sh
sudo pacman -S --needed archiso devtools git sbsigntools systemd-ukify
```

Then:

```sh
./tools/build-aur.sh     # build AUR packages into ./localrepo (NOT as root)
sudo ./build.sh          # build the ISO
```

The ISO is written to `./out/` and the intermediate files go to `./work/`. You
can delete both afterwards. To use other directories:

```sh
sudo ./build.sh -w /tmp/maze-work -o /tmp/maze-out
```

Signing the live ISO needs the private key `keys/secureboot/Maze.key`, which
`tools/gen-sb-keys.sh` creates once. It is git-ignored and never published.

## Testing in a VM

`tools/test-boot.sh` boots an ISO (or installed disk image) headless in QEMU and
checks that it really comes up, using screenshots and the QEMU guest agent. It
needs no root and suits CI (`--secboot` enforces Secure Boot). `tools/vm-install-test.sh` runs the full
install flow on a Secure Boot–enforcing OVMF with a TPM 2.0 (swtpm):

```sh
tools/vm-install-test.sh install    # boot the newest ISO in ./out, install onto a fresh 40 GiB disk
tools/vm-install-test.sh boot       # boot the installed disk
```

To test by hand with Secure Boot enabled:

```sh
cp /usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd /tmp/code.fd
cp /usr/share/edk2/x64/OVMF_VARS.4m.fd /tmp/vars.fd
qemu-system-x86_64 -m 4096 -enable-kvm \
    -machine q35,smm=on -global driver=cfi.pflash01,property=secure,value=on \
    -drive if=pflash,format=raw,unit=0,file=/tmp/code.fd,readonly=on \
    -drive if=pflash,format=raw,unit=1,file=/tmp/vars.fd \
    -cdrom out/mazelinux-*.iso -boot d
```

## Secure Boot

Maze supports UEFI Secure Boot on both the live ISO and the installed system. It
uses a Microsoft-signed **shim** plus a Maze key enrolled as a **MOK** (Machine
Owner Key). Factory and Windows keys stay in place, and firmware *Setup Mode* is
not needed.

```
firmware → shim (Microsoft-signed) → Unified Kernel Image (Maze-signed)
```

The kernel, initramfs and kernel command line are bundled into a single signed
**Unified Kernel Image** (UKI), installed as `grubx64.efi` (the name shim
chainloads). Shim verifies it through its own MOK-backed `shim_lock` protocol,
and the firmware never has to load a separate `vmlinuz`. This makes the chain
work on strict firmware (MSI, some ASUS, …) that would otherwise reject the boot
with *Security Policy Violation*.

- **Live ISO:** signed at build time with the Maze ISO key. On the first boot,
  MokManager appears: choose *Enroll key from disk* → `MOK.cer` on the ISO's
  EFI partition → enroll → reboot. `mokutil --sb-state` should then report
  *SecureBoot enabled*.
- **Installed system:** the installer generates a **per-machine** key (its
  private half never leaves that machine), signs systemd-boot and the UKI, and
  copies the certificate to the ESP as `MOK.cer`. `maze-secureboot` re-signs
  automatically after kernel and systemd updates. On the first boot, enroll
  `MOK.cer` the same way (no password, only physical presence). Details are in
  `/var/lib/maze-secureboot/ENROLLMENT.txt`.

If you prefer not to use Secure Boot, disable it in firmware or turn off the
installer toggle. Both the ISO and the installed system boot normally either way.

## Installing

> **UEFI is required.** Maze's boot stack (systemd-boot + UKI + shim) has no
> BIOS / legacy path. Boot the live medium in **UEFI mode** and disable CSM /
> Legacy Boot if needed. The installer detects a BIOS boot and refuses up front.

On the live desktop, connect to the internet and click **Install Maze Linux** in
the dock, or run `maze-calamares`.

The installer is [Calamares](https://calamares.io/) in an **offline /
`unpackfs`** model: the live system is copied to the target (no `pacstrap`), and
Maze's `deploy-to-target.sh` then finishes the install (branding, kernel
parameters, Secure Boot / MOK signing, AUR apps, security services). The
Calamares config, branding, launcher and `deploy-to-target.sh` ship in the
**`maze-installer`** package. It is live-ISO-only and is never installed on the
target. See `MD-Files/CALAMARES.md` for the module list and the VM debug
runbook.

## Checking an installed system

Every install ships `maze-tools`:

```sh
sudo maze-doctor              # read-only health check of the boot chain, kernels, packages, services, security
sudo maze-audit --deep        # did the install leave the machine the way the source intends?
sudo maze-exercise            # kernel-update rehearsal and daemon restarts, then maze-audit
```

`maze-doctor` never repairs anything, and every finding prints the command that
fixes it. `maze-doctor --no-color` gives plain text, which is the most useful
thing to attach when asking for help. `tools/audit-installed-system.sh` and
`tools/exercise-installed-system.sh` in this repo are symlinks to those scripts
in the `maze-tools` source tree.

## License

Copyright © 2026 Berk Küçük

Released under the GNU General Public License v3.0 — see [LICENSE](LICENSE).
