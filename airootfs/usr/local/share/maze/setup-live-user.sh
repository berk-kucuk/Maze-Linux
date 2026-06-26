#!/usr/bin/env bash
#
# setup-live-user.sh — Create the Maze Linux live user during the ISO build.
#
# Invoked as a pacman PostTransaction hook inside the build chroot, after all
# packages (and therefore `shadow`, `zsh`, the `wheel` group, ...) are present.
# Using useradd keeps /etc/{passwd,group,shadow,gshadow} consistent instead of
# hand-editing them.
#
set -euo pipefail

USERNAME="maze"
FULLNAME="Maze Live User"

if ! getent passwd "${USERNAME}" >/dev/null; then
    useradd --create-home --uid 1000 --user-group \
        --groups wheel \
        --shell /usr/bin/zsh \
        --comment "${FULLNAME}" \
        "${USERNAME}"
fi

# Add to extra groups if they exist (created by libvirt/qemu/wireshark packages).
for grp in libvirt kvm wireshark; do
    getent group "${grp}" >/dev/null && usermod -aG "${grp}" "${USERNAME}" || true
done

# Install Maze's zsh config into the user's home. It is staged here instead of
# /etc/skel/.zshrc because that path is owned by grml-zsh-config (file conflict).
if [[ -f /usr/local/share/maze/skel-zshrc ]]; then
    cp -f /usr/local/share/maze/skel-zshrc "/home/${USERNAME}/.zshrc"
fi

# Passwordless live account (autologin + no password prompt on the console).
passwd --delete "${USERNAME}" >/dev/null

# Live ISO only: keep the screen on for the whole installation. Installs can be
# long (AUR builds), so disable KDE's screen blanking / dimming / auto-suspend
# and the screen locker for the live session.
#
# These are written to the LIVE USER'S HOME, not /etc/skel, on purpose:
# deploy-to-target.sh copies /etc/skel/.config to the installed system, but NOT
# this home — so installed Maze systems keep normal power management and screen
# locking, while only the live session never sleeps.
LIVE_CONF="/home/${USERNAME}/.config"
mkdir -p "${LIVE_CONF}"

# Empty power profiles disable every idle action (powerdevil only performs an
# action when its config group is present in the profile): no DPMS screen-off,
# no dimming and no auto-suspend on AC, battery or low battery.
cat > "${LIVE_CONF}/powermanagementprofilesrc" <<'EOF'
[AC]

[Battery]

[LowBattery]
EOF

# Never lock the screen during the live session. Append to the kscreenlockerrc
# copied from /etc/skel (which only sets the greeter wallpaper).
cat >> "${LIVE_CONF}/kscreenlockerrc" <<'EOF'

[Daemon]
Autolock=false
LockOnResume=false
EOF

# Make sure the home directory is owned by the live user.
chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}"
