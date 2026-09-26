# Kernel Management

Maze always keeps **two kernels** installed:

| Kernel | Role |
|---|---|
| `linux` | Current Arch kernel — the one you normally boot |
| `linux-lts` | Long-term-support kernel — kept for **recovery** |

When a bad update arrives, the second kernel is already installed, built and
signed. You do not have to download or repair anything to get back in — you
pick it from the boot menu. See [If the System Won't Boot](Recovery).

Both kernels are sealed into signed Unified Kernel Images, so both boot with
Secure Boot enabled.

## Checking what is installed

```bash
pacman -Q linux linux-lts
```

## Choosing the default kernel

Graphical: **Maze Kernel Switcher**, in the application menu.

From a terminal:

```bash
sudo maze-kernel-helper set-default linux-lts
```

The choice survives updates — Maze will not silently switch you back.

## Why the ESP needs room

Each kernel is stored as a single signed image of roughly **90 MB**, and Maze
keeps two of them plus the previous image as a fallback. A 512 MB EFI System
Partition is tight; **1 GB or more is comfortable**. If your ESP is too small,
`maze-boot-check` will say so rather than failing silently at the next update.

See also: [Updating](Updating) · [Secure Boot](SecureBoot) ·
[Diagnostics](Diagnostics)
