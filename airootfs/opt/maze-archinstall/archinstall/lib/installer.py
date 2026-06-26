import os
import platform
import re
import shlex
import shutil
import subprocess
import textwrap
import time
from collections.abc import Callable
from pathlib import Path
from subprocess import CalledProcessError
from types import TracebackType
from typing import Any, Self

from archinstall.lib.boot import Boot
from archinstall.lib.bootloader.utils import validate_bootloader_layout
from archinstall.lib.command import SysCommand, run
from archinstall.lib.disk.fido import Fido2
from archinstall.lib.disk.luks import Luks2, unlock_luks2_dev
from archinstall.lib.disk.lvm import lvm_import_vg, lvm_pvseg_info, lvm_vol_change
from archinstall.lib.disk.utils import (
	get_lsblk_by_mountpoint,
	get_lsblk_info,
	get_parent_device_path,
	get_unique_path_for_device,
	mount,
	swapon,
)
from archinstall.lib.exceptions import DiskError, HardwareIncompatibilityError, RequirementError, ServiceException, SysCallError
from archinstall.lib.hardware import SysInfo
from archinstall.lib.linux_path import LPath
from archinstall.lib.locale.utils import verify_keyboard_layout, verify_x11_keyboard_layout
from archinstall.lib.log import debug, error, info, log, logger, warn
from archinstall.lib.mirror.mirror_handler import MirrorListHandler
from archinstall.lib.models.application import ZramAlgorithm
from archinstall.lib.models.bootloader import Bootloader, BootloaderConfiguration, PlymouthTheme
from archinstall.lib.models.device import (
	DiskEncryption,
	DiskLayoutConfiguration,
	EncryptionType,
	FilesystemType,
	LvmVolume,
	PartitionModification,
	SectorSize,
	Size,
	SnapshotType,
	SubvolumeModification,
	Unit,
)
from archinstall.lib.models.locale import LocaleConfiguration
from archinstall.lib.models.mirrors import MirrorConfiguration
from archinstall.lib.models.network import Nic
from archinstall.lib.models.package_types import DEFAULT_KERNEL, Kernel
from archinstall.lib.models.packages import Repository
from archinstall.lib.models.pacman import PacmanConfiguration
from archinstall.lib.models.users import User
from archinstall.lib.packages.packages import installed_package
from archinstall.lib.pacman.config import PacmanConfig
from archinstall.lib.pacman.pacman import Pacman
from archinstall.lib.pathnames import MIRRORLIST, PACMAN_CONF
from archinstall.lib.plugins import plugins
from archinstall.lib.translationhandler import tr

# Any package that the Installer() is responsible for (optional and the default ones)
# https://github.com/archlinux/archinstall/issues/4368
# mkinitcpio is listed explicitly so pacstrap installs it deterministically. Otherwise
# pacman picks the first initramfs provider from the host's pacman.conf, which on non-Arch
# hosts (EndeavourOS prefers dracut, etc.) breaks the installer's mkinitcpio() and
# _config_uki() methods that assume mkinitcpio is present in the chroot.
__packages__ = ['base', 'sudo', 'linux-firmware', 'mkinitcpio'] + [k.value for k in Kernel]

# Additional packages that are installed if the user is running the Live ISO with accessibility tools enabled
__accessibility_packages__ = ['brltty', 'espeakup', 'alsa-utils']


# Maze Linux Secure Boot: the on-disk signer run once at install time and then by
# the pacman hook below. It (re)signs the shim second stage and EVERY boot kernel
# artifact with the per-machine MOK key and restores the Microsoft-signed shim as
# the default loader, so the system keeps booting with UEFI Secure Boot enabled
# regardless of layout: unified kernel images OR separate kernel+initramfs (BLS),
# one OR several kernels (linux, linux-lts, ...), ESP == boot OR a separate boot
# partition.
MAZE_SB_SIGN_SCRIPT = r"""#!/bin/sh
# Managed by Maze Linux. (Re)signs every boot artifact the firmware/shim may
# chainload with the per-machine Secure Boot (MOK) key:
#   * shim second stage (systemd-boot, signed as grubx64.efi)
#   * unified kernel images:        <ESP|BOOT>/EFI/Linux/*.efi
#   * separate kernels (non-UKI):   <ESP|BOOT>/vmlinuz-*
# Idempotent and layout-agnostic (UKI or not, one or many kernels, ESP==boot or
# a separate boot partition). Safe to run repeatedly.
#
# Usage: maze-sb-sign [ESP_MOUNTPOINT]
#   The installer passes the ESP path explicitly (bootctl is unreliable inside
#   the install chroot). The pacman hook runs it with no argument and autodetects
#   (reliable on the booted system).
set -eu

KEYDIR=/var/lib/maze-secureboot
KEY="$KEYDIR/MOK.key"
CRT="$KEYDIR/MOK.crt"
CER="$KEYDIR/MOK.cer"

[ -r "$KEY" ] && [ -r "$CRT" ] || { echo "maze-sb-sign: no MOK key, skipping" >&2; exit 0; }

# --- arguments --------------------------------------------------------------
#   [ESP_MOUNTPOINT]      explicit ESP path (installer passes it; bootctl is
#                         unreliable inside the install chroot)
#   --force-bootloader    re-sign grubx64.efi (systemd-boot) even if it already
#                         verifies. Used by the pacman hook / installer where the
#                         systemd-boot binary may have changed. Routine callers
#                         (path-unit, boot self-heal) omit it so an already-valid
#                         grubx64 is left untouched -> zero writes when nothing
#                         changed, which is what makes frequent runs harmless.
ESP=""
force_bootloader=0
for arg in "$@"; do
    case "$arg" in
        --force-bootloader) force_bootloader=1 ;;
        *) ESP="$arg" ;;
    esac
done

# --- locate the EFI system partition (where shim/grubx64 live) --------------
if [ -z "$ESP" ]; then
    ESP="$(bootctl --print-esp-path 2>/dev/null || true)"
    [ -n "${ESP:-}" ] && [ -d "$ESP" ] || ESP=/efi
    [ -d "$ESP" ] || ESP=/boot
fi
if [ ! -d "$ESP" ]; then
    echo "maze-sb-sign: ESP path '$ESP' does not exist" >&2
    exit 1
fi

status_ok=1

# install_if_diff <src> <dst>: copy only when the destination differs, so a run
# where nothing changed touches the FAT ESP zero times (no needless flash writes).
install_if_diff() {
    [ -f "$1" ] || return 0
    cmp -s "$1" "$2" 2>/dev/null && return 0
    install -m644 "$1" "$2"
}

# sign_inplace <file>: sign in place if present and not already validly signed.
# A kernel/UKI that is already signed with our key is left untouched (idempotent).
sign_inplace() {
    f="$1"
    [ -e "$f" ] || return 0
    if sbverify --cert "$CRT" "$f" >/dev/null 2>&1; then
        echo "maze-sb-sign: OK     $f"
        return 0
    fi
    if sbsign --key "$KEY" --cert "$CRT" --output "$f.maze-signed" "$f" 2>/dev/null; then
        mv -f "$f.maze-signed" "$f"
        echo "maze-sb-sign: SIGNED $f"
    else
        rm -f "$f.maze-signed"
        echo "maze-sb-sign: FAIL   $f" >&2
        status_ok=0
    fi
}

# --- default loader: shim + MokManager + certificate (shim is never re-signed,
# only placed; install_if_diff keeps it a no-op once in place).
BOOTDIR="$ESP/EFI/BOOT"
mkdir -p "$BOOTDIR"
install_if_diff "$KEYDIR/shimx64.efi" "$BOOTDIR/BOOTX64.EFI"
install_if_diff "$KEYDIR/mmx64.efi"   "$BOOTDIR/mmx64.efi"
install_if_diff "$CER"                "$ESP/MOK.cer"

# --- second stage: systemd-boot signed as grubx64.efi. Re-signed from the fresh
# package binary only when forced (systemd-boot may have changed) or when the
# current grubx64 does not validate; otherwise left untouched (idempotent).
SDBOOT=/usr/lib/systemd/boot/efi/systemd-bootx64.efi
GRUB="$BOOTDIR/grubx64.efi"
if [ -f "$SDBOOT" ]; then
    if [ "$force_bootloader" = 0 ] && sbverify --cert "$CRT" "$GRUB" >/dev/null 2>&1; then
        echo "maze-sb-sign: OK     $GRUB"
    elif sbsign --key "$KEY" --cert "$CRT" --output "$GRUB" "$SDBOOT"; then
        echo "maze-sb-sign: SIGNED $GRUB"
    else
        echo "maze-sb-sign: FAIL   $GRUB" >&2
        status_ok=0
    fi
fi

# --- kernels: UKIs and separate vmlinuz across the ESP and the boot partition.
# Build a de-duplicated list of candidate directories (ESP, bootctl's boot path,
# and the usual /boot and /efi) and sign every kernel image found in each.
boot_path="$(bootctl --print-boot-path 2>/dev/null || true)"
dirs="$ESP"
for d in "$boot_path" /boot /efi; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    case " $dirs " in *" $d "*) ;; *) dirs="$dirs $d" ;; esac
done

for d in $dirs; do
    for f in "$d"/EFI/Linux/*.efi "$d"/vmlinuz-*; do
        sign_inplace "$f"
    done
done

if [ "$status_ok" = 1 ]; then
    echo "maze-sb-sign: signed all boot artifacts (ESP=$ESP)"
else
    echo "maze-sb-sign: WARNING - some boot files are NOT validly signed (ESP=$ESP)" >&2
    exit 1
fi
"""

# Triggers a re-sign after ANYTHING that can regenerate the kernel, initramfs/UKI
# or the systemd-boot binary — otherwise a freshly regenerated but unsigned UKI
# makes Secure Boot fail at the next boot ("Security violation"), and that would
# recur on every update. Runs after mkinitcpio's own hooks (95 > 90) so the UKIs
# already exist when we sign them.
#
# Two trigger groups (the hook fires if EITHER matches; the signer is idempotent
# — it sbverify's before sbsign'ing, so an extra fire is a cheap no-op):
#   * Path   — the package files that drive a UKI/initramfs/bootloader rebuild
#              (kernel image, systemd-boot binary, legacy initramfs/vmlinuz).
#   * Package — packages whose upgrade rebuilds the initramfs/UKI WITHOUT touching
#              one of those paths in the transaction: out-of-tree drivers rebuilt
#              by DKMS (nvidia in MODULES=() → the UKI changes) and the initramfs
#              generator / bootloader packages themselves.
MAZE_SB_PACMAN_HOOK = """[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/vmlinuz
Target = usr/lib/systemd/boot/efi/*
Target = boot/vmlinuz-*
Target = boot/initramfs-*.img

[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = nvidia
Target = nvidia-dkms
Target = nvidia-open
Target = nvidia-open-dkms
Target = nvidia-lts
Target = nvidia-utils
Target = dkms
Target = mkinitcpio
Target = systemd

[Action]
Description = Signing bootloader and kernels for Secure Boot (Maze)...
When = PostTransaction
Exec = /usr/local/bin/maze-sb-sign --force-bootloader
"""

# The pacman hook covers package-driven UKI rebuilds, but a user who runs
# `mkinitcpio -P` BY HAND (outside any pacman transaction) would otherwise be
# left with a freshly regenerated, unsigned UKI -> "Verification failed" at the
# next boot. mkinitcpio has no native post-build hook, so we watch the unified
# kernel image directory with a systemd .path unit and re-sign on any change.
#
# Covers BOTH layouts:
#   * UKI on  -> the signed artifact is the UKI in EFI/Linux/*.efi (initramfs is
#     embedded, so a rebuild MUST be re-signed).
#   * UKI off -> the signed artifact is vmlinuz-* directly in the boot dir
#     (systemd-boot validates it via shim; the separate initramfs is NOT
#     secure-boot-validated, so the signer never touches it).
# We therefore watch the EFI/Linux UKI dirs AND the boot dir itself.
#
# Loop-safety (inotify is NOT recursive): routine runs leave already-signed
# UKIs/vmlinuz untouched (sbverify passes -> no rewrite) and never rewrite the
# initramfs or grubx64.efi (grubx64 is only re-signed with --force, not on these
# triggers), so the signer's own writes settle after a single extra pass.
MAZE_SB_RESIGN_SERVICE = """[Unit]
Description=Re-sign bootloader and kernels for Secure Boot (Maze)
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/maze-sb-sign

[Install]
WantedBy=multi-user.target
"""

MAZE_SB_RESIGN_PATH = """[Unit]
Description=Watch for regenerated unified kernel images and re-sign them (Maze Secure Boot)

[Path]
# UKI dirs (ESP at /efi, or ESP/XBOOTLDR at /boot) for the UKI layout, plus the
# boot dir itself for the non-UKI layout (vmlinuz-* lives directly there). A path
# that does not exist yet is simply watched for creation. Directory watches are
# non-recursive on purpose (see above).
PathChanged=/efi/EFI/Linux
PathChanged=/boot/EFI/Linux
PathChanged=/boot
Unit=maze-sb-resign.service

[Install]
WantedBy=paths.target
"""

MAZE_SB_ENROLLMENT_NOTE = """Maze Linux — Secure Boot key enrollment
========================================

This machine boots with UEFI Secure Boot using a Microsoft-signed shim plus a
key unique to this computer. The key's certificate must be enrolled once. There
is NO password to remember — enrollment requires physical presence at this
machine instead (you confirm it at the firmware-level menu on the next boot).

On the FIRST reboot the boot loader is not trusted yet, so a blue "Verification
failed" / "MOK Management" (MokManager) screen appears. Do this once:

  1. Choose "Enroll key from disk"
  2. Select the EFI system partition volume, then the file:  MOK.cer
  3. Confirm / "Continue", then "Yes" to enroll
  4. Reboot

After that the system boots normally with Secure Boot enabled. Existing
factory/Windows keys are left untouched, and kernel updates are re-signed
automatically.

The certificate to enroll lives at:  /var/lib/maze-secureboot/MOK.cer
(also copied to the root of the EFI system partition as /MOK.cer).
To check status afterwards:  mokutil --sb-state
"""


class Installer:
	def __init__(
		self,
		target: Path,
		disk_config: DiskLayoutConfiguration,
		base_packages: list[str] = [],
		kernels: list[str] | None = None,
		silent: bool = False,
	):
		"""
		`Installer()` is the wrapper for most basic installation steps.
		It also wraps :py:func:`~archinstall.Installer.pacstrap` among other things.
		"""
		self._base_packages = base_packages or __packages__[:4]
		self.kernels = kernels or [DEFAULT_KERNEL.value]
		self._disk_config = disk_config

		self._disk_encryption = disk_config.disk_encryption or DiskEncryption(EncryptionType.NO_ENCRYPTION)
		self.target: Path = target

		self.init_time = time.strftime('%Y-%m-%d_%H-%M-%S')
		self._helper_flags: dict[str, str | bool | None] = {
			'base': False,
			'bootloader': None,
		}

		for kernel in self.kernels:
			self._base_packages.append(kernel)

		# If using accessibility tools in the live environment, append those to the packages list
		if accessibility_tools_in_use():
			self._base_packages.extend(__accessibility_packages__)

		self.post_base_install: list[Callable] = []  # type: ignore[type-arg]

		self._modules: list[str] = []
		self._binaries: list[str] = []
		self._files: list[str] = []

		# systemd, sd-vconsole and sd-encrypt will be replaced by udev, keymap and encrypt
		# if HSM is not used to encrypt the root volume. Check mkinitcpio() function for that override.
		self._hooks: list[str] = [
			'base',
			'systemd',
			'autodetect',
			'microcode',
			'modconf',
			'kms',
			'keyboard',
			'sd-vconsole',
			'block',
			'filesystems',
			'fsck',
		]
		self._kernel_params: list[str] = []
		self._fstab_entries: list[str] = []

		self._zram_enabled = False
		self._disable_fstrim = False

		self.pacman = Pacman(self.target, silent)

	def __enter__(self) -> Self:
		return self

	def __exit__(self, exc_type: type[BaseException] | None, exc_value: BaseException | None, traceback: TracebackType | None) -> bool | None:
		if exc_type is not None:
			error(str(exc_value))

			self.sync_log_to_install_medium()

			# We avoid printing /mnt/<log path> because that might confuse people if they note it down
			# and then reboot, and an identical log file will be found in the ISO medium anyway.
			print(tr('[!] A log file has been created here: {}').format(logger.path))
			print(tr('Please submit this issue (and file) to https://github.com/archlinux/archinstall/issues'))

			# Return None to propagate the exception
			return None

		info(tr('Syncing the system...'))
		os.sync()

		if not (missing_steps := self.post_install_check()):
			msg = f'Installation completed without any errors.\nLog files temporarily available at {logger.directory}.\nYou may reboot when ready.\n'
			log(msg, fg='green')
			self.sync_log_to_install_medium()
			return True
		else:
			warn('Some required steps were not successfully installed/configured before leaving the installer:')

			for step in missing_steps:
				warn(f' - {step}')

			warn(f'Detailed error logs can be found at: {logger.directory}')
			warn('Submit this zip file as an issue to https://github.com/archlinux/archinstall/issues')

			self.sync_log_to_install_medium()
			return False

	def remove_mod(self, mod: str) -> None:
		if mod in self._modules:
			self._modules.remove(mod)

	def append_mod(self, mod: str) -> None:
		if mod not in self._modules:
			self._modules.append(mod)

	def _verify_service_stop(self, offline: bool, skip_ntp: bool, skip_wkd: bool) -> None:
		"""
		Certain services might be running that affects the system during installation.
		One such service is "reflector.service" which updates /etc/pacman.d/mirrorlist
		We need to wait for it before we continue since we opted in to use a custom mirror/region.
		"""

		if not skip_ntp:
			info(tr('Waiting for time sync (timedatectl show) to complete.'))

			# Maze Linux: cap this wait. The upstream loop was unbounded and would
			# sit here for minutes (looking frozen, with no network activity of its
			# own) whenever timesyncd never reports "synchronized" — common in VMs
			# or when NTP is blocked. 20s is plenty when it does sync; otherwise we
			# continue rather than hang the whole install.
			started_wait = time.monotonic()
			while time.monotonic() - started_wait < 20:
				time_val = SysCommand('timedatectl show --property=NTPSynchronized --value').decode()
				if time_val and time_val.strip() == 'yes':
					break
				time.sleep(1)
			else:
				warn('Time sync did not complete within 20 seconds, continuing anyway...')
		else:
			info(tr('Skipping waiting for automatic time sync (this can cause issues if time is out of sync during installation)'))

		if not offline:
			info('Waiting for automatic mirror selection (reflector) to complete.')
			for _ in range(20):
				if self._service_state('reflector') in ('dead', 'failed', 'exited'):
					break
				time.sleep(1)
			else:
				warn('Reflector did not complete within 20 seconds, continuing anyway...')
		else:
			info('Skipped reflector...')

		# info('Waiting for pacman-init.service to complete.')
		# while self._service_state('pacman-init') not in ('dead', 'failed', 'exited'):
		# time.sleep(1)

		if not skip_wkd:
			info(tr('Waiting for Arch Linux keyring sync (archlinux-keyring-wkd-sync) to complete.'))
			# Maze Linux: both of these loops were unbounded upstream and were a
			# prime suspect for the multi-minute "it just sits there" stall — the
			# WKD keyring sync can take ages (or never finish on a blocked
			# network), and the installer would simply poll it forever. Cap the
			# total wait and move on; pacman will reinit the keyring if needed.
			started_wait = time.monotonic()
			# Wait for the timer to kick in (max 10s).
			while self._service_started('archlinux-keyring-wkd-sync.timer') is None:
				if time.monotonic() - started_wait > 10:
					break
				time.sleep(1)

			# Wait for the service to enter a finished state (max 30s total).
			while self._service_state('archlinux-keyring-wkd-sync.service') not in ('dead', 'failed', 'exited'):
				if time.monotonic() - started_wait > 30:
					warn('Keyring sync did not complete within 30 seconds, continuing anyway...')
					break
				time.sleep(1)

			if self._service_state('archlinux-keyring-wkd-sync.service') == 'failed':
				warn('archlinux-keyring-wkd-sync failed, keyring may need reinit during pacman sync')

	def _verify_boot_part(self) -> None:
		"""
		Check that mounted /boot device has at minimum size for installation
		The reason this check is here is to catch pre-mounted device configuration and potentially
		configured one that has not gone through any previous checks (e.g. --silence mode)

		NOTE: this function should be run AFTER running the mount_ordered_layout function
		"""
		boot_mount = self.target / 'boot'
		lsblk_info = get_lsblk_by_mountpoint(boot_mount)

		if len(lsblk_info) > 0:
			if lsblk_info[0].size < Size(200, Unit.MiB, SectorSize.default()):
				raise DiskError(
					f'The boot partition mounted at {boot_mount} is not large enough to install a boot loader. '
					f'Please resize it to at least 200MiB and re-run the installation.',
				)

	def sanity_check(
		self,
		offline: bool = False,
		skip_ntp: bool = False,
		skip_wkd: bool = False,
	) -> None:
		# self._verify_boot_part()
		self._verify_service_stop(offline, skip_ntp, skip_wkd)

	def mount_ordered_layout(self) -> None:
		debug('Mounting ordered layout')

		luks_handlers: dict[Any, Luks2] = {}

		match self._disk_encryption.encryption_type:
			case EncryptionType.NO_ENCRYPTION:
				self._import_lvm()
				self._mount_lvm_layout()
			case EncryptionType.LUKS:
				luks_handlers = self._prepare_luks_partitions(self._disk_encryption.partitions)
			case EncryptionType.LVM_ON_LUKS:
				luks_handlers = self._prepare_luks_partitions(self._disk_encryption.partitions)
				self._import_lvm()
				self._mount_lvm_layout(luks_handlers)
			case EncryptionType.LUKS_ON_LVM:
				self._import_lvm()
				luks_handlers = self._prepare_luks_lvm(self._disk_encryption.lvm_volumes)
				self._mount_lvm_layout(luks_handlers)

		# mount all regular partitions
		self._mount_partition_layout(luks_handlers)

	def _mount_partition_layout(self, luks_handlers: dict[Any, Luks2]) -> None:
		debug('Mounting partition layout')

		# do not mount any PVs part of the LVM configuration
		pvs = []
		if self._disk_config.lvm_config:
			pvs = self._disk_config.lvm_config.get_all_pvs()

		sorted_device_mods = self._disk_config.device_modifications.copy()

		# move the device with the root partition to the beginning of the list
		for mod in self._disk_config.device_modifications:
			if any(partition.is_root() for partition in mod.partitions):
				sorted_device_mods.remove(mod)
				sorted_device_mods.insert(0, mod)
				break

		for mod in sorted_device_mods:
			not_pv_part_mods = [p for p in mod.partitions if p not in pvs]

			# partitions have to mounted in the right order on btrfs the mountpoint will
			# be empty as the actual subvolumes are getting mounted instead so we'll use
			# '/' just for sorting
			sorted_part_mods = sorted(not_pv_part_mods, key=lambda x: x.mountpoint or Path('/'))

			for part_mod in sorted_part_mods:
				if luks_handler := luks_handlers.get(part_mod):
					self._mount_luks_partition(part_mod, luks_handler)
				else:
					self._mount_partition(part_mod)

	def _mount_lvm_layout(self, luks_handlers: dict[Any, Luks2] = {}) -> None:
		lvm_config = self._disk_config.lvm_config

		if not lvm_config:
			debug('No lvm config defined to be mounted')
			return

		debug('Mounting LVM layout')

		for vg in lvm_config.vol_groups:
			sorted_vol = sorted(vg.volumes, key=lambda x: x.mountpoint or Path('/'))

			for vol in sorted_vol:
				if luks_handler := luks_handlers.get(vol):
					self._mount_luks_volume(vol, luks_handler)
				else:
					self._mount_lvm_vol(vol)

	def _prepare_luks_partitions(
		self,
		partitions: list[PartitionModification],
	) -> dict[PartitionModification, Luks2]:
		return {
			part_mod: unlock_luks2_dev(
				part_mod.dev_path,
				part_mod.mapper_name,
				self._disk_encryption.encryption_password,
			)
			for part_mod in partitions
			if part_mod.mapper_name and part_mod.dev_path
		}

	def _import_lvm(self) -> None:
		lvm_config = self._disk_config.lvm_config

		if not lvm_config:
			debug('No lvm config defined to be imported')
			return

		for vg in lvm_config.vol_groups:
			lvm_import_vg(vg)

			for vol in vg.volumes:
				lvm_vol_change(vol, True)

	def _prepare_luks_lvm(
		self,
		lvm_volumes: list[LvmVolume],
	) -> dict[LvmVolume, Luks2]:
		return {
			vol: unlock_luks2_dev(
				vol.dev_path,
				vol.mapper_name,
				self._disk_encryption.encryption_password,
			)
			for vol in lvm_volumes
			if vol.mapper_name and vol.dev_path
		}

	def _mount_partition(self, part_mod: PartitionModification) -> None:
		if not part_mod.dev_path:
			return

		# it would be none if it's btrfs as the subvolumes will have the mountpoints defined
		if part_mod.mountpoint:
			target = self.target / part_mod.relative_mountpoint
			options = part_mod.mount_options

			if part_mod.is_efi():
				options = list(dict.fromkeys(options + ['fmask=0077', 'dmask=0077']))

			mount(part_mod.dev_path, target, options=options)
		elif part_mod.fs_type == FilesystemType.BTRFS:
			# Only mount BTRFS subvolumes that have mountpoints specified
			subvols_with_mountpoints = [sv for sv in part_mod.btrfs_subvols if sv.mountpoint is not None]
			if subvols_with_mountpoints:
				self._mount_btrfs_subvol(
					part_mod.dev_path,
					part_mod.btrfs_subvols,
					part_mod.mount_options,
				)
		elif part_mod.is_swap():
			swapon(part_mod.dev_path)

	def _mount_lvm_vol(self, volume: LvmVolume) -> None:
		if volume.fs_type != FilesystemType.BTRFS:
			if volume.mountpoint and volume.dev_path:
				target = self.target / volume.relative_mountpoint
				mount(volume.dev_path, target, options=volume.mount_options)

		if volume.fs_type == FilesystemType.BTRFS and volume.dev_path:
			# Only mount BTRFS subvolumes that have mountpoints specified
			subvols_with_mountpoints = [sv for sv in volume.btrfs_subvols if sv.mountpoint is not None]
			if subvols_with_mountpoints:
				self._mount_btrfs_subvol(volume.dev_path, volume.btrfs_subvols, volume.mount_options)

	def _mount_luks_partition(self, part_mod: PartitionModification, luks_handler: Luks2) -> None:
		if not luks_handler.mapper_dev:
			return

		if part_mod.fs_type == FilesystemType.BTRFS and part_mod.btrfs_subvols:
			# Only mount BTRFS subvolumes that have mountpoints specified
			subvols_with_mountpoints = [sv for sv in part_mod.btrfs_subvols if sv.mountpoint is not None]
			if subvols_with_mountpoints:
				self._mount_btrfs_subvol(luks_handler.mapper_dev, part_mod.btrfs_subvols, part_mod.mount_options)
		elif part_mod.mountpoint:
			target = self.target / part_mod.relative_mountpoint
			mount(luks_handler.mapper_dev, target, options=part_mod.mount_options)

	def _mount_luks_volume(self, volume: LvmVolume, luks_handler: Luks2) -> None:
		if volume.fs_type != FilesystemType.BTRFS:
			if volume.mountpoint and luks_handler.mapper_dev:
				target = self.target / volume.relative_mountpoint
				mount(luks_handler.mapper_dev, target, options=volume.mount_options)

		if volume.fs_type == FilesystemType.BTRFS and luks_handler.mapper_dev:
			# Only mount BTRFS subvolumes that have mountpoints specified
			subvols_with_mountpoints = [sv for sv in volume.btrfs_subvols if sv.mountpoint is not None]
			if subvols_with_mountpoints:
				self._mount_btrfs_subvol(luks_handler.mapper_dev, volume.btrfs_subvols, volume.mount_options)

	def _mount_btrfs_subvol(
		self,
		dev_path: Path,
		subvolumes: list[SubvolumeModification],
		mount_options: list[str] = [],
	) -> None:
		# Filter out subvolumes without mountpoints to avoid errors when sorting
		subvols_with_mountpoints = [sv for sv in subvolumes if sv.mountpoint is not None]
		for subvol in sorted(subvols_with_mountpoints, key=lambda x: x.relative_mountpoint):
			mountpoint = self.target / subvol.relative_mountpoint
			options = mount_options + [f'subvol={subvol.name}']
			mount(dev_path, mountpoint, options=options)

	def generate_key_files(self) -> None:
		match self._disk_encryption.encryption_type:
			case EncryptionType.LUKS:
				self._generate_key_files_partitions()
			case EncryptionType.LUKS_ON_LVM:
				self._generate_key_file_lvm_volumes()
			case EncryptionType.LVM_ON_LUKS:
				# currently LvmOnLuks only supports a single
				# partitioning layout (boot + partition)
				# so we won't need any keyfile generation atm
				pass

	def _generate_key_files_partitions(self) -> None:
		root_is_encrypted = any(p.is_root() for p in self._disk_encryption.partitions)

		for part_mod in self._disk_encryption.partitions:
			gen_enc_file = self._disk_encryption.should_generate_encryption_file(part_mod)

			luks_handler = Luks2(
				part_mod.safe_dev_path,
				mapper_name=part_mod.mapper_name,
				password=self._disk_encryption.encryption_password,
			)

			if gen_enc_file and not part_mod.is_root():
				if root_is_encrypted:
					debug(f'Creating key-file: {part_mod.dev_path}')
					luks_handler.create_keyfile(self.target)
				else:
					debug(f'Adding passphrase-based crypttab entry for {part_mod.dev_path}')
					luks_handler.create_crypttab_entry(self.target)

			if part_mod.is_root() and not gen_enc_file:
				if self._disk_encryption.hsm_device:
					if self._disk_encryption.encryption_password:
						Fido2.fido2_enroll(
							self._disk_encryption.hsm_device,
							part_mod.safe_dev_path,
							self._disk_encryption.encryption_password,
						)

	def _generate_key_file_lvm_volumes(self) -> None:
		root_is_encrypted = any(v.is_root() for v in self._disk_encryption.lvm_volumes)

		for vol in self._disk_encryption.lvm_volumes:
			gen_enc_file = self._disk_encryption.should_generate_encryption_file(vol)

			luks_handler = Luks2(
				vol.safe_dev_path,
				mapper_name=vol.mapper_name,
				password=self._disk_encryption.encryption_password,
			)

			if gen_enc_file and not vol.is_root():
				if root_is_encrypted:
					info(f'Creating key-file: {vol.dev_path}')
					luks_handler.create_keyfile(self.target)
				else:
					info(f'Adding passphrase-based crypttab entry for {vol.dev_path}')
					luks_handler.create_crypttab_entry(self.target)

			if vol.is_root() and not gen_enc_file:
				if self._disk_encryption.hsm_device:
					if self._disk_encryption.encryption_password:
						Fido2.fido2_enroll(
							self._disk_encryption.hsm_device,
							vol.safe_dev_path,
							self._disk_encryption.encryption_password,
						)

	def sync_log_to_install_medium(self) -> bool:
		# Copy over the install log (if there is one) to the install medium if
		# at least the base has been strapped in, otherwise we won't have a filesystem/structure to copy to.
		if self._helper_flags.get('base-strapped', False) is True:
			logfile_target = self.target / LPath(logger.directory).relative_to_root()
			logfile_target.mkdir(parents=True, exist_ok=True)
			logger.path.copy_into(logfile_target, preserve_metadata=True)

		return True

	def add_swapfile(self, size: str = '4G', enable_resume: bool = True, file: str = '/swapfile') -> None:
		if file[:1] != '/':
			file = f'/{file}'
		if len(file.strip()) <= 0 or file == '/':
			raise ValueError(f'The filename for the swap file has to be a valid path, not: {self.target}{file}')

		SysCommand(f'dd if=/dev/zero of={self.target}{file} bs={size} count=1')
		SysCommand(f'chmod 0600 {self.target}{file}')
		SysCommand(f'mkswap {self.target}{file}')

		self._fstab_entries.append(f'{file} none swap defaults 0 0')

		if enable_resume:
			resume_uuid = SysCommand(f'findmnt -no UUID -T {self.target}{file}').decode()
			resume_offset = (
				SysCommand(
					f'filefrag -v {self.target}{file}',
				)
				.decode()
				.split('0:', 1)[1]
				.split(':', 1)[1]
				.split('..', 1)[0]
				.strip()
			)

			self._hooks.append('resume')
			self._kernel_params.append(f'resume=UUID={resume_uuid}')
			self._kernel_params.append(f'resume_offset={resume_offset}')

	def post_install_check(self, *args: str, **kwargs: str) -> list[str]:
		return [step for step, flag in self._helper_flags.items() if flag is False]

	def set_mirrors(
		self,
		mirror_list_handler: MirrorListHandler,
		mirror_config: MirrorConfiguration,
		on_target: bool = False,
	) -> None:
		"""
		Set the mirror configuration for the installation.

		:param mirror_config: The mirror configuration to use.
		:type mirror_config: MirrorConfiguration

		:on_target: Whether to set the mirrors on the target system or the live system.
		:param on_target: bool
		"""
		debug('Setting mirrors on ' + ('target' if on_target else 'live system'))

		for plugin in plugins.values():
			if hasattr(plugin, 'on_mirrors'):
				if result := plugin.on_mirrors(mirror_config):
					mirror_config = result

		if on_target:
			mirrorlist_config = self.target / MIRRORLIST.relative_to_root()
			pacman_config = self.target / PACMAN_CONF.relative_to_root()
		else:
			mirrorlist_config = MIRRORLIST
			pacman_config = PACMAN_CONF

		repositories_config = mirror_config.repositories_config()
		if repositories_config:
			debug(f'Pacman config: {repositories_config}')

			with open(pacman_config, 'a') as fp:
				fp.write(repositories_config)

		regions_config = mirror_config.regions_config(mirror_list_handler, speed_sort=True)
		if regions_config:
			debug(f'Mirrorlist:\n{regions_config}')
			mirrorlist_config.write_text(regions_config)

		custom_servers = mirror_config.custom_servers_config()
		if custom_servers:
			debug(f'Custom servers:\n{custom_servers}')

			content = mirrorlist_config.read_text()
			mirrorlist_config.write_text(f'{custom_servers}\n\n{content}')

	def genfstab(self, flags: str = '-pU') -> None:
		fstab_path = self.target / 'etc' / 'fstab'
		info(f'Updating {fstab_path}')

		try:
			gen_fstab = SysCommand(f'genfstab {flags} -f {self.target} {self.target}').output()
		except SysCallError as err:
			raise RequirementError(f'Could not generate fstab, strapping in packages most likely failed (disk out of space?)\n Error: {err}')

		with open(fstab_path, 'ab') as fp:
			fp.write(gen_fstab)

		if not fstab_path.is_file():
			raise RequirementError('Could not create fstab file')

		for plugin in plugins.values():
			if hasattr(plugin, 'on_genfstab'):
				if plugin.on_genfstab(self) is True:
					break

		with open(fstab_path, 'a') as fp:
			for entry in self._fstab_entries:
				fp.write(f'{entry}\n')

	def set_hostname(self, hostname: str) -> None:
		(self.target / 'etc/hostname').write_text(hostname + '\n')

	def set_locale(self, locale_config: LocaleConfiguration) -> bool:
		modifier = ''
		lang = locale_config.sys_lang
		encoding = locale_config.sys_enc

		# This is a temporary patch to fix #1200
		if '.' in locale_config.sys_lang:
			lang, potential_encoding = locale_config.sys_lang.split('.', 1)

			# Override encoding if encoding is set to the default parameter
			# and the "found" encoding differs.
			if locale_config.sys_enc == 'UTF-8' and locale_config.sys_enc != potential_encoding:
				encoding = potential_encoding

		# Make sure we extract the modifier, that way we can put it in if needed.
		if '@' in locale_config.sys_lang:
			lang, modifier = locale_config.sys_lang.split('@', 1)
			modifier = f'@{modifier}'
		# - End patch

		locale_gen = self.target / 'etc/locale.gen'
		locale_gen_lines = locale_gen.read_text().splitlines(True)

		# A locale entry in /etc/locale.gen may or may not contain the encoding
		# in the first column of the entry; check for both cases.
		entry_re = re.compile(rf'#{lang}(\.{encoding})?{modifier} {encoding}')

		lang_value = None
		for index, line in enumerate(locale_gen_lines):
			if entry_re.match(line):
				uncommented_line = line.removeprefix('#')
				locale_gen_lines[index] = uncommented_line
				locale_gen.write_text(''.join(locale_gen_lines))
				lang_value = uncommented_line.split()[0]
				break

		if lang_value is None:
			error(f"Invalid locale: language '{locale_config.sys_lang}', encoding '{locale_config.sys_enc}'")
			return False

		try:
			self.arch_chroot('locale-gen')
		except SysCallError as e:
			error(f'Failed to run locale-gen on target: {e}')
			return False

		(self.target / 'etc/locale.conf').write_text(f'LANG={lang_value}\n')
		return True

	def set_timezone(self, zone: str) -> bool:
		if not zone:
			return True
		if not len(zone):
			return True  # Redundant

		for plugin in plugins.values():
			if hasattr(plugin, 'on_timezone'):
				if result := plugin.on_timezone(zone):
					zone = result

		if (Path('/usr') / 'share' / 'zoneinfo' / zone).exists():
			(Path(self.target) / 'etc' / 'localtime').unlink(missing_ok=True)
			self.arch_chroot(f'ln -s /usr/share/zoneinfo/{zone} /etc/localtime')
			return True

		else:
			warn(f'Time zone {zone} does not exist, continuing with system default')

		return False

	def activate_time_synchronization(self) -> None:
		info('Activating systemd-timesyncd for time synchronization using Arch Linux and ntp.org NTP servers')
		self.enable_service('systemd-timesyncd')

	def enable_espeakup(self) -> None:
		info('Enabling espeakup.service for speech synthesis (accessibility)')
		self.enable_service('espeakup')

	def enable_periodic_trim(self) -> None:
		info('Enabling periodic TRIM')
		# fstrim is owned by util-linux, a dependency of both base and systemd.
		self.enable_service('fstrim.timer')

	def enable_service(self, services: str | list[str]) -> None:
		if isinstance(services, str):
			services = [services]

		for service in services:
			info(f'Enabling service {service}')

			try:
				SysCommand(f'systemctl --root={self.target} enable {service}')
			except SysCallError as err:
				raise ServiceException(f'Unable to start service {service}: {err}')

			for plugin in plugins.values():
				if hasattr(plugin, 'on_service'):
					plugin.on_service(service)

	def disable_service(self, services_disable: str | list[str]) -> None:
		if isinstance(services_disable, str):
			services_disable = [services_disable]

		for service in services_disable:
			info(f'Disabling service {service}')

			try:
				SysCommand(f'systemctl --root={self.target} disable {service}')
			except SysCallError as err:
				raise ServiceException(f'Unable to disable service {service}: {err}')

	def run_command(self, cmd: str, peek_output: bool = False) -> SysCommand:
		return SysCommand(f'arch-chroot -S {self.target} {cmd}', peek_output=peek_output)

	def arch_chroot(self, cmd: str, run_as: str | None = None, peek_output: bool = False) -> SysCommand:
		if run_as:
			cmd = f'su - {run_as} -c {shlex.quote(cmd)}'

		return self.run_command(cmd, peek_output=peek_output)

	def _chroot_argv(self, *args: str) -> list[str]:
		return ['arch-chroot', '-S', str(self.target), *args]

	def drop_to_shell(self) -> None:
		subprocess.check_call(f'arch-chroot {self.target}', shell=True)

	def configure_nic(self, nic: Nic) -> None:
		conf = nic.as_systemd_config()

		for plugin in plugins.values():
			if hasattr(plugin, 'on_configure_nic'):
				conf = (
					plugin.on_configure_nic(
						nic.iface,
						nic.dhcp,
						nic.ip,
						nic.gateway,
						nic.dns,
					)
					or conf
				)

		with open(f'{self.target}/etc/systemd/network/10-{nic.iface}.network', 'a') as netconf:
			netconf.write(str(conf))

	def copy_iso_network_config(self, enable_services: bool = False) -> bool:
		# Copy (if any) iwd password and config files
		iwd_dir = LPath('/var/lib/iwd')
		if psk_files := list(iwd_dir.glob('*.psk')):
			iwd_target = self.target / iwd_dir.relative_to_root()
			iwd_target.mkdir(parents=True, exist_ok=True)

			for psk in psk_files:
				psk.copy(iwd_target / psk.name, preserve_metadata=True)

			if enable_services:
				# If we haven't installed the base yet (function called pre-maturely)
				if self._helper_flags.get('base', False) is False:
					self._base_packages.append('iwd')

					# This function will be called after minimal_installation()
					# as a hook for post-installs. This hook is only needed if
					# base is not installed yet.
					def post_install_enable_iwd_service(*args: str, **kwargs: str) -> None:
						self.enable_service('iwd')

					self.post_base_install.append(post_install_enable_iwd_service)
				# Otherwise, we can go ahead and add the required package
				# and enable it's service:
				else:
					self.pacman.strap('iwd')
					self.enable_service('iwd')

		# Enable systemd-resolved by (forcefully) setting a symlink
		# For further details see  https://wiki.archlinux.org/title/Systemd-resolved#DNS
		resolv_config_path = self.target / 'etc/resolv.conf'
		resolv_config_path.unlink(missing_ok=True)
		resolv_config_path.symlink_to('/run/systemd/resolve/stub-resolv.conf')

		# Copy (if any) systemd-networkd config files
		network_dir = LPath('/etc/systemd/network')
		if netconfigurations := list(network_dir.glob('*')):
			network_target = self.target / network_dir.relative_to_root()
			network_target.mkdir(parents=True, exist_ok=True)

			for netconf_file in netconfigurations:
				netconf_file.copy(network_target / netconf_file.name, preserve_metadata=True)

			if enable_services:
				# If we haven't installed the base yet (function called pre-maturely)
				if self._helper_flags.get('base', False) is False:

					def post_install_enable_networkd_resolved(*args: str, **kwargs: str) -> None:
						self.enable_service(['systemd-networkd', 'systemd-resolved'])

					self.post_base_install.append(post_install_enable_networkd_resolved)
				# Otherwise, we can go ahead and enable the services
				else:
					self.enable_service(['systemd-networkd', 'systemd-resolved'])

		return True

	def mkinitcpio(self, flags: list[str]) -> bool:
		for plugin in plugins.values():
			if hasattr(plugin, 'on_mkinitcpio'):
				# Allow plugins to override the usage of mkinitcpio altogether.
				if plugin.on_mkinitcpio(self):
					return True

		with open(f'{self.target}/etc/mkinitcpio.conf', 'r+') as mkinit:
			content = mkinit.read()
			content = re.sub('\nMODULES=(.*)', f'\nMODULES=({" ".join(self._modules)})', content)
			content = re.sub('\nBINARIES=(.*)', f'\nBINARIES=({" ".join(self._binaries)})', content)
			content = re.sub('\nFILES=(.*)', f'\nFILES=({" ".join(self._files)})', content)

			if not self._disk_encryption.hsm_device:
				# For now, if we don't use HSM we revert to the old
				# way of setting up encryption hooks for mkinitcpio.
				# This is purely for stability reasons, we're going away from this.
				# * systemd -> udev
				# * sd-vconsole -> keymap
				self._hooks = [hook.replace('systemd', 'udev').replace('sd-vconsole', 'keymap consolefont') for hook in self._hooks]

			content = re.sub('\nHOOKS=(.*)', f'\nHOOKS=({" ".join(self._hooks)})', content)
			mkinit.seek(0)
			mkinit.truncate()
			mkinit.write(content)

		try:
			self.arch_chroot(f'mkinitcpio {" ".join(flags)}', peek_output=True)
			return True
		except SysCallError as e:
			if e.worker_log:
				log(e.worker_log.decode())
			return False

	def _get_microcode(self) -> Path | None:
		if not SysInfo.is_vm():
			if vendor := SysInfo.cpu_vendor():
				return vendor.get_ucode()
		return None

	def _prepare_fs_type(
		self,
		fs_type: FilesystemType,
		mountpoint: Path | None,
	) -> None:
		if (pkg := fs_type.installation_pkg) is not None:
			self._base_packages.append(pkg)

		# https://github.com/archlinux/archinstall/issues/1837
		if fs_type == FilesystemType.BTRFS:
			self._disable_fstrim = True

	def _prepare_encrypt(self, before: str = 'filesystems') -> None:
		if self._disk_encryption.hsm_device:
			# Required by mkinitcpio to add support for fido2-device options
			self.pacman.strap('libfido2')

			if 'sd-encrypt' not in self._hooks:
				self._hooks.insert(self._hooks.index(before), 'sd-encrypt')
		else:
			if 'encrypt' not in self._hooks:
				self._hooks.insert(self._hooks.index(before), 'encrypt')

	def minimal_installation(
		self,
		optional_repositories: list[Repository] = [],
		mkinitcpio: bool = True,
		hostname: str | None = None,
		locale_config: LocaleConfiguration | None = LocaleConfiguration.default(),
		pacman_config: PacmanConfiguration | None = None,
	) -> None:
		if self._disk_config.lvm_config:
			lvm = 'lvm2'
			self.add_additional_packages(lvm)
			self._hooks.insert(self._hooks.index('filesystems') - 1, lvm)

			for vg in self._disk_config.lvm_config.vol_groups:
				for vol in vg.volumes:
					if vol.fs_type is not None:
						self._prepare_fs_type(vol.fs_type, vol.mountpoint)

			types = (EncryptionType.LVM_ON_LUKS, EncryptionType.LUKS_ON_LVM)
			if self._disk_encryption.encryption_type in types:
				self._prepare_encrypt(lvm)
		else:
			for mod in self._disk_config.device_modifications:
				for part in mod.partitions:
					if part.fs_type is None:
						continue

					self._prepare_fs_type(part.fs_type, part.mountpoint)

					if part in self._disk_encryption.partitions:
						self._prepare_encrypt()

		if ucode := self._get_microcode():
			(self.target / 'boot' / ucode).unlink(missing_ok=True)
			self._base_packages.append(ucode.stem)
		else:
			debug('Archinstall will not install any ucode.')

		debug(f'Optional repositories: {optional_repositories}')

		# This action takes place on the host system as pacstrap copies over package repository lists.
		pacman_conf = PacmanConfig(self.target)
		pacman_conf.enable(optional_repositories)
		pacman_conf.apply()

		if locale_config:
			self.set_vconsole(locale_config)

		self.pacman.strap(self._base_packages)
		self._helper_flags['base-strapped'] = True

		pacman_conf.persist()

		if pacman_config:
			pacman_conf.configure(pacman_config)

		# Periodic TRIM may improve the performance and longevity of SSDs whilst
		# having no adverse effect on other devices. Most distributions enable
		# periodic TRIM by default.
		#
		# https://github.com/archlinux/archinstall/issues/880
		# https://github.com/archlinux/archinstall/issues/1837
		# https://github.com/archlinux/archinstall/issues/1841
		if not self._disable_fstrim:
			self.enable_periodic_trim()

		# TODO: Support locale and timezone
		# os.remove(f'{self.target}/etc/localtime')
		# sys_command(f'arch-chroot {self.target} ln -s /usr/share/zoneinfo/{localtime} /etc/localtime')
		# sys_command('arch-chroot /mnt hwclock --hctosys --localtime')
		if hostname:
			self.set_hostname(hostname)

		if locale_config:
			self.set_locale(locale_config)
			self.set_keyboard_language(locale_config.kb_layout)

		if mkinitcpio and not self.mkinitcpio(['-P']):
			error('Error generating initramfs (continuing anyway)')

		self._helper_flags['base'] = True

		# Run registered post-install hooks
		for function in self.post_base_install:
			info(f'Running post-installation hook: {function}')
			function(self)

		for plugin in plugins.values():
			if hasattr(plugin, 'on_install'):
				plugin.on_install(self)

	def setup_btrfs_snapshot(
		self,
		snapshot_type: SnapshotType,
		bootloader: Bootloader | None = None,
	) -> None:
		if snapshot_type == SnapshotType.Snapper:
			debug('Setting up Btrfs snapper')
			self.pacman.strap('snapper')
			# snap-pac adds a pacman hook that takes a pre/post snapper snapshot
			# around every pacman transaction, so upgrades are always rollbackable.
			self.pacman.strap('snap-pac')

			snapper: dict[str, str] = {
				'root': '/',
				'home': '/home',
			}

			for config_name, mountpoint in snapper.items():
				command = self._chroot_argv('snapper', '--no-dbus', '-c', config_name, 'create-config', mountpoint)

				try:
					SysCommand(command, peek_output=True)
				except SysCallError as err:
					raise DiskError(f'Could not setup Btrfs snapper: {err}')

			self.enable_service('snapper-timeline.timer')
			self.enable_service('snapper-cleanup.timer')

		elif snapshot_type == SnapshotType.Timeshift:
			debug('Setting up Btrfs timeshift')

			self.pacman.strap('cronie')
			self.pacman.strap('timeshift')
			self.enable_service('cronie.service')

		if bootloader and bootloader == Bootloader.Grub:
			debug('Setting up grub integration for either')
			self.pacman.strap('grub-btrfs')
			self.pacman.strap('inotify-tools')
			self._configure_grub_btrfsd(snapshot_type)
			self.enable_service('grub-btrfsd.service')

	def setup_swap(self, algo: ZramAlgorithm = ZramAlgorithm.ZSTD) -> None:
		info('Setting up swap on zram')
		self.pacman.strap('zram-generator')

		info(f'Zram compression algorithm: {algo.value}')

		with open(f'{self.target}/etc/systemd/zram-generator.conf', 'w') as zram_conf:
			zram_conf.write('[zram0]\n')
			# Maze Linux: size the zram swap to the full amount of RAM. Without an
			# explicit zram-size, zram-generator defaults to min(ram / 2, 4096) MB
			# — i.e. capped at 4 GB — which is why it always produced ~4 GB. `ram`
			# evaluates to total RAM in MB, so this creates a swap equal to RAM.
			zram_conf.write('zram-size = ram\n')
			zram_conf.write(f'compression-algorithm = {algo.value}\n')

		self.enable_service('systemd-zram-setup@zram0.service')

		self._zram_enabled = True

	def _get_efi_partition(self) -> PartitionModification | None:
		for layout in self._disk_config.device_modifications:
			if partition := layout.get_efi_partition():
				return partition
		return None

	def _get_boot_partition(self) -> PartitionModification | None:
		for layout in self._disk_config.device_modifications:
			if boot := layout.get_boot_partition():
				return boot
		return None

	def _get_root(self) -> PartitionModification | LvmVolume | None:
		if self._disk_config.lvm_config:
			return self._disk_config.lvm_config.get_root_volume()
		else:
			for mod in self._disk_config.device_modifications:
				if root := mod.get_root_partition():
					return root
		return None

	def _configure_grub_btrfsd(self, snapshot_type: SnapshotType) -> None:
		if snapshot_type == SnapshotType.Timeshift:
			snapshot_path = '--timeshift-auto'
		elif snapshot_type == SnapshotType.Snapper:
			snapshot_path = '/.snapshots'
		else:
			raise ValueError('Unsupported snapshot type')

		debug(f'Configuring grub-btrfsd service for {snapshot_type} at {snapshot_path}')

		# Works for either snapper or ts just adapting default paths above
		# https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html#id-1.14.3
		systemd_dir = self.target / 'etc/systemd/system/grub-btrfsd.service.d'
		systemd_dir.mkdir(parents=True, exist_ok=True)

		override_conf = systemd_dir / 'override.conf'

		config_content = textwrap.dedent(
			"""
			[Service]
			ExecStart=
			ExecStart=/usr/bin/grub-btrfsd --syslog {snapshot_path}
			"""
		).format(snapshot_path=snapshot_path)

		override_conf.write_text(config_content)
		override_conf.chmod(0o644)

	def _get_luks_uuid_from_mapper_dev(self, mapper_dev_path: Path) -> str:
		lsblk_info = get_lsblk_info(mapper_dev_path, reverse=True, full_dev_path=True)

		if not lsblk_info.children or not lsblk_info.children[0].uuid:
			raise ValueError('Unable to determine UUID of luks superblock')

		return lsblk_info.children[0].uuid

	def _get_kernel_params_partition(
		self,
		root_partition: PartitionModification,
		id_root: bool = True,
		partuuid: bool = True,
	) -> list[str]:
		kernel_parameters = []

		if root_partition in self._disk_encryption.partitions:
			# TODO: We need to detect if the encrypted device is a whole disk encryption,
			# or simply a partition encryption. Right now we assume it's a partition (and we always have)

			if self._disk_encryption.hsm_device:
				debug(f'Root partition is an encrypted device, identifying by UUID: {root_partition.uuid}')
				# Note: UUID must be used, not PARTUUID for sd-encrypt to work
				kernel_parameters.append(f'rd.luks.name={root_partition.uuid}=root')
				# Note: tpm2-device and fido2-device don't play along very well:
				# https://github.com/archlinux/archinstall/pull/1196#issuecomment-1129715645
				kernel_parameters.append('rd.luks.options=fido2-device=auto,password-echo=no')
			elif partuuid:
				debug(f'Root partition is an encrypted device, identifying by PARTUUID: {root_partition.partuuid}')
				kernel_parameters.append(f'cryptdevice=PARTUUID={root_partition.partuuid}:root')
			else:
				debug(f'Root partition is an encrypted device, identifying by UUID: {root_partition.uuid}')
				kernel_parameters.append(f'cryptdevice=UUID={root_partition.uuid}:root')

			if id_root:
				kernel_parameters.append('root=/dev/mapper/root')
		elif id_root:
			if partuuid:
				debug(f'Identifying root partition by PARTUUID: {root_partition.partuuid}')
				kernel_parameters.append(f'root=PARTUUID={root_partition.partuuid}')
			else:
				debug(f'Identifying root partition by UUID: {root_partition.uuid}')
				kernel_parameters.append(f'root=UUID={root_partition.uuid}')

		return kernel_parameters

	def _get_kernel_params_lvm(
		self,
		lvm: LvmVolume,
	) -> list[str]:
		kernel_parameters = []

		match self._disk_encryption.encryption_type:
			case EncryptionType.LVM_ON_LUKS:
				if not lvm.vg_name:
					raise ValueError(f'Unable to determine VG name for {lvm.name}')

				pv_seg_info = lvm_pvseg_info(lvm.vg_name, lvm.name)

				if not pv_seg_info:
					raise ValueError(f'Unable to determine PV segment info for {lvm.vg_name}/{lvm.name}')

				uuid = self._get_luks_uuid_from_mapper_dev(pv_seg_info.pv_name)

				if self._disk_encryption.hsm_device:
					debug(f'LvmOnLuks, encrypted root partition, HSM, identifying by UUID: {uuid}')
					kernel_parameters.append(f'rd.luks.name={uuid}=cryptlvm root={lvm.safe_dev_path}')
				else:
					debug(f'LvmOnLuks, encrypted root partition, identifying by UUID: {uuid}')
					kernel_parameters.append(f'cryptdevice=UUID={uuid}:cryptlvm root={lvm.safe_dev_path}')
			case EncryptionType.LUKS_ON_LVM:
				uuid = self._get_luks_uuid_from_mapper_dev(lvm.mapper_path)

				if self._disk_encryption.hsm_device:
					debug(f'LuksOnLvm, encrypted root partition, HSM, identifying by UUID: {uuid}')
					kernel_parameters.append(f'rd.luks.name={uuid}=root root=/dev/mapper/root')
				else:
					debug(f'LuksOnLvm, encrypted root partition, identifying by UUID: {uuid}')
					kernel_parameters.append(f'cryptdevice=UUID={uuid}:root root=/dev/mapper/root')
			case EncryptionType.NO_ENCRYPTION:
				debug(f'Identifying root lvm by mapper device: {lvm.dev_path}')
				kernel_parameters.append(f'root={lvm.safe_dev_path}')

		return kernel_parameters

	def _get_kernel_params(
		self,
		root: PartitionModification | LvmVolume,
		id_root: bool = True,
		partuuid: bool = True,
	) -> list[str]:
		kernel_parameters = []

		if isinstance(root, LvmVolume):
			kernel_parameters = self._get_kernel_params_lvm(root)
		else:
			kernel_parameters = self._get_kernel_params_partition(root, id_root, partuuid)

		# Zswap should be disabled when using zram.
		# https://github.com/archlinux/archinstall/issues/881
		if self._zram_enabled:
			kernel_parameters.append('zswap.enabled=0')

		if id_root:
			for sub_vol in root.btrfs_subvols:
				if sub_vol.is_root():
					kernel_parameters.append(f'rootflags=subvol={sub_vol.name}')
					break

			kernel_parameters.append('rw')

		kernel_parameters.append(f'rootfstype={root.safe_fs_type.value}')
		kernel_parameters.extend(self._kernel_params)

		debug(f'kernel parameters: {" ".join(kernel_parameters)}')

		return kernel_parameters

	def _create_bls_entries(
		self,
		boot_partition: PartitionModification,
		root: PartitionModification | LvmVolume,
		entry_name: str,
	) -> None:
		# Loader entries are stored in $BOOT/loader:
		# https://uapi-group.org/specifications/specs/boot_loader_specification/#mount-points
		entries_dir = self.target / boot_partition.relative_mountpoint / 'loader/entries'
		# Ensure that the $BOOT/loader/entries/ directory exists before trying to create files in it
		entries_dir.mkdir(parents=True, exist_ok=True)

		entry_template = textwrap.dedent(
			f"""\
			# Created by: archinstall
			# Created on: {self.init_time}
			title	Maze Linux ({{kernel}})
			linux	/vmlinuz-{{kernel}}
			initrd	/initramfs-{{kernel}}.img
			options {' '.join(self._get_kernel_params(root))}
			""",
		)

		for kernel in self.kernels:
			# Setup the loader entry
			name = entry_name.format(kernel=kernel)
			entry_conf = entries_dir / name
			entry_conf.write_text(entry_template.format(kernel=kernel))

	def _add_systemd_bootloader(
		self,
		boot_partition: PartitionModification,
		root: PartitionModification | LvmVolume,
		efi_partition: PartitionModification | None,
		uki_enabled: bool = False,
	) -> None:
		debug('Installing systemd bootloader')

		self.pacman.strap('efibootmgr')

		if not SysInfo.has_uefi():
			raise HardwareIncompatibilityError

		if not efi_partition:
			raise ValueError('Could not detect EFI system partition')
		elif not efi_partition.mountpoint:
			raise ValueError('EFI system partition is not mounted')

		# TODO: Ideally we would want to check if another config
		# points towards the same disk and/or partition.
		# And in which case we should do some clean up.
		bootctl_options = []

		if boot_partition != efi_partition:
			bootctl_options.append(f'--esp-path={efi_partition.mountpoint}')
			bootctl_options.append(f'--boot-path={boot_partition.mountpoint}')

		# TODO: This is a temporary workaround to deal with https://github.com/archlinux/archinstall/pull/3396#issuecomment-2996862019
		# the systemd_version check can be removed once `--variables=BOOL` is merged into systemd.
		systemd_pkg = installed_package('systemd')

		# keep the version as a str as it can be something like 257.8-2
		if systemd_pkg is not None:
			systemd_version = systemd_pkg.version
		else:
			systemd_version = '257'  # This works as a safety workaround for this hot-fix

		try:
			# Force EFI variables since bootctl detects arch-chroot
			# as a container environment since v257 and skips them silently.
			# https://github.com/systemd/systemd/issues/36174
			if systemd_version >= '258':
				self.arch_chroot(f'bootctl --variables=yes {" ".join(bootctl_options)} install')
			else:
				self.arch_chroot(f'bootctl {" ".join(bootctl_options)} install')
		except SysCallError:
			if systemd_version >= '258':
				# Fallback, try creating the boot loader without touching the EFI variables
				self.arch_chroot(f'bootctl --variables=no {" ".join(bootctl_options)} install')
			else:
				self.arch_chroot(f'bootctl --no-variables {" ".join(bootctl_options)} install')

		# Loader configuration is stored in ESP/loader:
		# https://man.archlinux.org/man/loader.conf.5
		loader_conf = self.target / efi_partition.relative_mountpoint / 'loader/loader.conf'
		# Ensure that the ESP/loader/ directory exists before trying to create a file in it
		loader_conf.parent.mkdir(parents=True, exist_ok=True)

		default_kernel = self.kernels[0]
		if uki_enabled:
			default_entry = f'maze-{default_kernel}.efi'
		else:
			entry_name = self.init_time + '_{kernel}.conf'
			default_entry = entry_name.format(kernel=default_kernel)
			self._create_bls_entries(boot_partition, root, entry_name)

		default = f'default {default_entry}'

		# Modify or create a loader.conf
		try:
			loader_data = loader_conf.read_text().splitlines()
		except FileNotFoundError:
			loader_data = [
				default,
				'timeout 15',
			]
		else:
			for index, line in enumerate(loader_data):
				if line.startswith('default'):
					loader_data[index] = default
				elif line.startswith('#timeout'):
					# We add in the default timeout to support dual-boot
					loader_data[index] = line.removeprefix('#')

		loader_conf.write_text('\n'.join(loader_data) + '\n')

		self._helper_flags['bootloader'] = 'systemd'

	def _add_grub_bootloader(
		self,
		boot_partition: PartitionModification,
		root: PartitionModification | LvmVolume,
		efi_partition: PartitionModification | None,
		uki_enabled: bool = False,
		bootloader_removable: bool = False,
	) -> None:
		debug('Installing grub bootloader')

		self.pacman.strap('grub')

		info(f'GRUB boot partition: {boot_partition.dev_path}')

		boot_dir = Path('/boot')

		command = self._chroot_argv('grub-install', '--debug')

		if SysInfo.has_uefi():
			if not efi_partition:
				raise ValueError('Could not detect efi partition')

			info(f'GRUB EFI partition: {efi_partition.dev_path}')

			self.pacman.strap('efibootmgr')  # TODO: Do we need? Yes, but remove from minimal_installation() instead?

			boot_dir_arg = []
			if boot_partition.mountpoint and boot_partition.mountpoint != boot_dir:
				boot_dir_arg.append(f'--boot-directory={boot_partition.mountpoint}')
				boot_dir = boot_partition.mountpoint

			add_options = [
				f'--target={platform.machine()}-efi',
				f'--efi-directory={efi_partition.mountpoint}',
				*boot_dir_arg,
				'--bootloader-id=GRUB',
			]

			if bootloader_removable:
				add_options.append('--removable')

			command.extend(add_options)

			try:
				SysCommand(command, peek_output=True)
			except SysCallError as err:
				raise DiskError(f'Could not install GRUB to {self.target}{efi_partition.mountpoint}: {err}')
		else:
			info(f'GRUB boot partition: {boot_partition.dev_path}')

			parent_dev_path = get_parent_device_path(boot_partition.safe_dev_path)

			add_options = [
				'--target=i386-pc',
				'--recheck',
				str(parent_dev_path),
			]

			try:
				SysCommand(command + add_options, peek_output=True)
			except SysCallError as err:
				raise DiskError(f'Failed to install GRUB boot on {boot_partition.dev_path}: {err}')

		if SysInfo.has_uefi() and uki_enabled:
			grub_d = LPath(self.target) / 'etc/grub.d'
			linux_file = grub_d / '10_linux'
			uki_file = grub_d / '15_uki'

			raw_str_platform = r'\$grub_platform'
			space_indent_cmd = '  uki'
			content = textwrap.dedent(
				f"""\
				#! /bin/sh
				set -e

				cat << EOF
				if [ "{raw_str_platform}" = "efi" ]; then
				{space_indent_cmd}
				fi
				EOF
				""",
			)

			try:
				uki_file.write_text(content)
				uki_file.add_exec()
				linux_file.remove_exec()
			except OSError:
				error('Failed to enable UKI menu entries')
		else:
			grub_default = self.target / 'etc/default/grub'
			config = grub_default.read_text()

			kernel_parameters = ' '.join(
				self._get_kernel_params(root, id_root=False, partuuid=False),
			)
			config = re.sub(
				r'^(GRUB_CMDLINE_LINUX=")(")$',
				rf'\1{kernel_parameters}\2',
				config,
				count=1,
				flags=re.MULTILINE,
			)

			grub_default.write_text(config)

		# Maze Linux: brand the GRUB menu so every entry reads "Maze Linux", never
		# "Arch Linux". grub-mkconfig derives the entry title from GRUB_DISTRIBUTOR
		# in /etc/default/grub (the grub package ships it as "Arch"). This applies
		# to both the UKI and the classic branch, so set it unconditionally before
		# generating grub.cfg.
		grub_default = self.target / 'etc/default/grub'
		try:
			gd_cfg = grub_default.read_text()
			if re.search(r'^GRUB_DISTRIBUTOR=', gd_cfg, flags=re.MULTILINE):
				gd_cfg = re.sub(
					r'^GRUB_DISTRIBUTOR=.*$',
					'GRUB_DISTRIBUTOR="Maze Linux"',
					gd_cfg,
					count=1,
					flags=re.MULTILINE,
				)
			else:
				gd_cfg = gd_cfg.rstrip('\n') + '\nGRUB_DISTRIBUTOR="Maze Linux"\n'
			grub_default.write_text(gd_cfg)
		except OSError:
			error('Failed to set GRUB_DISTRIBUTOR for Maze branding')

		try:
			self.arch_chroot(
				f'grub-mkconfig -o {boot_dir}/grub/grub.cfg',
			)
		except SysCallError as err:
			raise DiskError(f'Could not configure GRUB: {err}')

		self._helper_flags['bootloader'] = 'grub'

	def _add_limine_bootloader(
		self,
		boot_partition: PartitionModification,
		efi_partition: PartitionModification | None,
		root: PartitionModification | LvmVolume,
		uki_enabled: bool = False,
		bootloader_removable: bool = False,
	) -> None:
		debug('Installing Limine bootloader')

		self.pacman.strap('limine')

		info(f'Limine boot partition: {boot_partition.dev_path}')

		limine_path = self.target / 'usr' / 'share' / 'limine'
		config_path = None
		hook_command = None

		if SysInfo.has_uefi():
			self.pacman.strap('efibootmgr')

			if not efi_partition:
				raise ValueError('Could not detect efi partition')
			elif not efi_partition.mountpoint:
				raise ValueError('EFI partition is not mounted')

			# Safety net for programmatic callers that bypass GlobalMenu and
			# guided.py validation.
			if failure := validate_bootloader_layout(
				BootloaderConfiguration(bootloader=Bootloader.Limine, uki=uki_enabled),
				self._disk_config,
			):
				raise DiskError(failure.description)

			info(f'Limine EFI partition: {efi_partition.dev_path}')

			parent_dev_path = get_parent_device_path(efi_partition.safe_dev_path)

			try:
				efi_dir_path = self.target / efi_partition.mountpoint.relative_to('/') / 'EFI'
				efi_dir_path_target = efi_partition.mountpoint / 'EFI'
				if bootloader_removable:
					efi_dir_path = efi_dir_path / 'BOOT'
					efi_dir_path_target = efi_dir_path_target / 'BOOT'
				else:
					efi_dir_path = efi_dir_path / 'arch-limine'
					efi_dir_path_target = efi_dir_path_target / 'arch-limine'

				config_path = efi_dir_path / 'limine.conf'

				efi_dir_path.mkdir(parents=True, exist_ok=True)

				for file in ('BOOTIA32.EFI', 'BOOTX64.EFI'):
					(limine_path / file).copy_into(efi_dir_path)
			except Exception as err:
				raise DiskError(f'Failed to install Limine in {self.target}{efi_partition.mountpoint}: {err}')

			hook_command = (
				f'/usr/bin/cp /usr/share/limine/BOOTIA32.EFI {efi_dir_path_target}/ && /usr/bin/cp /usr/share/limine/BOOTX64.EFI {efi_dir_path_target}/'
			)

			if not bootloader_removable:
				# Create EFI boot menu entry for Limine.
				try:
					with open('/sys/firmware/efi/fw_platform_size') as fw_platform_size:
						efi_bitness = fw_platform_size.read().strip()
				except Exception as err:
					raise OSError(f'Could not open or read /sys/firmware/efi/fw_platform_size to determine EFI bitness: {err}')

				if efi_bitness == '64':
					loader_path = '\\EFI\\arch-limine\\BOOTX64.EFI'
				elif efi_bitness == '32':
					loader_path = '\\EFI\\arch-limine\\BOOTIA32.EFI'
				else:
					raise ValueError(f'EFI bitness is neither 32 nor 64 bits. Found "{efi_bitness}".')

				try:
					SysCommand(
						'efibootmgr'
						' --create'
						f' --disk {parent_dev_path}'
						f' --part {efi_partition.partn}'
						' --label "Maze Linux Limine Bootloader"'
						f" --loader '{loader_path}'"
						' --unicode'
						' --verbose',
					)
				except Exception as err:
					raise ValueError(f'SysCommand for efibootmgr failed: {err}')
		else:
			boot_limine_path = self.target / 'boot' / 'limine'
			boot_limine_path.mkdir(parents=True, exist_ok=True)

			config_path = boot_limine_path / 'limine.conf'

			parent_dev_path = get_parent_device_path(boot_partition.safe_dev_path)

			if unique_path := get_unique_path_for_device(parent_dev_path):
				parent_dev_path = unique_path

			try:
				# The `limine-bios.sys` file contains stage 3 code.
				(limine_path / 'limine-bios.sys').copy_into(boot_limine_path)

				# `limine bios-install` deploys the stage 1 and 2 to the
				self.arch_chroot(f'limine bios-install {parent_dev_path}', peek_output=True)
			except Exception as err:
				raise DiskError(f'Failed to install Limine on {parent_dev_path}: {err}')

			hook_command = f'/usr/bin/limine bios-install {parent_dev_path} && /usr/bin/cp /usr/share/limine/limine-bios.sys /boot/limine/'

		hook_contents = textwrap.dedent(
			f'''\
			[Trigger]
			Operation = Install
			Operation = Upgrade
			Type = Package
			Target = limine

			[Action]
			Description = Deploying Limine after upgrade...
			When = PostTransaction
			Exec = /bin/sh -c "{hook_command}"
			''',
		)

		hooks_dir = self.target / 'etc' / 'pacman.d' / 'hooks'
		hooks_dir.mkdir(parents=True, exist_ok=True)

		hook_path = hooks_dir / '99-limine.hook'
		hook_path.write_text(hook_contents)

		kernel_params = ' '.join(self._get_kernel_params(root))
		config_contents = 'timeout: 5\n'

		path_root = 'boot()'
		if efi_partition and boot_partition != efi_partition:
			path_root = f'uuid({boot_partition.partuuid})'

		for kernel in self.kernels:
			if uki_enabled:
				entry = [
					'protocol: efi',
					f'path: boot():/EFI/Linux/arch-{kernel}.efi',
					f'cmdline: {kernel_params}',
				]
				config_contents += f'\n/Maze Linux ({kernel})\n'
				config_contents += '\n'.join(f'    {it}' for it in entry) + '\n'
			else:
				entry = [
					'protocol: linux',
					f'path: {path_root}:/vmlinuz-{kernel}',
					f'cmdline: {kernel_params}',
					f'module_path: {path_root}:/initramfs-{kernel}.img',
				]
				config_contents += f'\n/Maze Linux ({kernel})\n'
				config_contents += '\n'.join(f'    {it}' for it in entry) + '\n'

		config_path.write_text(config_contents)

		self._helper_flags['bootloader'] = 'limine'

	def _add_efistub_bootloader(
		self,
		boot_partition: PartitionModification,
		root: PartitionModification | LvmVolume,
		uki_enabled: bool = False,
	) -> None:
		debug('Installing efistub bootloader')

		self.pacman.strap('efibootmgr')

		if not SysInfo.has_uefi():
			raise HardwareIncompatibilityError

		# TODO: Ideally we would want to check if another config
		# points towards the same disk and/or partition.
		# And in which case we should do some clean up.

		if not uki_enabled:
			loader = '/vmlinuz-{kernel}'
			# EFI standards stipulate backslashes
			entries = (
				r'initrd=\initramfs-{kernel}.img',
				*self._get_kernel_params(root),
			)

			cmdline = [' '.join(entries)]
		else:
			loader = '/EFI/Linux/arch-{kernel}.efi'
			cmdline = []

		parent_dev_path = get_parent_device_path(boot_partition.safe_dev_path)

		cmd_template = (
			'efibootmgr',
			'--create',
			'--disk',
			str(parent_dev_path),
			'--part',
			str(boot_partition.partn),
			'--label',
			'Maze Linux ({kernel})',
			'--loader',
			loader,
			'--unicode',
			*cmdline,
			'--verbose',
		)

		for kernel in self.kernels:
			# Setup the firmware entry
			cmd = [arg.format(kernel=kernel) for arg in cmd_template]
			SysCommand(cmd)

		self._helper_flags['bootloader'] = 'efistub'

	def _add_refind_bootloader(
		self,
		boot_partition: PartitionModification,
		efi_partition: PartitionModification | None,
		root: PartitionModification | LvmVolume,
		uki_enabled: bool = False,
	) -> None:
		debug('Installing rEFInd bootloader')

		self.pacman.strap('refind')

		if not SysInfo.has_uefi():
			raise HardwareIncompatibilityError

		info(f'rEFInd boot partition: {boot_partition.dev_path}')

		if not efi_partition:
			raise ValueError('Could not detect EFI system partition')
		elif not efi_partition.mountpoint:
			raise ValueError('EFI system partition is not mounted')

		info(f'rEFInd EFI partition: {efi_partition.dev_path}')

		try:
			self.arch_chroot('refind-install')
		except SysCallError as err:
			raise DiskError(f'Could not install rEFInd to {self.target}{efi_partition.mountpoint}: {err}')

		if not boot_partition.mountpoint:
			raise ValueError('Boot partition is not mounted, cannot write rEFInd config')

		boot_is_separate = boot_partition != efi_partition and boot_partition.dev_path != efi_partition.dev_path

		if boot_is_separate:
			# Separate boot partition (not ESP, not root)
			config_path = self.target / boot_partition.mountpoint.relative_to('/') / 'refind_linux.conf'
			boot_on_root = False
		elif efi_partition.mountpoint == Path('/boot'):
			# ESP is mounted at /boot, kernels are on ESP
			config_path = self.target / 'boot' / 'refind_linux.conf'
			boot_on_root = False
		else:
			# ESP is elsewhere (/efi, /boot/efi, etc.), kernels are on root filesystem at /boot
			config_path = self.target / 'boot' / 'refind_linux.conf'
			boot_on_root = True

		config_contents = []

		kernel_params = ' '.join(self._get_kernel_params(root))

		for kernel in self.kernels:
			if uki_enabled:
				entry = f'"Maze Linux ({kernel}) UKI" "{kernel_params}"'
			else:
				if boot_on_root:
					# Kernels are in /boot subdirectory of root filesystem
					if hasattr(root, 'btrfs_subvols') and root.btrfs_subvols:
						# Root is btrfs with subvolume, find the root subvolume
						root_subvol = next((sv for sv in root.btrfs_subvols if sv.is_root()), None)
						if root_subvol:
							subvol_name = root_subvol.name
							initrd_path = f'initrd={subvol_name}\\boot\\initramfs-{kernel}.img'
						else:
							initrd_path = f'initrd=\\boot\\initramfs-{kernel}.img'
					else:
						# Root without btrfs subvolume
						initrd_path = f'initrd=\\boot\\initramfs-{kernel}.img'
				else:
					# Kernels are at root of their partition (ESP or separate boot partition)
					initrd_path = f'initrd=\\initramfs-{kernel}.img'
				entry = f'"Maze Linux ({kernel})" "{kernel_params} {initrd_path}"'

			config_contents.append(entry)

		config_path.write_text('\n'.join(config_contents) + '\n')

		hook_contents = textwrap.dedent(
			"""\
			[Trigger]
			Operation = Install
			Operation = Upgrade
			Type = Package
			Target = refind

			[Action]
			Description = Updating rEFInd on ESP
			When = PostTransaction
			Exec = /usr/bin/refind-install
			"""
		)

		hooks_dir = self.target / 'etc' / 'pacman.d' / 'hooks'
		hooks_dir.mkdir(parents=True, exist_ok=True)

		hook_path = hooks_dir / '99-refind.hook'
		hook_path.write_text(hook_contents)

		self._helper_flags['bootloader'] = 'refind'

	def _install_plymouth(self, plymouth: PlymouthTheme) -> None:
		debug(f'Installing plymouth with theme: {plymouth.value}')
		self.add_additional_packages(['plymouth'])

		# Maze Linux: the "maze" theme is not shipped by any package; it lives on
		# the live ISO at /usr/share/plymouth/themes/maze. Copy it into the target
		# before plymouth-set-default-theme so the branded splash actually applies.
		if plymouth == PlymouthTheme.MAZE:
			live_theme = Path('/usr/share/plymouth/themes/maze')
			if live_theme.is_dir():
				dest = self.target / 'usr/share/plymouth/themes/maze'
				try:
					dest.parent.mkdir(parents=True, exist_ok=True)
					shutil.copytree(live_theme, dest, dirs_exist_ok=True)
				except Exception as exc:
					debug(f'Could not copy Maze plymouth theme: {exc}')

		for param in ('quiet', 'splash', 'bgrt_disable', 'logo.nologo'):
			if param not in self._kernel_params:
				self._kernel_params.append(param)

		if 'plymouth' not in self._hooks:
			for hook, insert_after in [('kms', True), ('encrypt', False), ('sd-encrypt', False), ('systemd', True), ('filesystems', False), ('keyboard', True)]:
				try:
					idx = self._hooks.index(hook)
					self._hooks.insert(idx + (1 if insert_after else 0), 'plymouth')
					break
				except ValueError:
					continue
			else:
				self._hooks.append('plymouth')

		self.arch_chroot(f'plymouth-set-default-theme {plymouth.value}')
		self.mkinitcpio(['-P'])

	def _config_uki(
		self,
		root: PartitionModification | LvmVolume,
		efi_partition: PartitionModification | None,
		keep_initramfs: bool = False,
	) -> None:
		if not efi_partition or not efi_partition.mountpoint:
			raise ValueError(f'Could not detect ESP at mountpoint {self.target}')

		# Set up kernel command line
		with open(self.target / 'etc/kernel/cmdline', 'w') as cmdline:
			kernel_parameters = self._get_kernel_params(root)
			cmdline.write(' '.join(kernel_parameters) + '\n')

		diff_mountpoint = None

		if efi_partition.mountpoint != Path('/efi'):
			diff_mountpoint = str(efi_partition.mountpoint)

		image_re = re.compile('(.+_image="/([^"]+).+\n)')
		uki_re = re.compile('#((.+_uki=")/[^/]+(.+\n))')

		# Modify .preset files
		for kernel in self.kernels:
			preset = self.target / 'etc/mkinitcpio.d' / (kernel + '.preset')
			config = preset.read_text().splitlines(True)

			for index, line in enumerate(config):
				if m := image_re.match(line):
					if not keep_initramfs:
						image = self.target / m.group(2)
						image.unlink(missing_ok=True)
						config[index] = '#' + m.group(1)
				elif m := uki_re.match(line):
					if diff_mountpoint:
						uki_line = m.group(2) + diff_mountpoint + m.group(3)
					else:
						uki_line = m.group(1)
					# Rename arch-<kernel> → maze-<kernel> in the UKI path.
					config[index] = uki_line.replace('/arch-', '/maze-')
				elif line.startswith('#default_options=') or line.startswith('default_options='):
					import re as _re
					bare = line.removeprefix('#')
					# Comment out lines whose only content is a vendor splash BMP.
					if '--splash' in bare:
						config[index] = '#' + bare if not line.startswith('#') else line
					else:
						config[index] = bare

			preset.write_text(''.join(config))

		# Directory for the UKIs
		uki_dir = self.target / efi_partition.relative_mountpoint / 'EFI/Linux'
		uki_dir.mkdir(parents=True, exist_ok=True)

		# Build the UKIs
		if not self.mkinitcpio(['-P']):
			error('Error generating initramfs (continuing anyway)')

	def _setup_secure_boot(
		self,
		efi_partition: PartitionModification | None,
		root: PartitionModification | LvmVolume,
	) -> None:
		"""
		Set up UEFI Secure Boot for the installed system using the same shim +
		MOK model as the live ISO:

		  firmware -> shim (Microsoft-signed) -> systemd-boot (Maze-signed)
		           -> unified kernel image (Maze-signed)

		A per-machine key is generated (its private half never leaves the target),
		shim is taken from the running live system (the AUR ``shim-signed`` package
		is preinstalled there) and copied to the ESP, the bootloader and UKIs are
		signed, and a pacman hook keeps them signed across kernel/systemd updates.
		The Maze certificate is queued for one-time MOK enrollment so existing
		factory/Windows keys are preserved (no firmware Setup Mode required).
		"""
		debug('Setting up Secure Boot (shim + MOK)')

		if not efi_partition or not efi_partition.mountpoint:
			warn('Secure Boot: no ESP detected; skipping')
			return

		# Shim binaries come from the live system (shim-signed is an AUR package,
		# not installable from the official repos on the target).
		live_shim = Path('/usr/share/shim-signed/shimx64.efi')
		live_mm = Path('/usr/share/shim-signed/mmx64.efi')
		if not live_shim.exists():
			warn(f'Secure Boot: {live_shim} not found on the live system; skipping')
			return

		# Signing/enrollment tooling on the target (all in the official repos).
		self.pacman.strap(['sbsigntools', 'mokutil', 'efitools'])

		key_dir = self.target / 'var/lib/maze-secureboot'
		key_dir.mkdir(parents=True, exist_ok=True)
		key_dir.chmod(0o700)

		# Stash shim (and MokManager) so the re-sign hook can restore them later.
		shutil.copy2(live_shim, key_dir / 'shimx64.efi')
		if live_mm.exists():
			shutil.copy2(live_mm, key_dir / 'mmx64.efi')

		# 1) Per-machine key (private half stays on this machine only).
		try:
			self.arch_chroot(
				'openssl req -newkey rsa:2048 -nodes '
				'-keyout /var/lib/maze-secureboot/MOK.key '
				'-new -x509 -sha256 -days 3650 '
				'-subj "/CN=Maze Linux Secure Boot machine key/" '
				'-out /var/lib/maze-secureboot/MOK.crt'
			)
			self.arch_chroot(
				'openssl x509 -outform DER '
				'-in /var/lib/maze-secureboot/MOK.crt '
				'-out /var/lib/maze-secureboot/MOK.cer'
			)
			self.arch_chroot('chmod 600 /var/lib/maze-secureboot/MOK.key')
		except SysCallError as err:
			error(f'Secure Boot: failed to generate machine key: {err}')
			return

		# 2) The signer script + pacman hook (re-sign on kernel/systemd updates).
		sign_script = self.target / 'usr/local/bin/maze-sb-sign'
		sign_script.parent.mkdir(parents=True, exist_ok=True)
		sign_script.write_text(MAZE_SB_SIGN_SCRIPT)
		sign_script.chmod(0o755)

		hook_dir = self.target / 'etc/pacman.d/hooks'
		hook_dir.mkdir(parents=True, exist_ok=True)
		(hook_dir / '95-maze-secureboot.hook').write_text(MAZE_SB_PACMAN_HOOK)

		# 2b) systemd .path unit: catch a MANUAL `mkinitcpio -P` (no pacman txn, so
		#     the hook above never fires) by watching the UKI directory and re-signing
		#     on any change. Belt-and-suspenders with the pacman hook.
		systemd_unit_dir = self.target / 'etc/systemd/system'
		systemd_unit_dir.mkdir(parents=True, exist_ok=True)
		(systemd_unit_dir / 'maze-sb-resign.service').write_text(MAZE_SB_RESIGN_SERVICE)
		(systemd_unit_dir / 'maze-sb-resign.path').write_text(MAZE_SB_RESIGN_PATH)
		try:
			# .path watches for live UKI changes; .service also runs once per boot
			# as a self-heal (idempotent: a clean ESP is verified, never rewritten).
			self.arch_chroot('systemctl enable maze-sb-resign.path maze-sb-resign.service')
		except SysCallError as err:
			warn(f'Secure Boot: could not enable maze-sb-resign units ({err}); '
				'manual `mkinitcpio` runs will need `maze-sb-sign` by hand')

		# 2c) Mask systemd's own boot updater: under the shim chain `bootctl update`
		#     would overwrite the shim at EFI/BOOT/BOOTX64.EFI with an unsigned
		#     systemd-boot and break the chain. Our pacman hook already keeps the
		#     signed systemd-boot (grubx64.efi) current on every systemd upgrade.
		try:
			self.arch_chroot('systemctl mask systemd-boot-update.service')
		except SysCallError as err:
			warn(f'Secure Boot: could not mask systemd-boot-update.service ({err})')

		# 3) Sign the bootloader + UKIs now (the script also places shim). The ESP
		#    mountpoint is passed explicitly: bootctl --print-esp-path is unreliable
		#    inside the install chroot, and an unsigned grubx64.efi/UKI is exactly
		#    what makes Secure Boot fail after enrollment. peek_output streams the
		#    script's per-file OK/FAIL self-check into the install log.
		esp_mountpoint = str(efi_partition.mountpoint)
		# Remember the ESP so the install can re-sign one final time after every
		# later step that might regenerate the unified kernel image (KDE/AUR
		# package installs trigger mkinitcpio). See resign_secure_boot().
		self._secure_boot_esp = esp_mountpoint
		try:
			self.arch_chroot(f'/usr/local/bin/maze-sb-sign --force-bootloader {esp_mountpoint}', peek_output=True)
		except SysCallError as err:
			# Signing failed (e.g. self-check found unsigned binaries). Do not abort
			# the install: the system still boots if the user disables Secure Boot,
			# and the bootloader itself is in place. But make the failure loud.
			error(
				f'Secure Boot: signing FAILED ({err}). The system will NOT boot with '
				'Secure Boot enabled until this is resolved (re-run /usr/local/bin/maze-sb-sign). '
				'Boot with Secure Boot disabled in firmware for now.'
			)
			return

		# 4) NVRAM boot entry pointing at shim (the removable /EFI/BOOT/BOOTX64.EFI
		#    path). efibootmgr --create prepends it to BootOrder, so shim is tried
		#    first. The removable path is also a firmware fallback.
		try:
			parent_dev_path = get_parent_device_path(efi_partition.safe_dev_path)
			self.arch_chroot(
				'efibootmgr --create '
				f'--disk {parent_dev_path} '
				f'--part {efi_partition.partn} '
				'--label "Maze Linux" '
				r'--loader \\EFI\\BOOT\\BOOTX64.EFI '
				'--unicode'
			)
		except SysCallError as err:
			# Most firmware also auto-boots the removable path, so this is not fatal.
			warn(f'Secure Boot: could not create NVRAM boot entry ({err}); '
				'relying on the removable /EFI/BOOT/BOOTX64.EFI fallback')

		# 5) Leave the user clear first-boot instructions. Enrollment is
		#    password-less: on the first boot shim fails to validate the (not yet
		#    trusted) Maze-signed loader and opens MokManager, where the user picks
		#    "Enroll key from disk" -> MOK.cer. No shared password, physical
		#    presence is the protection — the same flow proven on the live ISO.
		enroll_note = self.target / 'var/lib/maze-secureboot/ENROLLMENT.txt'
		enroll_note.write_text(MAZE_SB_ENROLLMENT_NOTE)

		info(
			'Secure Boot configured (bootloader + kernel signed). On the first reboot '
			'a "Verification failed" / MokManager screen appears: choose "Enroll key '
			'from disk" -> select MOK.cer -> Continue -> Yes, then reboot. No password. '
			'Factory/Windows keys are kept; kernel updates are re-signed automatically.'
		)
		self._helper_flags['secure_boot'] = True

	def resign_secure_boot(self) -> None:
		"""
		Final Secure Boot re-sign pass, run as the very last installation step.

		The unified kernel image is regenerated by mkinitcpio whenever the kernel,
		systemd or a module-providing package is installed, which happens AFTER
		_setup_secure_boot during the desktop/AUR package phase. A freshly
		generated UKI is unsigned, so without this pass systemd-boot refuses to
		load it under Secure Boot ("Security violation") even though shim and
		systemd-boot themselves are signed. Re-signing here (with the known ESP
		path) guarantees the on-disk UKI is signed after the last regeneration.
		"""
		esp = getattr(self, '_secure_boot_esp', None)
		if not esp:
			return

		info('Secure Boot: final re-sign of bootloader and kernel images')
		try:
			self.arch_chroot(f'/usr/local/bin/maze-sb-sign --force-bootloader {esp}', peek_output=True)
		except SysCallError as err:
			error(
				f'Secure Boot: final re-sign FAILED ({err}). The system may not boot '
				'with Secure Boot enabled; boot with it disabled and run '
				'/usr/local/bin/maze-sb-sign as root, or re-enable Secure Boot afterwards.'
			)

	def add_bootloader(
		self,
		bootloader: Bootloader,
		uki_enabled: bool = False,
		bootloader_removable: bool = False,
		plymouth: PlymouthTheme | None = None,
		secure_boot: bool = False,
	) -> None:
		"""
		Adds a bootloader to the installation instance.
		Archinstall supports one of five types:
		* systemd-bootctl
		* grub
		* limine
		* efistub (beta)
		* refnd (beta)

		:param bootloader: Type of bootloader to be added
		:param uki_enabled: Whether to use unified kernel images
		:param bootloader_removable: Whether to install to removable media location (UEFI only, for GRUB and Limine)
		:param plymouth: Optional Plymouth theme to install and configure
		:param secure_boot: Whether to set up UEFI Secure Boot (shim + MOK, systemd-boot only)
		"""

		for plugin in plugins.values():
			if hasattr(plugin, 'on_add_bootloader'):
				# Allow plugins to override the boot-loader handling.
				# This allows for boot configuring and installing bootloaders.
				if plugin.on_add_bootloader(self):
					return

		efi_partition = self._get_efi_partition()
		boot_partition = self._get_boot_partition()
		root = self._get_root()

		if boot_partition is None:
			raise ValueError(f'Could not detect boot at mountpoint {self.target}')

		if root is None:
			raise ValueError(f'Could not detect root at mountpoint {self.target}')

		info(f'Adding bootloader {bootloader.value} to {boot_partition.dev_path}')

		# validate UKI support
		if uki_enabled and not bootloader.has_uki_support():
			warn(f'Bootloader {bootloader.value} does not support UKI; disabling.')
			uki_enabled = False

		# validate removable bootloader option
		if bootloader_removable:
			if not SysInfo.has_uefi():
				warn('Removable install requested but system is not UEFI; disabling.')
				bootloader_removable = False
			elif not bootloader.has_removable_support():
				warn(f'Bootloader {bootloader.value} lacks removable support; disabling.')
				bootloader_removable = False

		# validate Secure Boot option
		if secure_boot:
			if not SysInfo.has_uefi():
				warn('Secure Boot requested but system is not UEFI; disabling.')
				secure_boot = False
			elif not bootloader.has_secure_boot_support():
				warn(f'Bootloader {bootloader.value} does not support Maze Secure Boot; disabling.')
				secure_boot = False

		if plymouth is not None:
			self._install_plymouth(plymouth)

		if uki_enabled:
			keep_initramfs = (
				bootloader == Bootloader.Grub
				and self._disk_config.has_default_btrfs_vols()
				and self._disk_config.btrfs_options is not None
				and self._disk_config.btrfs_options.snapshot_config is not None
			)
			self._config_uki(root, efi_partition, keep_initramfs)

		match bootloader:
			case Bootloader.Systemd:
				self._add_systemd_bootloader(boot_partition, root, efi_partition, uki_enabled)
			case Bootloader.Grub:
				self._add_grub_bootloader(boot_partition, root, efi_partition, uki_enabled, bootloader_removable)
			case Bootloader.Efistub:
				self._add_efistub_bootloader(boot_partition, root, uki_enabled)
			case Bootloader.Limine:
				self._add_limine_bootloader(boot_partition, efi_partition, root, uki_enabled, bootloader_removable)
			case Bootloader.Refind:
				self._add_refind_bootloader(boot_partition, efi_partition, root, uki_enabled)

		# Maze Linux: set up Secure Boot (shim + MOK) once the bootloader and the
		# unified kernel images are in place. systemd-boot only (validated above).
		if secure_boot:
			self._setup_secure_boot(efi_partition, root)

	def add_additional_packages(self, packages: str | list[str]) -> None:
		return self.pacman.strap(packages)

	def enable_sudo(self, user: User, group: bool = False) -> None:
		info(f'Enabling sudo permissions for {user.username}')

		sudoers_dir = self.target / 'etc/sudoers.d'

		# Creates directory if not exists
		if not sudoers_dir.exists():
			sudoers_dir.mkdir(parents=True)
			# Guarantees sudoer confs directory recommended perms
			sudoers_dir.chmod(0o440)
			# Appends a reference to the sudoers file, because if we are here sudoers.d did not exist yet
			with open(self.target / 'etc/sudoers', 'a') as sudoers:
				sudoers.write('@includedir /etc/sudoers.d\n')

		# We count how many files are there already so we know which number to prefix the file with
		num_of_rules_already = len(os.listdir(sudoers_dir))
		file_num_str = f'{num_of_rules_already:02d}'  # We want 00_user1, 01_user2, etc

		# Guarantees that username str does not contain invalid characters for a linux file name:
		# \ / : * ? " < > |
		safe_username_file_name = re.sub(r'(\\|\/|:|\*|\?|"|<|>|\|)', '', user.username)

		rule_file = sudoers_dir / f'{file_num_str}_{safe_username_file_name}'

		with rule_file.open('a') as sudoers:
			sudoers.write(f'{"%" if group else ""}{user.username} ALL=(ALL) ALL\n')

		# Guarantees sudoer conf file recommended perms
		rule_file.chmod(0o440)

	def create_users(self, users: User | list[User]) -> None:
		if not isinstance(users, list):
			users = [users]

		for user in users:
			self._create_user(user)

	def _create_user(self, user: User) -> None:
		# This plugin hook allows for the plugin to handle the creation of the user.
		# Password and Group management is still handled by user_create()
		handled_by_plugin = False
		for plugin in plugins.values():
			if hasattr(plugin, 'on_user_create'):
				if result := plugin.on_user_create(self, user):
					handled_by_plugin = result

		if not handled_by_plugin:
			info(f'Creating user {user.username}')

			cmd = self._chroot_argv('useradd', '-m')

			if user.sudo:
				cmd += ['-G', 'wheel']

			cmd += ['--', user.username]

			try:
				run(cmd)
			except CalledProcessError as err:
				debug(f'Error creating user {user.username}: {err}')
				raise SystemError(f'Could not create user inside installation: {err}')

		for plugin in plugins.values():
			if hasattr(plugin, 'on_user_created'):
				if result := plugin.on_user_created(self, user):
					handled_by_plugin = result

		self.set_user_password(user)

		for group in user.groups:
			cmd = self._chroot_argv('gpasswd', '-a', user.username, group)
			try:
				run(cmd)
			except CalledProcessError as err:
				warn(f'Failed to add {user.username} to group {group}: {err}')

		if user.sudo:
			self.enable_sudo(user)

	def set_user_password(self, user: User) -> bool:
		info(f'Setting password for {user.username}')

		enc_password = user.password.enc_password

		if not enc_password:
			debug('User password is empty')
			return False

		input_data = f'{user.username}:{enc_password}'.encode()
		cmd = self._chroot_argv('chpasswd', '--encrypted')

		try:
			run(cmd, input_data=input_data)
			return True
		except CalledProcessError as err:
			debug(f'Error setting user password: {err}')
			return False

	def user_set_shell(self, user: str, shell: str) -> bool:
		info(f'Setting shell for {user} to {shell}')

		cmd = self._chroot_argv('chsh', '-s', shell, user)
		try:
			run(cmd)
			return True
		except CalledProcessError as err:
			debug(f'Error setting user shell: {err}')
			return False

	def chown(self, owner: str, path: str, options: list[str] | None = None) -> bool:
		options = options or []
		cmd = self._chroot_argv('chown', *options, '--', owner, path)
		try:
			run(cmd)
			return True
		except CalledProcessError as err:
			debug(f'Error changing ownership of {path}: {err}')
			return False

	def set_vconsole(self, locale_config: LocaleConfiguration) -> None:
		# use the already set kb layout
		kb_vconsole: str = locale_config.kb_layout
		font_vconsole = locale_config.console_font

		if font_vconsole.startswith('ter-'):
			self.pacman.strap(['terminus-font'])

		# Ensure /etc exists
		vconsole_dir: Path = self.target / 'etc'
		vconsole_dir.mkdir(parents=True, exist_ok=True)
		vconsole_path: Path = vconsole_dir / 'vconsole.conf'

		# Write both KEYMAP and FONT to vconsole.conf
		vconsole_content = f'KEYMAP={kb_vconsole}\n'
		# Corrects another warning
		vconsole_content += f'FONT={font_vconsole}\n'

		vconsole_path.write_text(vconsole_content)
		info(f'Wrote to {vconsole_path} using {kb_vconsole} and {font_vconsole}')

	def set_keyboard_language(self, language: str) -> bool:
		info(f'Setting keyboard language to {language}')

		if len(language.strip()):
			if not verify_keyboard_layout(language):
				error(f'Invalid keyboard language specified: {language}')
				return False

			# In accordance with https://github.com/archlinux/archinstall/issues/107#issuecomment-841701968
			# Setting an empty keymap first, allows the subsequent call to set layout for both console and x11.
			with Boot(self.target) as session:
				os.system('systemd-run --machine=archinstall --pty localectl set-keymap ""')  # type: ignore[deprecated]

				try:
					session.SysCommand(['localectl', 'set-keymap', language])
				except SysCallError as err:
					raise ServiceException(f"Unable to set locale '{language}' for console: {err}")

				info(f'Keyboard language for this installation is now set to: {language}')
		else:
			info('Keyboard language was not changed from default (no language specified)')

		return True

	def set_x11_keyboard_language(self, language: str) -> bool:
		"""
		A fallback function to set x11 layout specifically and separately from console layout.
		This isn't strictly necessary since .set_keyboard_language() does this as well.
		"""
		info(f'Setting x11 keyboard language to {language}')

		if len(language.strip()):
			if not verify_x11_keyboard_layout(language):
				error(f'Invalid x11-keyboard language specified: {language}')
				return False

			with Boot(self.target) as session:
				session.SysCommand(['localectl', 'set-x11-keymap', '""'])

				try:
					session.SysCommand(['localectl', 'set-x11-keymap', language])
				except SysCallError as err:
					raise ServiceException(f"Unable to set locale '{language}' for X11: {err}")
		else:
			info('X11-Keyboard language was not changed from default (no language specified)')

		return True

	def _service_started(self, service_name: str) -> str | None:
		if os.path.splitext(service_name)[1] not in ('.service', '.target', '.timer'):
			service_name += '.service'  # Just to be safe

		last_execution_time = (
			SysCommand(
				f'systemctl show --property=ActiveEnterTimestamp --no-pager {service_name}',
				environment_vars={'SYSTEMD_COLORS': '0'},
			)
			.decode()
			.removeprefix('ActiveEnterTimestamp=')
		)

		if not last_execution_time:
			return None

		return last_execution_time

	def _service_state(self, service_name: str) -> str:
		if os.path.splitext(service_name)[1] not in ('.service', '.target', '.timer'):
			service_name += '.service'  # Just to be safe

		return SysCommand(
			f'systemctl show --no-pager -p SubState --value {service_name}',
			environment_vars={'SYSTEMD_COLORS': '0'},
		).decode()


def accessibility_tools_in_use() -> bool:
	return os.system('systemctl is-active --quiet espeakup.service') == 0  # type: ignore[deprecated]


def run_custom_user_commands(commands: list[str], installation: Installer) -> None:
	for index, command in enumerate(commands):
		script_path = f'/var/tmp/user-command.{index}.sh'
		chroot_path = f'{installation.target}/{script_path}'

		info(f'Executing custom command "{command}" ...')
		with open(chroot_path, 'w') as user_script:
			user_script.write(command)

		SysCommand(f'arch-chroot -S {installation.target} bash {script_path}')

		os.unlink(chroot_path)
