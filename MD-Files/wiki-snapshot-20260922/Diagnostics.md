# Diagnostics

Three commands answer nearly every "what is wrong with my machine" question.

## `maze-doctor`

A full health report of the system — **18 sections**. This is the first thing
to run when anything misbehaves, and the output to attach when reporting a bug.

```bash
sudo maze-doctor
```

A healthy system reports `0 failures`.

### The Stability section

This section answers the question people actually have: **"was that Maze's
fault, or my hardware?"**

If your machine froze or shut itself down, `maze-doctor` shows the last line
the kernel wrote before the previous boot ended, and classifies the cause:

- hardware — a USB device that vanished, a disk that stopped answering,
  overheating
- out of memory
- graphics driver
- kernel fault

When the evidence is not conclusive it says **inconclusive** rather than
guessing. That is deliberate: a confident wrong answer sends you looking in the
wrong place for hours.

## `maze-boot-check`

Verifies the boot chain end to end — **12 checks**, covering the kernel image,
its signature, and encrypted-disk unlocking.

It runs automatically after every update, and warns you *before* you shut down
if something is wrong. You can also run it by hand:

```bash
sudo maze-boot-check
sudo maze-boot-check --repair    # fix what it finds
```

## `maze-boot-entries`

If you have installed Maze more than once, dead entries can pile up in the
firmware boot menu. This tool clears them out:

```bash
sudo maze-boot-entries           # show only
sudo maze-boot-entries --clean   # clean up (asks for confirmation)
```

It never touches entries belonging to other operating systems, nor the entry
you are currently booted from.

## Reporting a problem

Attach the output of:

```bash
sudo maze-doctor > report.txt
```

It answers almost every follow-up question on its own.

See also: [If the System Won't Boot](Recovery) ·
[Hardware Kill Switches](Hardware)
