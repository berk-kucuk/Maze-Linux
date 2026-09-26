# Security Reference

Maze Linux enables a layered security stack from first boot. Nothing needs to be turned on manually — every service listed here is active the moment you log in.

---

## Security at a Glance

| Layer | Tool | Version | Status |
|-------|------|---------|--------|
| Mandatory access control | AppArmor | 3.1.7 | Enabled (kernel + service) |
| Host firewall | firewalld | 2.2.3 | Active — strict public zone |
| SSH brute-force protection | fail2ban | — | Active jails for SSH and common services |
| System audit log | auditd | — | Active — hardened rule set |
| Application firewall | OpenSnitch | 1.6 | Autostarted on desktop |
| Antivirus | ClamAV + QLAM | 1.4.1 | On-access scanning + scheduled updates |
| Rootkit detection | rkhunter | — | Baseline database initialized |
| Security audit | lynis | — | Installed |
| Kernel hardening | sysctl (custom) | — | Applied at boot |

---

## AppArmor

AppArmor 3.1.7 is a **mandatory access control (MAC)** system. It confines applications to only the files, capabilities, and system calls defined in their profile, limiting damage if an app is exploited. Maze ships with enforcement profiles for all major browsers and system services active from first boot.

**How it's enabled:**
- The `apparmor` kernel parameter is added to the GRUB command line.
- `apparmor.service` is enabled and starts at boot.

**Check status:**
```bash
sudo aa-status
```

**View active profiles:**
```bash
sudo aa-status | grep enforce
```

AppArmor profiles shipped with packages are loaded automatically. You can write custom profiles in `/etc/apparmor.d/`.

---

## firewalld

firewalld 2.2.3 manages the `nftables` rule set using a zone-based model. The default zone is **`public`** with a strict policy — **all inbound connections are refused by default**. Only traffic initiated by you is permitted outbound.

**Check active rules:**
```bash
sudo firewall-cmd --list-all
```

**Add a port temporarily:**
```bash
sudo firewall-cmd --add-port=8080/tcp
```

**Add a port permanently:**
```bash
sudo firewall-cmd --add-port=8080/tcp --permanent
sudo firewall-cmd --reload
```

**GUI:** `firewall-config` (install with `sudo pacman -S firewall-config` if needed).

---

## fail2ban

fail2ban monitors log files and bans IP addresses that show repeated failed login attempts. Maze ships with **active jails for SSH and common services** using the `systemd-journal` backend.

**Check active jails:**
```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

**Unban an IP:**
```bash
sudo fail2ban-client set sshd unbanip <IP>
```

Config lives in `/etc/fail2ban/`. Create `/etc/fail2ban/jail.local` to override defaults without touching the package files.

---

## auditd

The Linux Audit daemon records security-relevant system calls and file accesses into a structured audit log. Useful for forensics, compliance, and detecting unusual activity.

**View recent audit events:**
```bash
sudo ausearch -ts recent
```

**Search for a specific file:**
```bash
sudo ausearch -f /etc/passwd
```

**Generate a report:**
```bash
sudo aureport
```

Maze ships a **hardened rule set** covering sensitive paths (`/etc/passwd`, `/etc/shadow`, `/etc/sudoers`) and privilege escalation events. Audit rules live in `/etc/audit/rules.d/`.

---

## Maze Guard (OpenSnitch)

OpenSnitch is an **interactive application firewall**. Every time an application tries to make an outbound network connection, OpenSnitch pops up a dialog asking you to allow or deny it.

- Rules can be set per-process, per-port, per-destination IP/hostname, or globally.
- Rules persist in `/etc/opensnitchd/rules/`.
- The OpenSnitch GUI (`opensnitch-ui`) shows live connection stats.

**On first use:** expect many prompts as your apps make their first connections. Allow what you trust — the rules are saved so you are not asked again.

**Check the service:**
```bash
systemctl status opensnitchd
```

**Open the GUI:**
```bash
opensnitch-ui
```

---

## ClamAV 1.4.1 + QLAM

ClamAV 1.4.1 is the antivirus engine. QLAM is the Maze-built GUI for it. **On-access scanning and scheduled definition updates are active from first boot.**

**Manual scan:**
```bash
sudo clamscan -r --bell /home/yourusername
```

**Force a definition update:**
```bash
sudo freshclam
```

**Scan with QLAM:** open **QLAM** from the application menu for a graphical scan interface with quarantine management.

---

## rkhunter

rkhunter checks for rootkits, backdoors, and local exploits by comparing file hashes and checking for known suspicious patterns.

**First run (baseline):**
```bash
sudo rkhunter --update
sudo rkhunter --propupd
```

**Periodic check:**
```bash
sudo rkhunter --check
```

Warnings should be investigated. Many are false positives — `--propupd` updates the baseline after you verify a change is legitimate.

---

## lynis

lynis performs a comprehensive security audit of your system configuration and produces a hardening score with specific recommendations.

```bash
sudo lynis audit system
```

The report is saved to `/var/log/lynis.log` and `/var/log/lynis-report.dat`.

---

## Hardened SSH

The SSH server (`sshd`) ships with secure defaults:

- `PermitRootLogin no` — root login over SSH is disabled.
- `MaxAuthTries 3` — lock out after 3 failed attempts.
- `AllowAgentForwarding no`, `AllowTcpForwarding no`, `X11Forwarding no` — forwarding disabled.

Switch to key-only authentication:

```bash
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

**The SSH server is not enabled at boot by default.** Enable it only when needed:

```bash
sudo systemctl enable --now sshd
```

Disable again when not in use:

```bash
sudo systemctl disable --now sshd
```

---

## Kernel Hardening (sysctl)

Maze applies kernel parameters at boot via `/etc/sysctl.d/maze-hardening.conf`. These are active from first boot — no action required.

### Kernel restrictions

| Parameter | Value | Effect |
|-----------|-------|--------|
| `kernel.kptr_restrict` | 2 | Hides kernel pointers from all users |
| `kernel.dmesg_restrict` | 1 | Only root can read `dmesg` |
| `kernel.yama.ptrace_scope` | 1 | Restricts `ptrace` to parent/child processes |
| `kernel.unprivileged_bpf_disabled` | 1 | Only root can load eBPF programs |
| `net.core.bpf_jit_harden` | 2 | Hardens the eBPF JIT compiler |
| `kernel.kexec_load_disabled` | 1 | Disables loading a new kernel at runtime |
| `kernel.sysrq` | 4 | Limits SysRq to safe keys only |
| `fs.suid_dumpable` | 0 | Disables core dumps from setuid programs |
| `fs.protected_hardlinks` | 1 | Prevents hardlink attacks in shared dirs |
| `fs.protected_symlinks` | 1 | Prevents symlink attacks in shared dirs |

### Network protections

| Parameter | Value | Effect |
|-----------|-------|--------|
| `net.ipv4.conf.all.rp_filter` | 1 | Reverse-path filtering (anti-spoofing) |
| `net.ipv4.tcp_syncookies` | 1 | SYN flood protection |
| `net.ipv4.conf.all.accept_redirects` | 0 | Ignores ICMP redirect packets |
| `net.ipv4.conf.all.send_redirects` | 0 | Does not send ICMP redirects |
| `net.ipv4.conf.all.accept_source_route` | 0 | Rejects source-routed packets |
| `net.ipv4.icmp_echo_ignore_broadcasts` | 1 | Ignores broadcast ping (smurf mitigation) |
| `net.ipv4.conf.all.log_martians` | 1 | Logs packets from impossible addresses |

---

## Maze Control Center — Security Tab

Open `maze-control-center` and select the **Security** tab to see the live status of every service listed here. Each service shows green (active) or red (inactive). Copyable commands let you start, stop, or enable any service from the terminal without memorizing `systemctl` syntax.
