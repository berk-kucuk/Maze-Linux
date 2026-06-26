#!/usr/bin/env bash
#
# build-nocompress.sh — Build the Maze Linux ISO with NO squashfs compression.
#
# Identical to build.sh in every way EXCEPT it stores the airootfs squashfs
# UNCOMPRESSED (mksquashfs -noD -noF -noI -noX). That skips the slow zstd-22
# pass, so the ISO builds much faster — ideal for the tight
# build -> boot in a VM -> fix -> rebuild loop (e.g. while bringing up Calamares).
#
# Trade-off: the resulting .iso is large (~14.5 GB, the full uncompressed
# airootfs) instead of ~4-5 GB. Use the normal ./build.sh for release images.
# (For a middle ground — fast build, still small — swap the override below to
#  ('-comp' 'zstd' '-Xcompression-level' '1' '-b' '1M').)
#
# The compression setting lives in profiledef.sh; this script patches it
# temporarily at build time and restores it on exit (just like build.sh already
# does for the pacman.conf localrepo path), so the working tree stays clean.
#
# Usage:
#   sudo ./build-nocompress.sh [-w WORKDIR] [-o OUTDIR]
#
# Options:
#   -w WORKDIR   Temporary build directory (default: ./work)
#   -o OUTDIR    Output directory for the ISO (default: ./out)
#   -h           Show this help message
#
# Requirements:
#   - The 'archiso' package must be installed.
#   - Must be run as root (mkarchiso needs root privileges).
#
set -euo pipefail

PROFILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${PROFILE_DIR}/work"
OUTDIR="${PROFILE_DIR}/out"

usage() {
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while getopts ':w:o:h' opt; do
    case "${opt}" in
        w) WORKDIR="${OPTARG}" ;;
        o) OUTDIR="${OPTARG}" ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done

if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: this script must be run as root (try: sudo ./build-nocompress.sh)." >&2
    exit 1
fi

if ! command -v mkarchiso >/dev/null 2>&1; then
    echo "Error: mkarchiso not found. Install the 'archiso' package first." >&2
    exit 1
fi

# The package list pulls AUR packages (paru + custom packages) from the local
# repository produced by tools/build-aur.sh. Make sure it has been built first,
# otherwise pacstrap fails with "target not found".
if ! ls "${PROFILE_DIR}/localrepo/maze-aur.db".* >/dev/null 2>&1; then
    echo "Error: local AUR repo not found at ${PROFILE_DIR}/localrepo." >&2
    echo "       Build it first (as a normal user, NOT root):" >&2
    echo "           sudo pacman -S --needed devtools git   # one-time" >&2
    echo "           ./tools/build-aur.sh" >&2
    exit 1
fi

# Safely reset the work directory. An aborted/failed mkarchiso run can leave
# virtual filesystems (proc, sys, dev, run) mounted under work/. A plain
# `rm -rf` would recurse into those live mounts (and potentially the host's
# /dev), so unmount every mountpoint under WORKDIR first, then delete.
clean_workdir() {
    local wd="$1"
    [[ -e "${wd}" ]] || return 0
    local target
    while read -r target; do
        [[ -n "${target}" ]] || continue
        echo "   Unmounting leftover mount: ${target}"
        umount -R "${target}" 2>/dev/null || umount -Rl "${target}" 2>/dev/null || true
    done < <(findmnt -rno TARGET | awk -v p="${wd}" 'index($0, p) == 1' | sort -r)

    if findmnt -rno TARGET | awk -v p="${wd}" 'index($0, p) == 1' | grep -q .; then
        echo "Error: could not unmount everything under ${wd}; refusing to delete it." >&2
        exit 1
    fi
    rm -rf "${wd}"
}

# The [maze-aur] repo line in pacman.conf needs an ABSOLUTE file:// path, but
# hardcoding one machine's path breaks builds anywhere else. So rewrite it to
# THIS checkout's localrepo at build time, and restore the file afterwards
# (trap) so the working tree stays clean and portable.
PACMAN_CONF="${PROFILE_DIR}/pacman.conf"
PROFILEDEF="${PROFILE_DIR}/profiledef.sh"
PATCHED_MKARCHISO=""
restore_pacman_conf() { [[ -f "${PACMAN_CONF}.bak" ]] && mv -f "${PACMAN_CONF}.bak" "${PACMAN_CONF}"; }
restore_profiledef()  { [[ -f "${PROFILEDEF}.bak" ]]  && mv -f "${PROFILEDEF}.bak"  "${PROFILEDEF}"; }
_cleanup() {
    restore_pacman_conf
    restore_profiledef
    [[ -n "${PATCHED_MKARCHISO}" ]] && rm -f "${PATCHED_MKARCHISO}"
}
trap _cleanup EXIT
if grep -qE '^\s*Server\s*=\s*file://.*/localrepo' "${PACMAN_CONF}"; then
    cp -a "${PACMAN_CONF}" "${PACMAN_CONF}.bak"
    sed -i -E "s#^(\s*Server\s*=\s*file://).*/localrepo\s*#\1${PROFILE_DIR}/localrepo#" "${PACMAN_CONF}"
    echo "   maze-aur repo -> file://${PROFILE_DIR}/localrepo"
fi

# THE difference from build.sh: temporarily store the airootfs squashfs
# UNCOMPRESSED so the (slow) zstd pass is skipped. Restored on exit by _cleanup.
if grep -qE '^airootfs_image_tool_options=' "${PROFILEDEF}"; then
    cp -a "${PROFILEDEF}" "${PROFILEDEF}.bak"
    sed -i -E "s|^airootfs_image_tool_options=.*|airootfs_image_tool_options=('-noD' '-noF' '-noI' '-noX')|" "${PROFILEDEF}"
    echo "   squashfs compression -> DISABLED (uncompressed, fast build, large ISO)"
fi

# ---------------------------------------------------------------------------
# Secure Boot: produce a Maze-patched copy of mkarchiso that signs the EFI
# system partition (shim as the default loader + Maze-signed systemd-boot and
# kernel) so the live ISO boots with UEFI Secure Boot enabled. See
# tools/gen-sb-keys.sh and the appended _maze_sb_sign_esp function below.
# ---------------------------------------------------------------------------
MKARCHISO="$(command -v mkarchiso)"
SB_KEYDIR="${PROFILE_DIR}/keys/secureboot"

prepare_secureboot() {
    if ! command -v sbsign >/dev/null 2>&1; then
        echo "Error: 'sbsign' not found (needed to sign the ISO for Secure Boot)." >&2
        echo "       Install it with:  sudo pacman -S --needed sbsigntools" >&2
        exit 1
    fi
    # The shared ISO signing key is generated once and reused for every build so
    # users never have to re-enroll the Maze key.
    if [[ ! -f "${SB_KEYDIR}/Maze.key" ]]; then
        echo ">> Secure Boot: generating ISO signing key"
        "${PROFILE_DIR}/tools/gen-sb-keys.sh"
    fi
    export MAZE_SB_KEY="${SB_KEYDIR}/Maze.key"
    export MAZE_SB_CERT="${SB_KEYDIR}/Maze.crt"
    export MAZE_SB_CER="${SB_KEYDIR}/Maze.cer"

    local anchor='_make_bootmode_uefi.systemd-boot() {'
    local done_msg='_msg_info "Done! systemd-boot set up for UEFI booting successfully."'
    if ! grep -qF "${anchor}" "${MKARCHISO}" || ! grep -qF "${done_msg}" "${MKARCHISO}"; then
        echo "Error: could not find the expected anchors in ${MKARCHISO}." >&2
        echo "       archiso may have changed; the Secure Boot patch needs updating." >&2
        exit 1
    fi

    PATCHED_MKARCHISO="$(mktemp --tmpdir maze-mkarchiso.XXXXXX)"
    # Insert the _maze_sb_sign_esp definition among the other functions and a call
    # to it at the very end of the systemd-boot bootmode setup (after the loader,
    # the kernel and the initramfs are all on the FAT image).
    awk -v deffile="${SB_KEYDIR}/.maze_sb_func.sh" '
        index($0, "_make_bootmode_uefi.systemd-boot() {") && !fdone {
            while ((getline line < deffile) > 0) print line
            close(deffile); fdone = 1
        }
        index($0, "_msg_info \"Done! systemd-boot set up for UEFI booting successfully.\"") && !cdone {
            match($0, /^[ \t]*/); print substr($0, 1, RLENGTH) "_maze_sb_sign_esp"
            cdone = 1
        }
        { print }
        END { if (!fdone || !cdone) exit 3 }
    ' "${MKARCHISO}" > "${PATCHED_MKARCHISO}" || {
        echo "Error: failed to patch mkarchiso for Secure Boot." >&2
        exit 1
    }
    # Brand the EFI system partition's FAT label (cosmetic; shown by MokManager
    # and file managers). archiso hardcodes "ARCHISO_EFI"; nothing boots off this
    # label (the live medium is found via archisosearchuuid), so it is safe to
    # rename. FAT labels are max 11 chars, uppercase.
    sed -i 's/-n ARCHISO_EFI/-n MAZE_EFI/' "${PATCHED_MKARCHISO}"

    chmod +x "${PATCHED_MKARCHISO}"
    MKARCHISO="${PATCHED_MKARCHISO}"
    echo "   Secure Boot: using patched mkarchiso (${PATCHED_MKARCHISO})"
}

# The signing function injected into mkarchiso. Written to disk so awk can splice
# it in; it runs in mkarchiso's context (uses ${efibootimg}, ${pacstrap_dir}, ...).
write_sb_func() {
    mkdir -p "${SB_KEYDIR}"
    cat > "${SB_KEYDIR}/.maze_sb_func.sh" <<'MAZE_SB_FUNC'
_maze_sb_sign_esp() {
    # Maze Linux Secure Boot: on the EFI system partition, replace the default
    # systemd-boot loader with a Microsoft-signed shim, sign systemd-boot (as the
    # "grubx64.efi" name shim chainloads) and the kernel with the Maze key, and
    # drop the Maze certificate (MOK.cer) for one-time MokManager enrollment.
    # Uses the 8 MiB of slack _make_efibootimg reserves in the FAT image.
    [[ -n "${MAZE_SB_KEY:-}" ]] || { _msg_info "Maze Secure Boot: no key, skipping"; return 0; }

    local arch_uc="${uefi_arch[$arch]}"   # e.g. X64
    local arch_lc="${arch_uc,,}"          # e.g. x64
    local shim="${pacstrap_dir}/usr/share/shim-signed/shim${arch_lc}.efi"
    local mm="${pacstrap_dir}/usr/share/shim-signed/mm${arch_lc}.efi"

    if [[ ! -f "${shim}" ]]; then
        printf '%s\n' "Maze Secure Boot ERROR: ${shim} missing (add shim-signed to packages.x86_64)" >&2
        exit 1
    fi

    _msg_info "Maze Secure Boot: signing the EFI system partition"
    local tmp; tmp="$(mktemp -d)"

    # systemd-boot -> signed grubx64.efi (the second stage shim loads by default)
    sbsign --key "${MAZE_SB_KEY}" --cert "${MAZE_SB_CERT}" \
        --output "${tmp}/grub${arch_lc}.efi" \
        "${pacstrap_dir}/usr/lib/systemd/boot/efi/systemd-boot${arch_lc}.efi"

    # Default loader = shim; second stage = signed systemd-boot; + MokManager + cert
    local d
    for d in "::/EFI/BOOT/BOOT${arch_uc}.EFI" "::/EFI/BOOT/grub${arch_lc}.efi" \
             "::/EFI/BOOT/mm${arch_lc}.efi" "::/MOK.cer"; do
        mdel -i "${efibootimg}" "${d}" 2>/dev/null || true
    done
    mcopy -i "${efibootimg}" "${shim}"                   "::/EFI/BOOT/BOOT${arch_uc}.EFI"
    mcopy -i "${efibootimg}" "${tmp}/grub${arch_lc}.efi" "::/EFI/BOOT/grub${arch_lc}.efi"
    mcopy -i "${efibootimg}" "${mm}"                     "::/EFI/BOOT/mm${arch_lc}.efi"
    mcopy -i "${efibootimg}" "${MAZE_SB_CER}"            "::/MOK.cer"

    # Sign the kernel(s) on the FAT ESP; systemd-boot validates them via shim.
    local k base
    for k in "${pacstrap_dir}/boot/vmlinuz-"*; do
        [[ -e "${k}" ]] || continue
        base="$(basename -- "${k}")"
        sbsign --key "${MAZE_SB_KEY}" --cert "${MAZE_SB_CERT}" --output "${tmp}/${base}" "${k}"
        mdel -i "${efibootimg}" "::/${install_dir}/boot/${arch}/${base}" 2>/dev/null || true
        mcopy -i "${efibootimg}" "${tmp}/${base}" "::/${install_dir}/boot/${arch}/${base}"
    done

    # Mirror the shim chain into the ISO 9660 tree (used when the ISO contents are
    # copied onto a FAT partition by hand) and sign that kernel copy best-effort.
    install -m0644 "${shim}"                   "${isofs_dir}/EFI/BOOT/BOOT${arch_uc}.EFI"
    install -m0644 "${tmp}/grub${arch_lc}.efi" "${isofs_dir}/EFI/BOOT/grub${arch_lc}.efi"
    install -m0644 "${mm}"                     "${isofs_dir}/EFI/BOOT/mm${arch_lc}.efi"
    install -m0644 "${MAZE_SB_CER}"            "${isofs_dir}/MOK.cer"
    for k in "${isofs_dir}/${install_dir}/boot/${arch}/vmlinuz-"*; do
        [[ -e "${k}" ]] || continue
        sbsign --key "${MAZE_SB_KEY}" --cert "${MAZE_SB_CERT}" --output "${k}.signed" "${k}" \
            && mv -f "${k}.signed" "${k}"
    done

    rm -rf "${tmp}"
    _msg_info "Maze Secure Boot: EFI system partition signed"
}
MAZE_SB_FUNC
}

write_sb_func
prepare_secureboot
rm -f "${SB_KEYDIR}/.maze_sb_func.sh"

echo ">> Building Maze Linux ISO (UNCOMPRESSED / fast build)"
echo "   Profile : ${PROFILE_DIR}"
echo "   Work    : ${WORKDIR}"
echo "   Output  : ${OUTDIR}"

# Start from a clean work directory; a leftover root from a failed run causes
# "conflicting files" errors on the next build.
clean_workdir "${WORKDIR}"
mkdir -p "${WORKDIR}" "${OUTDIR}"

# Run mkarchiso inside a private mount namespace.
#
# On a systemd host the root filesystem is mounted "shared", so the API
# filesystems (proc, sys, dev) that pacstrap bind-mounts into the work dir
# inherit shared propagation. pacstrap then cannot tear them down cleanly,
# which leaves /proc mounted under work/.../airootfs at squashfs time —
# mksquashfs tries to archive the live /proc and floods
# "Read failed because Invalid argument". A private mount namespace isolates
# those mounts from the host and tears them down automatically when mkarchiso
# exits (success, failure or Ctrl+C), so nothing leaks back to the host.
if command -v unshare >/dev/null 2>&1; then
    unshare --mount --propagation private -- \
        "${MKARCHISO}" -v -w "${WORKDIR}" -o "${OUTDIR}" "${PROFILE_DIR}"
else
    echo "Warning: 'unshare' not found; running mkarchiso without mount isolation." >&2
    "${MKARCHISO}" -v -w "${WORKDIR}" -o "${OUTDIR}" "${PROFILE_DIR}"
fi

echo ">> Done. UNCOMPRESSED ISO image is available in: ${OUTDIR}"
