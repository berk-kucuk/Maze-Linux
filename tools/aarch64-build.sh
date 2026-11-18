#!/usr/bin/env bash
# =============================================================================
#  aarch64 package builds for Maze Linux, on an x86_64 build host.
#
#  makepkg runs inside an Arch Linux ARM root, through qemu-user binfmt, so a
#  package comes out exactly as an ARM machine would build it — no cross
#  toolchain, no per-package changes. Only packages with compiled code need
#  this; arch=('any') packages are the same file on both architectures.
#
#    aarch64-build.sh setup                 one-time: create the ARM root
#    aarch64-build.sh build DIR [OUTDIR]    makepkg DIR (PKGBUILD + sources)
#                                           for aarch64; packages go to OUTDIR
#                                           (default: DIR)
#    aarch64-build.sh ready                 exit 0 if the ARM root is usable
#
#  Every package built here is also added to a local repo inside the root, so
#  a later build can depend on an earlier one (Qlam needs maze-python, which
#  no Arch Linux ARM mirror carries). Build maze-python first.
#
#  Needs: qemu-user-static + qemu-user-static-binfmt (pacman), and sudo — the
#  root is entered with systemd-nspawn. makepkg itself runs as a normal user
#  inside it, with the same uid as you, so the results are yours.
#
#  Location: $MAZE_AARCH64_HOME (default ~/.cache/maze-aarch64): root/ is the
#  ARM system (~2-4 GB with build deps), repo/ the packages built so far.
# =============================================================================
set -euo pipefail

BASE="${MAZE_AARCH64_HOME:-$HOME/.cache/maze-aarch64}"
ROOTFS="$BASE/root"
REPO="$BASE/repo"
TARBALL_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"
# Arch Linux ARM Build System <builder@archlinuxarm.org>. The tarball is only
# trusted when its signature is from exactly this key.
ALARM_KEY="68B3537F39A313B3E574D06777193F152BDBE6A6"
KEYSERVER="hkps://keyserver.ubuntu.com"

die()  { echo "aarch64-build: $*" >&2; exit 1; }
info() { echo ">> $*"; }

have_binfmt() { [[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; }

ready() { have_binfmt && [[ -f "$ROOTFS/etc/maze-aarch64-ready" ]]; }

nspawn() {
    # The image's resolv.conf points at a systemd-resolved that never runs in
    # here; the root shares the host's network, so the host's resolver (VPN
    # included) is the one to use.
    sudo systemd-nspawn -q -D "$ROOTFS" --resolv-conf=replace-host --bind="$REPO:/repo" "$@"
}

setup() {
    [[ $EUID -ne 0 ]] || die "run as your normal user (sudo is asked for where needed)"
    have_binfmt || die "qemu binfmt for aarch64 is not registered.
    Install it with:  sudo pacman -S qemu-user-static qemu-user-static-binfmt
    then run this again."
    if [[ -f "$ROOTFS/etc/maze-aarch64-ready" ]]; then
        info "ARM root already set up at $ROOTFS"; return 0
    fi
    command -v gpg >/dev/null || die "gpg is needed to verify the Arch Linux ARM tarball"
    command -v bsdtar >/dev/null || die "bsdtar (libarchive) is needed"

    mkdir -p "$BASE" "$REPO"
    local dl="$BASE/download"
    mkdir -p "$dl"
    # Unpacked by an earlier run that stopped later on: the tarball is only
    # deleted after a complete unpack, so its absence means the root is whole.
    if [[ -x "$ROOTFS/usr/bin/pacman" && ! -e "$dl/alarm.tar.gz" ]]; then
        info "ARM root already unpacked at $ROOTFS — continuing with its setup"
    else
    info "Downloading the Arch Linux ARM root (~700 MB) and its signature"
    curl -fL --retry 3 -o "$dl/alarm.tar.gz" "$TARBALL_URL"
    curl -fL --retry 3 -o "$dl/alarm.tar.gz.sig" "$TARBALL_URL.sig"

    info "Verifying the signature against key $ALARM_KEY"
    local gnupg status; gnupg="$(mktemp -d)"
    GNUPGHOME="$gnupg" gpg -q --keyserver "$KEYSERVER" --recv-keys "$ALARM_KEY"
    status="$(GNUPGHOME="$gnupg" gpg --status-fd 1 --verify "$dl/alarm.tar.gz.sig" "$dl/alarm.tar.gz" 2>/dev/null || true)"
    rm -rf "$gnupg"
    grep -q "^\[GNUPG:\] VALIDSIG $ALARM_KEY " <<<"$status" \
        || die "signature check FAILED — the tarball is not from Arch Linux ARM; not using it"

    info "Unpacking into $ROOTFS"
    sudo mkdir -p "$ROOTFS"
    sudo bsdtar -xpf "$dl/alarm.tar.gz" -C "$ROOTFS"
    rm -f "$dl/alarm.tar.gz" "$dl/alarm.tar.gz.sig"
    fi

    info "Preparing the ARM root (keys, base-devel, build user)"
    local uid gid; uid="$(id -u)"; gid="$(id -g)"
    nspawn /bin/bash -euc "
        # pacman's download sandbox (Landlock, seccomp, dropping to the alpm
        # user) cannot work under qemu-user, which does not emulate Landlock:
        # every download fails. Off for this build root only; packages and
        # databases are still signature-checked.
        sed -i -e 's/^DownloadUser/#DownloadUser/' \
               -e 's/^#DisableSandboxFilesystem/DisableSandboxFilesystem/' \
               -e 's/^#DisableSandboxSyscalls/DisableSandboxSyscalls/' /etc/pacman.conf
        grep -q '^DisableSandboxFilesystem' /etc/pacman.conf \
            || sed -i '/^\[options\]/a DisableSandboxFilesystem\nDisableSandboxSyscalls' /etc/pacman.conf
        pacman-key --init
        pacman-key --populate archlinuxarm
        pacman -Syu --noconfirm --needed base-devel sudo
        # The build user has your uid, so what it writes is yours. The image
        # already has 'alarm' at uid 1000 — reuse whoever holds the uid.
        getent group $gid >/dev/null || groupadd -g $gid builder
        user=\$(getent passwd $uid | cut -d: -f1)
        if [[ -z \$user ]]; then user=builder; useradd -m -u $uid -g $gid builder; fi
        echo \"\$user ALL=(ALL) NOPASSWD: /usr/bin/pacman\" > /etc/sudoers.d/maze-builder
        chmod 0440 /etc/sudoers.d/maze-builder
        echo \"\$user\" > /etc/maze-aarch64-ready
    "
    info "ARM root ready."
}

build() {
    local dir="${1:?build needs a directory with a PKGBUILD}"
    local out="${2:-$1}"
    [[ -f "$dir/PKGBUILD" ]] || die "no PKGBUILD in $dir"
    ready || die "the ARM root is not set up — run: $0 setup"
    dir="$(readlink -f "$dir")"; mkdir -p "$out"; out="$(readlink -f "$out")"

    local work; work="$(mktemp -d "$BASE/work.XXXXXX")"
    WORK_DIR="$work"; trap 'rm -rf "$WORK_DIR"' EXIT
    # Sources only: earlier packages and makepkg's own trees stay behind.
    tar -C "$dir" --exclude='*.pkg.tar.*' --exclude='./src' --exclude='./pkg' -cf - . \
        | tar -C "$work" -xf -

    info "makepkg for aarch64 in $(basename "$dir") (slow: runs under qemu)"
    nspawn --bind="$work:/build" /bin/bash -euc "
        user=\$(cat /etc/maze-aarch64-ready)
        # The local repo joins pacman.conf once it has a database.
        if [[ -f /repo/maze-aarch64.db ]] && ! grep -q '^\[maze-aarch64\]' /etc/pacman.conf; then
            printf '\n[maze-aarch64]\nSigLevel = Optional TrustAll\nServer = file:///repo\n' >> /etc/pacman.conf
        fi
        pacman -Sy --noconfirm >/dev/null
        cd /build
        su \"\$user\" -c 'makepkg -fs --noconfirm --needed'
    "
    local built=()
    while IFS= read -r -d '' f; do built+=("$f"); done \
        < <(find "$work" -maxdepth 1 -name '*-aarch64.pkg.tar.zst' -print0)
    [[ ${#built[@]} -gt 0 ]] || die "makepkg finished but produced no aarch64 package"

    cp -f "${built[@]}" "$REPO/"
    local f names=()
    for f in "${built[@]}"; do names+=("/repo/$(basename "$f")"); done
    nspawn /bin/bash -euc "su \"\$(cat /etc/maze-aarch64-ready)\" -c 'repo-add -q /repo/maze-aarch64.db.tar.gz ${names[*]}'"
    cp -f "${built[@]}" "$out/"
    for f in "${built[@]}"; do echo "Built (aarch64): $out/$(basename "$f")"; done
}

case "${1:-}" in
    setup) setup ;;
    build) shift; build "$@" ;;
    ready) ready ;;
    *) sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^#\s\?//'; exit 2 ;;
esac
