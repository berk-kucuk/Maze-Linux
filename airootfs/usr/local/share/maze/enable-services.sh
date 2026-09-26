#!/usr/bin/env bash
#
# enable-services.sh — Enable Maze Linux services in the image (build-time hook).
# Uses `systemctl enable` so each unit's [Install]/WantedBy is honoured, and
# tolerates missing units (e.g. an optional AUR package that was not built).
#
set -u

SERVICES=(
    # Security / privacy
    apparmor.service
    auditd.service
    firewalld.service
    opensnitchd.service
    # Anonymity (Tor SOCKS proxy on 127.0.0.1:9050; used by torsocks/torbrowser)
    tor.service
    # Privileged-action broker for the panic widget + hardware kill switches
    # (so the panic tray plasmoid works in the live session too).
    maze-guardd.service
    # MAC address randomisation. The daemon is what writes the NetworkManager
    # drop-in, and it deletes that drop-in again when it stops, so the shipped
    # /etc/maze-cloak/config.json defaults only take effect while this runs.
    # Those defaults enable the two free layers (scan-time and per-network
    # randomisation) and leave timer rotation off, so this costs an idle Python
    # process and drops no connections. See the config.json block in
    # maze-cloak's PKGBUILD for the reasoning behind each default.
    maze-cloak.service
    # AI
    ollama.service
    # Hardware / power / virtualization
    acpid.service
    power-profiles-daemon.service
    smartd.service
    # libvirtd — removed (libvirt not shipped in live ISO; installed on target
    # by deploy-to-target.sh).
    # Userspace OOM killer (pairs with zram swap)
    systemd-oomd.service
    # Firmware updates + mirror ranking + Flathub setup (first online boot)
    fwupd-refresh.timer
    reflector.timer
    maze-flatpak-setup.service
)

for svc in "${SERVICES[@]}"; do
    if systemctl enable "${svc}" >/dev/null 2>&1; then
        echo "enabled ${svc}"
    else
        echo "skipped ${svc} (unit not present)"
    fi
done

# LAN silence (belt and braces with maze-hardening.install): passim is fwupd's
# LAN firmware-cache sharing daemon and it socket-activates avahi; both
# advertise the machine over mDNS. maze-hardening masks them once via its
# scriptlet, which already ran in this chroot — repeat it here so an ISO built
# from an older package is covered too.
systemctl mask passim.service avahi-daemon.socket avahi-daemon.service >/dev/null 2>&1 || true

# firewalld: allow the services Maze uses (offline = no running daemon needed).
#
# maze-connect ships its own service definition and a scriptlet that would add
# it, but that scriptlet uses `firewall-cmd --permanent`, which talks to the
# firewalld DAEMON over D-Bus and therefore cannot work in this chroot — nothing
# is running here. So the rule was silently never added and the app's port stayed
# closed on every ISO and every install made from it. Add it the offline way,
# exactly like kdeconnect above (same TCP/UDP-port shape, same trust model).
if command -v firewall-offline-cmd >/dev/null 2>&1; then
    firewall-offline-cmd --add-service=ssh          >/dev/null 2>&1 || true
    firewall-offline-cmd --add-service=kdeconnect   >/dev/null 2>&1 || true
    firewall-offline-cmd --add-service=maze-connect >/dev/null 2>&1 || true
fi
