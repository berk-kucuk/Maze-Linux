from functools import lru_cache
from pathlib import Path

from archinstall.lib.command import SysCommand
from archinstall.lib.exceptions import ServiceException, SysCallError
from archinstall.lib.log import error
from archinstall.lib.utils.util import running_from_iso


# Maze Linux: every localectl/timedatectl call below talks to systemd-localed /
# systemd-timedated over D-Bus. On some live environments (notably VMware VMs)
# those calls can hang for *minutes* if the daemon is slow to D-Bus-activate.
# `get_kb_layout()` runs at installer-menu construction time, so such a hang made
# the whole installer look frozen on startup ("Building the installer menu..."
# with no further output, no network). We wrap each call in `timeout` so it can
# never block the UI for more than a few seconds; the callers already treat
# failure/empty output as "unknown" and fall back to sensible defaults.
_LOCALECTL_TIMEOUT = 5


def list_keyboard_languages() -> list[str]:
	return (
		SysCommand(
			f'timeout {_LOCALECTL_TIMEOUT} localectl --no-pager list-keymaps',
			environment_vars={'SYSTEMD_COLORS': '0'},
		)
		.decode()
		.splitlines()
	)


def list_locales() -> list[str]:
	locales = []

	with open('/usr/share/i18n/SUPPORTED') as file:
		for line in file:
			if line != 'C.UTF-8 UTF-8\n':
				locales.append(line.rstrip())

	return locales


@lru_cache
def list_console_fonts() -> list[str]:
	directory = Path('/usr/share/kbd/consolefonts')
	fonts = {path.name.split('.')[0] for path in directory.glob('*.gz')}
	return sorted(fonts)


def list_x11_keyboard_languages() -> list[str]:
	return (
		SysCommand(
			f'timeout {_LOCALECTL_TIMEOUT} localectl --no-pager list-x11-keymap-layouts',
			environment_vars={'SYSTEMD_COLORS': '0'},
		)
		.decode()
		.splitlines()
	)


def verify_keyboard_layout(layout: str) -> bool:
	for language in list_keyboard_languages():
		if layout.lower() == language.lower():
			return True
	return False


def verify_x11_keyboard_layout(layout: str) -> bool:
	for language in list_x11_keyboard_languages():
		if layout.lower() == language.lower():
			return True
	return False


def get_kb_layout() -> str:
	try:
		lines = (
			SysCommand(
				f'timeout {_LOCALECTL_TIMEOUT} localectl --no-pager status',
				environment_vars={'SYSTEMD_COLORS': '0'},
			)
			.decode()
			.splitlines()
		)
	except Exception:
		return ''

	vcline = ''
	for line in lines:
		if 'VC Keymap: ' in line:
			vcline = line

	if vcline == '':
		return ''

	layout = vcline.split(': ')[1]
	if not verify_keyboard_layout(layout):
		return ''

	return layout


def set_kb_layout(locale: str) -> bool:
	if not running_from_iso():
		# Skip when running from host - no need to change host keymap
		# The target installation keymap is set via installer.set_keyboard_language()
		return True

	if len(locale.strip()):
		if not verify_keyboard_layout(locale):
			error(f'Invalid keyboard locale specified: {locale}')
			return False

		try:
			SysCommand(f'timeout {_LOCALECTL_TIMEOUT} localectl set-keymap {locale}')
		except SysCallError as err:
			raise ServiceException(f"Unable to set locale '{locale}' for console: {err}")

		return True

	return False


def list_timezones() -> list[str]:
	return (
		SysCommand(
			f'timeout {_LOCALECTL_TIMEOUT} timedatectl --no-pager list-timezones',
			environment_vars={'SYSTEMD_COLORS': '0'},
		)
		.decode()
		.splitlines()
	)
