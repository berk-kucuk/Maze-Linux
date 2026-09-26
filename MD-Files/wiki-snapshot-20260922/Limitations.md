# Known Limitations

Honesty builds trust. These are written down deliberately rather than left for
you to discover at a bad moment.

## System

- **Full snapshot rollback is not reliable on every machine.** It is still
  being worked on. File-level undo (`snapper undochange`) is solid — see
  [Snapshots & Rollback](Snapshots).
- **There is no automatic recovery.** If the system will not boot, *you* choose
  the recovery kernel from the boot menu; the machine does not roll itself
  back. See [If the System Won't Boot](Recovery).
- **BIOS/Legacy boot is not supported.** Maze is UEFI-only, because the whole
  security chain depends on it.
- **DKMS modules (NVIDIA and similar) are unsigned.** In practice this causes
  no problem, because the Arch kernel does not enforce lockdown.
- **A 512 MB ESP is tight.** Two signed kernel images plus a fallback may not
  fit. 1 GB or more is recommended — see [Kernel Management](Kernels).

## What the security model does not cover

A security tool that states its limits is more trustworthy than one that does
not. Maze does **not** protect you from:

| Out of scope | Why | What does help |
|---|---|---|
| **Phishing** — entering your password on a fake site | It is ordinary HTTPS traffic to a real server | Browser warnings, and a password manager (it will not fill on the wrong domain) |
| **Malware already running** | Maze Guard watches the network, not processes | Qlam scans, Firejail sandboxing |
| **A service you use getting breached** | Nothing to do with your machine | Unique passwords, two-factor authentication |
| **Physical access to a powered-off machine** | Not a network event | LUKS full-disk encryption + Secure Boot |

Maze Guard is very good at what it does cover: **on the network you are
connected to.** In a café, hotel or airport it will tell you the MAC address,
vendor, operating system and behaviour of a device attacking you. Outside that
lane, other tools are the right answer.

## Optional apps that reach the internet

Two applications are **not installed by default** because they can send data
off the machine. Both warn you on first use:

- **SentinAI** — OSINT and password-list tooling; can connect to Google Gemini
- **Linux Chan AI** — works only with Google Gemini, no offline mode

The built-in **Maze AI** assistant is fully local (Ollama) and sends nothing.
See [Privacy Reference](Privacy).

See also: [Security Reference](Security) · [FAQ](FAQ)
