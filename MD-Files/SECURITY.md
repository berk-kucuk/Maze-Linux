# Security Policy

Maze Linux ships security-hardening tooling by default (AppArmor, firewalld,
fail2ban, auditd, OpenSnitch, Secure Boot). This document covers vulnerability
reporting for the distro itself — its own scripts, install pipeline, Secure
Boot chain, hardening defaults, and the `[mazelinux]` package repo.

For a vulnerability in a *bundled upstream package* (the Linux kernel, KDE,
Firefox, systemd, …), please report it to that project directly — Maze ships
it largely unmodified and cannot patch it faster than upstream.

## Reporting a vulnerability

Please **do not open a public GitHub issue** for a security report — that
discloses the issue to every user before a fix exists.

Instead, report it privately via **GitHub Security Advisories**:
<https://github.com/berk-kucuk/Maze-Linux/security/advisories/new>

Include:
- Affected component (installer, live ISO, Secure Boot signing, a specific
  `maze-*` tool, the `[mazelinux]` repo, …)
- Maze Linux version / ISO build date (`cat /etc/os-release`, or the ISO
  filename)
- Steps to reproduce, and the impact you believe it has

## Response

This is currently a single-maintainer project — there is no dedicated
security team and no fixed SLA. Reports are triaged as soon as possible;
expect an initial acknowledgement within a few days. Confirmed issues are
fixed and disclosed once a patched ISO/package is available.

## Scope

In scope:
- `deploy-to-target.sh` and the rest of the install pipeline
- Secure Boot signing (`maze-sb-sign`, kernel-install integration, MOK
  handling)
- The `[mazelinux]` and `[maze-aur]` pacman repositories and their signing
- Maze's own tools (`maze-guardd`, `maze-panic`, `maze-gpu-driver`, QLAM,
  entropy-shield, sentinai, haze, hazedrop, linux-chan-ai, …)
- Default hardening configuration (sysctl, sshd, AppArmor profiles, firewalld
  rules) shipped by Maze

Out of scope:
- Vulnerabilities purely in upstream Arch/AUR packages with no Maze-specific
  modification
- Issues requiring physical access combined with an already-unlocked,
  unencrypted system
