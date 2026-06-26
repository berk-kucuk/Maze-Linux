#!/bin/sh
# Maze Linux — prepare the Calamares OFFLINE target before initcpiocfg/initcpio/
# bootloader run. Called by the `shellprocess@mountapi` step (un-chrooted) with
# the target mountpoint as $1 (Calamares substitutes ${ROOT}). The logic lives in
# this script so Calamares never tries to expand the internal $R/$d shell vars.
#
# It does three things, all needed because the OFFLINE model copies the WHOLE
# live archiso system onto the target via unpackfs:
#
#   1) Mount /dev /proc /sys /run into the target. Calamares runs initcpiocfg/
#      initcpio/bootloader via a PLAIN chroot (not arch-chroot), so without these
#      mkinitcpio aborts with "==> ERROR: /dev must be mounted!".
#
#   2) De-archiso the target's mkinitcpio. unpackfs copied the LIVE preset
#      (/etc/mkinitcpio.d/*.preset set to the 'archiso' preset) and
#      /etc/mkinitcpio.conf.d/archiso.conf — these build the LIVE ISO image and
#      fail on an installed system. Remove the conf.d override and rewrite each
#      preset to a stock (default + fallback) preset so a NORMAL initramfs builds.
#
#   3) Ensure the kernel image is in the target /boot. mkarchiso often keeps
#      vmlinuz only on the boot medium, not in the squashfs, so /boot/vmlinuz-*
#      can be missing on the target. Copy it from /usr/lib/modules/<kver>/vmlinuz
#      (always present in the squashfs) to /boot/vmlinuz-<pkgbase>.
#
# Idempotent; the `umount` module tears the mounts down later.
set -e

R="$1"
[ -n "$R" ] || { echo "calamares-prepare-target: no target root given" >&2; exit 1; }

# --- 1) API/pseudo filesystems --------------------------------------------
# Mount FRESH pseudo-filesystems (exactly like arch-chroot), NOT `mount --rbind`
# of the live ones. An rbind inherits shared mount propagation, so when these are
# later torn down (or a failed install leaves them), the unmount propagates BACK
# to the live system and unmounts its /dev/pts — which breaks pty allocation in
# the live session ("sudo: unable to allocate pty: No such device"). Fresh,
# private instances never touch the host.
mountpoint -q "$R/proc"     || mount -t proc     proc   "$R/proc"     -o nosuid,noexec,nodev
mountpoint -q "$R/sys"      || mount -t sysfs    sys    "$R/sys"      -o nosuid,noexec,nodev
mountpoint -q "$R/dev"      || mount -t devtmpfs udev   "$R/dev"      -o mode=0755,nosuid
mkdir -p "$R/dev/pts" "$R/dev/shm"
mountpoint -q "$R/dev/pts"  || mount -t devpts   devpts "$R/dev/pts"  -o mode=0620,gid=5,nosuid,noexec
mountpoint -q "$R/dev/shm"  || mount -t tmpfs    shm    "$R/dev/shm"  -o mode=1777,nosuid,nodev
mountpoint -q "$R/run"      || mount -t tmpfs    run    "$R/run"      -o mode=0755,nosuid,nodev
# efivarfs so bootctl / kernel-install can read EFI variables (UEFI installs).
if [ -d /sys/firmware/efi/efivars ]; then
    mountpoint -q "$R/sys/firmware/efi/efivars" \
        || mount -t efivarfs efivarfs "$R/sys/firmware/efi/efivars" 2>/dev/null || true
fi

# --- 2) Replace the archiso mkinitcpio setup with a stock one -------------
rm -f "$R/etc/mkinitcpio.conf.d/archiso.conf"
for preset in "$R"/etc/mkinitcpio.d/*.preset; do
    [ -f "$preset" ] || continue
    grep -q archiso "$preset" 2>/dev/null || continue
    k=$(basename "$preset" .preset)        # e.g. 'linux'
    echo "calamares-prepare-target: restoring stock mkinitcpio preset for $k"
    cat > "$preset" <<PRESET
# mkinitcpio preset for '$k' (restored by the Maze installer; was the archiso preset)
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-$k"

PRESETS=('default' 'fallback')

default_image="/boot/initramfs-$k.img"

fallback_image="/boot/initramfs-$k-fallback.img"
fallback_options="-S autodetect"
PRESET
done

# --- 3) Make sure the kernel image is present in the target /boot ---------
for moddir in "$R"/usr/lib/modules/*/; do
    [ -f "$moddir/vmlinuz" ] || continue
    pkgbase=$(cat "$moddir/pkgbase" 2>/dev/null || echo linux)
    if [ ! -e "$R/boot/vmlinuz-$pkgbase" ]; then
        echo "calamares-prepare-target: installing /boot/vmlinuz-$pkgbase from modules"
        cp "$moddir/vmlinuz" "$R/boot/vmlinuz-$pkgbase"
    fi
done

# --- 4) Purge the live 'maze' user's leftover home ------------------------
# unpackfs copied the live user 'maze' and its /home/maze. The `removeuser`
# module (later in the sequence) drops the ACCOUNT, but we must remove the home
# HERE — BEFORE the `users` module creates the real account — so that even if the
# installer's new user is ALSO named 'maze' it gets a FRESH skel home instead of
# inheriting the live session's config (and so deploy-to-target never has to, and
# must never, delete a real user's home).
rm -rf "$R/home/maze"

echo "calamares-prepare-target: target prepared under $R"
