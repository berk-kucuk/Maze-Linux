# Changelog

All notable changes to Maze Linux (the distro build — ISO, installer, and
bundled `maze-*` tooling) are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
adapted for a rolling-release, date-versioned ISO rather than semver: each
ISO build is identified by its `iso_version` (`YYYY.MM.DD`, see
`profiledef.sh`). This file starts from the project's first public release;
history before that point was not tracked.

## [Unreleased]

### Fixed — eighth audit round, first audit of a REAL installed machine (11 Sep 2026)

Everything below was found by `tools/audit-installed-system.sh` (new — see
below) and a session-level sweep on a ThinkPad installed two days earlier from
this tree. Full write-up with evidence: `MD-Files/DENETIM-SEKIZINCI-TUR.md`.

- **The proprietary Broadcom `wl` module loaded on a machine with no Broadcom
  hardware** (`maze-hardening` 1.0.0-4). `wl.ko` carries a wildcard PCI alias
  matching every class-0280 network controller — Intel CNVi included — so
  udev loaded it at every boot: unsigned, tainting the kernel, and tripping
  `Unpatched return thunk in use`, which switches the retbleed/SRSO mitigation
  off for the whole kernel. It is now blacklisted for alias loading and loaded
  by a udev rule only when a Broadcom (14e4) controller is present; the
  scriptlet unloads a stray one immediately. `maze-doctor` reports both the
  stray module and the kernel warning.
- **The "Install Maze Linux" dock icon came back on an installed system**
  (`maze-plasma-config` 1.2.1-2). The pin shipped inside the package's
  `/etc/skel`; the installer stripped it with `sed`, and the next upgrade of
  the package put it back — exactly the failure §9.12 of the reference doc
  predicted. The pin is gone from the package; `setup-live-user.sh` adds it to
  the live user's own panel instead.
- **The machine announced itself on every LAN** (`maze-hardening` 1.0.0-4).
  resolved's compiled-in defaults answered mDNS and LLMNR, and fwupd's `passim`
  advertised a firmware cache through `avahi`. Removing archiso's drop-in (which
  the installer did) was never enough because the default underneath is also
  "yes". Now `resolved.conf.d/zz-maze-privacy.conf` sets `MulticastDNS=no
  LLMNR=no`, and `passim`/`avahi-daemon` are masked once (an admin who unmasks
  them is left alone). `maze-doctor` checks all of it.
- **Calamares stayed installed** (`maze-installer` 2.0.0-22). `packages.x86_64`
  lists `calamares` and `xorg-xhost` explicitly, so `pacman -Rns maze-installer`
  never took them along. All three are removed by name now, each checked first
  so a missing one cannot abort the transaction.
- **An unsigned `Fallback Linux Boot Manager` NVRAM entry survived** (2.0.0-22,
  `maze-secureboot` 1.2.0-14). Newer `bootctl` creates it next to `Linux Boot
  Manager`; the cleanup pattern only matched the latter. `maze-boot-entries`
  now labels and counts unsigned systemd-boot entries (it still never deletes
  what is not Maze's).
- **`linux-chan-ai` and `sentinai` were installed by default** (2.0.0-22).
  `maze-meta` and the docs excluded them on purpose (both can talk to Google
  Gemini); `deploy-to-target.sh`'s own list still had them. Removed.
- **`snapper-timeline.timer` was enabled on every install** (`maze-snapshots`
  1.1.0-4). `snapper create-config` enables it itself through snapperd, after
  which `TIMELINE_CREATE=no` made it fire hourly for nothing. The setup unit
  disables it, and re-checks at every boot for machines configured earlier.
- **The installer no longer downgrades packages the ISO shipped**
  (`maze-installer` 2.0.0-23, `maze-aur-setup`). `install_maze_repo_apps` ran
  `pacman -S --needed` over the default app set; `--needed` only skips an exact
  version match, so an ISO built with a newer, not-yet-published build (the
  `./localrepo` staging path) ended up with the OLDER published version on the
  installed system — seen in a VM install: haze 2.11.2 -> 2.11.1, maze-cloak
  1.2.1-2 -> 1.2.1-1. Only packages that are actually missing are installed
  now, in all three places that had the pattern. `maze-aur-setup` also still
  listed linux-chan-ai and sentinai; aligned with `DEFAULT_MAZE_APPS`.
- **`maze-boot-entries` could not verify a single entry on a current system**
  (`maze-secureboot` 1.2.0-15). It only understood the `File(\EFI\...)` form
  that old efibootmgr printed; efibootmgr >= 18 prints the raw device path, so
  every entry came back "could not verify - kept" and `--clean` never removed
  anything. Found by finally running it on real hardware. Both forms are parsed
  now.
- **Loose `/boot/vmlinuz-<pkgbase>` files no longer pile up on the ESP**
  (1.2.0-15). mkinitcpio's pacman hook copies the kernel there on every update
  even with Maze's empty presets; nothing boots it under layout=uki, and
  `maze-sb-sign` was signing it anyway. It is removed when the ESP is UKI-only
  (layout=uki and no BLS entries); any other layout keeps the old behaviour.
- **Typing `maze-guard` in a terminal no longer answers "ERR bad-command"**
  (`maze-tools` 1.1.0-35). Two different programs shared the name: the Maze
  Guard application at `/usr/bin/maze-guard`, and maze-tools' tiny client for
  the `maze-guardd` kill-switch broker at `/usr/local/bin/maze-guard`, which
  wins in PATH. The client is now `maze-guardctl`; `maze-panic`,
  `maze-panic-restore` and `maze-killswitch` were updated with it. The desktop
  entry always used the full path, which is why the menu never showed it.
- **`maze-install-vmware` no longer dies with "Missing dependencies:
  vmware-keymaps"** (`maze-tools` 1.1.0-36). The AUR vmware-workstation
  PKGBUILD adds that dependency at run time inside an `if`, which .SRCINFO and
  therefore paru never see; the tool now installs `vmware-keymaps` explicitly
  first.
- `maze-doctor` run without root no longer claims "No active firewall" — it
  cannot read the nftables ruleset unprivileged and says so instead.
- Smaller (2.0.0-22): `paru-debug` no longer installed with the AUR builds; the
  real user joins `wireshark`/`kvm`/`libvirt` when those groups exist (the live
  user already did); a dozen archiso leftovers (`choose-mirror`, `livecd-*`,
  `/root/.automated_script.sh`, networkd `.network` files) are removed from the
  target; `SNAP_PAC_SKIP=y` inside the install chroot ends the
  "fatal library error, lookup self" lines snap-pac wrote to pacman.log;
  the stale "maze-hardening provides a DNS config" comment is gone (that
  override was dropped deliberately — see `maze-hardening/PKGBUILD`).

### Added
- **`maze-audit` and `maze-exercise` ship in `maze-tools`** (1.1.0-37), so every
  installed machine — and every VM built from the next ISO — carries the two
  scripts below without fetching anything. In the source tree they remain
  `MazeLinux/tools/{audit,exercise}-installed-system.sh` (symlinks into the
  package), where `maze-audit` also finds the checkout and adds the
  source-drift and version comparisons.
- **`tools/exercise-installed-system.sh`** — the tests that only a real run can
  prove, run on purpose and verified afterwards: the kernel-update path (a
  `linux-lts` reinstall fires the same hook chain as `pacman -Syu linux`, and on
  its first run it turned into a real 6.18.50 -> 6.18.51 upgrade — every hook,
  the rebuilt and signed LTS UKI, the refreshed recovery image, the untouched
  primary image, DKMS, snap-pac and maze-boot-check all checked), Maze daemon
  restart resilience, read-only runs of the recovery tools, and an optional
  suspend/resume cycle read back from the journal. Ends with the audit below.
- **`tools/audit-installed-system.sh`** — verifies an installed machine against
  what THIS source tree says the installer should have produced: every
  live-only file `deploy-to-target.sh` removes, every cmdline parameter it
  adds, the boot-chain layout on the ESP (down to the hooks inside the sealed
  initrd), the service set from the presets and `enable-services.sh`, the
  Calamares subvolume layout, package coverage against `packages.x86_64`, and a
  byte-for-byte comparison of the installed Maze packages with the source tree.
  Read-only; ~400 checks; runs `maze-boot-check` and `maze-doctor` at the end.
  `maze-doctor` asks "is this machine healthy?"; this asks "did the ISO built
  from this tree leave the machine the way the tree intends?" — a different
  question, and the first run answered it with the seven findings above.
- **`maze-doctor` says whether a crash was Maze's fault** (`maze-tools`
  1.1.0-24). A new Stability section detects boots that ended without a clean
  shutdown, shows the last thing the kernel logged before each one, and
  classifies it — hardware (a USB device that vanished, a disk that stopped
  answering, overheating), software (out of memory), the graphics driver, or a
  real kernel fault — saying "unclear" rather than guessing when the evidence
  does not support an answer. Also counts USB surprise-removals and thermal
  events over the last week.

  This exists because every crash this system has actually suffered was
  hardware — a USB WiFi adapter that disconnected itself mid-flight, a display
  cable left unplugged after a repair, an SSD loose in its enclosure — and each
  one cost hours of looking in the wrong place, because nothing on the machine
  would say "this was not the operating system". A distribution that cannot
  answer that question feels fragile even when it is sound.

  Two wrong detection patterns were tried and are documented in the code:
  "Reached target Power-Off" never reaches the journal (journald stops first),
  so every clean shutdown read as a crash; "Deactivated successfully" matches
  ordinary session teardown, so a genuinely frozen boot read as clean. Only
  filesystem unmounts and target shutdown are specific to a real shutdown.
- **Maze Guard stops rebuilding its capture every minute** (2.16.0-1). The
  sniffer ran in 60-second slices, so the interface entered and left
  promiscuous mode roughly 600 times in an evening. Slices are now ten minutes,
  and a `stop_filter` leaves the capture the moment the interface actually
  changes — so it reacts faster than before while tearing the socket down ten
  times less often. Waste on a wired NIC, but a hazard on a USB WiFi adapter,
  where standing a capture back up is the path in which rt2x00usb mishandles a
  device that vanished — and an external adapter is the normal way to get
  monitor mode.

- **`maze-boot-entries`** (`maze-secureboot` 1.2.0-9) — lists the firmware boot
  menu and clears out the Maze entries that no longer lead anywhere. A machine
  installed several times accumulated one "Maze Linux" line per install, most
  aimed at partitions a later reinstall had already wiped, which makes the boot
  menu useless in the one moment it matters: picking the recovery kernel. It
  only ever touches entries Maze created — Windows, firmware setup and network
  boot are listed for context and never modified — never removes the entry the
  machine booted from, refuses to remove the last surviving Maze entry, and
  saves the previous state to `/var/lib/maze/efi-entries.before` before
  deleting anything, treating a failure to write that record as a reason to
  stop rather than a detail to log.

  "Dead" is decided by following the entry, not by guessing from the partition
  table: it names a partition and a file on it, and both have to be there. A
  surviving partition proves nothing on its own, because reformatting an ESP
  leaves it in place with the loader gone. The check has three outcomes rather
  than two — when it cannot look (partition not mounted, not running as root)
  the entry is reported unverified and kept, since reading "I could not check"
  as "it is dead" is how a tool deletes the boot entry of a second, working
  installation. More than one Maze install on a machine is expected: an entry
  on another partition that really does hold a loader is labelled as another
  installation and left alone.
- **`maze-doctor` counts stale boot entries** (`maze-tools` 1.1.0-22) and points
  at `maze-boot-entries`, so the mess is noticed before someone needs the menu.

- **The recovery kernel can finally be booted** (`maze-secureboot` 1.2.0-8).
  `linux-lts` was installed, its UKI built, signed and its DKMS modules
  compiled — and there was no way to select it: shim chainloads exactly one
  file, there is no boot menu, and firmware cannot load a MOK-signed image on
  its own. `maze-sb-sign` now keeps a second shim plus that kernel's signed UKI
  under `EFI/maze-recovery`, which works because shim looks for its second stage
  in its own directory, and adds one firmware entry, *Maze Linux (recovery
  kernel)*, appended to the end of BootOrder so it never displaces the real one.
  The recovery kernel is chosen automatically and is never a copy of the image
  that just broke. The primary chain is untouched: every failure here is a
  warning, and the entry is skipped entirely when the ESP lacks room for the
  next kernel update's own image.
- **`maze-boot-check` verifies the way back** — a twelfth check: the recovery
  image exists, is signed with the machine MOK, points at a kernel that is still
  installed, and has its firmware entry. A second kernel that cannot be reached
  is the same as not having one, so this reports recoverability rather than
  passing silently.
- **The emergency shell opens again** (`maze-secureboot` 1.2.0-8). `sulogin`
  refuses an account with no usable password, so locking root — which the
  installer now does — would have meant a failed mount left the owner with a
  live USB as the only way in. `SULOGIN_FORCE=1` drop-ins for
  `emergency.service` and `rescue.service` fix that. Safe here specifically
  because the kernel command line is sealed in a signed UKI:
  `systemd.unit=emergency.target` cannot be appended at the boot screen, so
  emergency mode is only reachable through a real failure.
- **`maze-doctor` checks the root account and the emergency shell together** —
  the two failures are opposites (a passwordless root is a hole, a locked root
  with no `SULOGIN_FORCE` is a trap) and only both answers say whether the
  machine is both safe and rescuable.

- **`maze-boot-check`** — end-to-end verification of the boot chain, run as the
  last hook of every kernel/systemd/mkinitcpio transaction. Until now every
  layer failed loudly in its own lane but nothing checked the chain as a whole,
  so a machine could pass every individual step and still not boot. The clearest
  case: a UKI that builds and signs perfectly but carries an initramfs with no
  `encrypt` hook on a LUKS root — it boots, cannot unlock its own disk, and
  nothing anywhere reports a problem. Eleven checks, each printing the command
  that fixes it; `--repair` rebuilds and re-signs.
- **`maze-boot-guard`** — holds a logind shutdown inhibitor while
  `/var/lib/maze/boot-unsafe` exists, so Plasma's log-out menu and
  `systemctl reboot` from a session are refused with the reason. `reboot -i` and
  `reboot -f` are deliberately not blocked. Backed by a critical desktop
  notification at login and a `/etc/profile.d` warning for TTY and SSH, plus a
  timer (3 min after boot, then daily) that catches drift outside any pacman
  transaction.
- **`maze-snapshots`** — snapper + snap-pac, with the configuration created by a
  boot-time oneshot (a pacman scriptlet cannot do it: during an ISO build it
  runs against the airootfs, which is not the btrfs root it would configure).
  Covers the half maze-secureboot does not — a bad library or a half-applied
  upgrade leaves a running system unusable without ever touching boot.
- **`linux-lts` + `linux-lts-headers`** in `maze-meta`. With one kernel
  installed a bad update is a live-USB recovery; with two, a known-good image is
  already built and signed on the ESP. `-headers` is required so nvidia-open-dkms
  and broadcom-wl-dkms build against LTS as well.
- **`publish.sh`** — resolves package/directory names out of the PKGBUILDs and
  topologically orders a publish. maze-meta depends on every other maze package,
  so publishing it first makes the next `pacman -Syu` fail with "target not
  found" on every installed machine. The ordering is now a property of the code.

### Changed
- **`maze-snapshots-setup` runs its two jobs independently.** Creating the
  snapper config is still one-shot, but the `/.snapshots` mount check now runs
  every boot — machines configured by an older version never had one, and the
  old script returned early the moment the config existed, so nothing new could
  ever reach them.
- **`maze-boot-guard` and `maze-boot-notify` speak to a person, not an admin.**
  The inhibitor reason is the entire user interface of that tool on a desktop:
  it is what Plasma's shutdown dialog shows, and someone at 3% battery has to
  act on it in one sentence. It now says what breaks, what to run, and that
  they can still shut down — in that order. (`maze-secureboot` 1.2.0-7)
- **`maze-doctor` distinguishes former defaults from real orphans**
  (`maze-tools` 1.1.0-20). Dropping the two cloud apps from `maze-meta` leaves
  them installed but unrequired, which pacman reports as orphaned — a fault
  message for a deliberate change. They are now named as no longer default,
  with the command to remove them if wanted.
- **The Secure Boot chain is now a package (`maze-secureboot`)**, pulled in by
  `maze-meta`. `maze-sb-sign`, `maze-kernel-install-add`, the two pacman hooks,
  the `kernel-install` plugin, the `maze-sb-resign` units and the
  `systemd-boot-update` drop-in used to be written per-machine as inline
  heredocs by `deploy-to-target.sh`, into `/usr/local/bin` and `/etc`. pacman
  owned none of them, so a bug in the signer — or an upstream `systemd` change
  breaking the `kernel-install` contract — could never be fixed on an
  already-installed machine: the one subsystem whose failure mode is "does not
  boot" was the one with no update path. Fixes now ship as `pkgrel++`.
  `deploy-to-target.sh` lost ~384 lines of heredocs and hard-fails the Secure
  Boot setup if the package is absent, rather than silently producing a machine
  that signs once and never again. The package's `.install` scriptlet migrates
  existing installs: the old `/etc` copies **shadow** the packaged ones (pacman
  reports no conflict, because the paths differ), so it deletes them, leaves
  exec shims at the old `/usr/local/bin` paths — pacman has already read the
  hook directories by the time a scriptlet runs, so the old hooks can still
  fire once in that same transaction — and rebuilds and re-signs the chain.

### Fixed
- **Every reinstall added another boot entry** (`maze-installer` 2.0.0-18).
  `deploy-to-target.sh` ran `efibootmgr --create` unconditionally and only ever
  deleted competing `systemd-boot` entries, never its own earlier ones. It now
  removes "Maze Linux" entries whose partition no longer exists before adding
  the new one — and only those, since an entry on a partition that is still
  present may belong to another install the user still boots.
- **`[mazelinux]` is signature-verified.** This was carried in "Known gaps" as
  an open `SigLevel = Optional TrustAll` long after it was closed. Both the
  ISO's `pacman.conf` and `deploy-to-target.sh` set `Required DatabaseOptional`
  and `mazelinux-keyring` ships the signing key; the only `Optional TrustAll`
  left is `[maze-aur]`, the local build-time repo that never reaches an
  installed machine. Documentation fix, not a code change — but the entry was
  telling readers the distribution's packages are unverified when they are not.
- **The installed system inherited a passwordless root** (`maze-installer`
  2.0.0-17). The live ISO ships `root::` so the live session works, Calamares is
  configured with `setRootPassword: false`, and `unpackfs` copies `/etc/shadow`
  wholesale — so anyone at a TTY on a finished install could log in as root by
  typing the name. `deploy-to-target.sh` now locks the account, verifies the
  result with `passwd -S` rather than trusting it, and repairs `/etc/shadow`
  directly if shadow-utils left an empty field (its behaviour on an empty
  password field varies by version, and the outcome here decides whether a
  stranger is root).
- **Privacy: no cloud AI by default.** `linux-chan-ai` and `sentinai` were in
  `maze-meta`, so every Maze install got them — and both send what you type to
  Google Gemini. Linux Chan has no offline mode at all and reads files and
  screenshots for you. A distribution whose promise is that nothing leaves the
  machine by default cannot install those without being asked, so `maze-meta`
  no longer pulls them in. They stay in `[mazelinux]`, one `pacman -S` away.
  (`maze-meta` 1.5.0-1)
- **SentinAI prefers the local backend** (1.6.0-1). `AI_BACKEND` used to default
  to `gemini`; `resolve_backend()` now picks a reachable local Ollama first and
  only falls back to the cloud when the user has actually configured a key, so
  an existing install keeps working while a fresh one is private. The Ollama
  model is chosen automatically from what is already pulled, preferring the one
  Maze AI uses so the two apps share it. Selecting the cloud backend shows a
  one-time notice saying where the data goes.
- **Linux Chan states the cloud dependency** (1.1.4-1) — a first-run notice
  naming Google, and pointing at Maze AI for a fully local assistant.
- **Maze Guard records what protected you** (2.15.0-1). A new `core/posture.py`
  reads the rest of the suite — MAC randomisation, DNSCrypt, Tor, last malware
  scan — and every incident dossier keeps that snapshot from the moment the
  source first turned hostile. The report gained a "Your defences at the time"
  section, so an incident answers not just *who attacked you* but *were you
  covered*. Unknown is recorded as unknown and never as "off": claiming DNS was
  in the clear on a machine that never had Entropy Shield would be a statement
  about the user's protection rather than a fact about a missing file.
- **Maze suite status contract** — `/run/maze/status/<app>.json`, one flat
  object per app, readers taking only the keys they understand. Maze Cloak
  publishes to it (1.2.0-1) alongside its own state file, so the two can never
  disagree, and clears it on shutdown so a stale claim cannot outlive the
  daemon. Maze Guard reads it, falling back to each app's existing artefacts
  for anything that does not publish yet.
- **`maze-rollback`** (`maze-snapshots` 1.1.0-1) — roll back to a snapshot
  without having to know that `snapper rollback` needs `--ambit classic` on
  Maze's layout. Without it snapper prints *"Cannot detect ambit"*, exits 1 and
  changes nothing; a user who misses that line reboots expecting an older
  system and gets the same one back. It also refuses a snapshot whose
  `/etc/fstab` still pins the root subvolume (it would silently undo itself)
  and warns when the snapshot has no modules for the kernel the ESP will boot.
- **`/.snapshots` is mounted from fstab** (`maze-snapshots` 1.1.0-1). The
  snapshot store is a subvolume nested inside the root subvolume, and nested
  subvolumes are not included in a snapshot of their parent — so the moment you
  boot a rollback, `/.snapshots` is empty and `snapper list` shows nothing, with
  the one tool needed to roll forward blind. Mounting it explicitly, the way
  openSUSE does, keeps it visible from whichever root is booted. `nofail`: a
  wrong entry costs snapshots, never the boot.
- **Maze Guard documents its own edge** — a "What it does not cover" section
  naming phishing, local malware and service breaches, with what does cover
  each. A tool that claims to catch everything teaches you to stop checking.
- **The pinned boot kernel was discarded by every kernel update.**
  `maze-sb-sign` always took the newest installed kernel and ignored
  `/etc/maze/kernel-default`, so `maze-kernel-helper set-default` had to warn
  that installing or updating any kernel would re-pin the newest one — someone
  deliberately running `linux-lts` was moved back onto `linux` with no notice.
  The signer now honours the pin (falling back to the newest, loudly, only when
  the pinned kernel is not installed or has no UKI), and the switcher keeps the
  boot markers in sync and clears the pin when the pinned kernel is removed.
- **No way back from a bad kernel.** shim chainloads `grubx64.efi` and nothing
  else — there is no systemd-boot menu and the sd-boot NVRAM entry is
  deliberately removed — so a kernel that booted badly left only a live USB.
  The outgoing image is now kept as `grubx64.efi.maze-prev`, rotated on a
  kernel *version* change (tracked in `grubx64.efi.maze-kver`) so the three
  signer invocations of one upgrade cannot overwrite the fallback with the
  image it is a fallback for.
- **Stale-UKI cleanup never ran in the case it existed for.** Pruning was
  gated on a successful sign, but a full ESP is the obvious way for `sbsign`
  to fail — so the space that caused the failure could never be reclaimed.
  Pruning now also runs *before* signing, which is safe for the same reason
  the after-prune was: the `grubx64.efi` on disk is a self-contained copy of a
  bootable UKI.
- **Secure Boot UKI signing race condition**: `kernel-install add` could
  trigger `maze-sb-sign` from up to three overlapping sources (the
  `85-maze-kernel-install.hook` → `kernel-install` → `95-maze-sb-sign.install`
  path, the `zz-maze-secureboot.hook` pacman hook, and the
  `maze-sb-resign.path` unit) with no locking, so two concurrent instances
  could race writing the same temp file and leave a truncated/corrupt UKI on
  disk — causing a kernel panic (`No working init found`) on next boot.
  Fixed by adding an `flock`-based lock around every `maze-sb-sign`
  invocation, regardless of trigger.
- Removed two duplicated, non-atomic `sbsign` code paths in
  `deploy-to-target.sh` (the "5b-bis" live-side re-sign and the final
  post-AUR re-sign) that wrote `grubx64.efi` directly instead of
  temp-file-then-rename — an install interrupted mid-write (power loss, kill)
  could have left a corrupt signed bootloader. Both now delegate to the
  single, already-atomic, lock-serialized `maze-sb-sign` script instead of
  re-implementing the signing logic.
- Corrected a stale code comment in `tools/gen-sb-keys.sh` pointing at a
  nonexistent `installer.py:_setup_secure_boot` (the real per-machine key
  setup lives in `deploy-to-target.sh:setup_secure_boot`).
- **`~/.ssh` permission/ownership drift**: on a real installed machine, a
  root-context maintenance session (a chroot repair after the kernel-panic
  bug above) left files under a user's `~/.ssh` root-owned, which silently
  stopped `known_hosts` from ever being written (ssh does not warn about
  this the way it does about private keys — it just skips the write).
  `deploy-to-target.sh`'s per-user home pass now explicitly re-asserts
  `~/.ssh` (700) and its contents (600/700) alongside the existing
  ownership/home-mode fix, instead of relying only on the broad recursive
  `chown`.

### Added
- `maze-gpu-driver` now installs `cuda` + `ollama-cuda` alongside the NVIDIA
  proprietary driver (best-effort, does not fail the driver install if the
  ~2.2 GiB CUDA download fails on a slow/offline mirror), so Ollama picks up
  GPU acceleration automatically. `--open` (revert to open-source drivers)
  symmetrically removes both.
- `SECURITY.md` — vulnerability reporting process and scope.
- `.github/workflows/lint.yml` — CI: shellcheck + `bash -n` over every script
  Maze itself owns, plus static drift checks (profiledef.sh's
  `file_permissions` paths actually exist, no duplicate `packages.x86_64`
  entries, `pacman.conf` has the repos the install pipeline expects). No
  full ISO build in CI yet (see Known gaps).
- This changelog.

### Known gaps (tracked, not yet fixed)
- **Booting a rollback is not proven yet.** `maze-enable-rollback --apply` was
  verified on real hardware — the machine came up with no `rootflags=subvol=`
  and mounted the btrfs default subvolume — but in the one full test after that,
  `snapper --ambit classic rollback` set the default to the snapshot, reported
  success, and the machine still booted `@`. The reason is unknown; the
  deciding data is `btrfs subvolume get-default /` taken after that reboot.
  Until it is understood, Faz A stays opt-in and is not the installer default.
  See `SNAPSHOT-BOOT.md`, "Sahada öğrendiklerimiz".
- Calamares' `unpackfs` copies `/var/lib/pacman` wholesale, so `pacman -S
  --needed` finds every Maze package already installed on the target and no
  `.install` scriptlet ever runs there. Every package's first-boot work has to
  be duplicated by hand in `deploy-to-target.sh`, which is where several
  install-time bugs have come from. Structural, not yet addressed.
- CI (`lint.yml`) is static-only — no full `mkarchiso` build or boot test yet
  (would need a privileged runner, ~10 AUR packages built from source, and
  the maintainer's Secure Boot signing key).
- Test coverage is concentrated in two packages. `maze-guard` (279 tests) and
  `maze-cloak` (48) are well covered and run with `./venv/bin/python -m unittest
  discover -s tests`; `haze`, `hazedrop`, `qlam`, `sentinai`, `linux-chan-ai`
  and `maze-tools` have none. The two that matter most are `haze` and
  `hazedrop` — both do their own cryptography — and `maze-tools`, whose
  743-line `maze-doctor` is what users run to decide whether to trust their
  own system.
- Nothing runs the tests automatically. The two `lint.yml` workflows are
  static-only, and the one in `maze-secureboot` sits in a directory with no git
  repository, so it has never executed at all.

## [2026.06.26] — Initial public release

First public release of Maze Linux. See [`README.md`](../README.md) and
[`FEATURES.md`](FEATURES.md) for what shipped.
