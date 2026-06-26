#!/usr/bin/env bash
#
# deploy-to-target.sh — Make an installed Maze Linux system match the live ISO.
#
# Called by the customized archinstall (PlasmaProfile.post_install) with the
# target mountpoint as $1 (e.g. /mnt). It runs in the LIVE environment, so the
# live system's own Maze configuration is the source for everything it copies.
#
# It is intentionally best-effort: every step is guarded so a single failure
# never aborts the installation. Re-runnable.
#
set -uo pipefail

TARGET="${1:?usage: deploy-to-target.sh <target-mountpoint> [maze-apps-csv] [security-csv]}"
# Comma-separated list of selected Maze applications (from the installer menu).
MAZE_APPS_CSV="${2:-}"
# Comma-separated list of selected security features (from the installer's
# Security section). Empty/unset means "all" (handled below).
SECURITY_CSV="${3:-}"
# Curated AUR apps that always ship with the Maze desktop.
#
# 'paru' is built FROM SOURCE (not paru-bin) on purpose: a source build compiles
# against the target's own pacman/libalpm, so it can never hit the ABI mismatch
# that makes the precompiled paru-bin break after a pacman soname bump. It is
# listed first so the AUR helper is in place early.
CURATED_AUR=(paru brave-origin-bin upscayl-bin session-desktop-bin joplin-bin onlyoffice-bin claude-code)
# Maze's OWN applications, shipped from the [mazelinux] repo. When the apps CSV
# ($2) is the keyword "all" (what the Calamares path passes), the whole set is
# installed. (The archinstall path may instead pass an explicit comma list.)
DEFAULT_MAZE_APPS=(entropy-shield qlam maze hazedrop haze linux-chan-ai sentinai)

log()  { printf '[maze-deploy] %s\n' "$*"; }
warn() { printf '[maze-deploy] WARNING: %s\n' "$*" >&2; }

# stdin from /dev/null so a chroot command (e.g. chsh's PAM prompt) can never
# block the whole install waiting on input that will never arrive.
in_chroot() { arch-chroot "${TARGET}" "$@" </dev/null; }

# Copy a path from the live system to the same path on the target.
copy_to_target() {
    local src="$1"
    [[ -e "${src}" || -L "${src}" ]] || { warn "missing source ${src}"; return 0; }
    local dst="${TARGET}${src}"
    mkdir -p "$(dirname "${dst}")"
    cp -a "${src}" "${dst}" 2>/dev/null || warn "could not copy ${src}"
}

# Remove machine-specific DISPLAY / OUTPUT state from a config tree so a freshly
# installed machine NEVER inherits the build host's monitor layout or primary-
# screen choice. KDE/KWin must re-detect outputs (and pick the primary) per
# hardware on first login. Without this, the skel (which was captured from a
# multi-monitor build host) drags that host's screen state onto every install,
# which is why the wrong monitor showed up as "Primary".
#   $1 = home-like dir (its .config / .local live underneath)
strip_display_state() {
    local h="$1"
    local cfg="${h}/.config"
    [[ -d "${cfg}" ]] || return 0
    # Wayland: the primary output is stored here as the output with "priority":1.
    # Entirely host-specific (keyed to the host's connectors/EDID) — must go.
    rm -f "${cfg}/kwinoutputconfig.json" 2>/dev/null || true
    # X11: per-output configs (incl. the primary flag) keyed by EDID hash.
    rm -rf "${h}/.local/share/kscreen" 2>/dev/null || true
    # kwinrc: drop [Tiling][<desktop-uuid>][<output-uuid>] blocks — they are
    # pinned to the build host's specific outputs and are dead weight elsewhere.
    local kwinrc="${cfg}/kwinrc"
    if [[ -f "${kwinrc}" ]] && grep -q '^\[Tiling\]' "${kwinrc}"; then
        awk '/^\[/{ drop = ($0 ~ /^\[Tiling\]/) } !drop { print }' \
            "${kwinrc}" > "${kwinrc}.maze.tmp" 2>/dev/null \
            && mv "${kwinrc}.maze.tmp" "${kwinrc}" || rm -f "${kwinrc}.maze.tmp"
    fi
    # appletsrc: blank any saved screen<->connector mapping and drop host-
    # resolution geometry keys so panels/desktops map onto THIS machine's screens.
    local appletsrc="${cfg}/plasma-org.kde.plasma.desktop-appletsrc"
    if [[ -f "${appletsrc}" ]]; then
        sed -i -E '/^ItemGeometries-[0-9]+x[0-9]+=/d' "${appletsrc}" 2>/dev/null || true
        sed -i -E 's/^(screenMapping|itemsOnDisabledScreens)=.*/\1=/' "${appletsrc}" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
log "Deploying Maze configuration to ${TARGET}"

# DNS inside the chroot, set up ONCE up front so every later in_chroot step that
# needs the network works — the AUR builds (step 11) git clone from the AUR.
cp -L /etc/resolv.conf "${TARGET}/etc/resolv.conf" 2>/dev/null || true

# 1) Applications come from two sources, both handled near the end of this
#    script. Maze's OWN apps (entropy-shield, qlam, maze, ...) install from the
#    official [mazelinux] pacman repo with 'pacman -S' (see install_maze_repo_apps).
#    The third-party apps (brave, joplin, paru, ...) are built with makepkg and
#    installed with pacman -U inside the target chroot, as the installer-created
#    user. 'paru' is built from source as part of that set so the installed
#    system has a working AUR helper for future updates (built from source, it
#    matches the target's libalpm ABI, unlike the precompiled paru-bin). The AUR
#    builds intentionally avoid a pinned local repo so the packages stay on the
#    latest version and can receive normal updates afterwards.

# 2) Desktop look, tools and branding (copied from the live system) --------
log "Copying Maze desktop configuration and tools"
# /etc/skel — KDE layout, theme, oh-my-zsh, etc.
copy_to_target /etc/skel/.config
copy_to_target /etc/skel/.local
copy_to_target /etc/skel/.oh-my-zsh
# Scrub any display/output state from the target skel so users created LATER
# (post-install) also start with a clean, auto-detected monitor/primary setup.
strip_display_state "${TARGET}/etc/skel"
# our zsh config is staged outside /etc/skel on the live medium (grml conflict)
if [[ -f /usr/local/share/maze/skel-zshrc ]]; then
    cp -a /usr/local/share/maze/skel-zshrc "${TARGET}/etc/skel/.zshrc" 2>/dev/null || warn "skel .zshrc failed"
fi
# Branding assets and shared data
# All Maze wallpaper packages (Maze, Maze1..Maze9, MazeOLED) — not just the
# default one, so the full set shows up in the Plasma wallpaper picker.
for _wp in /usr/share/wallpapers/Maze*; do
    [[ -d "${_wp}" ]] && copy_to_target "${_wp}"
done
copy_to_target /usr/share/plymouth/themes/maze
copy_to_target /usr/share/plymouth/themes/default.plymouth
copy_to_target /usr/share/pixmaps/maze-logo.png
copy_to_target /usr/share/pixmaps/maze-simple-logo.png
copy_to_target /usr/share/maze/fastfetch-logo.txt
# Branded distro logo for KDE's "About this System" (os-release LOGO=mazelinux).
copy_to_target /usr/share/icons/hicolor/128x128/apps/mazelinux.png
copy_to_target /usr/share/icons/hicolor/256x256/apps/mazelinux.png
copy_to_target /usr/share/icons/hicolor/512x512/apps/mazelinux.png
# Maze Plasma colour schemes (system-wide, so the greeter sees them too).
# Maze Dark + Maze Light schemes so the System Settings light/dark switch stays
# on-brand instead of falling back to Breeze.
copy_to_target /usr/share/color-schemes/MazeDark.colors
copy_to_target /usr/share/color-schemes/MazeLight.colors
# Maze OLED global theme (Plasma look-and-feel + splash) and the matching OLED
# SDDM login theme. The live autologin drop-in (10-maze-autologin.conf) is
# deliberately NOT copied.
copy_to_target /usr/share/plasma/look-and-feel/com.mazelinux.oled
# Matching light variant — without it the System Settings dark/light switch
# (DefaultLightLookAndFeel in kdeglobals) falls back to Breeze on the target.
copy_to_target /usr/share/plasma/look-and-feel/com.mazelinux.oled.light
copy_to_target /usr/share/sddm/themes/maze-oled
copy_to_target /etc/sddm.conf.d/20-maze-theme.conf
# Breeze greeter override (the default SDDM theme) — puts the Maze wallpaper
# behind Breeze. Breeze itself ships with plasma; this only adds the override.
copy_to_target /usr/share/sddm/themes/breeze/theme.conf.user
# Maze CLI tools. NOTE: the installer itself (maze-install + its .desktop launcher)
# is intentionally NOT deployed — the system is already installed, so it must not
# appear in the menu or the dock.
copy_to_target /usr/local/bin/maze-gpu-driver
copy_to_target /usr/local/bin/maze-apply-wallpaper
copy_to_target /usr/local/bin/mac_anonymizer.py
copy_to_target /usr/local/bin/change-mac-now
copy_to_target /usr/local/bin/mac-changer-logs
# Maze Welcome app (first-boot greeter) + its menu entry.
copy_to_target /usr/local/bin/maze-welcome
copy_to_target /usr/share/applications/maze-welcome.desktop
# First-login helper: promote the best monitor to primary (see step below).
copy_to_target /usr/local/bin/maze-primary-screen
# Security / privacy hardening
copy_to_target /etc/NetworkManager/conf.d/mac-randomize.conf
copy_to_target /etc/fail2ban/jail.d/sshd.conf
copy_to_target /etc/ssh/sshd_config.d/00-maze-hardening.conf
copy_to_target /etc/systemd/system/mac-changer.service
# Per-adapter hotplug unit + the udev rule that starts it for newly plugged NICs.
copy_to_target /etc/systemd/system/mac-changer@.service
copy_to_target /etc/udev/rules.d/80-maze-mac-changer.rules
# Flathub-on-first-boot helper (registers the remote when the network is up)
copy_to_target /usr/local/bin/maze-flatpak-setup
copy_to_target /etc/systemd/system/maze-flatpak-setup.service
# Panic mode (Ctrl+Alt+P + tray), honeypot/deception layer, and the hardware
# privacy kill switches. The privileged work is brokered by maze-guardd (root
# daemon, wheel-only socket, fixed verb whitelist — NO pkexec/setuid), so the
# user-facing tools (maze-panic, maze-killswitch, maze-guard) hold no privilege.
# (In the offline Calamares path unpackfs already copies these; the explicit
# copies keep the archinstall fallback working too.)
copy_to_target /usr/local/bin/maze-guardd
copy_to_target /usr/local/bin/maze-guard
copy_to_target /etc/systemd/system/maze-guardd.service
copy_to_target /usr/local/bin/maze-panic
copy_to_target /usr/local/bin/maze-panic-restore
copy_to_target /usr/share/applications/maze-panic.desktop
# Panic tray is a Plasma WIDGET (plasmoid), not a Qt app — added to the system
# tray via skel; ship the plasmoid package.
copy_to_target /usr/share/plasma/plasmoids/com.mazelinux.panic
copy_to_target /usr/local/bin/maze-honeypot
copy_to_target /usr/local/bin/maze-honeypot-setup
copy_to_target /etc/maze/honeypot.conf
copy_to_target /etc/systemd/system/maze-honeypot.service
copy_to_target /etc/systemd/system/maze-honeypot-setup.service
copy_to_target /usr/local/bin/maze-killswitch
copy_to_target /usr/local/bin/maze-hardware
copy_to_target /usr/share/applications/maze-hardware.desktop
# Maze Control Center + shared Python libs (maze_ui / maze_status) used by it
# and by maze-welcome — without these the welcome app fails to import.
copy_to_target /usr/local/bin/maze-control-center
copy_to_target /usr/share/applications/maze-control-center.desktop
copy_to_target /usr/local/lib/maze
# Kernel/network hardening, zram swap and hardened Firefox policy. These live in
# /etc, which (unlike /etc/skel) is not copied wholesale.
copy_to_target /etc/sysctl.d/99-maze-hardening.conf
copy_to_target /etc/systemd/zram-generator.conf
copy_to_target /etc/firefox/policies/policies.json
# systemd-oomd tuning + baseline auditd rules.
copy_to_target /etc/systemd/oomd.conf.d/10-maze.conf
copy_to_target /etc/systemd/system/-.slice.d/10-oomd.conf
copy_to_target /etc/systemd/system/user@.service.d/10-oomd.conf
copy_to_target /etc/audit/rules.d/maze.rules

# Branded os-release (write directly; do not rely on package files)
if [[ -f /usr/local/share/maze/os-release ]]; then
    cp -f /usr/local/share/maze/os-release "${TARGET}/usr/lib/os-release" 2>/dev/null || warn "os-release failed"
    ln -sf ../usr/lib/os-release "${TARGET}/etc/os-release" 2>/dev/null || true
fi

# Ship the AUR installer as a manual retry helper (run it after login if the
# build below hit a transient network/build error).
install -Dm755 /usr/share/maze/target-firstboot/maze-aur-setup \
    "${TARGET}/usr/local/bin/maze-aur-setup" 2>/dev/null || warn "maze-aur-setup copy failed"

# Maze's OWN applications (entropy-shield, qlam, maze, ...) now ship from the
# official [mazelinux] pacman repo — added to the target's pacman.conf in step
# 7b — so they are installed with a plain 'pacman -S' instead of being built from
# the AUR. The user's installer-menu selection (MAZE_APPS_CSV) decides which ones.
# Fast and reliable, so this runs before the slow AUR builds below. Best-effort.
install_maze_repo_apps() {
    local pkgs=() a _selected=()
    if [[ "${MAZE_APPS_CSV}" == "all" ]]; then
        # "all" => the full default Maze app set (the Calamares path passes this).
        pkgs=("${DEFAULT_MAZE_APPS[@]}")
    else
        IFS=',' read -ra _selected <<< "${MAZE_APPS_CSV}"
        for a in "${_selected[@]}"; do [[ -n "${a}" ]] && pkgs+=("${a}"); done
    fi
    if [[ ${#pkgs[@]} -eq 0 ]]; then
        log "No Maze applications selected; skipping [mazelinux] install"
        return 0
    fi
    log "Installing Maze applications from the [mazelinux] repo: ${pkgs[*]}"
    # DNS for pacman to reach the Maze repo / mirrors (also set up front above).
    cp -L /etc/resolv.conf "${TARGET}/etc/resolv.conf" 2>/dev/null || true
    local _try
    # Refresh databases (retried) so a transient mirror/repo hiccup does not drop
    # the whole set.
    for _try in 1 2 3; do
        in_chroot pacman -Sy --noconfirm && break
        warn "pacman -Sy failed (attempt ${_try}/3); retrying in 5s"
        sleep 5
    done
    for _try in 1 2 3; do
        if in_chroot pacman -S --noconfirm --needed "${pkgs[@]}"; then
            log "Maze applications installed from [mazelinux]"
            return 0
        fi
        warn "Maze app install from [mazelinux] failed (attempt ${_try}/3); retrying in 5s"
        sleep 5
    done
    warn "could not install Maze applications from [mazelinux] (run 'maze-aur-setup' after login)"
    return 0
}

# The actual AUR build is the slowest, most failure-prone step (large downloads,
# building as the user), so it is deferred to the very END of this script via the
# function below. That way the fast, critical desktop config — Maze Plymouth
# splash, wallpaper, Breeze greeter, services — is ALWAYS applied first and can
# never be skipped because an AUR build was slow or got stuck.
install_aur_packages() {
    # Only the third-party curated apps are built from the AUR here. Maze's OWN
    # applications (the user's MAZE_APPS_CSV selection) now ship from the
    # [mazelinux] repo and are installed separately by install_maze_repo_apps().
    local aur_list=("${CURATED_AUR[@]}")

    log "Installing AUR packages from the AUR (makepkg): ${aur_list[*]:-<none>}"
    local build_user
    build_user=$(in_chroot awk -F: '$3>=1000 && $3<65000 {print $1; exit}' /etc/passwd 2>/dev/null)
    if [[ -z "${build_user}" || ${#aur_list[@]} -eq 0 ]]; then
        warn "no regular user found; skipping AUR install (run maze-aur-setup after login)"
        return 0
    fi
    # The build runs as ${build_user}; put the helper script in *their* home so
    # it is always readable/executable by them. /root (mode 700) and /tmp both
    # failed here before ("Permission denied", then "No such file or directory"
    # because arch-chroot does not share the live /tmp the way we assumed).
    local build_home
    build_home=$(in_chroot getent passwd "${build_user}" | cut -d: -f6)
    [[ -n "${build_home}" ]] || build_home="/home/${build_user}"
    log "AUR build user: ${build_user} (home ${build_home}; logging to /var/log/maze-aur-install.log on the target)"

    # DNS inside the chroot so git can reach the AUR and pacman the mirrors.
    cp -L /etc/resolv.conf "${TARGET}/etc/resolv.conf" 2>/dev/null || true
    # Temporary passwordless sudo for the build user (makepkg calls sudo pacman).
    local sudoers="${TARGET}/etc/sudoers.d/99-maze-build"
    printf '%s ALL=(ALL) NOPASSWD: ALL\n' "${build_user}" > "${sudoers}"
    chmod 440 "${sudoers}"
    trap 'rm -f "'"${sudoers}"'"' EXIT

    # Refresh the package databases (retried): a transient mirror hiccup here
    # otherwise cascades into every makepkg dependency resolution failing.
    local _try
    for _try in 1 2 3; do
        in_chroot pacman -Sy --noconfirm && break
        warn "pacman -Sy failed (attempt ${_try}/3); retrying in 5s"
        sleep 5
    done

    # Write the build steps to a file in the build user's home and run it as the
    # user. A standalone script (instead of a heredoc piped through
    # arch-chroot+sudo) is far more reliable. stdin is /dev/null so any
    # unexpected prompt fails fast instead of hanging; each package gets a hard
    # timeout for the same reason.
    local buildscript="${TARGET}${build_home}/.maze-aur-build.sh"
    local buildscript_in_chroot="${build_home}/.maze-aur-build.sh"
    cat > "${buildscript}" <<'MAKEPKG'
#!/usr/bin/env bash
set -u
exec </dev/null
PKGS=("$@")
total=${#PKGS[@]}
rc=0
failed=()

# Verbose build output (git/makepkg/pacman) goes ONLY to this file; the terminal
# gets just short, human-readable status lines ("Installing brave-bin from the
# AUR..."). The file lives in the build user's home (always writable) and is
# folded into /var/log/maze-aur-install.log by the caller afterwards.
VLOG="${HOME:-/tmp}/.maze-aur-verbose.log"
: > "${VLOG}" 2>/dev/null || VLOG=/dev/null

# Retry a network-bound command a few times with a short backoff (its output goes
# to the verbose log), so a single unresponsive mirror/AUR no longer drops a
# package — which is how a transient clone/build failure used to drop an app.
retry() {
    local tries="$1"; shift
    local n=1
    while true; do
        "$@" >>"${VLOG}" 2>&1 && return 0
        if (( n >= tries )); then
            return 1
        fi
        echo "   ...attempt ${n}/${tries} failed, retrying in $((n*5))s"
        sleep $((n*5))
        ((n++))
    done
}

# Clone, build and install one AUR package by name. Returns 0 on success. Always
# clones fresh from the AUR so packages are the current upstream version with the
# latest PKGBUILD — never a stale snapshot frozen into the ISO. The chroot has
# working DNS (resolv.conf copied up front). Every network-bound step is retried
# so a momentarily unresponsive AUR/repo does not drop the package. All the noisy
# command output is sent to ${VLOG}; only short status lines reach the terminal.
build_one() {
    local pkg="$1" tmp ok=1
    tmp=$(mktemp -d)
    if retry 3 git clone --depth 1 "https://aur.archlinux.org/${pkg}.git" "$tmp/$pkg"; then
        # Build only (-s installs build/runtime deps from the repos), with a
        # 30-minute ceiling so a stuck build can never block the install. The
        # whole makepkg run is retried because most build failures here are
        # transient source/dependency download errors, not real build breaks.
        if retry 2 timeout 1800 bash -c "cd '$tmp/$pkg' && makepkg -s --noconfirm --needed"; then
            # Install the built package(s) ourselves with --overwrite so leftover
            # files from a previous partial/retried run don't cause a
            # "conflicting files" failure (these apps ship a self-contained venv).
            shopt -s nullglob
            local pkgfiles=("$tmp/$pkg"/*.pkg.tar.*)
            shopt -u nullglob
            if [[ ${#pkgfiles[@]} -gt 0 ]]; then
                if retry 2 sudo pacman -U --noconfirm --needed --overwrite '*' "${pkgfiles[@]}"; then
                    ok=0
                fi
            fi
        fi
    fi
    rm -rf "$tmp"
    return "$ok"
}

i=0
for pkg in "${PKGS[@]}"; do
    ((i++))
    echo ":: (${i}/${total}) Installing ${pkg} from the AUR..."
    if build_one "$pkg"; then
        echo "   -> ${pkg} installed."
    else
        echo "   -> ERROR: ${pkg} failed (see /var/log/maze-aur-install.log)."
        rc=1; failed+=("$pkg")
    fi
done

# AUR helper fallback: if paru was requested but did not end up installed (e.g.
# its source build failed), try yay instead — also built from source so it
# matches this system's libalpm ABI — so the system still has a usable helper.
if printf '%s\n' "${PKGS[@]}" | grep -qx paru && ! pacman -Qq paru >/dev/null 2>&1; then
    echo ":: paru not installed — falling back to yay as the AUR helper..."
    if build_one yay; then
        echo "   -> yay installed (paru fallback)."
        # A working helper is present, so paru's earlier failure is no longer a
        # real problem — drop it from the failure list.
        _kept=()
        for _x in "${failed[@]}"; do [[ "$_x" == paru ]] || _kept+=("$_x"); done
        failed=("${_kept[@]}")
        (( ${#failed[@]} == 0 )) && rc=0
    else
        echo "   -> ERROR: yay fallback also failed — no AUR helper installed."
        failed+=(yay)
    fi
fi

echo ""
if (( ${#failed[@]} == 0 )); then
    echo ":: All AUR packages installed successfully."
else
    echo ":: Done with errors. Failed: ${failed[*]}"
    echo ":: Re-run 'maze-aur-setup' after login to retry the failed ones."
fi
exit "$rc"
MAKEPKG
    chmod 755 "${buildscript}"
    # Owned by the build user so they can read/execute it.
    in_chroot chown "${build_user}:${build_user}" "${buildscript_in_chroot}" 2>/dev/null || true

    # The build script prints only short status lines ("Installing brave-bin from
    # the AUR...") to stdout; post_install runs this with peek_output=True, so the
    # user sees those concise lines live instead of a frozen screen. The verbose
    # git/makepkg/pacman output is written to the build user's ~/.maze-aur-verbose.log
    # and folded into /var/log/maze-aur-install.log afterwards for debugging.
    log "Installing AUR packages now — progress follows (full details in /var/log/maze-aur-install.log):"
    in_chroot sudo -u "${build_user}" -H bash "${buildscript_in_chroot}" "${aur_list[@]}" 2>&1 \
        | tee "${TARGET}/var/log/maze-aur-install.log"
    local _aur_rc="${PIPESTATUS[0]}"
    # Append the detailed build transcript so the log has both the summary and the
    # full output, even though only the summary was shown on screen.
    local _vlog="${TARGET}${build_home}/.maze-aur-verbose.log"
    if [[ -f "${_vlog}" ]]; then
        { echo ""; echo "===== detailed build log ====="; cat "${_vlog}"; } \
            >> "${TARGET}/var/log/maze-aur-install.log" 2>/dev/null || true
        rm -f "${_vlog}"
    fi
    if [[ "${_aur_rc}" -ne 0 ]]; then
        warn "AUR install had failures — see /var/log/maze-aur-install.log (or run 'maze-aur-setup' after login)"
    fi

    rm -f "${buildscript}"
    rm -f "${sudoers}"
    trap - EXIT
}

# Secure Boot (shim + per-machine MOK) — ported from the archinstall installer so
# the Calamares path gets the SAME model:
#   firmware -> shim (Microsoft-signed) -> systemd-boot (Maze-signed as
#   grubx64.efi) -> kernel (Maze-signed).
# A per-machine key is generated (private half never leaves the target), shim is
# taken from the live system (shim-signed is AUR, preinstalled on the live ISO),
# the bootloader + kernels are signed, and a pacman hook + .path unit keep them
# signed across updates. Best-effort: NEVER aborts the install — on failure the
# system still boots with Secure Boot DISABLED in firmware. Replacing the
# removable BOOTX64.EFI with shim is harmless when SB is off (shim just
# chainloads), so this does not affect a Secure-Boot-OFF boot.
MAZE_SB_ESP=""
setup_secure_boot() {
    local live_shim=/usr/share/shim-signed/shimx64.efi
    local live_mm=/usr/share/shim-signed/mmx64.efi
    if [[ ! -f "${live_shim}" ]]; then
        warn "Secure Boot: ${live_shim} not on live system; skipping SB setup"
        return 0
    fi
    # Locate the ESP on the target (Calamares mounts Maze's ESP at /boot).
    local esp_rel="" cand
    for cand in /boot /efi /boot/efi; do
        [[ -d "${TARGET}${cand}/EFI" ]] && { esp_rel="${cand}"; break; }
    done
    if [[ -z "${esp_rel}" ]]; then
        warn "Secure Boot: no ESP (EFI dir) under target; skipping (BIOS install?)"
        return 0
    fi
    local esp_abs="${TARGET}${esp_rel}"
    log "Secure Boot: configuring shim + per-machine MOK (ESP=${esp_rel})"

    # Signing tooling is already on the target via unpackfs; top up if online.
    in_chroot pacman -S --needed --noconfirm sbsigntools mokutil efitools >/dev/null 2>&1 || true

    local keydir="${TARGET}/var/lib/maze-secureboot"
    mkdir -p "${keydir}"; chmod 700 "${keydir}"
    cp -f "${live_shim}" "${keydir}/shimx64.efi" 2>/dev/null || true
    [[ -f "${live_mm}" ]] && cp -f "${live_mm}" "${keydir}/mmx64.efi" 2>/dev/null || true

    # 1) Per-machine MOK key.
    if [[ ! -f "${keydir}/MOK.key" ]]; then
        if ! in_chroot openssl req -newkey rsa:2048 -nodes \
                -keyout /var/lib/maze-secureboot/MOK.key -new -x509 -sha256 -days 3650 \
                -subj "/CN=Maze Linux Secure Boot machine key/" \
                -out /var/lib/maze-secureboot/MOK.crt >/dev/null 2>&1; then
            warn "Secure Boot: MOK key generation failed; skipping SB"
            return 0
        fi
        in_chroot openssl x509 -outform DER -in /var/lib/maze-secureboot/MOK.crt \
            -out /var/lib/maze-secureboot/MOK.cer >/dev/null 2>&1 || true
        in_chroot chmod 600 /var/lib/maze-secureboot/MOK.key >/dev/null 2>&1 || true
    fi

    # 2) The signer script (layout-agnostic: UKI or separate vmlinuz, ESP==boot
    #    or split). Idempotent. Identical to the archinstall installer's version.
    install -Dm755 /dev/stdin "${TARGET}/usr/local/bin/maze-sb-sign" <<'SBSIGN'
#!/bin/sh
# Managed by Maze Linux. (Re)signs every boot artifact the firmware/shim may
# chainload with the per-machine Secure Boot (MOK) key. Idempotent and
# layout-agnostic. Usage: maze-sb-sign [ESP_MOUNTPOINT] [--force-bootloader]
set -eu

KEYDIR=/var/lib/maze-secureboot
KEY="$KEYDIR/MOK.key"
CRT="$KEYDIR/MOK.crt"
CER="$KEYDIR/MOK.cer"

[ -r "$KEY" ] && [ -r "$CRT" ] || { echo "maze-sb-sign: no MOK key, skipping" >&2; exit 0; }

ESP=""
force_bootloader=0
for arg in "$@"; do
    case "$arg" in
        --force-bootloader) force_bootloader=1 ;;
        *) ESP="$arg" ;;
    esac
done

if [ -z "$ESP" ]; then
    ESP="$(bootctl --print-esp-path 2>/dev/null || true)"
    [ -n "${ESP:-}" ] && [ -d "$ESP" ] || ESP=/efi
    [ -d "$ESP" ] || ESP=/boot
fi
if [ ! -d "$ESP" ]; then
    echo "maze-sb-sign: ESP path '$ESP' does not exist" >&2
    exit 1
fi

status_ok=1

install_if_diff() {
    [ -f "$1" ] || return 0
    cmp -s "$1" "$2" 2>/dev/null && return 0
    install -m644 "$1" "$2"
}

sign_inplace() {
    f="$1"
    [ -e "$f" ] || return 0
    if sbverify --cert "$CRT" "$f" >/dev/null 2>&1; then
        echo "maze-sb-sign: OK     $f"
        return 0
    fi
    if sbsign --key "$KEY" --cert "$CRT" --output "$f.maze-signed" "$f" 2>/dev/null; then
        mv -f "$f.maze-signed" "$f"
        echo "maze-sb-sign: SIGNED $f"
    else
        rm -f "$f.maze-signed"
        echo "maze-sb-sign: FAIL   $f" >&2
        status_ok=0
    fi
}

BOOTDIR="$ESP/EFI/BOOT"
mkdir -p "$BOOTDIR"
install_if_diff "$KEYDIR/shimx64.efi" "$BOOTDIR/BOOTX64.EFI"
install_if_diff "$KEYDIR/mmx64.efi"   "$BOOTDIR/mmx64.efi"
install_if_diff "$CER"                "$ESP/MOK.cer"

SDBOOT=/usr/lib/systemd/boot/efi/systemd-bootx64.efi
GRUB="$BOOTDIR/grubx64.efi"
if [ -f "$SDBOOT" ]; then
    if [ "$force_bootloader" = 0 ] && sbverify --cert "$CRT" "$GRUB" >/dev/null 2>&1; then
        echo "maze-sb-sign: OK     $GRUB"
    elif sbsign --key "$KEY" --cert "$CRT" --output "$GRUB" "$SDBOOT"; then
        echo "maze-sb-sign: SIGNED $GRUB"
    else
        echo "maze-sb-sign: FAIL   $GRUB" >&2
        status_ok=0
    fi
fi

boot_path="$(bootctl --print-boot-path 2>/dev/null || true)"
dirs="$ESP"
for d in "$boot_path" /boot /efi; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    case " $dirs " in *" $d "*) ;; *) dirs="$dirs $d" ;; esac
done

for d in $dirs; do
    # Kernel images across every layout systemd-boot may load:
    #   * EFI/Linux/*.efi      — UKIs
    #   * vmlinuz-*            — flat / archiso-style BLS
    #   * */*/linux            — kernel-install BLS layout (Calamares default):
    #                            $ESP/<machine-id>/<version>/linux. THIS is what
    #                            systemd-boot loads on a Calamares install; missing
    #                            it left the kernel unsigned -> "Security violation".
    for f in "$d"/EFI/Linux/*.efi "$d"/vmlinuz-* "$d"/*/*/linux; do
        sign_inplace "$f"
    done
done

if [ "$status_ok" = 1 ]; then
    echo "maze-sb-sign: signed all boot artifacts (ESP=$ESP)"
else
    echo "maze-sb-sign: WARNING - some boot files are NOT validly signed (ESP=$ESP)" >&2
    exit 1
fi
SBSIGN

    # pacman hook: re-sign after anything that regenerates kernel/initramfs/UKI or
    # the systemd-boot binary.
    install -Dm644 /dev/stdin "${TARGET}/etc/pacman.d/hooks/95-maze-secureboot.hook" <<'SBHOOK'
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/vmlinuz
Target = usr/lib/systemd/boot/efi/*
Target = boot/vmlinuz-*
Target = boot/initramfs-*.img

[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = nvidia
Target = nvidia-dkms
Target = nvidia-open
Target = nvidia-open-dkms
Target = nvidia-lts
Target = nvidia-utils
Target = dkms
Target = mkinitcpio
Target = systemd

[Action]
Description = Signing bootloader and kernels for Secure Boot (Maze)...
When = PostTransaction
Exec = /usr/local/bin/maze-sb-sign --force-bootloader
SBHOOK

    # systemd .path unit: catch a MANUAL `mkinitcpio -P` (no pacman txn) + a once-
    # per-boot self-heal.
    install -Dm644 /dev/stdin "${TARGET}/etc/systemd/system/maze-sb-resign.service" <<'SBSVC'
[Unit]
Description=Re-sign bootloader and kernels for Secure Boot (Maze)
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/maze-sb-sign

[Install]
WantedBy=multi-user.target
SBSVC
    install -Dm644 /dev/stdin "${TARGET}/etc/systemd/system/maze-sb-resign.path" <<'SBPATH'
[Unit]
Description=Watch for regenerated unified kernel images and re-sign them (Maze Secure Boot)

[Path]
PathChanged=/efi/EFI/Linux
PathChanged=/boot/EFI/Linux
PathChanged=/boot
Unit=maze-sb-resign.service

[Install]
WantedBy=paths.target
SBPATH
    in_chroot systemctl enable maze-sb-resign.path maze-sb-resign.service >/dev/null 2>&1 \
        || warn "Secure Boot: could not enable maze-sb-resign units"
    # Mask systemd's own boot updater: `bootctl update` would overwrite the shim at
    # EFI/BOOT/BOOTX64.EFI with an unsigned systemd-boot and break the chain.
    in_chroot systemctl mask systemd-boot-update.service >/dev/null 2>&1 || true

    # 3) Sign now (explicit ESP — bootctl is unreliable in the install chroot).
    if in_chroot /usr/local/bin/maze-sb-sign --force-bootloader "${esp_rel}"; then
        MAZE_SB_ESP="${esp_rel}"
    else
        warn "Secure Boot: initial signing reported problems; boot with SB disabled until resolved"
        MAZE_SB_ESP="${esp_rel}"
    fi

    # 4) NVRAM entry pointing at shim (best-effort; the removable
    #    /EFI/BOOT/BOOTX64.EFI fallback covers most firmware incl. OVMF VMs).
    local espdev disk="" partn=""
    espdev="$(findmnt -no SOURCE "${esp_abs}" 2>/dev/null || true)"
    if [[ -n "${espdev}" ]]; then
        if [[ "${espdev}" =~ ^(/dev/.*[0-9])p([0-9]+)$ ]]; then      # nvme/mmcblk
            disk="${BASH_REMATCH[1]}"; partn="${BASH_REMATCH[2]}"
        elif [[ "${espdev}" =~ ^(/dev/.*[a-z])([0-9]+)$ ]]; then     # sd/vd
            disk="${BASH_REMATCH[1]}"; partn="${BASH_REMATCH[2]}"
        fi
        if [[ -n "${disk}" && -n "${partn}" ]]; then
            in_chroot efibootmgr --create --disk "${disk}" --part "${partn}" \
                --label "Maze Linux" --loader '\EFI\BOOT\BOOTX64.EFI' --unicode >/dev/null 2>&1 \
                || warn "Secure Boot: NVRAM entry not created (relying on removable fallback)"
        fi
    fi

    # 4b) Remove the competing UNSIGNED boot entry. Calamares' bootloader module
    # ran `bootctl install`, which created a "Linux Boot Manager" NVRAM entry
    # pointing DIRECTLY at \EFI\systemd\systemd-bootx64.efi. With Secure Boot ON
    # the firmware would boot THAT entry first and fail validation — the binary is
    # signed by nobody, and even a MOK signature would not help because MOK is only
    # honoured when shim is in the chain. Delete every such entry so the firmware
    # can only boot through shim (our "Maze Linux" entry, or the removable
    # \EFI\BOOT\BOOTX64.EFI fallback — both are shim).
    local bn
    for bn in $(in_chroot efibootmgr -v 2>/dev/null \
                  | grep -i 'systemd-bootx64\.efi' \
                  | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\).*/\1/p'); do
        in_chroot efibootmgr --bootnum "${bn}" --delete-bootnum >/dev/null 2>&1 \
            && log "Secure Boot: removed unsigned direct systemd-boot entry Boot${bn}" \
            || true
    done

    # 5) First-boot enrollment instructions (password-less, physical presence).
    install -Dm644 /dev/stdin "${TARGET}/var/lib/maze-secureboot/ENROLLMENT.txt" <<'SBNOTE'
Maze Linux — Secure Boot key enrollment
========================================

This machine boots with UEFI Secure Boot using a Microsoft-signed shim plus a
key unique to this computer. The key's certificate must be enrolled once. There
is NO password — enrollment requires physical presence (you confirm it at the
firmware-level MokManager menu on the next boot).

On the FIRST reboot the boot loader is not trusted yet, so a blue "Verification
failed" / "MOK Management" (MokManager) screen appears. Do this once:

  1. Choose "Enroll key from disk"
  2. Select the EFI system partition volume, then the file:  MOK.cer
  3. Confirm / "Continue", then "Yes" to enroll
  4. Reboot

After that the system boots normally with Secure Boot enabled. Factory/Windows
keys are left untouched; kernel updates are re-signed automatically.

Certificate:  /var/lib/maze-secureboot/MOK.cer  (also at the ESP root /MOK.cer)
Check status:  mokutil --sb-state
SBNOTE

    log "Secure Boot configured. Enroll MOK.cer via MokManager on first boot (no password)."
}

# 2c) Installed system must not advertise the installer ---------------------
# Remove the "Install Maze Linux" launcher from the panel/dock in the skel that
# will be copied to each user (the live ISO keeps it; the installed system does
# not need it). The live skel was already copied above, so patch it here.
log "Removing the installer launcher from the panel (installed system)"
strip_installer_launcher() {
    local appletsrc="$1"
    [[ -f "${appletsrc}" ]] || return 0
    # Drop the installer .desktop entries (archinstall + Calamares) from any
    # 'launchers=' list.
    sed -i -E 's#applications:maze-install\.desktop,?##g'    "${appletsrc}" 2>/dev/null || true
    sed -i -E 's#applications:maze-calamares\.desktop,?##g'  "${appletsrc}" 2>/dev/null || true
}
strip_installer_launcher "${TARGET}/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc"
# Also drop any stray installer desktop entry/icon on the target.
rm -f "${TARGET}/usr/share/applications/maze-install.desktop" 2>/dev/null || true

# 2c-bis) Strip LIVE-ONLY files that the Calamares OFFLINE (unpackfs) install
# copies wholesale onto the target. The live medium is intentionally permissive
# (passwordless sudo/pkexec, autologin) so the installer can run unattended; NONE
# of that may reach the installed system. These rm's are guarded/no-op on the
# archinstall path (a pacstrapped target never had these files). SECURITY: do not
# remove this block.
log "Stripping live-only files (autologin / passwordless sudo+pkexec / installers)"
# 1. Passwordless sudo for wheel (live only). Calamares' users module writes a
#    password-REQUIRED wheel sudoers file; we additionally guarantee one below.
rm -f "${TARGET}/etc/sudoers.d/10-maze" 2>/dev/null || true
# 2. Passwordless pkexec polkit rule that the live medium uses to elevate the
#    Calamares launcher silently — catastrophic if left on a real system.
rm -f "${TARGET}/etc/polkit-1/rules.d/49-maze-calamares.rules" 2>/dev/null || true
# 3. Console autologin (getty@tty1) and the SDDM autologin drop-in for 'maze'.
rm -f "${TARGET}/etc/systemd/system/getty@tty1.service.d/autologin.conf" 2>/dev/null || true
rmdir "${TARGET}/etc/systemd/system/getty@tty1.service.d" 2>/dev/null || true
rm -f "${TARGET}/etc/sddm.conf.d/10-maze-autologin.conf" 2>/dev/null || true
# 4. Installer binaries + launchers (archinstall CLI/TUI/GUI and Calamares).
for _b in maze-calamares maze-install maze-install-gui mazeinstaller \
          maze-installer-gui maze-installer-config; do
    rm -f "${TARGET}/usr/local/bin/${_b}" 2>/dev/null || true
done
rm -f "${TARGET}/usr/share/applications/maze-calamares.desktop" 2>/dev/null || true
# 5. The live-user build helper (harmless but live-only).
rm -f "${TARGET}/usr/local/share/maze/setup-live-user.sh" 2>/dev/null || true
# 5b. The live medium's /etc/motd ("...live and install medium", "run maze-install",
#     "default user is root no password") must not greet an installed system.
rm -f "${TARGET}/etc/motd" 2>/dev/null || true
# 5c. The live "never suspend/hibernate/lid" logind drop-in keeps an installed
#     LAPTOP from sleeping on lid-close and ignores the suspend/hibernate keys.
#     It is live-only — remove it so power management works on the real system.
rm -f "${TARGET}/etc/systemd/logind.conf.d/do-not-suspend.conf" 2>/dev/null || true
# NOTE: the live /home/maze leftover is purged EARLY by calamares-mount-api.sh
# (before the Calamares `users` module runs), NOT here — deleting it at this
# point would wipe the home of a real user who named THEIR OWN account 'maze'.

# Guarantee a password-REQUIRED sudoers rule for wheel on the target, regardless
# of whether Calamares' users module wrote its own (file name varies by version).
# Written atomically with 0440 so sudo accepts it.
_sudoers_dir="${TARGET}/etc/sudoers.d"
if [[ -d "${_sudoers_dir}" ]]; then
    printf '# Maze Linux: members of group wheel may use sudo (password required).\n%%wheel ALL=(ALL:ALL) ALL\n' \
        > "${_sudoers_dir}/10-maze-wheel" 2>/dev/null \
        && chmod 0440 "${_sudoers_dir}/10-maze-wheel" 2>/dev/null \
        || warn "could not write target wheel sudoers"
fi

# 2d) Maze wallpaper on the installed system --------------------------------
# Patch the Plasma defaults so "Maze" is the default wallpaper (covers fresh
# profiles / fallback when the live containment's plugin is unavailable).
if [[ -f /usr/local/share/maze/set-default-wallpaper.sh ]]; then
    install -Dm755 /usr/local/share/maze/set-default-wallpaper.sh \
        "${TARGET}/usr/local/share/maze/set-default-wallpaper.sh" 2>/dev/null || true
    in_chroot /usr/local/share/maze/set-default-wallpaper.sh >/dev/null 2>&1 \
        || warn "set-default-wallpaper on target failed"
fi

# 2e) Maze Welcome on the FIRST boot after install -------------------------
# Drop the welcome autostart into the target skel so each newly created user
# sees it once on first login. The app deletes this entry the first time it
# runs, so it never opens again. This lives only on the installed system (it is
# NOT in the live ISO's /etc/skel), so the live session never autostarts it.
if [[ -f /usr/share/maze/target-firstboot/maze-welcome-autostart.desktop ]]; then
    install -Dm644 /usr/share/maze/target-firstboot/maze-welcome-autostart.desktop \
        "${TARGET}/etc/skel/.config/autostart/maze-welcome.desktop" 2>/dev/null \
        || warn "welcome autostart install failed"
fi

# 2f) Best monitor as primary on the FIRST login ---------------------------
# Multi-monitor installs start with no saved screen state (it is stripped above
# so KWin re-detects per hardware), so KWin can make the wrong connector primary
# and the Maze panel — pinned to screen 0 — lands on the wrong monitor. The
# maze-primary-screen helper promotes the highest-resolution output to primary
# on first login, then drops a per-user marker so it never overrides the user's
# own Display-settings choices afterwards. Installed-system only (not live skel).
if [[ -f /usr/share/maze/target-firstboot/maze-primary-screen-autostart.desktop ]]; then
    install -Dm644 /usr/share/maze/target-firstboot/maze-primary-screen-autostart.desktop \
        "${TARGET}/etc/skel/.config/autostart/maze-primary-screen.desktop" 2>/dev/null \
        || warn "primary-screen autostart install failed"
fi

# 2f) Remove KDE's stock Plasma Welcome so only the Maze Welcome app appears.
# -Rdd ignores the plasma-meta dependency (harmless: meta-package only). Without
# the plasma-welcome binary, its autostart entry simply does nothing. We also
# keep the skel Hidden=true mask as a fallback in case an upgrade pulls it back.
if in_chroot pacman -Qq plasma-welcome >/dev/null 2>&1; then
    log "Removing KDE's stock Plasma Welcome (only Maze Welcome should run)"
    in_chroot pacman -Rdd --noconfirm plasma-welcome >/dev/null 2>&1 \
        || warn "could not remove plasma-welcome (Hidden=true mask still applies)"
fi

# 2g) Default account picture — the Maze maze-block logo --------------------
# Drop the logo into the skel as ~/.face.icon (KDE and SDDM use it as the user
# avatar). Each created user also gets an authoritative AccountsService entry in
# the per-user loop below, which is what the login screen and System Settings
# read first; ~/.face.icon is the fallback. Both point at the same image.
MAZE_AVATAR_SRC="/usr/share/pixmaps/maze-user-avatar.png"
if [[ -f "${MAZE_AVATAR_SRC}" ]]; then
    install -Dm644 "${MAZE_AVATAR_SRC}" "${TARGET}/etc/skel/.face.icon" 2>/dev/null \
        || warn "skel .face.icon install failed"
fi

# 3) Apply the desktop config to the user(s) created by the installer -------
log "Applying Maze defaults to user home directories"
for home in "${TARGET}"/home/*; do
    [[ -d "${home}" ]] || continue
    user=$(basename "${home}")
    owner_uid=$(stat -c '%u' "${home}")
    owner_gid=$(stat -c '%g' "${home}")
    cp -an "${TARGET}/etc/skel/." "${home}/" 2>/dev/null || warn "skel copy to ${home} failed"
    # FORCE the Maze .zshrc over whatever the home already has. grml-zsh-config
    # ships its OWN /etc/skel/.zshrc, so Calamares seeds the home with grml's
    # version at account-creation; the no-clobber copy above then can't replace it
    # and the user loses the Maze oh-my-zsh prompt + fastfetch banner. Overwrite
    # it explicitly. Same for .oh-my-zsh (must be the Maze one).
    if [[ -f "${TARGET}/etc/skel/.zshrc" ]]; then
        cp -f "${TARGET}/etc/skel/.zshrc" "${home}/.zshrc" 2>/dev/null || true
    fi
    [[ -d "${TARGET}/etc/skel/.oh-my-zsh" ]] && cp -an "${TARGET}/etc/skel/.oh-my-zsh" "${home}/" 2>/dev/null || true
    # Scrub display/output state from THIS user's home. useradd already seeded the
    # home from skel with cp -an (no-clobber) at account-creation time, so the
    # stale config can survive the skel copy above — strip it directly so the
    # primary monitor is auto-detected for this machine, not inherited.
    strip_display_state "${home}"
    # Default avatar: register the Maze avatar logo with AccountsService so the
    # SDDM login screen and System Settings > Users show it as the account
    # picture (~/.face.icon, copied from skel above, is the fallback).
    if [[ -f "${MAZE_AVATAR_SRC}" ]]; then
        acc_icons="${TARGET}/var/lib/AccountsService/icons"
        acc_users="${TARGET}/var/lib/AccountsService/users"
        mkdir -p "${acc_icons}" "${acc_users}"
        cp -f "${MAZE_AVATAR_SRC}" "${acc_icons}/${user}" 2>/dev/null || warn "avatar copy for ${user} failed"
        cat > "${acc_users}/${user}" <<EOF
[User]
Icon=/var/lib/AccountsService/icons/${user}
SystemAccount=false
EOF
    fi
    # The live panel config hard-codes the live user's home (/home/maze) for the
    # video wallpaper; repoint it at this user's home so the wallpaper resolves.
    user_appletsrc="${home}/.config/plasma-org.kde.plasma.desktop-appletsrc"
    if [[ -f "${user_appletsrc}" && "${user}" != "maze" ]]; then
        sed -i "s#/home/maze/#/home/${user}/#g" "${user_appletsrc}" 2>/dev/null || true
    fi
    # Drop the installer (maze-install / maze-calamares) launcher from THIS user's
    # dock too. useradd seeded the home from skel BEFORE skel was stripped, and the
    # cp -an above is no-clobber, so the installer pin survives here and must be
    # removed explicitly — otherwise the installed system keeps an installer icon.
    strip_installer_launcher "${user_appletsrc}"
    chown -R "${owner_uid}:${owner_gid}" "${home}" 2>/dev/null || true
    # Private home: 700 (not world-readable). A desktop home holds keys, tokens
    # and history; a 755 home leaks all of it to every local account. (lynis
    # HOME-9304.)
    chmod 700 "${home}" 2>/dev/null || true
    # Match the live medium: zsh as the login shell. usermod edits /etc/passwd
    # directly (no PAM), so it can never prompt/hang the way chsh can.
    in_chroot usermod -s /usr/bin/zsh "${user}" >/dev/null 2>&1 || true
done

# 3b) GPU: configure the NVIDIA proprietary driver if the installer added it ---
NVIDIA_PARAMS=""
if in_chroot pacman -Qq nvidia nvidia-dkms nvidia-open nvidia-open-dkms nvidia-lts 2>/dev/null | grep -q .; then
    log "Configuring NVIDIA proprietary driver (modeset + early KMS)"
    cat > "${TARGET}/etc/modprobe.d/nvidia.conf" <<'EOF'
# DRM kernel mode setting + framebuffer console handover (clean splash, no
# vendor-fbdev flicker) and GPU System Processor firmware for Turing+ cards.
options nvidia_drm modeset=1 fbdev=1
options nvidia NVreg_EnableGpuFirmware=1
# Keep VRAM contents across suspend/hibernate so the desktop comes back without
# corruption (works together with the nvidia-suspend/resume services below).
options nvidia NVreg_PreserveVideoMemoryAllocations=1
# Use the Page Attribute Table for memory mappings (better GPU throughput).
options nvidia NVreg_UsePageAttributeTable=1

blacklist nouveau
options nouveau modeset=0
EOF
    mkc="${TARGET}/etc/mkinitcpio.conf"
    if [[ -f "${mkc}" ]] && ! grep -q 'nvidia' "${mkc}"; then
        sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' "${mkc}" 2>/dev/null \
            || warn "mkinitcpio MODULES (nvidia) edit failed"
    fi
    # Preserve-VRAM needs these to actually save/restore on sleep & hibernate.
    in_chroot systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service \
        >/dev/null 2>&1 || warn "could not enable nvidia suspend/resume services"
    NVIDIA_PARAMS=" nvidia-drm.modeset=1 nvidia-drm.fbdev=1"
fi

# 4) Plymouth boot splash --------------------------------------------------
log "Configuring Plymouth"
mkconf="${TARGET}/etc/mkinitcpio.conf"
if [[ -f "${mkconf}" ]]; then
    if ! grep -q 'plymouth' "${mkconf}"; then
        # Not in hooks yet — add right after kms (GPU up = clean splash), or after udev.
        if grep -qE 'HOOKS=\([^)]*\bkms\b' "${mkconf}"; then
            sed -i -E 's/(HOOKS=\([^)]*\bkms\b)/\1 plymouth/' "${mkconf}" 2>/dev/null || warn "mkinitcpio HOOKS edit failed"
        else
            sed -i 's/\(HOOKS=([^)]*udev\)/\1 plymouth/' "${mkconf}" 2>/dev/null || warn "mkinitcpio HOOKS edit failed"
        fi
    elif grep -qE '\bkms\b' "${mkconf}" && ! grep -qE '\bkms\b[[:space:]]+\bplymouth\b' "${mkconf}"; then
        # Plymouth already in hooks but not right after kms — reposition it.
        sed -i -E 's/[[:space:]]*\bplymouth\b//' "${mkconf}" 2>/dev/null || true
        sed -i -E 's/(HOOKS=\([^)]*\bkms\b)/\1 plymouth/' "${mkconf}" 2>/dev/null || warn "mkinitcpio plymouth reposition failed"
    fi
fi
# 5) Kernel command line — must be written BEFORE mkinitcpio so UKI picks it up.
log "Adding kernel parameters (quiet splash bgrt_disable + AppArmor${NVIDIA_PARAMS:+ + NVIDIA})"
# The full set of params Maze wants on every boot. NONE of these is root=/
# rootflags=/rootfstype= — those belong to the installer and must never be
# duplicated by us.
EXTRA_PARAMS="quiet splash bgrt_disable logo.nologo lsm=landlock,lockdown,yama,integrity,apparmor,bpf apparmor=1 security=apparmor${NVIDIA_PARAMS}"

# /etc/kernel/cmdline is the authoritative source for UKI builds. archinstall
# already wrote it with root=, rootflags=, etc. We APPEND only the missing
# params; never overwrite, so root= is preserved.
#
# Token-exact dedup: compare whole tokens, not substrings. (A naive grep for
# "apparmor" would match the "apparmor" inside lsm=...,apparmor,bpf and wrongly
# skip apparmor=1.)
mkdir -p "${TARGET}/etc/kernel"
_existing_cmdline="$(cat "${TARGET}/etc/kernel/cmdline" 2>/dev/null || true)"
_new_cmdline="${_existing_cmdline}"
for _p in ${EXTRA_PARAMS}; do
    _key="${_p%%=*}"
    _present=0
    for _e in ${_new_cmdline}; do
        if [[ "${_e}" == "${_p}" || "${_e}" == "${_key}="* ]]; then
            _present=1; break
        fi
    done
    [[ "${_present}" -eq 1 ]] || _new_cmdline="${_new_cmdline} ${_p}"
done
printf '%s\n' "${_new_cmdline}" > "${TARGET}/etc/kernel/cmdline"

# For systemd-boot/GRUB/Limine config files we append ONLY the extra params
# (these files already carry their own root=). Never the full cmdline.
PARAMS="${EXTRA_PARAMS}"

# Write plymouthd.conf explicitly so BGRT is never shown as a transition
# frame and the maze theme starts immediately (ShowDelay=0).
mkdir -p "${TARGET}/etc/plymouth"
cat > "${TARGET}/etc/plymouth/plymouthd.conf" <<'PLYMOUTHD'
[Daemon]
Theme=maze
ShowDelay=0
DeviceTimeout=5
PLYMOUTHD
in_chroot plymouth-set-default-theme maze >/dev/null 2>&1 || warn "plymouth-set-default-theme failed"

# Fix mkinitcpio presets: remove Arch Linux branding before building UKI.
for _preset in "${TARGET}"/etc/mkinitcpio.d/*.preset; do
    [[ -f "${_preset}" ]] || continue
    # Comment out --splash so no vendor logo BMP is embedded in the UKI.
    sed -i -E 's/^(default_options=.*--splash.*)/# \1/' "${_preset}" 2>/dev/null || true
    # Rename arch-<kernel> → maze-<kernel> in the UKI output path.
    sed -i 's|/arch-\([^"]*\)\.efi|/maze-\1.efi|g' "${_preset}" 2>/dev/null || true
done

# Update loader.conf default entry to match renamed UKI.
_loaderconf="${TARGET}/efi/loader/loader.conf"
[[ -f "${_loaderconf}" ]] || _loaderconf="${TARGET}/boot/loader/loader.conf"
if [[ -f "${_loaderconf}" ]]; then
    sed -i 's|default arch-\([^ ]*\)\.efi|default maze-\1.efi|' "${_loaderconf}" 2>/dev/null || true
fi

in_chroot mkinitcpio -P >/dev/null 2>&1 || warn "mkinitcpio rebuild failed"

# systemd-boot BLS entries (non-UKI). Entries live under $BOOT/loader/entries
# where $BOOT is the ESP mounted at /boot or an XBOOTLDR at /boot; also cover an
# ESP mounted at /efi so the params are never missed regardless of layout.
for e in "${TARGET}"/boot/loader/entries/*.conf "${TARGET}"/efi/loader/entries/*.conf; do
    [[ -f "${e}" ]] || continue
    grep -q 'bgrt_disable' "${e}" || sed -i "/^options/ s/\$/ ${PARAMS}/" "${e}" 2>/dev/null || true
done
# GRUB (installed-system bootloader): kernel cmdline params + Maze OLED theme.
grubdef="${TARGET}/etc/default/grub"
if [[ -f "${grubdef}" ]]; then
    _grub_changed=0
    if ! grep -q 'bgrt_disable' "${grubdef}"; then
        sed -i "s|^\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\)\"|\1 ${PARAMS}\"|" "${grubdef}" 2>/dev/null \
            && _grub_changed=1
    fi
    # Brand the GRUB menu: every entry must read "Maze Linux", never "Arch Linux".
    # grub-mkconfig builds the title from GRUB_DISTRIBUTOR (grub ships it as Arch).
    if grep -q '^GRUB_DISTRIBUTOR=' "${grubdef}"; then
        grep -q '^GRUB_DISTRIBUTOR="Maze Linux"' "${grubdef}" \
            || { sed -i 's|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR="Maze Linux"|' "${grubdef}"; _grub_changed=1; }
    else
        printf '\nGRUB_DISTRIBUTOR="Maze Linux"\n' >> "${grubdef}"; _grub_changed=1
    fi
    # Maze true-black OLED boot theme (copied from the live system).
    if [[ -d /usr/share/grub/themes/maze ]]; then
        mkdir -p "${TARGET}/boot/grub/themes"
        if cp -a /usr/share/grub/themes/maze "${TARGET}/boot/grub/themes/" 2>/dev/null; then
            if grep -q '^GRUB_THEME=' "${grubdef}"; then
                sed -i 's|^GRUB_THEME=.*|GRUB_THEME="/boot/grub/themes/maze/theme.txt"|' "${grubdef}"
            else
                printf '\n# Maze OLED boot theme\nGRUB_THEME="/boot/grub/themes/maze/theme.txt"\n' >> "${grubdef}"
            fi
            _grub_changed=1
        else
            warn "could not install GRUB theme"
        fi
    fi
    if [[ "${_grub_changed}" == 1 ]]; then
        in_chroot grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || true
    fi
fi
# (Limine is NOT used by Maze — UEFI uses systemd-boot, BIOS uses GRUB — so the
# old Limine cmdline-patching block was removed.)

# 5b) Secure Boot (shim + per-machine MOK). Runs AFTER the kernel/initramfs and
# bootloader are in place so there are artifacts to sign, and BEFORE the AUR/app
# phase so the pacman re-sign hook is already active when those rebuild the
# initramfs. A final re-sign runs at the very end (after AUR). Best-effort.
setup_secure_boot

# pacman polish on the target: colour, verbose lists, parallel downloads and the
# on-brand pac-man progress bar (mirror the live ISO's pacman.conf flair).
pconf="${TARGET}/etc/pacman.conf"
if [[ -f "${pconf}" ]]; then
    grep -q '^Color'             "${pconf}" || sed -i 's/^#Color/Color/'                       "${pconf}"
    grep -q '^VerbosePkgLists'   "${pconf}" || sed -i 's/^#VerbosePkgLists/VerbosePkgLists/'   "${pconf}"
    grep -q '^ParallelDownloads' "${pconf}" || sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 15/' "${pconf}"
    grep -q '^ILoveCandy'        "${pconf}" || sed -i '/^Color$/a ILoveCandy'                  "${pconf}"
fi

# 5c) Locale: make date/number formats follow the LANGUAGE -----------------
# Calamares can set the FORMAT locales (LC_TIME, LC_NUMERIC, ...) to the install
# LOCATION's country (e.g. Turkey -> tr_TR) even when the chosen language is
# English — so the clock/date show up in Turkish on an "English" system. Align
# everything to LANG: drop the LC_* overrides so the whole locale follows the
# language (the same clean setup a stock English machine has). Timezone is
# separate (/etc/localtime) and is left as the user chose it.
lconf="${TARGET}/etc/locale.conf"
if [[ -f "${lconf}" ]] && grep -q '^LANG=' "${lconf}"; then
    _lang="$(sed -n 's/^LANG=//p' "${lconf}" | tr -d '"' | head -1)"
    log "Aligning format locales to the language (${_lang})"
    sed -i '/^LC_/d' "${lconf}"
fi

# 5d) /etc/hosts: map the hostname so name resolution is clean (and lynis
# NAME-4404 stops warning). Add the loopback hostname line if missing.
_hn="$(cat "${TARGET}/etc/hostname" 2>/dev/null | head -1)"
if [[ -n "${_hn}" ]]; then
    [[ -f "${TARGET}/etc/hosts" ]] || printf '127.0.0.1\tlocalhost\n::1\t\tlocalhost\n' > "${TARGET}/etc/hosts"
    grep -qE "[[:space:]]${_hn}([[:space:]]|\$)" "${TARGET}/etc/hosts" 2>/dev/null \
        || printf '127.0.1.1\t%s.localdomain %s\n' "${_hn}" "${_hn}" >> "${TARGET}/etc/hosts"
fi

# 6) Enable services on the target -----------------------------------------
# Non-security services are always enabled. Security services are enabled only
# if the user kept them in the installer's Security section (empty = all).
# zram-generator drives the compressed RAM swap configured above; install it on
# the target if we can reach the network (best-effort, skipped offline).
in_chroot pacman -S --needed --noconfirm zram-generator >/dev/null 2>&1 \
    || warn "zram-generator not installed (offline?); /etc/systemd/zram-generator.conf is in place for later"

log "Enabling base Maze services"
for svc in ollama acpid power-profiles-daemon smartd libvirtd bluetooth cups \
           tor systemd-oomd fwupd-refresh.timer reflector.timer maze-flatpak-setup.service \
           maze-guardd.service maze-honeypot-setup.service maze-honeypot.service; do
    in_chroot systemctl enable "${svc}" >/dev/null 2>&1 || true
done

# Disable LIVE-only services that unpackfs carried over but must NOT run on an
# installed desktop. sshd is the important one: the live ISO enables it for
# remote installs, so without this every installed Maze boots with an SSH server
# listening — an attack surface a privacy desktop should not expose by default.
# (The Maze sshd hardening drop-in stays in place, so if the user enables sshd
# later it is already hardened.) The VM guest agents are harmless on real
# hardware but pointless to keep enabled.
log "Disabling live-only services on the target (sshd, VM guest agents)"
for svc in sshd vboxservice vmtoolsd vmware-vmblock-fuse \
           hv_kvp_daemon hv_vss_daemon hv_fcopy_daemon; do
    in_chroot systemctl disable "${svc}" >/dev/null 2>&1 || true
done

# Resolve the selected security features (empty selection => all of them).
sec_selected() {
    local key="$1"
    [[ -z "${SECURITY_CSV}" ]] && return 0          # empty => everything on
    case ",${SECURITY_CSV}," in
        *",${key},"*) return 0 ;;
        *) return 1 ;;
    esac
}

log "Applying Security selection: ${SECURITY_CSV:-<all>}"
sec_selected apparmor   && in_chroot systemctl enable apparmor          >/dev/null 2>&1 || true
sec_selected firewalld  && in_chroot systemctl enable firewalld         >/dev/null 2>&1 || true
sec_selected fail2ban   && in_chroot systemctl enable fail2ban          >/dev/null 2>&1 || true
sec_selected auditd     && in_chroot systemctl enable auditd            >/dev/null 2>&1 || true
sec_selected clamav     && in_chroot systemctl enable clamav-freshclam  >/dev/null 2>&1 || true
sec_selected macchanger && in_chroot systemctl enable mac-changer       >/dev/null 2>&1 || true

# OpenSnitch: daemon always enabled but starts in allow-all (passive) mode.
# GUI autostarts so user sees it in the tray; they can activate interception manually.
if sec_selected opensnitch; then
    copy_to_target /etc/opensnitchd/default-config.json
    in_chroot systemctl enable opensnitchd >/dev/null 2>&1 || true
else
    rm -f "${TARGET}/etc/skel/.config/autostart/opensnitch_ui.desktop" 2>/dev/null || true
    for home in "${TARGET}"/home/*; do
        [[ -d "${home}" ]] && rm -f "${home}/.config/autostart/opensnitch_ui.desktop" 2>/dev/null || true
    done
fi

if sec_selected firewalld; then
    in_chroot firewall-offline-cmd --add-service=ssh        >/dev/null 2>&1 || true
    in_chroot firewall-offline-cmd --add-service=kdeconnect >/dev/null 2>&1 || true
fi

# 7) pacman tuning on the installed system (match the live medium) ---------
log "Tuning pacman on the target (ParallelDownloads=15, Color)"
tconf="${TARGET}/etc/pacman.conf"
if [[ -f "${tconf}" ]]; then
    if grep -qE '^\s*#?\s*ParallelDownloads' "${tconf}"; then
        sed -i -E 's/^\s*#?\s*ParallelDownloads\s*=.*/ParallelDownloads = 15/' "${tconf}"
    else
        sed -i '/^\[options\]/a ParallelDownloads = 15' "${tconf}"
    fi
    sed -i -E 's/^\s*#\s*Color\s*$/Color/' "${tconf}"
    grep -qE '^\s*Color\s*$' "${tconf}" || sed -i '/^\[options\]/a Color' "${tconf}"
fi

# 7b) Maze Linux package repository on the target --------------------------
# Ship the official Maze repo so installed systems pull Maze packages and
# updates. Listed before the official repos so Maze's curated builds win.
# Packages are published unsigned -> Optional TrustAll. Idempotent: skip if the
# section was already inherited from the live medium's pacman.conf.
tconf="${TARGET}/etc/pacman.conf"
if [[ -f "${tconf}" ]] && ! grep -q '^\[mazelinux\]' "${tconf}"; then
    log "Adding Maze Linux repository to target pacman.conf"
    if grep -q '^\[core\]' "${tconf}"; then
        sed -i '/^\[core\]/i [mazelinux]\nSigLevel = Optional TrustAll\nServer = https://mazerepo.berkkucukk.com.tr/packages\n' "${tconf}"
    else
        printf '\n[mazelinux]\nSigLevel = Optional TrustAll\nServer = https://mazerepo.berkkucukk.com.tr/packages\n' >> "${tconf}"
    fi
fi

# 8) Ensure BlackArch is NOT configured on the target ----------------------
# A half-configured [blackarch] (repo enabled but keyring untrusted) poisons
# EVERY pacman operation — "database 'blackarch' is not valid (PGP signature)"
# — which then fails all AUR installs. We don't ship BlackArch, so make sure no
# stray [blackarch] section was inherited from the live pacman.conf.
tconf="${TARGET}/etc/pacman.conf"
if [[ -f "${tconf}" ]] && grep -q '^\[blackarch\]' "${tconf}"; then
    log "Removing stray BlackArch repo from target pacman.conf"
    sed -i '/^\[blackarch\]/,/^Include.*blackarch/d' "${tconf}" 2>/dev/null || true
fi
rm -f "${TARGET}/etc/pacman.d/blackarch-mirrorlist" 2>/dev/null || true

# 9) Refresh the icon cache so the branded "About this System" logo resolves.
in_chroot gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true

# 10) Install Maze's own applications from the [mazelinux] repo (fast, reliable).
install_maze_repo_apps

# 11) FINALLY, install the third-party AUR packages (slowest/most fragile step —
#     done last so everything above is guaranteed to be applied even if this
#     struggles).
install_aur_packages

# 12) FINAL Secure Boot re-sign. The AUR/app phase (and the [mazelinux] apps) can
# regenerate the initramfs/UKI (e.g. an nvidia or mkinitcpio pull) AFTER the
# initial signing, leaving an UNSIGNED kernel that Secure Boot would reject. The
# pacman hook usually catches this, but re-sign once more explicitly so the
# on-disk kernel/bootloader are guaranteed signed after the very last change.
if [[ -n "${MAZE_SB_ESP}" ]]; then
    log "Secure Boot: final re-sign after package install"
    in_chroot /usr/local/bin/maze-sb-sign --force-bootloader "${MAZE_SB_ESP}" \
        || warn "Secure Boot: final re-sign reported problems (boot with SB disabled if it won't boot)"
fi

log "Maze deployment finished"
exit 0
