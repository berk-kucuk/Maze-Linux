"""maze_status — shared system / security / AI status helpers for Maze GUI apps.

Imported by both `maze-welcome` and `maze-control-center` (which add
/usr/local/lib/maze to sys.path). Every probe is best-effort and fails soft:
service queries return True (active), False (inactive) or None (unknown / not
installed), so callers can render a neutral state without crashing.
"""
from __future__ import annotations

import glob
import os
import platform
import shutil
import socket
import subprocess
from pathlib import Path

from maze_i18n import tr


def _run(cmd: list[str], timeout: float = 4.0):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except Exception:  # noqa: BLE001
        return None


def service_active(unit: str) -> bool | None:
    r = _run(["systemctl", "is-active", unit])
    if r is None:
        return None
    out = r.stdout.strip()
    if out == "active":
        return True
    if out in ("inactive", "failed", "activating", "deactivating", "reloading"):
        return False
    return None  # unknown / not-found


def service_enabled(unit: str) -> bool | None:
    r = _run(["systemctl", "is-enabled", unit])
    if r is None:
        return None
    out = r.stdout.strip()
    if out in ("enabled", "enabled-runtime", "static", "alias", "indirect", "generated"):
        return True
    if out in ("disabled", "masked", "masked-runtime"):
        return False
    return None


SECURITY_SERVICES: list[tuple[str, str]] = [
    ("AppArmor", "apparmor.service"),
    ("firewalld", "firewalld.service"),
    ("OpenSnitch", "opensnitchd.service"),
    ("fail2ban", "fail2ban.service"),
    ("auditd", "auditd.service"),
]


def security_status() -> list[tuple[str, str, bool | None]]:
    """[(label, unit, active?)] for the core Maze security services."""
    return [(label, unit, service_active(unit)) for label, unit in SECURITY_SERVICES]


def mac_randomization_enabled() -> bool:
    """Detect NetworkManager MAC randomization in /etc/NetworkManager/conf.d."""
    needles = (
        "wifi.scan-rand-mac-address",
        "cloned-mac-address=random",
        "cloned-mac-address=stable",
        "mac-address=random",
    )
    try:
        for f in Path("/etc/NetworkManager/conf.d").glob("*.conf"):
            text = f.read_text(errors="ignore")
            if any(n in text for n in needles):
                return True
    except Exception:  # noqa: BLE001
        pass
    return False


def secure_boot_status() -> bool | None:
    """UEFI Secure Boot state.

    True  → enabled, False → disabled (UEFI present), None → not applicable
    (legacy BIOS) or undeterminable. Reads the firmware SecureBoot EFI variable
    directly (a 4-byte attribute header followed by one data byte: 1 = on); falls
    back to `mokutil --sb-state` when that is not readable.
    """
    if not os.path.exists("/sys/firmware/efi"):
        return None  # legacy BIOS boot — Secure Boot does not apply
    try:
        for path in glob.glob("/sys/firmware/efi/efivars/SecureBoot-*"):
            data = Path(path).read_bytes()
            if len(data) >= 5:
                return data[4] == 1
    except Exception:  # noqa: BLE001
        pass
    if shutil.which("mokutil"):
        r = _run(["mokutil", "--sb-state"])
        if r and r.returncode == 0:
            low = r.stdout.lower()
            if "enabled" in low:
                return True
            if "disabled" in low:
                return False
    return None


def tor_status() -> bool | None:
    return service_active("tor.service")


def ollama_status() -> bool | None:
    return service_active("ollama.service")


def ollama_models() -> list[str] | None:
    """Installed Ollama model names, or None if Ollama is unavailable."""
    if not shutil.which("ollama"):
        return None
    r = _run(["ollama", "list"], timeout=5)
    if r is None or r.returncode != 0:
        return None
    models: list[str] = []
    for line in r.stdout.strip().splitlines()[1:]:  # skip header row
        parts = line.split()
        if parts:
            models.append(parts[0])
    return models


def _cpu_model() -> str:
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name"):
                return line.split(":", 1)[1].strip()
    except Exception:  # noqa: BLE001
        pass
    return platform.processor() or "Unknown CPU"


def _mem_total() -> str:
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            if line.startswith("MemTotal"):
                kib = int(line.split()[1])
                return f"{kib / 1024 / 1024:.1f} GiB RAM"
    except Exception:  # noqa: BLE001
        pass
    return "Unknown RAM"


def _root_disk() -> str:
    try:
        st = os.statvfs("/")
        total = st.f_blocks * st.f_frsize
        free = st.f_bavail * st.f_frsize
        used = total - free
        return f"{used / 1e9:.0f} / {total / 1e9:.0f} GB disk"
    except Exception:  # noqa: BLE001
        return ""


def _gpu_model_from_vendor() -> str:
    vmap = {"0x10de": "NVIDIA GPU", "0x1002": "AMD GPU", "0x8086": "Intel GPU"}
    try:
        for card in sorted(glob.glob("/sys/class/drm/card[0-9]")):
            vid = Path(card, "device", "vendor")
            if vid.exists():
                return vmap.get(vid.read_text().strip().lower(), "GPU")
    except Exception:  # noqa: BLE001
        pass
    return "GPU"


def gpu_info() -> tuple[str, str]:
    """Best-effort (model, kernel_driver) of the primary GPU."""
    model, driver = "", ""
    try:
        for card in sorted(glob.glob("/sys/class/drm/card[0-9]")):
            link = os.path.join(card, "device", "driver")
            if os.path.exists(link):
                driver = os.path.basename(os.path.realpath(link))
                break
    except Exception:  # noqa: BLE001
        pass
    if shutil.which("lspci"):
        import shlex
        r = _run(["lspci", "-mm"])
        if r and r.returncode == 0:
            for line in r.stdout.splitlines():
                try:
                    parts = shlex.split(line)
                except ValueError:
                    continue
                if len(parts) < 4:
                    continue
                cls = parts[1].lower()
                if "vga" in cls or "3d" in cls or "display" in cls:
                    dev = parts[3]
                    if "[" in dev and "]" in dev:  # marketing name in brackets
                        dev = dev[dev.find("[") + 1: dev.rfind("]")]
                    model = dev
                    break
    if not model:
        model = _gpu_model_from_vendor()
    return model, driver


def gpu_temperature() -> str | None:
    """Primary-GPU temperature as e.g. "62 °C", best-effort.

    Reads the DRM hwmon node (amdgpu / i915 expose temp1_input in millidegrees);
    falls back to `nvidia-smi` because the NVIDIA kernel driver does NOT publish a
    hwmon temperature (so KDE's thermal monitor / `gpu/all/temperature` show
    nothing), yet NVML still reports it. Returns None when no sensor is available.
    """
    try:
        for node in sorted(glob.glob(
                "/sys/class/drm/card[0-9]/device/hwmon/hwmon*/temp1_input")):
            raw = Path(node).read_text().strip()
            if raw:
                return f"{int(raw) / 1000:.0f} °C"
    except Exception:  # noqa: BLE001
        pass
    if shutil.which("nvidia-smi"):
        r = _run(["nvidia-smi", "--query-gpu=temperature.gpu",
                  "--format=csv,noheader,nounits"])
        if r and r.returncode == 0:
            val = r.stdout.strip().splitlines()[0].strip() if r.stdout.strip() else ""
            if val.isdigit():
                return f"{val} °C"
    return None


def system_facts() -> list[tuple[str, str]]:
    """Best-effort live system information as (icon-name, value) pairs.

    The first element is a freedesktop icon name (resolved against the active
    icon theme by the GUI); callers that only need text ignore it.
    """
    def clip(text: str, n: int = 34) -> str:
        return text if len(text) <= n else text[: n - 1] + "…"

    de = (
        os.environ.get("XDG_CURRENT_DESKTOP")
        or os.environ.get("DESKTOP_SESSION")
        or "Plasma"
    )
    session = os.environ.get("XDG_SESSION_TYPE", "")
    if session:
        de = f"{de} ({session})"

    gpu_model, gpu_driver = gpu_info()
    gpu_temp = gpu_temperature()
    disk = _root_disk()

    facts: list[tuple[str, str]] = [
        ("cpu", clip(_cpu_model())),
        ("video-display", clip(gpu_model)),
        ("application-x-sharedlib",
         tr("{driver} driver").format(driver=gpu_driver) if gpu_driver
         else tr("GPU driver: unknown")),
    ]
    if gpu_temp:
        facts.append(("temperature-normal", f"GPU {gpu_temp}"))
    facts.append(("memory", _mem_total()))
    if disk:
        facts.append(("drive-harddisk-root", disk))
    facts += [
        ("utilities-system-monitor", f"Kernel {platform.release()}"),
        ("preferences-desktop-display", de),
    ]
    return facts


def system_summary() -> str:
    lines = ["Maze Linux — system information", ""]
    lines += [f"• {value}" for _, value in system_facts()]
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Live metrics (for the Control Center dashboard) — all read-only, no privilege.
# ---------------------------------------------------------------------------
_prev_cpu: tuple[int, int] | None = None


def cpu_usage_percent() -> float:
    """Whole-system CPU busy % from the delta between two /proc/stat samples.

    Stateful: the first call primes the baseline and returns 0.0; subsequent
    calls (e.g. from a refresh timer) return the real utilisation since the
    previous call.
    """
    global _prev_cpu
    try:
        with open("/proc/stat") as f:
            nums = [int(x) for x in f.readline().split()[1:]]
        idle = nums[3] + (nums[4] if len(nums) > 4 else 0)
        total = sum(nums)
        if _prev_cpu is not None:
            dt = total - _prev_cpu[0]
            di = idle - _prev_cpu[1]
            _prev_cpu = (total, idle)
            return max(0.0, min(100.0, 100.0 * (dt - di) / dt)) if dt > 0 else 0.0
        _prev_cpu = (total, idle)
    except Exception:  # noqa: BLE001
        pass
    return 0.0


def mem_usage() -> tuple[float, float, float]:
    """(used_GiB, total_GiB, percent) of physical memory."""
    try:
        info: dict[str, int] = {}
        for line in Path("/proc/meminfo").read_text().splitlines():
            key, _, val = line.partition(":")
            info[key] = int(val.split()[0])  # kB
        total = info["MemTotal"]
        avail = info.get("MemAvailable", info.get("MemFree", 0))
        used = total - avail
        g = 1024 * 1024
        return (used / g, total / g, 100.0 * used / total if total else 0.0)
    except Exception:  # noqa: BLE001
        return (0.0, 0.0, 0.0)


def disk_usage() -> tuple[float, float, float]:
    """(used_GB, total_GB, percent) of the root filesystem."""
    try:
        st = os.statvfs("/")
        total = st.f_blocks * st.f_frsize
        free = st.f_bavail * st.f_frsize
        used = total - free
        return (used / 1e9, total / 1e9, 100.0 * used / total if total else 0.0)
    except Exception:  # noqa: BLE001
        return (0.0, 0.0, 0.0)


def cpu_temperature() -> float | None:
    """CPU package temperature in °C, best-effort across common hwmon drivers."""
    preferred = ("k10temp", "zenpower", "coretemp", "acpitz")
    try:
        named: dict[str, str] = {}
        for hw in glob.glob("/sys/class/hwmon/hwmon*"):
            name_f = Path(hw, "name")
            if name_f.exists():
                named[name_f.read_text().strip()] = hw
        for drv in preferred:
            hw = named.get(drv)
            if not hw:
                continue
            inputs = sorted(glob.glob(hw + "/temp*_input"))
            if inputs:
                return int(Path(inputs[0]).read_text().strip()) / 1000.0
    except Exception:  # noqa: BLE001
        pass
    return None


def gpu_usage_percent() -> float | None:
    """GPU utilisation %, via amdgpu sysfs or nvidia-smi. None if unavailable."""
    try:
        for busy in glob.glob(
                "/sys/class/drm/card[0-9]/device/gpu_busy_percent"):
            return float(Path(busy).read_text().strip())
    except Exception:  # noqa: BLE001
        pass
    if shutil.which("nvidia-smi"):
        r = _run(["nvidia-smi", "--query-gpu=utilization.gpu",
                  "--format=csv,noheader,nounits"])
        if r and r.returncode == 0 and r.stdout.strip():
            val = r.stdout.strip().splitlines()[0].strip()
            if val.isdigit():
                return float(val)
    return None


def live_metrics() -> list[dict]:
    """Dashboard meters: list of {key,label,icon,percent,detail}."""
    mu, mt, mp = mem_usage()
    du, dt, dp = disk_usage()
    metrics = [
        {"key": "cpu", "label": tr("CPU"), "icon": "cpu",
         "percent": cpu_usage_percent(), "detail": None},
        {"key": "mem", "label": tr("Memory"), "icon": "memory",
         "percent": mp, "detail": f"{mu:.1f} / {mt:.1f} GiB"},
        {"key": "disk", "label": tr("Disk"), "icon": "drive-harddisk-root",
         "percent": dp, "detail": f"{du:.0f} / {dt:.0f} GB"},
    ]
    gu = gpu_usage_percent()
    if gu is not None:
        metrics.append({"key": "gpu", "label": tr("GPU"), "icon": "video-display",
                        "percent": gu, "detail": None})
    ct = cpu_temperature()
    if ct is not None:
        metrics[0]["detail"] = f"{ct:.0f} °C"
    return metrics


# ---------------------------------------------------------------------------
# Network & anonymity (read-only; no external requests — local probes only).
# ---------------------------------------------------------------------------
def local_ip() -> str | None:
    """Primary outbound IPv4 address (no traffic is sent — UDP connect only)."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("1.1.1.1", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:  # noqa: BLE001
        return None


def default_interface() -> str | None:
    """Interface backing the default route, from /proc/net/route."""
    try:
        for line in Path("/proc/net/route").read_text().splitlines()[1:]:
            f = line.split()
            if len(f) >= 2 and f[1] == "00000000":  # destination 0.0.0.0
                return f[0]
    except Exception:  # noqa: BLE001
        pass
    return None


def wifi_ssid() -> str | None:
    if shutil.which("iwgetid"):
        r = _run(["iwgetid", "-r"])
        if r and r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    return None


def vpn_active() -> tuple[bool, str | None]:
    """(active?, label) by inspecting interfaces for tun/wg/proton/mullvad."""
    try:
        for iface in sorted(os.listdir("/sys/class/net")):
            low = iface.lower()
            if low.startswith(("tun", "wg", "proton", "mullvad", "tap")):
                return (True, iface)
    except Exception:  # noqa: BLE001
        pass
    return (False, None)


def tor_socks_reachable() -> bool:
    """Whether Tor's SOCKS proxy (127.0.0.1:9050) is accepting connections."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(0.4)
        rc = s.connect_ex(("127.0.0.1", 9050))
        s.close()
        return rc == 0
    except Exception:  # noqa: BLE001
        return False


def dns_servers() -> list[str]:
    """Current DNS resolvers, via resolvectl when present else resolv.conf."""
    out: list[str] = []
    if shutil.which("resolvectl"):
        r = _run(["resolvectl", "dns"])
        if r and r.returncode == 0:
            for line in r.stdout.splitlines():
                out += line.split(":", 1)[1].split() if ":" in line else []
    if not out:
        try:
            for line in Path("/etc/resolv.conf").read_text().splitlines():
                if line.startswith("nameserver"):
                    out.append(line.split()[1])
        except Exception:  # noqa: BLE001
            pass
    seen: list[str] = []
    for x in out:
        if x and x not in seen:
            seen.append(x)
    return seen


def network_info() -> list[tuple[str, str, bool | None]]:
    """(label, value, good?) rows for the network/anonymity panel."""
    rows: list[tuple[str, str, bool | None]] = []
    iface = default_interface()
    ip = local_ip()
    rows.append((tr("Local IP"), ip or "—", None))
    rows.append((tr("Interface"), iface or "—", None))
    ssid = wifi_ssid()
    if ssid:
        rows.append((tr("Wi-Fi"), ssid, None))
    vpn_on, vpn_if = vpn_active()
    rows.append((tr("VPN"),
                 tr("Connected ({iface})").format(iface=vpn_if) if vpn_on
                 else tr("Not connected"), vpn_on))
    tor = tor_socks_reachable()
    rows.append((tr("Tor"),
                 tr("Reachable (127.0.0.1:9050)") if tor else tr("Not running"),
                 tor))
    mac = mac_randomization_enabled()
    rows.append((tr("MAC randomisation"),
                 tr("Enabled") if mac else tr("Disabled"), mac))
    dns = dns_servers()
    if dns:
        rows.append((tr("DNS"), ", ".join(dns[:3]), None))
    return rows


# ---------------------------------------------------------------------------
# Security hardening posture — checklist + score.
# ---------------------------------------------------------------------------
def _sysctl_hardening_present() -> bool:
    return any(Path(p).exists() for p in (
        "/etc/sysctl.d/99-maze-hardening.conf",
        "/etc/sysctl.d/99-maze.conf",
    ))


def hardening_report() -> tuple[list[tuple[str, bool]], int]:
    """([(check, passed)], score_percent) summarising the security posture."""
    checks: list[tuple[str, bool]] = []
    for label, unit in SECURITY_SERVICES:
        checks.append((tr("{label} active").format(label=label),
                       service_active(unit) is True))
    sb = secure_boot_status()
    if sb is not None:
        checks.append((tr("Secure Boot enabled"), sb is True))
    checks.append((tr("MAC randomisation"), mac_randomization_enabled()))
    checks.append((tr("Kernel/network hardening (sysctl)"),
                   _sysctl_hardening_present()))
    vpn_on, _vpn_if = vpn_active()
    checks.append((tr("VPN or Tor active"), vpn_on or tor_socks_reachable()))
    passed = sum(1 for _, ok in checks if ok)
    score = round(100 * passed / len(checks)) if checks else 0
    return (checks, score)
