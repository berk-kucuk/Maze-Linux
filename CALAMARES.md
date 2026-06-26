# Maze Linux — Calamares installer migration

Goal: replace the archinstall-based installer with **Calamares** (the installer
framework EndeavourOS/Manjaro/Garuda use), so we stop maintaining an archinstall
fork and chasing its internal-API/schema churn. archinstall stays as an
**Advanced (TUI)** fallback until Calamares is verified.

Approach: **offline / `unpackfs`** model — the live ISO already has the full Maze
desktop baked in, so Calamares just *copies the live system onto the target*
(no pacstrap), then runs Maze's existing **`deploy-to-target.sh`** to finalise
(branding, Plymouth, kernel params, Secure Boot/UKI, services, AUR + [mazelinux]
apps). Grounded in EndeavourOS's proven `settings_offline.conf`.

## Where Calamares comes from
Not in the official Arch repos → built from the **AUR** by `tools/build-aur.sh`
(added to `OPTIONAL`) into `localrepo`, baked into the live ISO via
`packages.x86_64`. Live ISO only (not the installed system). Heavy build
(KPMcore/Qt6/KF6). Promote AUR entry `OPTIONAL`→`REQUIRED` once stable.

## Done (this pass — all no-sudo prep)
- `airootfs/etc/calamares/settings.conf` — Maze sequence (trimmed from EOS offline).
- `airootfs/etc/calamares/modules/shellprocess_mazedeploy.conf` — runs
  `deploy-to-target.sh @@ROOT@@ '' ''` (dontChroot, the Maze finalisation step).
- `airootfs/usr/share/calamares/branding/maze/` — `branding.desc`, `stylesheet.qss`
  (OLED black + white accent), `show.qml` slideshow, `maze-logo.png`.
- Launcher: `usr/local/bin/maze-calamares` (XWayland+pkexec), polkit rule
  `etc/polkit-1/rules.d/49-maze-calamares.rules` (LIVE-only passwordless pkexec),
  `usr/share/applications/maze-calamares.desktop`. profiledef.sh perm added.
- `tools/build-aur.sh` OPTIONAL += `calamares`; `packages.x86_64` += `calamares`.
- `build-nocompress.sh` — uncompressed ISO build for a fast VM iteration loop.

## Module configs — DONE (authored 2026-06-25, verified YAML-parse; VM-verify next)
All live in `airootfs/etc/calamares/modules/`, grounded in EndeavourOS's offline
config + upstream Calamares examples (fetched/checked online):
- `unpackfs.conf` — source `/run/archiso/bootmnt/maze/x86_64/airootfs.sfs`,
  sourcefs squashfs (confirmed against EOS, which uses the identical
  `.../<dir>/x86_64/airootfs.sfs` path). **Re-verify this exact path in the VM.**
- `partition.conf` — btrfs default, luks2, **ESP at /boot** (1 GiB), zram-first so
  disk swap defaults to none.
- `mount.conf` — btrfs subvolumes @, @home, @cache, @log; zstd:1.
- `bootloader.conf` — **systemd-boot**, plain BLS entries (NOT UKI), id "Maze",
  EFI fallback on. deploy-to-target already patches `/boot/loader/entries/*.conf`.
- `initcpiocfg.conf` — writes target HOOKS incl. **`encrypt`** for LUKS (the live
  mkinitcpio.conf has none); the single `mkinitcpio -P` is still deploy-to-target's.
- `users.conf` (wheel sudo w/ password, zsh shell, no root pw), `removeuser.conf`
  (username: maze), `displaymanager.conf` (sddm), `fstab.conf`, `machineid.conf`,
  `locale.conf`, `keyboard.conf`, `welcome.conf` (internet NOT required — offline),
  `services-systemd.conf` (NetworkManager + graphical target), `finished.conf`.
- `localecfg`, `luksbootkeyfile`, `networkcfg`, `hwclock`, `hardwaredetect`,
  `summary`, `umount` use Calamares defaults (no `.conf` needed).

## Live→target cleanup — DONE (in deploy-to-target.sh, section "2c-bis")
unpackfs copies the WHOLE permissive live airootfs; deploy-to-target.sh now
strips the live-only bits that must never reach an installed system:
- `/etc/sudoers.d/10-maze` (passwordless `%wheel`!) → replaced with a
  password-REQUIRED `10-maze-wheel`.
- `/etc/polkit-1/rules.d/49-maze-calamares.rules` (passwordless pkexec!).
- console autologin `getty@tty1.service.d/autologin.conf` + SDDM
  `10-maze-autologin.conf`.
- installer binaries (maze-calamares, maze-install*, mazeinstaller, GUI) +
  `maze-calamares.desktop`; appletsrc launcher entries; leftover `/home/maze`.
The `removeuser` module drops the `maze` account itself.

## Integration risks (verify in VM — these only prove out at runtime)
1. **Secure Boot is NOT wired into the Calamares path yet — DEFERRED on purpose.**
   The MOK-key gen + UKI/bootloader signing + `maze-sb-sign` + pacman re-sign hook
   all lived in archinstall's `installer.py` ([[secure-boot-architecture]]), which
   Calamares does NOT run. The Calamares path therefore installs **plain (unsigned)
   systemd-boot with BLS entries** (not UKI). Get a clean *unsigned* boot first;
   then port the signing into deploy-to-target.sh as a follow-up (generate per-
   machine MOK, sign vmlinuz + systemd-boot on the Calamares ESP, install the
   re-sign hook). Until then, installs must run with Secure Boot OFF in firmware.
2. **Live→target cleanup — DONE** (see section above). Verify in VM that the
   installed system: has NO passwordless sudo (`sudo` prompts for a password), has
   NO autologin (boots to SDDM login), and that `/etc/polkit-1/rules.d/
   49-maze-calamares.rules` and the installer launchers are gone.
3. **Launch as root on Wayland.** `maze-calamares` uses XWayland+pkexec; verify it
   actually opens on the live KDE Wayland session (may need `xorg-xhost` installed,
   and Calamares' `QT_QPA_PLATFORM=xcb`).
4. **deploy-to-target under Calamares.** It expects live paths (/etc/skel,
   /usr/share/maze, …) which exist in the live env, and `@@ROOT@@` as target. The
   AUR/app install needs network. Confirm it runs to completion as a shellprocess.

## VM iteration runbook (needs sudo — do when back at the machine)
```
# 1. Build the AUR set incl. Calamares (normal user):
./tools/build-aur.sh
# 2. Fast uncompressed ISO (root):
sudo ./build-nocompress.sh
# 3. Boot ./out/*.iso in a UEFI VM (virt-manager/qemu, OVMF, >=8 GB disk).
# 4. In the live session, launch "Install Maze Linux (Calamares)".
#    If it doesn't open / a module fails, get the debug log:
#       calamares -d            # run from a terminal; copy the output
#    or  ~/.cache/calamares/session.log  /  journalctl
# 5. Paste the failing module + error here → fix the .conf → rebuild → repeat.
```
Calamares errors are specific ("module X: ...") so they converge fast.

## Decisions taken (defaults, change if you disagree)
- archinstall GUI kept as **Advanced** fallback (both dock icons exist during
  transition); make Calamares the primary once it boots clean.
- Branding: OLED black + white (matches the rest), simple glow slideshow — not a
  full multi-slide deck yet.
- Maze apps/security: passed empty to deploy-to-target = "all" (the Maze default);
  no in-installer picker (same as the simplified archinstall flow).
