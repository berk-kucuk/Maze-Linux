from typing import override

from archinstall.default_profiles.profile import GreeterType
from archinstall.lib.applications.application_menu import ApplicationMenu
from archinstall.lib.args import ArchConfig
from archinstall.lib.authentication.authentication_menu import AuthenticationMenu
from archinstall.lib.bootloader.bootloader_menu import BootloaderMenu
from archinstall.lib.bootloader.utils import validate_bootloader_layout
from archinstall.lib.configuration import ConfigurationOutput, save_config
from archinstall.lib.disk.disk_menu import DiskLayoutConfigurationMenu
from archinstall.lib.general.general_menu import select_hostname, select_ntp, select_timezone
from archinstall.lib.general.system_menu import select_driver, select_kernel, select_swap
from archinstall.lib.hardware import GfxDriver, SysInfo
from archinstall.lib.locale.locale_menu import LocaleMenu
from archinstall.lib.menu.abstract_menu import AbstractMenu, SpecialMenuKey
from archinstall.lib.mirror.mirror_handler import MirrorListHandler
from archinstall.lib.mirror.mirror_menu import MirrorMenu
from archinstall.lib.models.application import (
	ApplicationConfiguration,
	Audio,
	AudioConfiguration,
	BluetoothConfiguration,
	Firewall,
	FirewallConfiguration,
	PowerManagement,
	PowerManagementConfiguration,
	PrintServiceConfiguration,
	ZramConfiguration,
)
from archinstall.lib.models.authentication import AuthenticationConfiguration
from archinstall.lib.models.bootloader import Bootloader, BootloaderConfiguration
from archinstall.lib.models.device import DiskLayoutConfiguration, DiskLayoutType, PartitionModification
from archinstall.lib.models.locale import LocaleConfiguration
from archinstall.lib.models.mirrors import MirrorConfiguration
from archinstall.lib.models.network import NetworkConfiguration, NicType
from archinstall.lib.models.package_types import DEFAULT_KERNEL
from archinstall.lib.models.packages import Repository
from archinstall.lib.models.pacman import PacmanConfiguration
from archinstall.lib.models.profile import ProfileConfiguration
from archinstall.lib.network.network_menu import select_network
from archinstall.lib.packages.packages import list_available_packages, select_additional_packages
from archinstall.lib.pacman.config import PacmanConfig
from archinstall.lib.pacman.pacman_menu import PacmanMenu
from archinstall.lib.translationhandler import Language, tr, translation_handler
from archinstall.lib.utils.format import as_table
from archinstall.tui.components import tui
from archinstall.tui.menu_item import MenuItem, MenuItemGroup, MsgLevelType, PreviewResult


class GlobalMenu(AbstractMenu[None]):
	def __init__(
		self,
		arch_config: ArchConfig,
		mirror_list_handler: MirrorListHandler | None = None,
		skip_boot: bool = False,
		advanced: bool = False,
		title: str | None = None,
	) -> None:
		self._arch_config = arch_config
		self._mirror_list_handler = mirror_list_handler
		self._skip_boot = skip_boot
		self._advanced = advanced
		self._uefi = SysInfo.has_uefi()
		menu_options = self._get_menu_options()

		self._item_group = MenuItemGroup(
			menu_options,
			sort_items=False,
			checkmarks=True,
		)

		# Maze Linux: a short, friendly guide line under the title bar. It explains
		# the status glyphs (set in archinstall/tui/components.py::_format_label) and
		# the overall flow, so a first-time user is never left guessing.
		header = tr('Configure each step below, then choose Install.   ✓ already set    ● still required')

		super().__init__(self._item_group, config=arch_config, title=title, header=header)

	def _get_menu_options(self) -> list[MenuItem]:
		menu_options = [
			MenuItem(
				text=tr('Installer language'),
				action=self._select_archinstall_language,
				preview_action=self._prev_archinstall_language,
				key='archinstall_language',
			),
			MenuItem(
				text=tr('Locales'),
				value=LocaleConfiguration.default(),
				action=self._locale_selection,
				preview_action=self._prev_locale,
				key='locale_config',
			),
			MenuItem(
				text=tr('Mirrors and repositories'),
				action=self._mirror_configuration,
				preview_action=self._prev_mirror_config,
				key='mirror_config',
			),
			MenuItem(
				text=tr('Disk configuration'),
				action=self._select_disk_config,
				preview_action=self._prev_disk_config,
				mandatory=True,
				key='disk_config',
			),
			MenuItem(
				text=tr('Swap'),
				value=ZramConfiguration(enabled=True),
				action=select_swap,
				preview_action=self._prev_swap,
				key='swap',
			),
			MenuItem(
				text=tr('Bootloader'),
				value=BootloaderConfiguration.get_default(self._uefi, self._skip_boot),
				action=self._select_bootloader_config,
				preview_action=self._prev_bootloader_config,
				key='bootloader_config',
			),
			MenuItem(
				text=tr('Kernels'),
				value=[DEFAULT_KERNEL],
				action=select_kernel,
				preview_action=self._prev_kernel,
				mandatory=True,
				key='kernels',
			),
			MenuItem(
				text=tr('Hostname'),
				value='maze',
				action=select_hostname,
				preview_action=self._prev_hostname,
				key='hostname',
			),
			MenuItem(
				text=tr('Authentication'),
				action=self._select_authentication,
				preview_action=self._prev_authentication,
				key='auth_config',
			),
			# Maze Linux: there is exactly one desktop (KDE Plasma) and one greeter
			# (plasma-login-manager), both fixed — so the old "Profile" submenu
			# (Type / Graphics driver / Greeter) is collapsed into a single
			# "Graphics driver" entry. The profile is pre-set to the Maze KDE Plasma
			# desktop with its default greeter, so the desktop installs even if the
			# user never opens this item; selecting it only asks for the GPU driver.
			MenuItem(
				text=tr('Graphics driver'),
				action=self._select_gfx_driver,
				value=self._default_profile_config(),
				preview_action=self._prev_gfx_driver,
				key='profile_config',
			),
			# Maze Linux: the application stack is fixed, so the Applications picker
			# is hidden (enabled=False) and pre-set to the Maze defaults — Bluetooth,
			# PipeWire audio, firewalld, power-profiles-daemon and printing are all
			# enabled. The value still syncs to the config, so install_applications()
			# sets these up automatically.
			MenuItem(
				text=tr('Applications'),
				action=self._select_applications,
				value=ApplicationConfiguration(
					bluetooth_config=BluetoothConfiguration(enabled=True),
					audio_config=AudioConfiguration(Audio.PIPEWIRE),
					power_management_config=PowerManagementConfiguration(PowerManagement.POWER_PROFILES_DAEMON),
					print_service_config=PrintServiceConfiguration(enabled=True),
					firewall_config=FirewallConfiguration(Firewall.FWD),
				),
				preview_action=self._prev_applications,
				key='app_config',
				enabled=False,
			),
			# Maze Linux: networking is fixed to NetworkManager (the default
			# backend) — every Maze install ships and relies on it, so there is no
			# reason to ask. The item is kept (so its value still syncs to the
			# config) but hidden via enabled=False, with NicType.NM as the value so
			# install_network_config() sets up NetworkManager automatically.
			MenuItem(
				text=tr('Network configuration'),
				action=select_network,
				value=NetworkConfiguration(NicType.NM),
				preview_action=self._prev_network_config,
				key='network_config',
				enabled=False,
			),
			# Maze Linux: the only thing the Pacman menu really asks is the `color`
			# option, which we always want on. PacmanConfiguration.default() already
			# has color=True (and parallel_downloads=5), so the menu is hidden via
			# enabled=False while its value still syncs to the config.
			MenuItem(
				text=tr('Pacman'),
				action=self._pacman_configuration,
				value=PacmanConfiguration.default(),
				preview_action=self._prev_pacman_config,
				key='pacman_config',
				enabled=False,
			),
			# Maze Linux: the curated package set is fixed (see the Plasma profile's
			# MAZE_PACKAGES), so the free-form "Additional packages" picker is
			# removed to keep the installer simple. Hidden via enabled=False with an
			# empty value so nothing extra is installed.
			MenuItem(
				text=tr('Additional packages'),
				action=self._select_additional_packages,
				value=[],
				preview_action=self._prev_additional_pkgs,
				key='packages',
				enabled=False,
			),
			MenuItem(
				text=tr('Timezone'),
				action=select_timezone,
				value='UTC',
				preview_action=self._prev_tz,
				key='timezone',
			),
			MenuItem(
				text=tr('Automatic time sync (NTP)'),
				action=select_ntp,
				value=True,
				preview_action=self._prev_ntp,
				key='ntp',
			),
			MenuItem(
				text='',
				read_only=True,
			),
			MenuItem(
				text=tr('Save configuration'),
				action=lambda x: self._safe_config(),
				key=SpecialMenuKey.SAVE.value,
			),
			MenuItem(
				text=tr('Install'),
				preview_action=self._prev_install_invalid_config,
				key=SpecialMenuKey.INSTALL.value,
			),
			MenuItem(
				text=tr('Abort'),
				key=SpecialMenuKey.ABORT.value,
			),
		]

		return menu_options

	async def _safe_config(self) -> None:
		# data: dict[str, Any] = {}
		# for item in self._item_group.items:
		# if item.key is not None:
		# data[item.key] = item.value

		self.sync_all_to_config()
		await save_config(self._arch_config)

	def _missing_configs(self) -> list[str]:
		item: MenuItem = self._item_group.find_by_key('auth_config')
		auth_config: AuthenticationConfiguration | None = item.value

		def check(s: str) -> bool:
			item = self._item_group.find_by_key(s)
			return item.has_value()

		missing = set()

		if (auth_config is None or auth_config.root_enc_password is None) and not (auth_config and auth_config.has_superuser()):
			missing.add(
				tr('Either root-password or at least 1 user with sudo privileges must be specified'),
			)

		# These greeters only show users with UID >= 1000 and have no manual login by default
		if not (auth_config and auth_config.has_regular_user()):
			profile_item: MenuItem = self._item_group.find_by_key('profile_config')
			profile_config: ProfileConfiguration | None = profile_item.value

			if profile_config and profile_config.profile and profile_config.profile.is_desktop_profile():
				problematic_greeters = {GreeterType.Sddm}
				if any(p.default_greeter_type in problematic_greeters for p in profile_config.profile.current_selection):
					missing.add(
						tr('The selected desktop profile requires a regular user to log in via the greeter'),
					)

		for item in self._item_group.items:
			if item.mandatory:
				assert item.key is not None
				if not check(item.key):
					missing.add(item.text)

		return list(missing)

	@override
	def is_config_valid(self) -> bool:
		"""
		Checks the validity of the current configuration.
		"""
		if len(self._missing_configs()) != 0:
			return False
		return self._validate_bootloader() is None

	async def _select_archinstall_language(self, preset: Language) -> Language:
		from archinstall.lib.general.general_menu import select_archinstall_language

		language = await select_archinstall_language(translation_handler.translated_languages, preset)
		translation_handler.activate(language)

		self._update_lang_text()

		return language

	def _prev_archinstall_language(self, item: MenuItem) -> str | None:
		if not item.value:
			return None

		lang: Language = item.value
		return f'{tr("Language")}: {lang.display_name}'

	async def _select_applications(self, preset: ApplicationConfiguration | None) -> ApplicationConfiguration | None:
		app_config = await ApplicationMenu(preset).show()
		return app_config

	async def _select_authentication(self, preset: AuthenticationConfiguration | None) -> AuthenticationConfiguration | None:
		auth_config = await AuthenticationMenu(preset).show()
		return auth_config

	def _update_lang_text(self) -> None:
		"""
		The options for the global menu are generated with a static text;
		each entry of the menu needs to be updated with the new translation
		"""
		new_options = self._get_menu_options()

		for o in new_options:
			if o.key is not None:
				self._item_group.find_by_key(o.key).text = o.text

		tui.translate_bindings()

	async def _locale_selection(self, preset: LocaleConfiguration) -> LocaleConfiguration | None:
		locale_config = await LocaleMenu(preset).show()
		return locale_config

	def _prev_locale(self, item: MenuItem) -> str | None:
		if not item.value:
			return None

		config: LocaleConfiguration = item.value
		return config.preview()

	def _prev_network_config(self, item: MenuItem) -> str | None:
		if item.value:
			network_config: NetworkConfiguration = item.value
			if network_config.type == NicType.MANUAL:
				output = as_table(network_config.nics)
			else:
				output = f'{tr("Network configuration")}:\n{network_config.type.display_msg()}'

			return output
		return None

	def _prev_additional_pkgs(self, item: MenuItem) -> str | None:
		if item.value:
			output = '\n'.join(sorted(item.value))
			return output
		return None

	def _prev_authentication(self, item: MenuItem) -> str | None:
		if item.value:
			auth_config: AuthenticationConfiguration = item.value
			output = ''

			if auth_config.root_enc_password:
				output += f'{tr("Root password")}: {auth_config.root_enc_password.hidden()}\n'

			if auth_config.users:
				output += as_table(auth_config.users) + '\n'

			if auth_config.u2f_config:
				u2f_config = auth_config.u2f_config
				login_method = u2f_config.u2f_login_method.display_value()
				output = tr('U2F login method: ') + login_method

				output += '\n'
				output += tr('Passwordless sudo: ') + (tr('Enabled') if u2f_config.passwordless_sudo else tr('Disabled'))

			return output

		return None

	def _prev_applications(self, item: MenuItem) -> str | None:
		if item.value:
			app_config: ApplicationConfiguration = item.value
			output = ''

			if app_config.bluetooth_config:
				output += f'{tr("Bluetooth")}: '
				output += tr('Enabled') if app_config.bluetooth_config.enabled else tr('Disabled')
				output += '\n'

			if app_config.audio_config:
				audio_config = app_config.audio_config
				output += f'{tr("Audio")}: {audio_config.audio.value}'
				output += '\n'

			if app_config.print_service_config:
				output += f'{tr("Print service")}: '
				output += tr('Enabled') if app_config.print_service_config.enabled else tr('Disabled')
				output += '\n'

			if app_config.power_management_config:
				power_management_config = app_config.power_management_config
				output += f'{tr("Power management")}: {power_management_config.power_management.value}'
				output += '\n'

			if app_config.firewall_config:
				firewall_config = app_config.firewall_config
				output += f'{tr("Firewall")}: {firewall_config.firewall.value}'
				output += '\n'

			return output

		return None

	def _prev_tz(self, item: MenuItem) -> str | None:
		if item.value:
			return f'{tr("Timezone")}: {item.value}'
		return None

	def _prev_ntp(self, item: MenuItem) -> str | None:
		if item.value is not None:
			output = f'{tr("NTP")}: '
			output += tr('Enabled') if item.value else tr('Disabled')
			return output
		return None

	def _prev_disk_config(self, item: MenuItem) -> str | None:
		disk_layout_conf: DiskLayoutConfiguration | None = item.value

		if disk_layout_conf:
			output = tr('Configuration type: {}').format(disk_layout_conf.config_type.display_msg()) + '\n'

			if disk_layout_conf.config_type == DiskLayoutType.Pre_mount:
				output += tr('Mountpoint') + ': ' + str(disk_layout_conf.mountpoint)

			if disk_layout_conf.lvm_config:
				output += '{}: {}'.format(tr('LVM configuration type'), disk_layout_conf.lvm_config.config_type.display_msg()) + '\n'

			if disk_layout_conf.disk_encryption:
				output += tr('Disk encryption') + ': ' + disk_layout_conf.disk_encryption.encryption_type.type_to_text() + '\n'

			if disk_layout_conf.btrfs_options:
				btrfs_options = disk_layout_conf.btrfs_options
				if btrfs_options.snapshot_config:
					output += tr('Btrfs snapshot type: {}').format(btrfs_options.snapshot_config.snapshot_type.value) + '\n'

			return output

		return None

	def _prev_swap(self, item: MenuItem) -> str | None:
		if item.value is not None:
			output = f'{tr("Swap on zram")}: '
			output += tr('Enabled') if item.value.enabled else tr('Disabled')
			if item.value.enabled:
				output += f'\n{tr("Compression algorithm")}: {item.value.algorithm.value}'
			return output
		return None

	def _prev_hostname(self, item: MenuItem) -> str | None:
		if item.value is not None:
			return f'{tr("Hostname")}: {item.value}'
		return None

	async def _pacman_configuration(self, preset: PacmanConfiguration) -> PacmanConfiguration | None:
		return await PacmanMenu(preset, advanced=self._advanced).show()

	def _prev_pacman_config(self, item: MenuItem) -> str | None:
		if not item.value:
			return None
		config: PacmanConfiguration = item.value
		output = ''
		if self._advanced:
			output += '{}: {}\n'.format(tr('Parallel Downloads'), config.parallel_downloads)
		output += '{}: {}'.format(tr('Color'), config.color)
		return output

	def _prev_kernel(self, item: MenuItem) -> str | None:
		if item.value:
			kernel = ', '.join(item.value)
			return f'{tr("Kernel")}: {kernel}'
		return None

	def _prev_bootloader_config(self, item: MenuItem) -> str | None:
		bootloader_config: BootloaderConfiguration | None = item.value
		if bootloader_config:
			return bootloader_config.preview(self._uefi)
		return None

	def _validate_bootloader(self) -> str | None:
		"""
		Checks the selected bootloader is valid for the selected filesystem
		type of the boot partition.

		Returns [`None`] if the bootloader is valid, otherwise returns a
		string with the error message.
		"""
		bootloader_config: BootloaderConfiguration | None = None
		root_partition: PartitionModification | None = None
		boot_partition: PartitionModification | None = None
		efi_partition: PartitionModification | None = None

		bootloader_config = self._item_group.find_by_key('bootloader_config').value

		if not bootloader_config or bootloader_config.bootloader == Bootloader.NO_BOOTLOADER:
			return None

		if disk_config := self._item_group.find_by_key('disk_config').value:
			for layout in disk_config.device_modifications:
				if root_partition := layout.get_root_partition():
					break
			for layout in disk_config.device_modifications:
				if boot_partition := layout.get_boot_partition():
					break
			if self._uefi:
				for layout in disk_config.device_modifications:
					if efi_partition := layout.get_efi_partition():
						break
		else:
			return 'No disk layout selected'

		if root_partition is None:
			return 'Root partition not found'

		if boot_partition is None:
			return 'Boot partition not found'

		if self._uefi:
			if efi_partition is None:
				return 'EFI system partition (ESP) not found'

			if efi_partition.fs_type is None or not efi_partition.fs_type.is_fat():
				return 'ESP must be formatted as a FAT filesystem'

		if failure := validate_bootloader_layout(bootloader_config, disk_config):
			return failure.description

		return None

	def _get_install_warnings(self) -> list[str]:
		warnings: list[str] = []

		if not isinstance(self._arch_config.network_config, NetworkConfiguration):
			warnings.append(tr('No network configuration selected. Network will need to be set up manually on the installed system.'))

		return warnings

	def _prev_install_invalid_config(self, item: MenuItem) -> PreviewResult | None:
		self.sync_all_to_config()
		config_output = ConfigurationOutput(self._arch_config)

		warnings = self._get_install_warnings()
		messages: list[tuple[str, MsgLevelType]] = []

		errors = ''
		if missing := self._missing_configs():
			errors += f'{tr("Missing configurations:")}\n'
			errors += '\n'.join(f'- {m}' for m in missing)

		disk_item = self._item_group.find_by_key('disk_config')
		if disk_item.has_value():
			if error := self._validate_bootloader():
				if errors:
					errors += '\n\n'
				errors += f'{tr("Invalid configuration:")}\n- {error}'

		if errors:
			messages.append((errors, MsgLevelType.MsgError))
		else:
			messages.append((tr('Ready to install'), MsgLevelType.MsgInfo))

		if warnings:
			text = f'{tr("Warnings:")}\n' + '\n'.join(f'- {w}' for w in warnings)
			messages.append((text, MsgLevelType.MsgWarning))

		if not errors:
			summary = config_output.as_summary()
			if summary:
				messages.append((summary, MsgLevelType.MsgNone))

		return PreviewResult(messages)

	def _prev_profile(self, item: MenuItem) -> str | None:
		profile_config: ProfileConfiguration | None = item.value

		if profile_config and profile_config.profile:
			output = tr('Profiles') + ': '
			if profile_names := profile_config.profile.current_selection_names():
				output += ', '.join(profile_names) + '\n'
			else:
				output += profile_config.profile.name + '\n'

			if profile_config.gfx_driver:
				output += tr('Graphics driver') + ': ' + profile_config.gfx_driver.value + '\n'

			if profile_config.greeter:
				output += tr('Greeter') + ': ' + profile_config.greeter.value + '\n'

			return output

		return None

	async def _select_disk_config(
		self,
		preset: DiskLayoutConfiguration | None = None,
	) -> DiskLayoutConfiguration | None:
		disk_config = await DiskLayoutConfigurationMenu(preset).show()
		return disk_config

	async def _select_bootloader_config(
		self,
		preset: BootloaderConfiguration | None = None,
	) -> BootloaderConfiguration | None:
		if preset is None:
			preset = BootloaderConfiguration.get_default(self._uefi, self._skip_boot)

		bootloader_config = await BootloaderMenu(preset, self._uefi, self._skip_boot).show()

		return bootloader_config

	def _default_profile_config(self) -> ProfileConfiguration:
		# Maze Linux: the fixed Maze desktop = the single "KDE Plasma" top-level
		# profile (a DesktopProfile with Plasma preselected). The greeter defaults
		# to the profile's own default (plasma-login-manager) and the GPU driver to
		# the all-open-source set, which the user can change via the menu.
		from archinstall.lib.profile.profiles_handler import profile_handler

		profile = profile_handler.get_top_level_profiles()[0]
		return ProfileConfiguration(
			profile=profile,
			gfx_driver=GfxDriver.AllOpenSource,
			greeter=profile.default_greeter_type,
		)

	def _prev_gfx_driver(self, item: MenuItem) -> str | None:
		# Maze Linux: the "Graphics driver" entry only configures the GPU driver,
		# so its preview shows just the driver (and its packages) — not the fixed
		# KDE Plasma profile / greeter (which _prev_profile would also list).
		profile_config: ProfileConfiguration | None = item.value

		if profile_config and profile_config.gfx_driver:
			driver = profile_config.gfx_driver
			text = tr('Graphics driver') + ': ' + driver.value
			if packages := driver.packages_text():
				text += '\n' + packages
			return text

		return None

	async def _select_gfx_driver(self, current_profile: ProfileConfiguration | None) -> ProfileConfiguration | None:
		# Maze Linux: only the GPU driver is asked; the profile + greeter stay
		# fixed. We keep the preset ProfileConfiguration and just update its driver.
		profile_config = current_profile or self._default_profile_config()

		driver = await select_driver(preset=profile_config.gfx_driver)
		if driver is not None:
			profile_config.gfx_driver = driver

		return profile_config

	async def _select_additional_packages(self, preset: list[str]) -> list[str]:
		config: MirrorConfiguration | None = self._item_group.find_by_key('mirror_config').value

		repositories: set[Repository] = set()
		if config:
			repositories = set(config.optional_repositories)

		packages = await select_additional_packages(
			preset,
			repositories=repositories,
		)

		return packages

	async def _mirror_configuration(self, preset: MirrorConfiguration | None = None) -> MirrorConfiguration | None:
		if self._mirror_list_handler is None:
			self._mirror_list_handler = MirrorListHandler()

		mirror_configuration = await MirrorMenu(self._mirror_list_handler, preset=preset).run()

		if mirror_configuration and mirror_configuration.optional_repositories:
			# reset the package list cache in case the repository selection has changed
			list_available_packages.cache_clear()

			# enable the repositories in the config
			pacman_config = PacmanConfig(None)
			pacman_config.enable(mirror_configuration.optional_repositories)
			pacman_config.apply()

		return mirror_configuration

	def _prev_mirror_config(self, item: MenuItem) -> str | None:
		if not item.value:
			return None

		mirror_config: MirrorConfiguration = item.value

		output = ''
		if mirror_config.mirror_regions:
			title = tr('Selected mirror regions')
			divider = '-' * len(title)
			regions = mirror_config.region_names
			output += f'{title}\n{divider}\n{regions}\n\n'

		if mirror_config.custom_servers:
			title = tr('Custom servers')
			divider = '-' * len(title)
			servers = mirror_config.custom_server_urls
			output += f'{title}\n{divider}\n{servers}\n\n'

		if mirror_config.optional_repositories:
			title = tr('Optional repositories')
			divider = '-' * len(title)
			repos = ', '.join(r.value for r in mirror_config.optional_repositories)
			output += f'{title}\n{divider}\n{repos}\n\n'

		if mirror_config.custom_repositories:
			title = tr('Custom repositories')
			table = as_table(mirror_config.custom_repositories)
			output += f'{title}:\n\n{table}'

		return output.strip()
