import os
import sys
import time

from archinstall.lib.applications.application_handler import ApplicationHandler
from archinstall.lib.args import ArchConfig, ArchConfigHandler
from archinstall.lib.authentication.authentication_handler import AuthenticationHandler
from archinstall.lib.bootloader.utils import validate_bootloader_layout
from archinstall.lib.configuration import ConfigurationOutput
from archinstall.lib.disk.filesystem import FilesystemHandler
from archinstall.lib.disk.utils import disk_layouts
from archinstall.lib.general.general_menu import PostInstallationAction, select_post_installation
from archinstall.lib.global_menu import GlobalMenu
from archinstall.lib.installer import Installer, accessibility_tools_in_use, run_custom_user_commands
from archinstall.lib.log import debug, error, info
from archinstall.lib.menu.util import delayed_warning
from archinstall.lib.mirror.mirror_handler import MirrorListHandler
from archinstall.lib.models import Bootloader
from archinstall.lib.models.device import DiskLayoutType, EncryptionType
from archinstall.lib.models.users import User
from archinstall.lib.network.network_handler import install_network_config
from archinstall.lib.profile.profiles_handler import profile_handler
from archinstall.lib.translationhandler import tr
from archinstall.tui.components import tui


def show_menu(
	arch_config_handler: ArchConfigHandler,
	mirror_list_handler: MirrorListHandler,
) -> None:
	# Maze Linux is not upstream archinstall, so there is no "latest archinstall
	# version" to check for — skip that online lookup entirely. It was also a big
	# part of the silent startup delay on first run.
	info('Building the installer menu...')
	# Branded title bar shown docked at the top of every menu (see the
	# .app-header style in archinstall/tui/components.py).
	title_text = '◆  MAZE LINUX  ·  Installer'

	global_menu = GlobalMenu(
		arch_config_handler.config,
		mirror_list_handler,
		arch_config_handler.args.skip_boot,
		advanced=arch_config_handler.args.advanced,
		title=title_text,
	)

	result: ArchConfig | None = tui.run(global_menu)
	if result is None:
		sys.exit(0)


def perform_installation(
	arch_config_handler: ArchConfigHandler,
	mirror_list_handler: MirrorListHandler,
	auth_handler: AuthenticationHandler,
	application_handler: ApplicationHandler,
) -> None:
	"""
	Performs the installation steps on a block device.
	Only requirement is that the block devices are
	formatted and setup prior to entering this function.
	"""
	start_time = time.monotonic()
	info('Starting installation...')

	# Maze Linux: print a prominent banner before each major stage so the user
	# can follow progress during the (long) install — especially while the
	# desktop/AUR deployment builds packages. The verbose log lines still stream
	# underneath; these banners just punctuate the stages with a running count.
	stage_no = 0

	def stage(title: str) -> None:
		nonlocal stage_no
		stage_no += 1
		info(f'━━━━━  Stage {stage_no}:  {title}  ━━━━━')

	mountpoint = arch_config_handler.args.mountpoint
	config = arch_config_handler.config

	if not config.disk_config:
		error('No disk configuration provided')
		return

	disk_config = config.disk_config
	run_mkinitcpio = not config.bootloader_config or not config.bootloader_config.uki
	locale_config = config.locale_config
	optional_repositories = config.mirror_config.optional_repositories if config.mirror_config else []
	mountpoint = disk_config.mountpoint if disk_config.mountpoint else mountpoint

	with Installer(
		mountpoint,
		disk_config,
		kernels=config.kernels,
		silent=arch_config_handler.args.silent,
	) as installation:
		# Mount all the drives to the desired mountpoint
		if disk_config.config_type != DiskLayoutType.Pre_mount:
			installation.mount_ordered_layout()

		installation.sanity_check(
			arch_config_handler.args.offline,
			arch_config_handler.args.skip_ntp,
			arch_config_handler.args.skip_wkd,
		)

		if disk_config.config_type != DiskLayoutType.Pre_mount:
			if disk_config.disk_encryption and disk_config.disk_encryption.encryption_type != EncryptionType.NO_ENCRYPTION:
				# generate encryption key files for the mounted luks devices
				installation.generate_key_files()

		if mirror_config := config.mirror_config:
			installation.set_mirrors(mirror_list_handler, mirror_config, on_target=False)

		stage(tr('Installing the base system'))
		installation.minimal_installation(
			optional_repositories=optional_repositories,
			mkinitcpio=run_mkinitcpio,
			hostname=arch_config_handler.config.hostname,
			locale_config=locale_config,
			pacman_config=config.pacman_config,
		)

		if mirror_config := config.mirror_config:
			installation.set_mirrors(mirror_list_handler, mirror_config, on_target=True)

		if config.swap and config.swap.enabled:
			stage(tr('Configuring swap (zram)'))
			installation.setup_swap(algo=config.swap.algorithm)

		# Maze Linux: install the graphics driver BEFORE the bootloader. For the
		# proprietary Nvidia driver this lets install_gfx_driver() register the
		# nvidia early-KMS modules (nvidia nvidia_modeset nvidia_uvm nvidia_drm) and
		# the nvidia_drm.modeset=1 kernel parameter on the installer state, so that
		# add_bootloader() bakes them into every UKI/boot entry and the DKMS modules
		# already exist when mkinitcpio builds the initramfs. Doing this after the
		# bootloader (the old behaviour) meant the modules and kernel params were
		# never written for any selected kernel. It is skipped again in
		# install_profile_config() to avoid a redundant pacman transaction.
		gfx_driver_installed = False
		if (profile_config := config.profile_config) and profile_config.gfx_driver:
			profile = profile_config.profile
			if profile and (profile.is_xorg_type_profile() or profile.is_desktop_profile()):
				stage(tr('Installing the graphics driver'))
				profile_handler.install_gfx_driver(installation, profile_config.gfx_driver)
				gfx_driver_installed = True

		if config.bootloader_config and config.bootloader_config.bootloader != Bootloader.NO_BOOTLOADER:
			stage(tr('Installing the bootloader'))
			installation.add_bootloader(
				config.bootloader_config.bootloader,
				config.bootloader_config.uki,
				config.bootloader_config.removable,
				config.bootloader_config.plymouth,
				config.bootloader_config.secure_boot,
			)

		if config.network_config:
			stage(tr('Setting up the network (NetworkManager)'))
			install_network_config(
				config.network_config,
				installation,
				config.profile_config,
			)

		users = None
		if config.auth_config:
			if config.auth_config.users:
				stage(tr('Creating user accounts'))
				users = config.auth_config.users
				installation.create_users(config.auth_config.users)
				auth_handler.setup_auth(installation, config.auth_config, config.hostname)

		if app_config := config.app_config:
			stage(tr('Installing applications'))
			application_handler.install_applications(installation, app_config)

		if profile_config := config.profile_config:
			stage(tr('Installing the KDE Plasma desktop and Maze applications'))
			profile_handler.install_profile_config(installation, profile_config, skip_gfx_driver=gfx_driver_installed)

		if config.packages and config.packages[0] != '':
			installation.add_additional_packages(config.packages)

		if timezone := config.timezone:
			installation.set_timezone(timezone)

		if config.ntp:
			installation.activate_time_synchronization()

		if accessibility_tools_in_use():
			installation.enable_espeakup()

		if config.auth_config and config.auth_config.root_enc_password:
			root_user = User('root', config.auth_config.root_enc_password, False)
			installation.set_user_password(root_user)

		if (profile_config := config.profile_config) and profile_config.profile:
			# This is the slow stage: deploy-to-target replicates the live system
			# and builds the Maze AUR packages, which can take a while.
			stage(tr('Deploying Maze configuration and building AUR packages (this can take a while)'))
			profile_config.profile.post_install(installation)

			if users:
				profile_config.profile.provision(installation, users)

		stage(tr('Finalizing the installation'))

		# If the user provided a list of services to be enabled, pass the list to the enable_service function.
		# Note that while it's called enable_service, it can actually take a list of services and iterate it.
		if services := config.services:
			installation.enable_service(services)

		if disk_config.has_default_btrfs_vols():
			btrfs_options = disk_config.btrfs_options
			snapshot_config = btrfs_options.snapshot_config if btrfs_options else None
			snapshot_type = snapshot_config.snapshot_type if snapshot_config else None
			if snapshot_type:
				bootloader = config.bootloader_config.bootloader if config.bootloader_config else None
				installation.setup_btrfs_snapshot(snapshot_type, bootloader)

		# If the user provided custom commands to be run post-installation, execute them now.
		if cc := config.custom_commands:
			run_custom_user_commands(cc, installation)

		installation.genfstab()

		# Maze Linux: re-sign the bootloader/UKI one last time, after every step
		# that could have regenerated the unified kernel image (desktop/AUR package
		# installs trigger mkinitcpio). Otherwise systemd-boot rejects a freshly
		# regenerated, unsigned UKI under Secure Boot ("Security violation").
		if config.bootloader_config and config.bootloader_config.secure_boot:
			installation.resign_secure_boot()

		debug(f'Disk states after installing:\n{disk_layouts()}')

		if not arch_config_handler.args.silent:
			elapsed_time = time.monotonic() - start_time
			action: PostInstallationAction = tui.run(lambda: select_post_installation(elapsed_time))

			match action:
				case PostInstallationAction.EXIT:
					pass
				case PostInstallationAction.REBOOT:
					_ = os.system('reboot')  # type: ignore[deprecated]
				case PostInstallationAction.CHROOT:
					try:
						installation.drop_to_shell()
					except Exception:
						pass


def main(arch_config_handler: ArchConfigHandler | None = None) -> None:
	if arch_config_handler is None:
		arch_config_handler = ArchConfigHandler()

	info('Loading the Arch mirror list...')
	mirror_list_handler = MirrorListHandler(
		offline=arch_config_handler.args.offline,
		verbose=arch_config_handler.args.verbose,
	)

	if not arch_config_handler.args.silent:
		show_menu(arch_config_handler, mirror_list_handler)

	config = ConfigurationOutput(arch_config_handler.config)
	config.write_debug()
	config.save()

	# Safety net for silent/config-file flow. The TUI menu blocks Install via
	# GlobalMenu._validate_bootloader() before reaching this point.
	if failure := validate_bootloader_layout(
		arch_config_handler.config.bootloader_config,
		arch_config_handler.config.disk_config,
	):
		error(failure.description)
		return

	if arch_config_handler.args.dry_run:
		return

	if not arch_config_handler.args.silent:
		aborted = False
		res: bool = tui.run(config.confirm_config)

		if not res:
			debug('Installation aborted')
			aborted = True

		if aborted:
			return main(arch_config_handler)

	if arch_config_handler.config.disk_config:
		fs_handler = FilesystemHandler(arch_config_handler.config.disk_config)

		if not delayed_warning(tr('Starting device modifications in ')):
			return main()

		fs_handler.perform_filesystem_operations()

	perform_installation(
		arch_config_handler,
		mirror_list_handler,
		AuthenticationHandler(),
		ApplicationHandler(),
	)


if __name__ == '__main__':
	main()
