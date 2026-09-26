# First Boot: Approve the Security Key

**This step happens once, and it cannot be skipped.**

On the first reboot after installation, a blue screen appears saying
*"Verification failed"* or *"MOK Management"*.

> **This is not an error, and nothing is broken.** Do not turn Secure Boot off
> to make it go away.

## Why it appears

Maze generates a signing key that is unique to *your* machine — its private
half never leaves the computer. Your firmware has not seen that key before, so
it asks you to approve it once, in person.

There is no password. Being physically at the machine **is** the authorisation.

## What to do

```
1. Choose  "Enroll key from disk"
2. Select the EFI partition, then the file:   MOK.cer
3. "Continue" → "Yes"
4. "Reboot"
```

After this the system boots normally, every time. Factory and Windows keys are
untouched, and kernel updates are re-signed automatically — **you never repeat
this step.**

A copy of these instructions is also written to the installed system at
`/var/lib/maze-secureboot/ENROLLMENT.txt`.

## Verifying it worked

```bash
mokutil --sb-state          # should say "SecureBoot enabled"
sudo maze-boot-check        # checks the whole chain
```

## If you missed the screen, or chose the wrong option

No harm done — the machine still boots, it just runs with Secure Boot
inactive. To get the prompt back:

```bash
sudo mokutil --import /var/lib/maze-secureboot/MOK.cer
sudo reboot
```

The blue screen will appear again on the next boot. Follow the four steps
above.

See also: [Secure Boot](SecureBoot) — the full technical reference ·
[After Install](After-Install)
