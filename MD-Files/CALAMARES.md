# Maze Linux — Calamares installer migration

> **STATUS (2026-06-27): COMPLETE.** Calamares is now the sole installer. The
> entire archinstall stack (the vendored fork, the GUI/TUI wrappers,
> `/etc/maze-installer`, the `archinstall` package and the old `maze-install`
> launcher) has been **deleted** from the repo — there is no longer an archinstall
> fallback or second dock icon. The notes below are kept as the design/runbook
> record of how the migration was done.

Goal: replace the archinstall-based installer with **Calamares** (the installer
framework EndeavourOS/Manjaro/Garuda use), so we stop maintaining an archinstall
fork and chasing its internal-API/schema churn.

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
- `bootloader.conf` — **systemd-boot**, id "Maze", EFI fallback on. Calamares'
  systemd-boot backend delegates entry creation to `kernel-install add`; since
  `airootfs/etc/kernel/install.conf` ships `layout=uki`, that produces a real
  UKI at `$ESP/EFI/Linux/` from the start — no plain BLS entries are ever
  written, so deploy-to-target.sh has nothing to convert after the fact (it
  only re-signs the UKI kernel-install already built). *(Updated 2026-07-02;
  this file originally documented a plain-BLS-then-manual-ukify design that has
  since been replaced.)*
- `initcpiocfg.conf` — writes target HOOKS incl. **`encrypt`** for LUKS (the live
  mkinitcpio.conf has none); the single `mkinitcpio -P` is still deploy-to-target's.
- `users.conf` (wheel sudo w/ password, zsh shell, no root pw), `removeuser.conf`
  (username: maze), `displaymanager.conf` (sddm), `fstab.conf`, `machineid.conf`,
  `locale.conf`, `keyboard.conf`, `welcome.conf` (internet NOT required — offline),
  `services-systemd.conf` (NetworkManager + graphical target), `finished.conf`.
- `localecfg`, `luksbootkeyfile`, `networkcfg`, `hwclock`, `hardwaredetect`,
  `summary`, `umount` use Calamares defaults (no `.conf` needed).
- `packagechooser_blackarch.conf` + `contextualprocess_blackarch.conf` — **optional
  BlackArch repo**. A `packagechooser` page (shown after `users`, both declared as
  the `blackarch` instance) records the choice in GlobalStorage key
  `packagechooser_blackarch` (`""` = standard, `"blackarch"` = + BlackArch). A
  `contextualprocess` step (in `exec`, right AFTER `shellprocess@mazedeploy`) then
  runs `/usr/local/bin/maze-enable-blackarch` **inside the target** but ONLY when
  `"blackarch"` was chosen. That script fetches BlackArch's **own upstream
  `strap.sh`** and runs it with only its two heavy tail commands neutralised
  (`pacman -Syy` and the `pacman -S blackarch-mirrorlist` install) — so strap still
  installs + trusts the keyring and registers the `[blackarch]` repo in
  `pacman.conf`, but runs **no db sync and installs no package** (the big BlackArch
  db syncs on the user's first `pacman -Sy`). Using upstream strap keeps us on
  BlackArch's always-current setup logic with nothing to maintain; trust model is
  the same as an official BlackArch install (HTTPS keyring fetch). It runs after mazedeploy on
  purpose: on top of the finalised pacman keyring and the stray-`[blackarch]`
  cleanup (deploy-to-target.sh §8), and best-effort (always exits 0, never aborts
  the install). **Verify keyring download + GPG verify + repo register in the VM.**

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
1. **SUPERSEDED (see `setup_secure_boot()` in `deploy-to-target.sh` instead).**
   This item originally said Secure Boot was deferred/unwired from the
   Calamares path. That is no longer true: the MOK-key generation, UKI
   signing (`maze-sb-sign`), the pacman re-sign hooks, and the
   `maze-sb-resign.path` self-heal unit were all ported into
   `deploy-to-target.sh` and now run as part of every Calamares install (on
   by default on UEFI — see `README.md`'s "Secure Boot" section). Left here
   only so the historical risk-list numbering doesn't shift.
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
- archinstall GUI kept as **Advanced** fallback during the migration (both dock
  icons existed for a transition period); it has since been fully removed (see
  the STATUS banner at the top) — Calamares is now the sole installer.
- Branding: OLED black + white (matches the rest), simple glow slideshow — not a
  full multi-slide deck yet.
- Maze apps/security: passed empty to deploy-to-target = "all" (the Maze default);
  no in-installer picker (same as the simplified archinstall flow).
