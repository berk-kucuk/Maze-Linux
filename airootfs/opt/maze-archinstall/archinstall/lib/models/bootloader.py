import sys
from dataclasses import dataclass
from enum import Enum
from typing import Any, Self, override

from archinstall.lib.log import warn
from archinstall.lib.models.config import SubConfig
from archinstall.lib.translationhandler import tr


class Bootloader(Enum):
	NO_BOOTLOADER = 'No bootloader'
	Systemd = 'Systemd-boot'
	Grub = 'Grub'
	Efistub = 'Efistub'
	Limine = 'Limine'
	Refind = 'Refind'

	def has_uki_support(self) -> bool:
		return self != Bootloader.NO_BOOTLOADER

	def has_removable_support(self) -> bool:
		match self:
			case Bootloader.Grub | Bootloader.Limine:
				return True
			case _:
				return False

	def is_uefi_only(self) -> bool:
		match self:
			case Bootloader.Systemd | Bootloader.Efistub | Bootloader.Refind:
				return True
			case _:
				return False

	def has_secure_boot_support(self) -> bool:
		# Maze Linux Secure Boot uses a Microsoft-signed shim that chainloads a
		# Maze-signed second stage (systemd-boot) which in turn validates the
		# signed unified kernel image via shim's lock protocol. Only systemd-boot
		# is wired up for this; GRUB/efistub/limine are not signed by Maze.
		return self == Bootloader.Systemd

	def json(self) -> str:
		return self.value

	@classmethod
	def get_default(cls, uefi: bool, skip_boot: bool = False) -> Self:
		if skip_boot:
			return cls.NO_BOOTLOADER
		elif uefi:
			return cls.Systemd
		else:
			return cls.Grub

	@classmethod
	def from_arg(cls, bootloader: str, skip_boot: bool) -> Self:
		# to support old configuration files
		bootloader = bootloader.capitalize()

		bootloader_options = [e.value for e in cls if e != cls.NO_BOOTLOADER or skip_boot is True]

		if bootloader not in bootloader_options:
			values = ', '.join(bootloader_options)
			warn(f'Invalid bootloader value "{bootloader}". Allowed values: {values}')
			sys.exit(1)

		return cls(bootloader)


class PlymouthTheme(Enum):
	# Maze Linux: the ONLY supported boot splash is the branded Maze animation
	# shipped on the live ISO (/usr/share/plymouth/themes/maze). All the stock
	# archinstall themes (bgrt, spinner, ...) were intentionally removed so the
	# installer can never select anything other than the Maze boot animation.
	MAZE = 'maze'

	@classmethod
	def from_arg(cls, plymouth: str | None) -> Self | None:
		if plymouth is None:
			return None

		plymouth = plymouth.lower()

		values = [e.value for e in cls]

		if plymouth not in values:
			warn(f'Invalid plymouth value "{plymouth}". Allowed values: {", ".join(values)}')
			sys.exit(1)

		return cls(plymouth)


@dataclass
class BootloaderConfiguration(SubConfig):
	bootloader: Bootloader
	uki: bool = False
	removable: bool = True
	secure_boot: bool = False
	plymouth: PlymouthTheme | None = None

	@override
	def json(self) -> dict[str, Any]:
		data = {
			'bootloader': self.bootloader.json(),
			'uki': self.uki,
			'removable': self.removable,
			'secure_boot': self.secure_boot,
		}

		if self.plymouth is not None:
			data['plymouth'] = self.plymouth.value
		return data

	@override
	def summary(self) -> list[str]:
		out = [tr('Bootloader "{}"').format(self.bootloader.value)]

		if self.uki:
			out.append(tr('UKI enabled'))
		if self.removable:
			out.append(tr('Removable'))
		if self.secure_boot:
			out.append(tr('Secure Boot enabled'))
		if self.plymouth is not None:
			out.append(tr('Plymouth "{}"').format(self.plymouth.value))

		return out

	@classmethod
	def parse_arg(cls, config: dict[str, Any], skip_boot: bool) -> Self:
		bootloader = Bootloader.from_arg(config.get('bootloader', ''), skip_boot)
		uki = config.get('uki', False)
		removable = config.get('removable', True)
		secure_boot = config.get('secure_boot', False)
		plymouth = PlymouthTheme.from_arg(config.get('plymouth', None))
		return cls(bootloader=bootloader, uki=uki, removable=removable, secure_boot=secure_boot, plymouth=plymouth)

	@classmethod
	def get_default(cls, uefi: bool, skip_boot: bool = False) -> Self:
		bootloader = Bootloader.get_default(uefi, skip_boot)
		removable = uefi and bootloader.has_removable_support()
		uki = uefi and bootloader.has_uki_support()
		# Maze Linux: Secure Boot is on by default on UEFI systems (the live ISO
		# and the installed system are both signed for shim + MOK). Disabled on
		# BIOS systems where Secure Boot does not apply.
		secure_boot = uefi and bootloader.has_secure_boot_support()
		# Maze Linux: always default to the Maze boot animation (the only theme).
		plymouth = PlymouthTheme.MAZE
		return cls(bootloader=bootloader, uki=uki, removable=removable, secure_boot=secure_boot, plymouth=plymouth)

	def preview(self, uefi: bool) -> str:
		text = f'{tr("Bootloader")}: {self.bootloader.value}'
		text += '\n'
		if uefi and self.bootloader.has_uki_support():
			if self.uki:
				uki_string = tr('Enabled')
			else:
				uki_string = tr('Disabled')
			text += f'UKI: {uki_string}'
			text += '\n'
		if uefi and self.bootloader.has_removable_support():
			if self.removable:
				removable_string = tr('Enabled')
			else:
				removable_string = tr('Disabled')
			text += f'{tr("Removable")}: {removable_string}'
			text += '\n'
		if uefi and self.bootloader.has_secure_boot_support():
			secure_boot_string = tr('Enabled') if self.secure_boot else tr('Disabled')
			text += f'{tr("Secure Boot")}: {secure_boot_string}'
			text += '\n'
		if self.plymouth is not None:
			text += f'{tr("Plymouth")}: {self.plymouth.value}'
			text += '\n'
		return text
