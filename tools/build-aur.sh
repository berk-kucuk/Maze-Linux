#!/usr/bin/env bash
#
# build-aur.sh — Fetch AUR packages with git and build them in an ISOLATED clean
# chroot (devtools), then publish the results into a local pacman repository
# (./localrepo) that the ISO build (mkarchiso) installs from. This is how the
# Maze AUR packages end up PREINSTALLED in the (offline) live ISO.
#
# Host isolation: every build runs inside ./aur/chroot, never on your host.
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
CHROOT="${BUILDDIR}/chroot"
LOCALREPO="${ROOT}/localrepo"
DBNAME="maze-aur"

# REQUIRED: AUR packages that are NOT published in the [mazelinux] repo and must
# be built locally. If any of these fail, the build aborts.
#
# Maze's OWN applications (entropy-shield, qlam, maze, hazedrop, haze,
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
    brave-origin-bin
    upscayl-bin
    session-desktop-bin
    joplin-bin
    claude-code
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

mkdir -p "${BUILDDIR}" "${LOCALREPO}"

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

echo ">> Building packages in the chroot"
remaining=("${PACKAGES[@]}")
built_files=()
# Pre-seed built_files with packages already present in the local repo so reruns
# do not rebuild them (delete ./localrepo to force a full rebuild).
already=()
for pkg in "${PACKAGES[@]}"; do
    f=$(ls "${LOCALREPO}/${pkg}"-*.pkg.tar.* 2>/dev/null | head -n1 || true)
    if [[ -n "${f}" ]]; then
        echo "   already built: ${pkg}"
        built_files+=("${f}")
        already+=("${pkg}")
    fi
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
            for f in "${BUILDDIR}/${pkg}"/*.pkg.tar.*; do
                [[ -e "${f}" ]] || continue
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
repo-add "${LOCALREPO}/${DBNAME}.db.tar.zst" "${LOCALREPO}"/*.pkg.tar.*

echo ">> Done."
echo "   Local repo: ${LOCALREPO}"
ls -1 "${LOCALREPO}"/*.pkg.tar.* | sed 's/^/     /'
echo "   Now build the ISO:  sudo ./build.sh"
