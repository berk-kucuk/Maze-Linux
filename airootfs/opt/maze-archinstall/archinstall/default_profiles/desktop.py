from typing import TYPE_CHECKING, Self, override

from archinstall.default_profiles.desktops.utils import provision_seat_access
from archinstall.default_profiles.profile import CustomSetting, DisplayServerType, GreeterType, Profile, ProfileType, SelectResult
from archinstall.lib.log import info
from archinstall.lib.profile.profiles_handler import profile_handler

if TYPE_CHECKING:
	from archinstall.lib.installer import Installer
	from archinstall.lib.models.users import User


class DesktopProfile(Profile):
	def __init__(self, current_selection: list[Self] = []) -> None:
		super().__init__(
			'Desktop',
			ProfileType.Desktop,
			current_selection=current_selection,
			support_greeter=True,
		)

	@property
	@override
	def packages(self) -> list[str]:
		return [
			'nano',
			'vim',
			'openssh',
			'htop',
			'wget',
			'smartmontools',
			'xdg-utils',
		]

	@property
	@override
	def default_greeter_type(self) -> GreeterType | None:
		combined_greeters: dict[GreeterType, int] = {}
		for profile in self.current_selection:
			if profile.default_greeter_type:
				combined_greeters.setdefault(profile.default_greeter_type, 0)
				combined_greeters[profile.default_greeter_type] += 1

		if len(combined_greeters) >= 1:
			return list(combined_greeters)[0]

		return None

	async def _do_on_select_profiles(self) -> None:
		for profile in self.current_selection:
			await profile.do_on_select()

	@override
	async def do_on_select(self) -> SelectResult:
		# Maze Linux: KDE Plasma is the only supported desktop, so the multi-select
		# desktop-environment picker is redundant. Skip it: ensure Plasma is the
		# current selection and run its own sub-selections (flavor / Maze apps /
		# security). This makes the single "KDE Plasma" top-level entry go straight
		# to the Plasma configuration instead of through a one-item list.
		if not self.current_selection:
			self.current_selection = profile_handler.get_desktop_profiles()

		await self._do_on_select_profiles()
		return SelectResult.NewSelection

	@override
	def post_install(self, install_session: Installer) -> None:
		for profile in self.current_selection:
			profile.post_install(install_session)

	@override
	def provision(self, install_session: Installer, users: list[User]) -> None:
		for profile in self.current_selection:
			profile.provision(install_session, users)

			if seat_access := profile.custom_settings.get(CustomSetting.SeatAccess):
				provision_seat_access(install_session, users, seat_access)

	@override
	def install(self, install_session: Installer) -> None:
		# Install common packages for all desktop environments
		install_session.add_additional_packages(self.packages)

		xorg_installed = False

		for profile in self.current_selection:
			info(f'Installing profile {profile.name}...')

			install_session.add_additional_packages(profile.packages)
			install_session.enable_service(profile.services)

			if not xorg_installed and profile.display_server == DisplayServerType.Xorg:
				install_session.add_additional_packages(['xorg-server', 'xorg-xinit'])
				xorg_installed = True

			profile.install(install_session)
