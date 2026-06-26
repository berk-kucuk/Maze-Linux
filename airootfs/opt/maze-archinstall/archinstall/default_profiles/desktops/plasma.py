from enum import StrEnum
from typing import TYPE_CHECKING, override

from archinstall.default_profiles.profile import CustomSetting, DisplayServerType, GreeterType, Profile, ProfileType
from archinstall.lib.command import SysCommand
from archinstall.lib.log import error, info

if TYPE_CHECKING:
	from archinstall.lib.installer import Installer

# Script (shipped on the live ISO) that replicates the live configuration onto
# the freshly installed system.
MAZE_DEPLOY_SCRIPT = '/usr/share/maze/install/deploy-to-target.sh'

# Maze's own AUR applications, offered as a selectable menu (all on by default).
MAZE_APPS = [
	'entropy-shield',
	'qlam',
	'maze',
	'hazedrop',
	'haze',
	'linux-chan-ai',
	'sentinai',
]

# Maze Linux: the security/hardening features shown in the installer's
# "Security" section. Each entry is (key, human label). The packages themselves
# are always installed with the desktop; the selection here controls which
# security services get *enabled* (and which UIs autostart) on the installed
# system. All are selected by default. The keys are passed verbatim to
# deploy-to-target.sh, which maps them to systemd services / autostart entries.
MAZE_SECURITY: list[tuple[str, str]] = [
	('opensnitch', 'OpenSnitch — interactive application firewall'),
	('firewalld', 'firewalld — network firewall'),
	('apparmor', 'AppArmor — mandatory access control'),
	('auditd', 'auditd — security auditing'),
	('fail2ban', 'Fail2ban — brute-force protection'),
	('clamav', 'ClamAV — antivirus engine'),
	('rkhunter', 'rkhunter — rootkit scanner'),
	('macchanger', 'MAC address randomization'),
]

# Maze Linux: official-repo packages installed on top of KDE Plasma so an
# installed system matches the live ISO (security/privacy/AI + curated apps).
# AUR-only tools (maze, qlam, brave-bin, ...) are handled separately.
MAZE_PACKAGES: list[str] = [
	# KDE applications
	'konsole', 'dolphin', 'dolphin-plugins', 'ark', 'kate', 'gwenview', 'okular',
	'kcalc', 'kfind', 'kwalletmanager', 'filelight', 'partitionmanager',
	'kdeconnect', 'kdeplasma-addons', 'kclock',
	# Security & privacy
	'tor', 'torbrowser-launcher', 'onionshare', 'wireguard-tools',
	'openvpn', 'clamav', 'clamtk', 'firewalld', 'fail2ban', 'apparmor', 'audit',
	'lynis', 'rkhunter', 'macchanger', 'aircrack-ng', 'wireshark-qt',
	'openbsd-netcat', 'opensnitch',
	# AI
	'ollama',
	# Virtualization
	'qemu-full', 'libvirt', 'virt-manager', 'edk2-ovmf', 'vde2', 'dnsmasq',
	# Desktop apps & utilities
	'firefox', 'thunderbird', 'vlc', 'discord', 'bitwarden', 'spotify-launcher',
	'proton-vpn-gtk-app', 'filezilla', 'distrobox', 'btop', 'fastfetch',
	# Gaming (multilib — enabled in the installed system's pacman.conf)
	'steam',
	'btrfs-assistant', 'isoimagewriter', 'bash-completion', 'wget', 'unzip',
	'unrar', 'smartmontools', 'ethtool', 'xsensors', 'acpi', 'acpid',
	'network-manager-applet', 'python-pip', 'python-setuptools', 'flatpak',
	# Firmware updates + Qt6/PySide6 for the Maze welcome app
	'fwupd', 'pyside6', 'linux-headers',
	# Audio: Maze standardizes on PipeWire (PulseAudio is removed from the audio
	# menu, so there is no pulseaudio/pipewire-pulse conflict).
	'pipewire', 'pipewire-alsa', 'pipewire-pulse', 'pipewire-jack', 'wireplumber',
	# Fonts
	'noto-fonts', 'noto-fonts-emoji', 'noto-fonts-cjk', 'ttf-dejavu',
	'ttf-liberation', 'ttf-nerd-fonts-symbols',
	# Graphics (Vulkan + VA-API)
	'vulkan-intel', 'vulkan-radeon', 'vulkan-nouveau', 'vulkan-swrast',
	'vulkan-mesa-layers', 'intel-media-driver',
	# Multimedia codecs
	'gst-plugins-good', 'gst-plugins-bad', 'gst-plugins-ugly', 'gst-libav',
	'ffmpeg',
	# System integration
	'power-profiles-daemon', 'bluez', 'bluez-utils', 'cups', 'plymouth',
	'lm_sensors', 'pciutils', 'xdg-user-dirs', 'xdg-desktop-portal', 'qt6-wayland',
	'xorg-xwayland', 'sof-firmware', 'reflector',
	# Shell + build tools (AUR packages are built with makepkg post-install)
	'zsh', 'base-devel', 'git',
]

# Services enabled on the installed system (units exist because the packages
# above are installed). Networking is left to the installer's network menu.
MAZE_SERVICES: list[str] = [
	'apparmor', 'firewalld', 'fail2ban', 'auditd', 'opensnitchd',
	'ollama', 'acpid', 'power-profiles-daemon', 'smartd', 'libvirtd',
	'bluetooth', 'cups',
]


class PlasmaFlavor(StrEnum):
	Meta = 'plasma-meta'
	Plasma = 'plasma'
	Desktop = 'plasma-desktop'

	def packages(self) -> list[str]:
		match self:
			case PlasmaFlavor.Meta:
				return ['plasma-meta']
			case PlasmaFlavor.Plasma:
				return ['plasma']
			case PlasmaFlavor.Desktop:
				return ['plasma-desktop']


class PlasmaProfile(Profile):
	def __init__(self) -> None:
		super().__init__(
			'KDE Plasma',
			ProfileType.DesktopEnv,
			support_gfx_driver=True,
			display_server=DisplayServerType.Wayland,
		)

	@property
	@override
	def packages(self) -> list[str]:
		flavor_str = self.custom_settings.get(CustomSetting.PlasmaFlavor)

		if flavor_str is not None:
			flavor = PlasmaFlavor(flavor_str)
			base = flavor.packages()
		else:
			base = PlasmaFlavor.Meta.packages()  # use plasma-meta as the recommended default

		# Maze Linux: install the full curated package set on top of Plasma.
		return base + MAZE_PACKAGES

	@property
	@override
	def services(self) -> list[str]:
		# Maze Linux: enable the security/privacy/AI and hardware services.
		return MAZE_SERVICES

	@property
	@override
	def default_greeter_type(self) -> GreeterType:
		# Use KDE's own login manager (plasma-login-manager). It picks up the
		# Plasma desktop theme and wallpaper for the login screen automatically,
		# so the Maze wallpaper shows on the greeter — which the plain SDDM
		# greeter did not do. This is also archinstall's stock default for Plasma.
		return GreeterType.PlasmaLoginManager

	def _selected_maze_apps(self) -> list[str]:
		# Default: all Maze apps selected. Empty string means the user
		# deselected all; only None means "not configured" -> default to all.
		stored = self.custom_settings.get(CustomSetting.MazeApps)
		if stored is None:
			return list(MAZE_APPS)
		return [a for a in stored.split(',') if a]

	def _selected_security(self) -> list[str]:
		# Default: all security features enabled. Empty string means the user
		# turned them all off; None means "not configured" -> default to all.
		stored = self.custom_settings.get(CustomSetting.MazeSecurity)
		if stored is None:
			return [key for key, _ in MAZE_SECURITY]
		return [s for s in stored.split(',') if s]

	@override
	def post_install(self, install_session: 'Installer') -> None:
		# Replicate the live ISO experience onto the installed system: Maze AUR
		# tools, desktop layout/theme, hardening configs, Plymouth and branding.
		# Best-effort — a failure here must not abort a successful installation.
		try:
			info('Maze: deploying live configuration to the installed system...')
			maze_apps = ','.join(self._selected_maze_apps())
			security = ','.join(self._selected_security())
			# Empty positional args must still be passed so $2/$3 line up; quote
			# them so an empty selection does not shift the argument positions.
			# peek_output=True streams the deploy script's progress (including the
			# slow AUR build) to the terminal so the user can see it is working.
			SysCommand(
				f"{MAZE_DEPLOY_SCRIPT} {install_session.target} '{maze_apps}' '{security}'",
				peek_output=True,
			)
		except Exception as exc:
			error(f'Maze: deploy-to-target step failed (system still installed): {exc}')

	@override
	async def do_on_select(self) -> None:
		# Maze Linux: no interactive desktop configuration. KDE Plasma is the only
		# desktop, plasma-meta is always the flavor, and every Maze app + security
		# feature is installed/enabled by default — so the flavor / Maze-apps /
		# security pickers are all skipped. We only lock in the plasma-meta flavor;
		# leaving MazeApps / MazeSecurity unset makes _selected_maze_apps() and
		# _selected_security() fall back to "all", which is exactly the default.
		self.custom_settings[CustomSetting.PlasmaFlavor] = PlasmaFlavor.Meta.value
