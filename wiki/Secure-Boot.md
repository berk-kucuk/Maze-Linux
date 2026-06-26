# Secure Boot

Maze Linux supports **UEFI Secure Boot** on both the live ISO and the installed
system. It uses a Microsoft-signed **shim** that chainloads a Maze-signed boot
loader and kernel, with the Maze certificate enrolled once as a **MOK** (Machine
Owner Key). Your existing factory and Windows keys are kept — you never have to
put the firmware into *Setup Mode*.

```
firmware → shim (Microsoft-signed) → systemd-boot (Maze-signed) → UKI / kernel (Maze-signed)
```

There are **two separate moments** where you enroll the key, and each only has to
be done once:

1. [When you boot the live ISO](#1-booting-the-live-iso-with-secure-boot)
2. [After installation finishes (first boot of the installed system)](#2-after-installation-first-boot-of-the-installed-system)

> **No password.** Enrollment is protected by *physical presence* — you confirm
> it at the firmware-level MokManager screen on the next boot — so there is no
> Secure Boot password to set or remember.

---

## Requirements

- A computer in **UEFI** mode (not legacy BIOS/CSM).
- Secure Boot **enabled** in firmware (it can stay in the normal "User Mode" with
  the factory keys present — no Setup Mode needed).
- For VM testing: writable OVMF firmware + vars copies (see
  [Testing in a VM](#testing-in-a-vm)).

---

## 1. Booting the live ISO with Secure Boot

The live ISO is signed at build time with the shared Maze ISO key. The first time
you boot it with Secure Boot on, you enroll that key:

1. Boot the ISO. A blue **"Verification failed" / MOK Management** screen
   (MokManager) appears because the loader is not trusted yet.
2. Choose **Enroll key from disk**.
3. Select the **ISO's EFI system partition**, then the file **`MOK.cer`**.
4. **Continue** → **Yes** to enroll the key.
5. **Reboot**. The live session now boots normally with Secure Boot active.

**Verify** inside the live session:

```sh
mokutil --sb-state          # → "SecureBoot enabled"
```

If you would rather not enroll, just **disable Secure Boot in firmware** — the ISO
boots normally either way.

---

## 2. After installation (first boot of the installed system)

When you enable the **Secure Boot** toggle in the installer (it is **on by
default** on UEFI systems using systemd-boot + UKI), the installer:

- generates a **per-machine** key — its private half never leaves that computer;
- signs `systemd-boot` and the **Unified Kernel Image** (UKI);
- copies the certificate to the EFI system partition as **`/MOK.cer`** (and keeps
  a copy at `/var/lib/maze-secureboot/MOK.cer`);
- installs a **pacman hook** that re-signs the boot loader and kernel
  automatically after every kernel / initramfs / systemd-boot update.

On the **first reboot** the new boot loader is not trusted yet, so MokManager
appears again. Enroll the machine's own key once:

1. On the blue **MOK Management** screen, choose **Enroll key from disk**.
2. Select the **EFI system partition** volume, then the file **`MOK.cer`**.
3. **Continue** → **Yes** to enroll.
4. **Reboot** — the system now boots normally with Secure Boot enabled.

A copy of these instructions is written to the installed system at:

```
/var/lib/maze-secureboot/ENROLLMENT.txt
```

**Verify** after logging in:

```sh
mokutil --sb-state          # → "SecureBoot enabled"
```

### Kernel & system updates

Nothing to do. The pacman hook (`maze-sb-sign`) runs after any transaction that
touches the kernel, initramfs/UKI or systemd-boot, so updates stay signed and
the machine keeps booting with Secure Boot on. You do **not** re-enroll after
updates — the key is already trusted.

---

## Testing in a VM

Use **writable** OVMF code + vars copies so the enrolled key survives reboots:

```sh
cp /usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd /tmp/code.fd
cp /usr/share/edk2/x64/OVMF_VARS.4m.fd /tmp/vars.fd

qemu-system-x86_64 -m 4096 -enable-kvm \
    -machine q35,smm=on -global driver=cfi.pflash01,property=secure,value=on \
    -drive if=pflash,format=raw,unit=0,file=/tmp/code.fd,readonly=on \
    -drive if=pflash,format=raw,unit=1,file=/tmp/vars.fd \
    -cdrom out/mazelinux-*.iso -boot d
```

After installing into the VM disk, boot **without** `-cdrom` and complete the
[first-boot enrollment](#2-after-installation-first-boot-of-the-installed-system).

---

## Troubleshooting

**MokManager doesn't appear / it boots straight to "Verification failed" and
stops.** Your firmware may not be showing the prompt. Reboot once more; on most
machines the shim shows the blue screen on the next attempt. Make sure Secure
Boot is in normal **User Mode**, not disabled.

**"Enroll key from disk" can't find `MOK.cer`.** Pick the **EFI system
partition** volume (the small FAT partition), not the root filesystem. The file
is at the **root** of that partition.

**System won't boot after a manual kernel change.** Re-sign by hand from a
working environment (live ISO chroot or the installed system), pointing the
signer at the mounted EFI system partition:

```sh
maze-sb-sign /boot          # or wherever the ESP is mounted
```

**Check what is signed:**

```sh
sbverify --list /boot/EFI/BOOT/grubx64.efi   # adjust path to your loader
mokutil --list-enrolled                       # confirm the Maze key is enrolled
```

---

## Turning Secure Boot off

- **At install time:** turn the **Secure Boot** toggle **off** in the installer's
  *Bootloader* menu.
- **Later / from firmware:** disable Secure Boot in your firmware setup. The
  installed system and the live ISO both boot normally with it off.

---

## How it's built (for maintainers)

- ISO key lives in `keys/secureboot/` (generated once by `tools/gen-sb-keys.sh`).
  `build.sh` patches `mkarchiso` to inject the shim and sign systemd-boot + the
  kernel onto the ISO's `efiboot.img`.
- The installer's signer and pacman hook are defined in
  `airootfs/opt/maze-archinstall/archinstall/lib/installer.py`
  (`maze-sb-sign`, the pacman hook, and the enrollment note).
- `maze-sb-sign` takes the **ESP mountpoint** as its first argument; it must be
  explicit because `bootctl` is unreliable inside the install chroot.
