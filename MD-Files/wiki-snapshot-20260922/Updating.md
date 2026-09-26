# Updating

```bash
sudo pacman -Syu
```

Maze is a rolling release: there are no version upgrades to plan for, just a
steady stream of updates.

## What happens automatically on every update

- A **btrfs snapshot** is taken before and after the transaction (snap-pac)
- If the kernel changed, its image is **rebuilt and re-signed**
- The **boot chain is verified end to end** when the transaction finishes

If something is wrong, the system tells you **before you shut down**, and tells
you what the problem is. That ordering matters: a boot problem you learn about
while you are still booted is an inconvenience; the same problem discovered at
the next power-on is an outage.

## If an update breaks something

In rough order of effort:

1. **Undo the file that changed** — [Snapshots & Rollback](Snapshots)
2. **Boot the recovery kernel** if the machine will not start —
   [If the System Won't Boot](Recovery)
3. **Ask what happened** — `sudo maze-doctor`, see [Diagnostics](Diagnostics)

## Updating the Maze packages only

Maze's own packages come from the `mazelinux` repository, and every package and
the database itself are GPG-signed. Normal `pacman -Syu` covers them; nothing
special is required.

## A note on partial upgrades

Do not use `pacman -Sy <package>` to install a single package against an
un-updated system. On any Arch-based system this produces a partial upgrade and
is a genuine way to break things. Always `-Syu`.

See also: [Kernel Management](Kernels) · [Snapshots & Rollback](Snapshots) ·
[Known Limitations](Limitations)
