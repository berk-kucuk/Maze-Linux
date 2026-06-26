#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="mazelinux"
iso_label="MAZE_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Maze Linux <https://mazelinux.berkkucukk.com.tr>"
iso_application="Maze Linux Live/Install Medium"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="maze"
buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
# Compress the squashfs with zstd at the maximum level (22). This gets close to
# xz's ratio (the 14.5 GB uncompressed airootfs drops to roughly 4-5 GB) while
# decompressing far faster than xz — so the live session boots noticeably
# quicker and the build itself is faster than xz too. 1 MiB blocks balance
# ratio against random-access speed. For the absolute smallest image (slower
# build/boot) swap to: ('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M').
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '22' '-b' '1M')
# Bootstrap tarball (unused while buildmodes only contains 'iso'); kept fast.
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '-1')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  ["/usr/local/bin/maze-install"]="0:0:755"
  ["/usr/local/bin/maze-install-gui"]="0:0:755"
  ["/usr/local/bin/mazeinstaller"]="0:0:755"
  ["/usr/local/bin/maze-installer-gui"]="0:0:755"
  ["/usr/local/bin/maze-installer-config"]="0:0:755"
  ["/usr/local/bin/maze-calamares"]="0:0:755"
  ["/usr/local/share/maze/setup-live-user.sh"]="0:0:755"
  ["/usr/local/share/maze/calamares-mount-api.sh"]="0:0:755"
  ["/usr/local/share/maze/set-default-wallpaper.sh"]="0:0:755"
  ["/usr/local/share/maze/enable-services.sh"]="0:0:755"
  ["/usr/share/maze/install/deploy-to-target.sh"]="0:0:755"
  ["/usr/local/bin/mac_anonymizer.py"]="0:0:755"
  ["/usr/local/bin/change-mac-now"]="0:0:755"
  ["/usr/local/bin/mac-changer-logs"]="0:0:755"
  ["/usr/local/bin/maze-flatpak-setup"]="0:0:755"
  ["/usr/local/bin/maze-welcome"]="0:0:755"
  ["/usr/local/bin/maze-gpu-driver"]="0:0:755"
  ["/usr/local/bin/maze-apply-wallpaper"]="0:0:755"
  ["/usr/local/bin/maze-panic"]="0:0:755"
  ["/usr/local/bin/maze-panic-restore"]="0:0:755"
  ["/usr/local/bin/maze-guardd"]="0:0:755"
  ["/usr/local/bin/maze-guard"]="0:0:755"
  ["/usr/local/bin/maze-honeypot"]="0:0:755"
  ["/usr/local/bin/maze-honeypot-setup"]="0:0:755"
  ["/usr/local/bin/maze-killswitch"]="0:0:755"
  ["/usr/local/bin/maze-hardware"]="0:0:755"
  ["/usr/local/bin/maze-control-center"]="0:0:755"
  ["/etc/sudoers.d/10-maze"]="0:0:440"
)
