#!/usr/bin/env bash
#
# build-aur.sh — Fetch AUR packages with git and build them in an ISOLATED clean
# chroot (devtools), then publish the results into a local pacman repository
# (./localrepo) that the ISO build (mkarchiso) installs from. This is how the
# Maze AUR packages end up PREINSTALLED in the (offline) live ISO.
#
# Host isolation: every build runs inside a throwaway chroot (see CHROOT below,
# by default ~/.cache/maze-aur-chroot), never on your host.
# Build dependencies and the AUR packages are installed into that throwaway
# chroot only, so your host's installed package set is left untouched. sudo is
# used solely to manage the chroot (mkarchroot/makechrootpkg require it).
#
# Requirements (host): devtools + git  ->  sudo pacman -S --needed devtools git
#
# Run as a NORMAL user (not root), then build the ISO:
#
#     ./tools/build-aur.sh
#     sudo ./build.sh
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDDIR="${ROOT}/aur"
# The build chroot must NOT live on the project drive. This checkout sits under
# /run/media, which udisks mounts nosuid,nodev — inside such a chroot sudo loses
# its setuid bit and makechrootpkg dies with "/etc/sudo.conf is owned by uid
# 1000, should be 0" for EVERY package. Keep the chroot on the internal disk.
# Override with MAZE_CHROOT=/some/path if you want it elsewhere.
CHROOT="${MAZE_CHROOT:-${XDG_CACHE_HOME:-${HOME}/.cache}/maze-aur-chroot}"
LOCALREPO="${ROOT}/localrepo"
DBNAME="maze-aur"

# REQUIRED: AUR packages that are NOT published in the [mazelinux] repo and must
# be built locally. If any of these fail, the build aborts.
#
# Maze's OWN applications (entropy-shield, qlam, maze-guard, hazedrop, haze,
# linux-chan-ai, sentinai) are deliberately NOT here anymore: they now ship from
# the official [mazelinux] repo, so mkarchiso pulls them straight from there
# (see pacman.conf) instead of building them from the AUR.
REQUIRED=(
    # Microsoft-signed shim — Secure Boot depends on it (live ISO + installer).
    shim-signed
)

# OPTIONAL: desktop/AI/privacy apps. If one fails to build it is skipped with a
# warning (the ISO build still succeeds) instead of aborting everything.
OPTIONAL=(
    # obfs4proxy — Tor pluggable transport (obfs4 + meek_lite). entropy-shield's
    # bridge feature shells out to it; it used to be an official package but is
    # AUR-only now, so without this the bridge option had nothing to run.
    obfs4proxy
    upscayl-bin
    session-desktop-bin
    joplin-bin
    claude-code
    # paru — AUR helper, shipped on the ISO so the installer does not have to
    # compile it (Rust) at install time. Built from source, never paru-bin: it
    # links the libalpm of this build, which is the one the ISO ships. Rebuild
    # it whenever pacman's libalpm soname changes, or paru stops starting.
    paru
    # Calamares installer (live ISO only). Not in the official repos, so it is
    # built from the AUR here. Heavy build (KPMcore/Qt6/KF6). Optional during
    # bring-up so a build hiccup never blocks the ISO; once stable, promote to
    # REQUIRED. Maze ships its own /etc/calamares config + branding in airootfs.
    calamares
    # onlyoffice-bin is deliberately NOT prebuilt into the live ISO (~1.3 GB
    # unpacked). It is installed on the TARGET system instead (deploy-to-target's
    # CURATED_AUR + maze-aur-setup build it fresh from the AUR at install time).
)

PACKAGES=("${REQUIRED[@]}" "${OPTIONAL[@]}")

is_required() { local p; for p in "${REQUIRED[@]}"; do [[ "$p" == "$1" ]] && return 0; done; return 1; }

if [[ "${EUID}" -eq 0 ]]; then
    echo "Error: do not run build-aur.sh as root." >&2
    exit 1
fi
for tool in git mkarchroot makechrootpkg arch-nspawn repo-add; do
    command -v "${tool}" >/dev/null 2>&1 || {
        echo "Error: '${tool}' not found. Install with:  sudo pacman -S --needed devtools git" >&2
        exit 1
    }
done

# Extra build tools installed into the chroot. Some Python AUR packages build a
# venv with --system-site-packages and pip --no-build-isolation, which expects
# the build backend to already be present (it is not in a clean base-devel
# chroot). Providing these lets such packages build.
CHROOT_EXTRA=(python-setuptools python-wheel python-pip)

# Refuse to build on a nosuid/nodev mount — the failure mode is otherwise a wall
# of confusing sudo errors, one per package.
chroot_mount_opts="$(findmnt -T "$(dirname "${CHROOT}")" -no OPTIONS 2>/dev/null || true)"
case ",${chroot_mount_opts}," in
    *,nosuid,*|*,nodev,*)
        echo "Error: ${CHROOT} is on a nosuid/nodev mount (${chroot_mount_opts})." >&2
        echo "       makechrootpkg cannot work there. Set MAZE_CHROOT to a path on" >&2
        echo "       the internal disk, e.g. MAZE_CHROOT=\"\${HOME}/.cache/maze-aur-chroot\"" >&2
        exit 1
        ;;
esac

mkdir -p "${BUILDDIR}" "${LOCALREPO}" "$(dirname "${CHROOT}")"

echo ">> Fetching AUR sources via git"
for pkg in "${PACKAGES[@]}"; do
    if [[ -d "${BUILDDIR}/${pkg}/.git" ]]; then
        git -C "${BUILDDIR}/${pkg}" pull --ff-only >/dev/null 2>&1 && echo "   updated ${pkg}" || echo "   (kept) ${pkg}"
    else
        echo "   cloning ${pkg}"
        git clone --quiet "https://aur.archlinux.org/${pkg}.git" "${BUILDDIR}/${pkg}" \
            || echo "   WARNING: could not clone ${pkg}"
    fi
done

# Create the clean build chroot once (base-devel + extra build tools).
if [[ ! -d "${CHROOT}/root" ]]; then
    echo ">> Creating clean build chroot at ${CHROOT} (one-time)"
    mkdir -p "${CHROOT}"
    mkarchroot "${CHROOT}/root" base-devel "${CHROOT_EXTRA[@]}"
else
    echo ">> Ensuring build tools in existing chroot"
    arch-nspawn "${CHROOT}/root" pacman -Sy --needed --noconfirm "${CHROOT_EXTRA[@]}"
fi

# pkg_field <package-file> <Name|Version> — read a field from the package
# itself (filename parsing breaks on epochs and on names that contain dashes).
pkg_field() {
    pacman -Qip "$1" 2>/dev/null | awk -F': +' -v k="$2" '$1 ~ ("^" k " *$") {print $2; exit}'
}

# srcinfo_version <clone-dir> — "[epoch:]pkgver-pkgrel" the AUR currently ships,
# from the .SRCINFO the git pull above just updated (empty if unknown).
srcinfo_version() {
    [[ -f "$1/.SRCINFO" ]] || return 0
    awk -F' = ' '/^\t(epoch|pkgver|pkgrel) = /{ sub(/^\t/, "", $1); v[$1] = $2 }
        END { if (v["pkgver"] != "" && v["pkgrel"] != "")
                  printf "%s%s-%s\n", (v["epoch"] != "" ? v["epoch"] ":" : ""), v["pkgver"], v["pkgrel"] }' "$1/.SRCINFO"
}

# index_localrepo — fill LOCAL_FILE[name] / LOCAL_VER[name] with the NEWEST file
# per package name in ./localrepo (signatures skipped).
declare -A LOCAL_FILE=() LOCAL_VER=()
index_localrepo() {
    local f n v
    LOCAL_FILE=(); LOCAL_VER=()
    for f in "${LOCALREPO}"/*.pkg.tar.*; do
        [[ -e "${f}" && "${f}" != *.sig ]] || continue
        n="$(pkg_field "${f}" Name)"; v="$(pkg_field "${f}" Version)"
        [[ -n "${n}" && -n "${v}" ]] || continue
        if [[ -z "${LOCAL_VER[${n}]+x}" ]] || (( $(vercmp "${v}" "${LOCAL_VER[${n}]}") > 0 )); then
            LOCAL_FILE["${n}"]="${f}"; LOCAL_VER["${n}"]="${v}"
        fi
    done
}

echo ">> Building packages in the chroot"
remaining=("${PACKAGES[@]}")
built_files=()
# Pre-seed built_files with packages already in the local repo so reruns do not
# rebuild them — UNLESS the AUR now ships a NEWER version. Skipping on mere
# presence (the old rule) froze every package at its first build: upstream
# security fixes for the bundled Electron apps never reached the ISO. A local
# copy that is newer than the AUR (a locally bumped pkgrel) is kept as is.
# Delete ./localrepo to force a full rebuild.
index_localrepo
already=()
for pkg in "${PACKAGES[@]}"; do
    [[ -n "${LOCAL_FILE[${pkg}]+x}" ]] || continue
    aur_ver="$(srcinfo_version "${BUILDDIR}/${pkg}")"
    if [[ -n "${aur_ver}" ]] && (( $(vercmp "${aur_ver}" "${LOCAL_VER[${pkg}]}") > 0 )); then
        echo "   outdated: ${pkg} ${LOCAL_VER[${pkg}]} -> ${aur_ver} (rebuilding)"
        continue
    fi
    echo "   already built: ${pkg} ${LOCAL_VER[${pkg}]}"
    built_files+=("${LOCAL_FILE[${pkg}]}")
    already+=("${pkg}")
done
# remove already-built from the work list
tmp=(); for pkg in "${remaining[@]}"; do
    skip=0; for a in "${already[@]}"; do [[ "$a" == "$pkg" ]] && skip=1; done
    [[ ${skip} -eq 0 ]] && tmp+=("${pkg}")
done
remaining=("${tmp[@]}")

# Pass 1 builds every package independently (no injection). Only on later passes
# do we inject already-built packages, to satisfy any inter-AUR dependency.
MAXPASS=4
pass=0
while [[ ${#remaining[@]} -gt 0 && ${pass} -lt ${MAXPASS} ]]; do
    pass=$((pass + 1))
    built_this_pass=0
    still=()
    for pkg in "${remaining[@]}"; do
        [[ -d "${BUILDDIR}/${pkg}" ]] || { echo "   skipping ${pkg} (no source)"; continue; }
        echo "   [pass ${pass}] building ${pkg}"
        inject=()
        if [[ ${pass} -gt 1 ]]; then
            for f in "${built_files[@]}"; do inject+=(-I "${f}"); done
        fi
        if ( cd "${BUILDDIR}/${pkg}" && makechrootpkg -c -r "${CHROOT}" "${inject[@]}" ); then
            index_localrepo
            for f in "${BUILDDIR}/${pkg}"/*.pkg.tar.*; do
                [[ -e "${f}" && "${f}" != *.sig ]] || continue
                n="$(pkg_field "${f}" Name)"
                # makepkg's default OPTIONS=(debug) emits <pkg>-debug split
                # packages; nothing installs them, so keep them out of the repo.
                if [[ "${n}" == *-debug ]]; then
                    rm -f "${f}"
                    continue
                fi
                # Retire the previous build of this package so exactly one
                # version remains (repo-add would otherwise index whichever
                # file sorts last, which is not necessarily the newest).
                if [[ -n "${n}" && -n "${LOCAL_FILE[${n}]+x}" ]]; then
                    echo "   replacing ${n} ${LOCAL_VER[${n}]} in ./localrepo"
                    rm -f "${LOCAL_FILE[${n}]}" "${LOCAL_FILE[${n}]}.sig"
                fi
                mv -f "${f}" "${LOCALREPO}/"
                built_files+=("${LOCALREPO}/$(basename "${f}")")
            done
            built_this_pass=$((built_this_pass + 1))
        else
            still+=("${pkg}")
        fi
    done
    remaining=("${still[@]}")
    [[ ${built_this_pass} -eq 0 ]] && break
done

# Categorize anything that never built.
req_failed=() opt_failed=()
for pkg in "${remaining[@]}"; do
    if is_required "${pkg}"; then req_failed+=("${pkg}"); else opt_failed+=("${pkg}"); fi
done
if [[ ${#opt_failed[@]} -gt 0 ]]; then
    echo ">> WARNING: optional packages skipped (not installed in the ISO): ${opt_failed[*]}" >&2
fi
if [[ ${#req_failed[@]} -gt 0 ]]; then
    echo "Error: REQUIRED packages failed to build: ${req_failed[*]}" >&2
    exit 1
fi

# Reconcile packages.x86_64: enable optional apps that built, comment out
# (#MAZE-SKIP#) those that did not, so pacstrap never hits a missing target.
PKGLIST="${ROOT}/packages.x86_64"
in_list() { local x; for x in "${remaining[@]}"; do [[ "$x" == "$1" ]] && return 0; done; return 1; }
for pkg in "${OPTIONAL[@]}"; do
    if in_list "${pkg}"; then   # failed -> comment out
        sed -i "s|^${pkg}\$|#MAZE-SKIP# ${pkg}|" "${PKGLIST}"
    else                        # built -> ensure enabled
        sed -i "s|^#MAZE-SKIP# ${pkg}\$|${pkg}|" "${PKGLIST}"
    fi
done

echo ">> Creating local repository database (${DBNAME})"
rm -f "${LOCALREPO}/${DBNAME}".db* "${LOCALREPO}/${DBNAME}".files*
# Index packages only: no detached signatures, no -debug split packages.
repo_files=()
for f in "${LOCALREPO}"/*.pkg.tar.*; do
    [[ -e "${f}" && "${f}" != *.sig ]] || continue
    [[ "$(pkg_field "${f}" Name)" == *-debug ]] && continue
    repo_files+=("${f}")
done
repo-add "${LOCALREPO}/${DBNAME}.db.tar.zst" "${repo_files[@]}"

echo ">> Done."
echo "   Local repo: ${LOCALREPO}"
ls -1 "${LOCALREPO}"/*.pkg.tar.* | sed 's/^/     /'
echo "   Now build the ISO:  sudo ./build.sh"
