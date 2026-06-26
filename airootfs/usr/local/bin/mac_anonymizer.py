#!/usr/bin/env python3
"""Randomize the MAC address of physical network interfaces.

Usage:
    mac_anonymizer.py                 # randomize every physical interface
    mac_anonymizer.py wlan0 enp3s0    # randomize only the named interface(s)

A desktop notification is sent to every active graphical session BEFORE the
change starts and AFTER it finishes (best-effort — it never blocks or fails the
MAC change). Used three ways:
  * boot:    mac-changer.service runs it once (no args) after NetworkManager.
  * hotplug: mac-changer@<iface>.service runs it for the newly added adapter.
  * manual:  change-mac-now / the Maze tools run it on demand.
"""

import os
import pwd
import subprocess
import re
import sys
import time
import datetime

APP_NAME = "Maze MAC Changer"
APP_ICON = "maze"


def log_message(message):
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {message}")


def is_physical(iface):
    """A physical NIC has a backing device under /sys; virtual ones do not."""
    if iface.startswith(('lo', 'tun', 'tap', 'docker', 'br-', 'veth', 'virbr', 'wg', 'bond', 'dummy')):
        return False
    return os.path.exists(f"/sys/class/net/{iface}/device")


def notify(title, body, urgency="normal"):
    """Send a desktop notification to every active graphical user session.

    The MAC change runs as root (boot service, udev unit or sudo), so we hop
    into each logged-in user's session bus to post the notification. Entirely
    best-effort: any failure is swallowed so it can never disrupt the change.
    """
    try:
        run_users = os.listdir("/run/user")
    except OSError:
        return
    for uid in run_users:
        bus = f"/run/user/{uid}/bus"
        if not os.path.exists(bus):
            continue
        try:
            user = pwd.getpwuid(int(uid)).pw_name
        except (KeyError, ValueError):
            continue
        addr = f"unix:path={bus}"
        # Prefer notify-send (libnotify); fall back to gdbus (always present via
        # glib2) so a missing libnotify still gets the notification through.
        notify_send = [
            "sudo", "-u", user, "env", f"DBUS_SESSION_BUS_ADDRESS={addr}",
            "notify-send", "-a", APP_NAME, "-i", APP_ICON, "-u", urgency,
            title, body,
        ]
        try:
            subprocess.run(notify_send, check=True, timeout=10,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            continue
        except Exception:
            pass
        gdbus = [
            "sudo", "-u", user, "env", f"DBUS_SESSION_BUS_ADDRESS={addr}",
            "gdbus", "call", "--session",
            "--dest", "org.freedesktop.Notifications",
            "--object-path", "/org/freedesktop/Notifications",
            "--method", "org.freedesktop.Notifications.Notify",
            APP_NAME, "0", APP_ICON, title, body, "[]", "{}", "5000",
        ]
        try:
            subprocess.run(gdbus, check=True, timeout=10,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass


def get_network_interfaces():
    try:
        output = subprocess.check_output(["ip", "link"], text=True)
        all_interfaces = re.findall(r'\d+: ([\w\d@]+):', output)
        # strip "@if12" style suffixes that show on some virtual links
        return [i.split('@')[0] for i in all_interfaces if is_physical(i.split('@')[0])]
    except subprocess.CalledProcessError as e:
        log_message(f"ERROR: 'ip link' failed: {e}")
        sys.exit(1)


def get_current_mac(interface):
    try:
        output = subprocess.check_output(["ip", "link", "show", interface], text=True)
        mac_match = re.search(r'ether ([a-f0-9:]{17})', output)
        return mac_match.group(1) if mac_match else "Unknown"
    except Exception:
        return "Unknown"


def change_mac(interface):
    old_mac = get_current_mac(interface)
    try:
        log_message(f"INFO: processing {interface} (old MAC: {old_mac})")

        subprocess.run(["nmcli", "device", "disconnect", interface],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1)

        subprocess.run(["ip", "link", "set", interface, "down"],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["macchanger", "-r", interface],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["ip", "link", "set", interface, "up"],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        time.sleep(2)
        subprocess.run(["nmcli", "device", "connect", interface],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(3)

        new_mac = get_current_mac(interface)
        log_message(f"INFO: {interface} MAC changed: {old_mac} -> {new_mac}")
        return (interface, old_mac, new_mac)

    except subprocess.CalledProcessError as e:
        log_message(f"ERROR: could not change MAC for {interface}: {e}")
        return (interface, old_mac, "FAILED")


def main():
    log_message("MAC anonymizer started")

    # Explicit interface(s) on the command line (hotplug path) override the scan.
    requested = [a for a in sys.argv[1:] if a]
    if requested:
        interfaces = [i for i in requested if is_physical(i)]
        for s in (i for i in requested if i not in interfaces):
            log_message(f"INFO: skipping non-physical/absent interface {s}")
    else:
        interfaces = get_network_interfaces()

    if not interfaces:
        log_message("WARN: no physical network interfaces to process")
        sys.exit(0)

    log_message(f"INFO: interfaces: {', '.join(interfaces)}")
    # Heads-up notification BEFORE touching anything.
    notify("Randomizing MAC address",
           "Changing the hardware address for: " + ", ".join(interfaces),
           urgency="low")

    results = [change_mac(iface) for iface in interfaces]

    # Summary notification AFTER the change.
    lines = [f"{i}: {new}" for (i, _old, new) in results]
    ok = all(new not in ("FAILED", "Unknown") for (_i, _old, new) in results)
    notify("MAC address changed" if ok else "MAC change finished with errors",
           "\n".join(lines),
           urgency="normal" if ok else "critical")

    log_message("MAC anonymizer finished")


if __name__ == "__main__":
    main()
