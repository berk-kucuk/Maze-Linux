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
    fail2ban.service
    opensnitchd.service
    # Anonymity (Tor SOCKS proxy on 127.0.0.1:9050; used by torsocks/torbrowser)
    tor.service
    # Privileged-action broker for the panic widget + hardware kill switches
    # (so the panic tray plasmoid works in the live session too).
    maze-guardd.service
    # AI
    ollama.service
    # Hardware / power / virtualization
    acpid.service
    power-profiles-daemon.service
    smartd.service
    libvirtd.service
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

# firewalld: allow the services Maze uses (offline = no running daemon needed).
if command -v firewall-offline-cmd >/dev/null 2>&1; then
    firewall-offline-cmd --add-service=ssh        >/dev/null 2>&1 || true
    firewall-offline-cmd --add-service=kdeconnect >/dev/null 2>&1 || true
fi
