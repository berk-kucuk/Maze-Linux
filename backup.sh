#!/usr/bin/env bash
#
# backup.sh - MazeLinux build dizinini yedekler.
#
# Yeniden uretilebilen (regenerable) agir cikti/onbellek klasorlerini
# DISARIDA birakir; sadece kaynak + konfigurasyon dosyalarini arsivler.
# Symlink ve dosya izinlerini korur (keys/, airootfs/ icin onemli).
#
# Disarida birakilanlar:
#   out/           -> uretilen ISO ciktilari (~41G)
#   work/          -> mkarchiso gecici calisma dizini (~19G)
#   aur/chroot/    -> makechrootpkg chroot onbellegi (~2.5G)
#   aur/*/pkg|src  -> AUR derleme ciktilari (PKGBUILD/.SRCINFO korunur)
#   localrepo/     -> her build'de yeniden uretilen derlenmis paketler (~1.1G)
#   *.pkg.tar.*    -> derlenmis paket dosyalari
#   *.log          -> build loglari
#
# Kullanim:
#   ./backup.sh                 -> ./maze-build-backup-YYYYMMDD-HHMM.tar.zst uretir
#   ./backup.sh /hedef/dizin    -> belirtilen dizine yedek olusturur

set -euo pipefail

# --- Ayarlar ---------------------------------------------------------------
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="maze-build-backup-$(date +%Y%m%d-%H%M)"
DEST_DIR="${1:-$SRC_DIR}"
ARCHIVE="$DEST_DIR/$NAME.tar.zst"
# tar, hedef SRC_DIR'in icindeyse arsiv dosyasi olusup buyudukce "."
# dizininin mtime'i degisir ve GNU tar "file changed as we read it"
# uyarisi verir. Bunu onlemek icin once SRC_DIR disinda gecici bir
# dosyaya yazip sonunda gercek hedefe tasiyoruz.
TMP_ARCHIVE="$(mktemp "${TMPDIR:-/tmp}/$NAME.tar.zst.XXXXXX")"

# Yedege DAHIL EDILMEYECEK desenler (tar --exclude sozdizimi).
EXCLUDES=(
  "./out"
  "./work"
  "./aur/chroot"
  "./localrepo"
  "./aur/*/pkg"
  "./aur/*/src"
  # AUR clone'larina build sirasinda indirilen upstream binary yukleri
  # (PKGBUILD/.SRCINFO/.install/.git recetesi korunur, yeniden indirilebilir)
  "./aur/*/*.deb"
  "./aur/*/*.zip"
  "./aur/*/*.AppImage"
  "./aur/*/*.tar.xz"
  "./aur/*/*.tar.zst"
  "*.pkg.tar.zst"
  "*.pkg.tar.xz"
  "*.log"
  "*.png.bak"
  "./maze-build-backup-*.tar.zst"
)

# --- On kontroller ---------------------------------------------------------
command -v tar  >/dev/null 2>&1 || { echo "HATA: 'tar' bulunamadi";  exit 1; }
command -v zstd >/dev/null 2>&1 || { echo "HATA: 'zstd' kurulu degil (pacman -S zstd)"; exit 1; }
mkdir -p "$DEST_DIR"

# --exclude argumanlarini olustur
EXCLUDE_ARGS=()
for pat in "${EXCLUDES[@]}"; do
  EXCLUDE_ARGS+=(--exclude="$pat")
done

echo ">> Kaynak   : $SRC_DIR"
echo ">> Hedef    : $ARCHIVE"
echo ">> Disarida : ${EXCLUDES[*]}"
echo

# --- Yedekleme -------------------------------------------------------------
# -C ile dizine gir, "." arsivler. zstd -19 -T0: cok cekirdekli yuksek sikistirma.
# Once SRC_DIR disindaki gecici dosyaya yaziyoruz (bkz. yukaridaki not),
# sonra hedef konuma tasiyoruz.
cleanup() { rm -f "$TMP_ARCHIVE"; }
trap cleanup EXIT

tar --zstd \
    "${EXCLUDE_ARGS[@]}" \
    -cf "$TMP_ARCHIVE" \
    -C "$SRC_DIR" \
    --exclude="./$NAME.tar.zst" \
    .

mv "$TMP_ARCHIVE" "$ARCHIVE"
trap - EXIT

echo
echo ">> Tamamlandi."
du -h "$ARCHIVE" | awk '{print ">> Boyut    : " $1}'
echo ">> Acmak icin: tar --zstd -xf $(basename "$ARCHIVE")"
