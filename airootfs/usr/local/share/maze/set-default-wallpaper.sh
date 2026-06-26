#!/usr/bin/env bash
#
# set-default-wallpaper.sh — Make "Maze" the default Plasma wallpaper.
#
# Run as a pacman PostTransaction hook inside the build chroot, after Plasma is
# installed. It only changes *defaults*, so Plasma still generates its normal
# panel + desktop layout — just with the Maze wallpaper. The wallpaper itself is
# shipped as the package /usr/share/wallpapers/Maze, so the name "Maze" resolves.
#
set -euo pipefail

WALL="Maze"

# 1) Default for the org.kde.image wallpaper plugin (used for fresh desktops).
main_xml="/usr/share/plasma/wallpapers/org.kde.image/contents/config/main.xml"
if [[ -f "${main_xml}" ]]; then
    python3 - "${main_xml}" "${WALL}" <<'PY'
import re, sys
path, wall = sys.argv[1], sys.argv[2]
data = open(path, encoding="utf-8").read()
patched = re.sub(
    r'(<entry name="Image"[^>]*>.*?<default>).*?(</default>)',
    r'\g<1>' + wall + r'\g<2>',
    data, count=1, flags=re.DOTALL,
)
if patched != data:
    open(path, "w", encoding="utf-8").write(patched)
PY
fi

# 2) Wallpaper referenced by the Breeze look-and-feel packages (desktop + lock
#    screen). Best-effort: not every Plasma version sets it here.
shopt -s nullglob
for defaults in /usr/share/plasma/look-and-feel/org.kde.*/contents/defaults; do
    sed -i -E "s/^Image=.*/Image=${WALL}/" "${defaults}"
done
