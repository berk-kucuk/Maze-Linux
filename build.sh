#!/usr/bin/env bash
#
# build.sh — Build the Maze Linux ISO image with archiso/mkarchiso.
#
# Usage:
#   sudo ./build.sh [-w WORKDIR] [-o OUTDIR]
#
# Options:
#   -w WORKDIR   Temporary build directory (default: /tmp/mazelinux-build/work —
#                RAM-backed tmpfs, never the disk the checkout lives on; see
#                ensure_workdir_space for the sizing rules)
#   -o OUTDIR    Output directory for the ISO (default: ./out)
#   -h           Show this help message
#
# Requirements:
#   - The 'archiso' package must be installed.
#   - Must be run as root (mkarchiso needs root privileges).
#
# Every run is transcribed to MazeLinux/logs/build-<timestamp>.log while still
# printing to the terminal. Set MAZE_BUILD_LOG=0 to turn that off.
#
set -euo pipefail

PROFILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# NOT under the checkout. This tree normally lives on an external USB-C SSD, and
# a build is ~16 GiB of small-file writes followed by a zstd -22 mksquashfs pass —
# a load that has locked up the USB bridge chip here more than once (the disk
# drops off the bus, the filesystem goes read-only, mkarchiso dies with SIGBUS
# 40 minutes in). /tmp is a tmpfs: RAM-backed, internal, and gone at reboot.
# ensure_workdir_space() below makes sure it is actually big enough first.
WORKDIR="/tmp/mazelinux-build/work"
OUTDIR="${PROFILE_DIR}/out"
LOGDIR="${PROFILE_DIR}/logs"

# ── Transcript ────────────────────────────────────────────────────────────────
# An ISO build prints thousands of lines over the better part of an hour, and the
# one line that matters — a failed pacman hook, a missing firmware warning, a
# package that resolved to the wrong version — scrolls past long before the build
# ends. Keep the terminal live AND write the whole thing to a file.
#
# Done by re-executing through `tee` rather than `exec > >(tee …)`: process
# substitution can lose the tail of the output when the script exits, and the
# exit status needs preserving so a failed build still fails. PIPESTATUS carries
# it back. As a side effect the child sees a pipe rather than a tty, so pacman
# and mkarchiso drop their colour codes and progress redraws — which is exactly
# what you want in a file you might paste into a bug report.
#
# Set MAZE_BUILD_LOG=0 to skip logging entirely.
if [[ -z "${MAZE_BUILD_LOG_ACTIVE:-}" && "${MAZE_BUILD_LOG:-1}" != "0" ]]; then
    export MAZE_BUILD_LOG_ACTIVE=1
    mkdir -p "${LOGDIR}"
    _logfile="${LOGDIR}/build-$(date +%Y%m%d-%H%M%S).log"
    printf '>> Build log: %s\n\n' "${_logfile}"
    {
        printf '# Maze Linux ISO build\n'
        printf '# started : %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
        printf '# host    : %s\n' "$(uname -n)"
        printf '# kernel  : %s\n' "$(uname -r)"
        printf '# command : %s %s\n' "${BASH_SOURCE[0]}" "$*"
        printf '\n'
    } > "${_logfile}"
    set +e
    "${BASH_SOURCE[0]}" "$@" 2>&1 | tee -a "${_logfile}"
    _rc="${PIPESTATUS[0]}"
    set -e
    {
        printf '\n# finished: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
        printf '# exit    : %s\n' "${_rc}"
    } >> "${_logfile}"
    printf '\n>> Build log written to: %s\n' "${_logfile}"
    exit "${_rc}"
fi

usage() {
    sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
    echo "Error: this script must be run as root (try: sudo ./build.sh)." >&2
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

# ---------------------------------------------------------------------------
# Pre-flight: report which published packages ./localrepo will OVERRIDE.
#
# pacman.conf lists [maze-aur] (./localrepo) BEFORE [mazelinux] on purpose, and
# pacman resolves a name from the first repo that carries it WITHOUT comparing
# versions across repos. That makes ./localrepo a staging area — a freshly built
# package dropped there ships in the next ISO instead of the published one, so a
# new version can be proven in a real ISO before it is pushed to the public repo.
#
# The same rule means a stale file left in ./localrepo would silently ship in
# place of the published package (this has bitten before: an ancient
# entropy-shield/haze/sentinai set sat there for months). So never let it be
# silent — list every override, every build, and say what is being replaced.
# ---------------------------------------------------------------------------
if command -v expac >/dev/null 2>&1 || command -v pacman >/dev/null 2>&1; then
    _overrides=()
    for _pkgfile in "${PROFILE_DIR}"/localrepo/*.pkg.tar.*; do
        [[ -e "${_pkgfile}" ]] || continue
        # Read the name/version from the package itself; filename parsing breaks
        # on epochs (e.g. foo-1:2.3-1-x86_64.pkg.tar.zst).
        _l="$(pacman -Qip "${_pkgfile}" 2>/dev/null)" || continue
        _n="$(printf '%s\n' "${_l}" | awk -F': +' '/^Name +:/{print $2; exit}')"
        _v="$(printf '%s\n' "${_l}" | awk -F': +' '/^Version +:/{print $2; exit}')"
        [[ -n "${_n}" ]] || continue
        # Is this name also published in [mazelinux]? If so, the local copy wins.
        # `|| true` is load-bearing: this script runs under `set -euo pipefail`,
        # and pacman -Si exits non-zero for any name that is in NO repo (every
        # AUR package in ./localrepo — calamares, upscayl-bin, shim-signed...).
        # With pipefail that failure propagates out of the pipeline, the
        # assignment fails, and set -e would kill the whole build silently — no
        # output at all, which is exactly what it did before this guard.
        _pub="$( { pacman -Si "${_n}" 2>/dev/null || true; } \
                 | awk -F': +' '/^Repository +: +mazelinux$/{f=1} f&&/^Version +:/{print $2; exit}')"
        [[ -n "${_pub}" ]] && _overrides+=("${_n}  ${_v}  (published: ${_pub})")
    done
    if [[ ${#_overrides[@]} -gt 0 ]]; then
        echo
        echo "   >> local repo OVERRIDES ${#_overrides[@]} published package(s):"
        printf '        %s\n' "${_overrides[@]}"
        echo "      The ISO will ship the ./localrepo copies, NOT the published ones."
        echo "      Intended for testing before publishing — remove the files to undo."
        echo
    else
        echo "   Local repo    : OK (overrides nothing published in [mazelinux])"
    fi
fi

# packages.x86_64 pulls `mazelinux-keyring` and `maze-meta` from the remote
# [mazelinux] repo (SigLevel = Required) — neither is in ./localrepo, so there is
# no unsigned fallback. pacstrap verifies those signatures against the BUILD
# HOST's keyring, which means the Maze signing key has to be trusted here before
# the build starts. Without it pacstrap dies mid-run with an opaque "required key
# ... is missing from keyring" (on the keyring package itself — the usual
# bootstrap chicken-and-egg), so check up front and say exactly how to fix it.
MAZE_KEY_FPR="7C4D515A6B930CB04794CEF6147C8159B3E2EE5F"
if ! pacman-key --list-keys "${MAZE_KEY_FPR}" >/dev/null 2>&1; then
    echo "Error: the Maze Linux signing key is not trusted by this build host." >&2
    echo "       [mazelinux] uses SigLevel = Required, so pacstrap cannot verify" >&2
    echo "       mazelinux-keyring / maze-meta without it. Import it once:" >&2
    echo "           sudo pacman-key --add /path/to/mazelinux.gpg" >&2
    echo "           sudo pacman-key --lsign-key ${MAZE_KEY_FPR}" >&2
    echo "       (mazelinux.gpg lives in the maze-keyring project.)" >&2
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
    # Match the workdir itself or paths UNDER it (p + "/"), never a sibling
    # that merely shares the prefix (e.g. ./work must not match ./work2).
    while read -r target; do
        [[ -n "${target}" ]] || continue
        echo "   Unmounting leftover mount: ${target}"
        umount -R "${target}" 2>/dev/null || umount -Rl "${target}" 2>/dev/null || true
    done < <(findmnt -rno TARGET | awk -v p="${wd}" '$0 == p || index($0, p "/") == 1' | sort -r)

    if findmnt -rno TARGET | awk -v p="${wd}" '$0 == p || index($0, p "/") == 1' | grep -q .; then
        echo "Error: could not unmount everything under ${wd}; refusing to delete it." >&2
        exit 1
    fi
    rm -rf "${wd}"
}

# ---------------------------------------------------------------------------
# Pre-flight: validate the Firefox enterprise policy.
#
# airootfs/etc/firefox/policies/policies.json is the ONLY thing configuring
# Firefox on the live ISO (start page, telemetry off, tracking protection, DoH).
# Firefox parses it silently: a single stray comma makes it discard the file and
# fall back to stock defaults with no error anywhere the user would look — the
# ISO builds and boots "fine", just unconfigured. mkarchiso copies airootfs
# verbatim, so nothing downstream would catch it either. Fail the build instead.
# ---------------------------------------------------------------------------
FF_POLICY="${PROFILE_DIR}/airootfs/etc/firefox/policies/policies.json"
if [[ -f "${FF_POLICY}" ]]; then
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 -m json.tool "${FF_POLICY}" >/dev/null 2>&1; then
            echo "Error: ${FF_POLICY} is not valid JSON." >&2
            echo "       Firefox would silently ignore it and ship with stock defaults." >&2
            python3 -m json.tool "${FF_POLICY}" >/dev/null || true
            exit 1
        fi
        # A valid JSON document that is missing the top-level "policies" key parses
        # fine and is still ignored wholesale — check the key exists too.
        if ! python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if isinstance(d.get("policies"), dict) else 1)' \
                "${FF_POLICY}" 2>/dev/null; then
            echo "Error: ${FF_POLICY} has no top-level \"policies\" object." >&2
            echo "       Firefox requires that wrapper; without it every setting is ignored." >&2
            exit 1
        fi
        echo "   Firefox policy : OK (${FF_POLICY#"${PROFILE_DIR}"/})"
    else
        echo "Warning: python3 not found — skipping the Firefox policy JSON check." >&2
    fi
else
    echo "Warning: ${FF_POLICY} is missing; the live ISO will ship stock Firefox defaults." >&2
fi

# The [maze-aur] repo line in pacman.conf needs an ABSOLUTE file:// path, but
# hardcoding one machine's path breaks builds anywhere else. So rewrite it to
# THIS checkout's localrepo at build time, and restore the file afterwards
# (trap) so the working tree stays clean and portable.
PACMAN_CONF="${PROFILE_DIR}/pacman.conf"
PATCHED_MKARCHISO=""

# A leftover .bak means a previous run died before its EXIT trap could restore the
# file (e.g. the work disk went read-only mid-build). Stop here: the grep below
# matches the ALREADY-PATCHED absolute path just as happily as the portable one, so
# a blind `cp -a` would overwrite the pristine backup with the patched copy and lose
# `file://./localrepo` for good. Checked BEFORE the trap is installed, so exiting
# here cannot make the trap quietly restore the very file we are flagging.
if [[ -e "${PACMAN_CONF}.bak" ]]; then
    echo "Error: ${PACMAN_CONF}.bak already exists — a previous build did not restore it." >&2
    echo "       Refusing to overwrite it (that would lose the portable file:// path)." >&2
    echo "       Compare the two files, then restore by hand:" >&2
    echo "           mv ${PACMAN_CONF}.bak ${PACMAN_CONF}" >&2
    exit 1
fi

# Always return 0: this runs inside the EXIT trap with errexit active, and a
# "nothing to restore" non-zero here would abort the trap before the tempfile
# cleanup below. A FAILED restore is a different matter from "nothing to restore",
# though — say so loudly instead of swallowing it, because it leaves the working
# tree carrying this machine's absolute path.
restore_pacman_conf() {
    [[ -f "${PACMAN_CONF}.bak" ]] || return 0
    if ! mv -f "${PACMAN_CONF}.bak" "${PACMAN_CONF}"; then
        echo "Error: could not restore ${PACMAN_CONF} (read-only fs? disk full?)." >&2
        echo "       The working tree is left patched. Restore it by hand:" >&2
        echo "           mv ${PACMAN_CONF}.bak ${PACMAN_CONF}" >&2
    fi
    return 0
}
_cleanup() { restore_pacman_conf; [[ -n "${PATCHED_MKARCHISO}" ]] && rm -f "${PATCHED_MKARCHISO}"; return 0; }
trap _cleanup EXIT
if grep -qE '^\s*Server\s*=\s*file://.*/localrepo' "${PACMAN_CONF}"; then
    cp -a "${PACMAN_CONF}" "${PACMAN_CONF}.bak"
    sed -i -E "s#^(\s*Server\s*=\s*file://).*/localrepo\s*#\1${PROFILE_DIR}/localrepo#" "${PACMAN_CONF}"
    echo "   maze-aur repo -> file://${PROFILE_DIR}/localrepo"
fi

# ---------------------------------------------------------------------------
# Secure Boot: produce a Maze-patched copy of mkarchiso that replaces the ESP's
# default systemd-boot with a shim -> Unified Kernel Image chain (shim as the
# default loader, Maze-signed UKI as grubx64.efi) so the live ISO boots with
# UEFI Secure Boot enabled on EVERY firmware — strict ones (MSI/ASUS) that
# ignore the MOK for loose kernels and only consult their db no longer reject
# the boot, because the kernel is embedded in the UKI and never loaded via a
# separate firmware LoadImage(). See tools/gen-sb-keys.sh and the appended
# _maze_sb_sign_esp function below.
# ---------------------------------------------------------------------------
MKARCHISO="$(command -v mkarchiso)"
SB_KEYDIR="${PROFILE_DIR}/keys/secureboot"

prepare_secureboot() {
    if ! command -v sbsign >/dev/null 2>&1; then
        echo "Error: 'sbsign' not found (needed to sign the ISO for Secure Boot)." >&2
        echo "       Install it with:  sudo pacman -S --needed sbsigntools" >&2
        exit 1
    fi
    if ! command -v ukify >/dev/null 2>&1; then
        echo "Error: 'ukify' not found (needed to build the Unified Kernel Image for Secure Boot)." >&2
        echo "       Install it with:  sudo pacman -S --needed systemd-ukify" >&2
        exit 1
    fi
    if [[ ! -f /usr/lib/systemd/boot/efi/linuxx64.efi.stub ]]; then
        echo "Error: linuxx64.efi.stub not found (provided by the 'systemd' package)." >&2
        echo "       Install it with:  sudo pacman -S --needed systemd" >&2
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
    # Guard the two sed targets below the same way: if archiso renames the FAT
    # slack formula, the sed would silently no-op and the build would only fail
    # much later ("Disk full" while mcopy-ing the ~261 MiB UKI). Fail fast here
    # instead. (grep -F: the pattern contains $1/()+ which regex grep mangles.)
    if ! grep -qF 'byte_to_kib($1)+8192)' "${MKARCHISO}"; then
        echo "Error: FAT slack formula not found in ${MKARCHISO}." >&2
        echo "       archiso changed _make_efibootimg; update the slack sed in build.sh." >&2
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
    # archiso reserves only 8 MiB of slack in the FAT image (_make_efibootimg).
    # That is enough for the stock shim+systemd-boot+kernel layout, but the UKI
    # is a single ~261 MiB PE binary that must be written contiguously after the
    # stock files are deleted — FAT cluster overhead and fragmentation eat into
    # that 8 MiB margin and mcopy can hit "disk full". Bump the slack to 64 MiB
    # so the image always has room for the UKI reshuffle.
    sed -i 's/byte_to_kib($1)+8192)/byte_to_kib($1)+65536)/' "${PATCHED_MKARCHISO}"

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
    # Maze Linux Secure Boot: build a Unified Kernel Image (kernel + initramfs +
    # cmdline, glued together by the systemd PE stub) and install it as
    # grubx64.efi — the second stage shim chainloads by that exact name. The
    # shim ALWAYS verifies its second stage through its own shim_lock protocol
    # (MOK-backed), never via the firmware's db. Because the kernel is already
    # embedded inside the UKI, no separate LoadImage() of vmlinuz happens, so
    # strict firmwares (MSI, some ASUS, etc.) that ignore the MOK for kernels
    # and only consult their db no longer reject the boot with
    # "Security Policy Violation". This makes the chain portable across every
    # UEFI machine instead of depending on per-vendor firmware behaviour.
    # Also drops the Maze certificate (MOK.cer) for one-time MokManager
    # enrollment. Uses the slack _make_efibootimg reserves in the FAT image.
    [[ -n "${MAZE_SB_KEY:-}" ]] || { _msg_info "Maze Secure Boot: no key, skipping"; return 0; }

    local arch_uc="${uefi_arch[$arch]}"   # e.g. X64
    local arch_lc="${arch_uc,,}"          # e.g. x64
    local shim="${pacstrap_dir}/usr/share/shim-signed/shim${arch_lc}.efi"
    local mm="${pacstrap_dir}/usr/share/shim-signed/mm${arch_lc}.efi"

    if [[ ! -f "${shim}" ]]; then
        printf '%s\n' "Maze Secure Boot ERROR: ${shim} missing (add shim-signed to packages.x86_64)" >&2
        exit 1
    fi

    # The systemd PE stub lives in the HOST's systemd package (not pacstrap_dir)
    # because ukify runs on the build host, not inside the image.
    local stub="/usr/lib/systemd/boot/efi/linux${arch_lc}.efi.stub"
    if [[ ! -f "${stub}" ]]; then
        printf '%s\n' "Maze Secure Boot ERROR: ${stub} missing on the build host (install systemd)" >&2
        exit 1
    fi

    # Collect kernel + matching initramfs from the pacstrap root. archiso's
    # _make_boot_on_iso9660 installs the mainline "linux" package, whose files
    # are named vmlinuz-linux / initramfs-linux.img (NOT vmlinuz-<arch>). We
    # only embed the regular image; the fallback initramfs is intentionally
    # left out of the UKI to keep it lean and the cmdline deterministic.
    local vmlinuz initramfs
    vmlinuz="${pacstrap_dir}/boot/vmlinuz-linux"
    initramfs="${pacstrap_dir}/boot/initramfs-linux.img"
    if [[ ! -f "${vmlinuz}" || ! -f "${initramfs}" ]]; then
        printf '%s\n' "Maze Secure Boot ERROR: kernel/initramfs not found under ${pacstrap_dir}/boot" >&2
        exit 1
    fi

    _msg_info "Maze Secure Boot: building + signing the Unified Kernel Image"
    local tmp; tmp="$(mktemp -d)"

    # Kernel command line — must match efiboot/loader/entries/01-archiso-linux.conf
    # verbatim (modulo the placeholders, which mkarchiso already substituted into
    # ${install_dir} and ${iso_uuid} by the time this runs).
    local cmdline="archisobasedir=${install_dir} archisosearchuuid=${iso_uuid} quiet splash bgrt_disable logo.nologo lsm=landlock,lockdown,yama,integrity,apparmor,bpf apparmor=1 security=apparmor"

    # Build the UKI. --cmdline=@file would be safer for weird chars, but the
    # archiso cmdline has none; passing it inline is fine and avoids quoting
    # headaches across awk/heredoc/mkarchiso layers. Microcode (if archiso
    # detected it is NOT embedded in the initramfs) is prepended BEFORE the
    # main initramfs — the stub concatenates --initrd= in order and the CPU
    # microcode must come first to take effect during early boot.
    local ukify_args=(
        build
        --linux="${vmlinuz}"
        --cmdline="${cmdline}"
        --stub="${stub}"
        --output="${tmp}/maze-linux.efi"
    )
    if (( need_external_ucodes )); then
        local uc
        for uc in "${ucodes[@]}"; do
            [[ -e "${pacstrap_dir}/boot/${uc}" ]] && ukify_args+=(--initrd="${pacstrap_dir}/boot/${uc}")
        done
    fi
    ukify_args+=(--initrd="${initramfs}")
    ukify "${ukify_args[@]}"

    # Sign the UKI with the Maze key and rename to the name shim expects.
    sbsign --key "${MAZE_SB_KEY}" --cert "${MAZE_SB_CERT}" \
        --output "${tmp}/grub${arch_lc}.efi" \
        "${tmp}/maze-linux.efi"

    # Free up space on the FAT BEFORE writing the UKI. The UKI (~261 MiB) is a
    # single large file; the FAT image was sized for the stock archiso layout
    # (separate vmlinuz + initramfs + fallback + microcode) plus only a small
    # slack margin. If we copy the UKI while the old kernel/initramfs are still
    # on the image, mcopy hits "Disk full". Delete everything we replace first,
    # then write the new files into the freed space.
    local d
    for d in "::/EFI/BOOT/BOOT${arch_uc}.EFI" "::/EFI/BOOT/grub${arch_lc}.efi" \
             "::/EFI/BOOT/mm${arch_lc}.efi" "::/EFI/BOOT/systemd${arch_lc}.efi" \
             "::/MOK.cer"; do
        mdel -i "${efibootimg}" "${d}" 2>/dev/null || true
    done
    # Drop the loose kernel/initramfs/microcode from the ESP — they now live
    # inside the UKI, and leaving unsigned copies on the FAT could confuse some
    # firmware boot entries or trigger spurious verification failures.
    mdel -i "${efibootimg}" "::/${install_dir}/boot/${arch}/vmlinuz-linux" 2>/dev/null || true
    mdel -i "${efibootimg}" "::/${install_dir}/boot/${arch}/initramfs-linux.img" 2>/dev/null || true
    mdel -i "${efibootimg}" "::/${install_dir}/boot/${arch}/initramfs-linux-fallback.img" 2>/dev/null || true
    # External microcode images (if any) are now inside the UKI too.
    if (( need_external_ucodes )); then
        local uc
        for uc in "${ucodes[@]}"; do
            mdel -i "${efibootimg}" "::/${install_dir}/boot/${uc}" 2>/dev/null || true
        done
    fi

    # Default loader = shim; second stage = signed UKI; + MokManager + cert.
    mcopy -i "${efibootimg}" "${shim}"                   "::/EFI/BOOT/BOOT${arch_uc}.EFI"
    mcopy -i "${efibootimg}" "${tmp}/grub${arch_lc}.efi" "::/EFI/BOOT/grub${arch_lc}.efi"
    mcopy -i "${efibootimg}" "${mm}"                     "::/EFI/BOOT/mm${arch_lc}.efi"
    mcopy -i "${efibootimg}" "${MAZE_SB_CER}"            "::/MOK.cer"

    # Mirror the shim chain into the ISO 9660 tree (used when the ISO contents
    # are copied onto a FAT partition by hand). The loose kernel already on the
    # ISO9660 tree is left as-is: shim never reaches it (the UKI is the only
    # thing the shim chainloads), so it does not need to be signed.
    install -m0644 "${shim}"                   "${isofs_dir}/EFI/BOOT/BOOT${arch_uc}.EFI"
    install -m0644 "${tmp}/grub${arch_lc}.efi" "${isofs_dir}/EFI/BOOT/grub${arch_lc}.efi"
    install -m0644 "${mm}"                     "${isofs_dir}/EFI/BOOT/mm${arch_lc}.efi"
    install -m0644 "${MAZE_SB_CER}"            "${isofs_dir}/MOK.cer"

    rm -rf "${tmp}"
    _msg_info "Maze Secure Boot: Unified Kernel Image built and signed"
}
MAZE_SB_FUNC
}

write_sb_func
prepare_secureboot
rm -f "${SB_KEYDIR}/.maze_sb_func.sh"

echo ">> Building Maze Linux ISO"
echo "   Profile : ${PROFILE_DIR}"
echo "   Work    : ${WORKDIR}"
echo "   Output  : ${OUTDIR}"

# With -w pointing at the checkout (the old default) on a USB disk,
# the whole build lands there too — ~14 GiB of small-file writes followed by a
# zstd -22 mksquashfs pass. USB-NVMe bridge chips are known to lock up under
# exactly that load; when one drops off the bus the filesystem remounts read-only
# and mkarchiso dies with SIGBUS (it mmaps the files it is writing), taking the
# build with it. Warn early rather than 40 minutes in. Purely advisory: any
# detection hiccup must never block a build, hence the fallbacks to "".
warn_if_workdir_on_usb() {
    local dir src tran
    # WORKDIR normally does NOT exist yet at this point (clean_workdir deletes it,
    # and it is absent entirely on a fresh checkout), and `findmnt --target` yields
    # nothing for a path that is not there — so walk up to the nearest existing
    # ancestor first, otherwise the warning would silently never fire.
    dir="${WORKDIR}"
    while [[ ! -e "${dir}" && "${dir}" != "/" && "${dir}" != "." ]]; do
        dir="$(dirname "${dir}")"
    done
    src="$(findmnt -no SOURCE --target "${dir}" 2>/dev/null)" || return 0
    # On btrfs findmnt appends the subvolume — "/dev/mapper/x[/@]" — which is not a
    # block device path; strip it so the -b test and lsblk still work.
    src="${src%%\[*}"
    [[ -b "${src}" ]] || return 0
    # -s walks towards the backing devices, so a dm-crypt/LVM mapper still
    # resolves to the physical disk and a USB enclosure is detected through it.
    tran="$(lsblk -nso TRAN "${src}" 2>/dev/null | grep -m1 . || true)"
    [[ "${tran}" == "usb" ]] || return 0
    echo >&2
    echo "Warning: the work directory is on a USB device (${src})." >&2
    echo "         Sustained build I/O has hung USB bridge chips mid-build here." >&2
    echo "         Prefer internal storage:  sudo ./build.sh -w /var/tmp/maze-work" >&2
    echo "         (-o may stay on the USB disk; the ISO is one sequential write.)" >&2
    echo >&2
}
warn_if_workdir_on_usb

# The work directory needs room for the unpacked root (~11 GiB), the package
# cache, the squashfs and the ISO staging tree: ~16 GiB today, so 24 GiB is the
# floor. On a tmpfs that space is RAM: Arch mounts /tmp at half of physical
# memory, which on a 32 GiB machine is 16 GiB — enough to get most of the way
# through a build and then fail at mksquashfs. So: measure, and if the tmpfs is
# too small, grow it (a remount, in effect until reboot) — but only when the
# machine has the memory to back it, because a tmpfs that outgrows RAM does not
# fail cleanly, it swaps the whole desktop out. Otherwise say exactly what to do.
_NEED_GIB=24
ensure_workdir_space() {
    local dir mp fstype avail_gib size_gib mem_gib want_gib
    dir="${WORKDIR}"
    while [[ ! -e "${dir}" && "${dir}" != "/" ]]; do dir="$(dirname "${dir}")"; done
    mp="$(findmnt -no TARGET --target "${dir}" 2>/dev/null)" || return 0
    fstype="$(findmnt -no FSTYPE --target "${dir}" 2>/dev/null)" || return 0
    avail_gib=$(( $(df -k --output=avail "${dir}" | tail -1) / 1024 / 1024 ))
    if [[ "${fstype}" != "tmpfs" ]]; then
        if (( avail_gib < _NEED_GIB )); then
            echo "Error: only ${avail_gib} GiB free on ${mp} for the work directory; a build needs ~${_NEED_GIB} GiB." >&2
            echo "       Pick another location:  sudo ./build.sh -w /var/tmp/mazelinux-work" >&2
            exit 1
        fi
        return 0
    fi
    (( avail_gib >= _NEED_GIB )) && { echo "   Work fs : tmpfs ${mp}, ${avail_gib} GiB free"; return 0; }
    mem_gib=$(( $(awk '/^MemTotal/{print $2}' /proc/meminfo) / 1024 / 1024 ))
    size_gib=$(( $(df -k --output=size "${mp}" | tail -1) / 1024 / 1024 ))
    want_gib=$(( size_gib - avail_gib + _NEED_GIB ))     # what is used now + what we need
    # Leave the desktop at least 8 GiB of real memory beside the build.
    if (( want_gib + 8 > mem_gib )); then
        echo "Error: ${mp} is a ${size_gib} GiB tmpfs with ${avail_gib} GiB free; a build needs ~${_NEED_GIB} GiB" >&2
        echo "       and this machine has ${mem_gib} GiB RAM — not enough to grow it safely." >&2
        echo "       Build on the internal disk instead:  sudo ./build.sh -w /var/tmp/mazelinux-work" >&2
        exit 1
    fi
    echo "   Work fs : tmpfs ${mp} is ${size_gib} GiB (${avail_gib} GiB free) — growing it to ${want_gib} GiB for this build (until reboot)"
    if ! mount -o "remount,size=${want_gib}G" "${mp}"; then
        echo "Error: could not grow ${mp}. Build on the internal disk instead:  sudo ./build.sh -w /var/tmp/mazelinux-work" >&2
        exit 1
    fi
}
ensure_workdir_space

# On a tmpfs the work directory is RAM: 16 GiB of it, held until someone
# remembers. Release it once the ISO is out and verified. On a real disk it is
# left alone (a failed build is worth inspecting; a successful one is cheap).
release_tmpfs_workdir() {
    [[ "$(findmnt -no FSTYPE --target "${WORKDIR}" 2>/dev/null)" == "tmpfs" ]] || return 0
    echo ">> Work directory is on tmpfs (RAM) — removing ${WORKDIR}"
    clean_workdir "${WORKDIR}"
}

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

# ---------------------------------------------------------------------------
# ÇIKIŞ KAPISI. Boot zinciri mkarchiso'ya çalışma anında enjekte edilen
# _maze_sb_sign_esp() ile kuruluyor; o fonksiyon sessizce yanlış çalışırsa
# mkarchiso yine "başarılı" der ve hiçbir makinede açılmayan bir ISO üretilir.
# verify-iso.sh tam olarak bunu yakalar: ESP düzeni, shim→UKI sırası, kesilme,
# Maze anahtarıyla imza, gömülü cmdline ve çekirdek. Doğrulama düşerse ISO
# yayınlanmasın diye build başarısız sayılır.
_iso_path="$(ls -t "${OUTDIR}"/*.iso 2>/dev/null | head -1)"
if [[ -x "${PROFILE_DIR}/tools/verify-iso.sh" && -n "${_iso_path}" ]]; then
    echo
    echo ">> Doğrulanıyor: $(basename "${_iso_path}")"
    if "${PROFILE_DIR}/tools/verify-iso.sh" "${_iso_path}"; then
        release_tmpfs_workdir
        echo ">> Done. ISO image is available in: ${OUTDIR}"
    else
        echo >&2
        echo "HATA: ISO doğrulamayı geçemedi — YAYINLAMAYIN." >&2
        echo "      Dosya duruyor: ${_iso_path}" >&2
        exit 1
    fi
else
    release_tmpfs_workdir
    echo ">> Done. ISO image is available in: ${OUTDIR}"
    [[ -n "${_iso_path}" ]] || echo "   (uyarı: ${OUTDIR} içinde ISO bulunamadı, doğrulama atlandı)" >&2
fi
