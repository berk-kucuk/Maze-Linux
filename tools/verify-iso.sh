#!/usr/bin/env bash
#
# verify-iso.sh — Maze Linux ISO çıkış kapısı.
#
# Derlenen ISO'nun (veya henüz paketlenmemiş work/iso ağacının) boot zincirini
# doğrular. Root GEREKTİRMEZ, hiçbir şeyi değiştirmez, CI'da çalışacak şekilde
# yazıldı: her şey geçerse 0, tek bir kontrol düşerse 1 döner.
#
# Neden var: canlı ISO'nun boot zinciri mkarchiso'ya çalışma anında enjekte
# edilen bir fonksiyonla (_maze_sb_sign_esp) kuruluyor. O fonksiyon sessizce
# yanlış çalışırsa ISO "derlendi" der ama hiçbir makinede açılmaz. Bu script
# tam olarak o boşluğu kapatır.
#
# Kullanım:
#     tools/verify-iso.sh out/mazelinux-*.iso
#     tools/verify-iso.sh work/iso          # ISO paketlenmeden önce
#     tools/verify-iso.sh <hedef> --cert keys/secureboot/Maze.crt
#
set -uo pipefail

PROFILE_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
CERT="${PROFILE_DIR}/keys/secureboot/Maze.crt"
TARGET=""
FAIL=0
TMP=""

ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[1;31m✗\033[0m %s\n' "$*"; FAIL=1; }
info() { printf '    %s\n' "$*"; }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$*"; }

cleanup() { [[ -n "${TMP}" && -d "${TMP}" ]] && rm -rf "${TMP}"; }
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cert) CERT="$2"; shift 2 ;;
        -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) TARGET="$1"; shift ;;
    esac
done
[[ -n "${TARGET}" ]] || { echo "kullanim: $0 <iso|iso-agaci> [--cert <crt>]" >&2; exit 2; }
[[ -e "${TARGET}" ]] || { echo "bulunamadi: ${TARGET}" >&2; exit 2; }

for t in objcopy bsdtar; do
    command -v "$t" >/dev/null 2>&1 || { echo "gerekli arac yok: $t" >&2; exit 2; }
done

# --- ESP dosyalarını eriş ------------------------------------------------
# ISO ise gerekli dosyaları geçici dizine çıkar; dizinse doğrudan kullan.
TMP="$(mktemp -d)"
ESP=""
ISO_MODE=0
if [[ -d "${TARGET}" ]]; then
    ESP="${TARGET}"
    hdr "Kaynak: ISO ağacı — ${TARGET}"
else
    ISO_MODE=1
    hdr "Kaynak: ISO — ${TARGET} ($(du -h "${TARGET}" | cut -f1))"
    for f in EFI/BOOT/BOOTx64.EFI EFI/BOOT/grubx64.efi EFI/BOOT/mmx64.efi MOK.cer; do
        mkdir -p "${TMP}/$(dirname "$f")"
        bsdtar xOf "${TARGET}" "$f" > "${TMP}/$f" 2>/dev/null || rm -f "${TMP}/$f"
    done
    ESP="${TMP}"
fi

BOOTX="${ESP}/EFI/BOOT/BOOTx64.EFI"
[[ -f "${BOOTX}" ]] || BOOTX="${ESP}/EFI/BOOT/BOOTX64.EFI"
GRUB="${ESP}/EFI/BOOT/grubx64.efi"
MM="${ESP}/EFI/BOOT/mmx64.efi"

sec()   { objcopy -O binary --only-section="$2" "$1" /dev/stdout 2>/dev/null; }
has()   { objdump -h "$1" 2>/dev/null | grep -qE "[[:space:]]$2[[:space:]]"; }

# --- 1. ESP düzeni -------------------------------------------------------
hdr "1. ESP düzeni"
[[ -s "${BOOTX}" ]] && ok "BOOTx64.EFI var ($(du -h "${BOOTX}" | cut -f1))" \
                    || bad "BOOTx64.EFI yok — firmware açacak bir şey bulamaz"
[[ -s "${GRUB}"  ]] && ok "grubx64.efi var ($(du -h "${GRUB}" | cut -f1))" \
                    || bad "grubx64.efi yok — shim chainload edecek bir şey bulamaz"
[[ -s "${MM}"    ]] && ok "mmx64.efi var (MokManager)" \
                    || bad "mmx64.efi yok — kullanıcı anahtarı enroll edemez"
if [[ -s "${ESP}/MOK.cer" ]]; then ok "MOK.cer ESP kökünde"
else bad "MOK.cer yok — MokManager'da enroll edilecek sertifika bulunamaz"; fi

# --- 2. Zincirin doğru sırada olması ------------------------------------
hdr "2. Boot zinciri"
if [[ -s "${BOOTX}" ]]; then
    if has "${BOOTX}" ".linux"; then
        bad "BOOTx64.EFI bir UKI — shim olması gerekiyordu, zincir yanlış kurulmuş"
    else
        ok "BOOTx64.EFI bir UKI değil (shim olması beklenen)"
    fi
fi
if [[ -s "${GRUB}" ]]; then
    miss=""
    for s in .linux .initrd .cmdline .osrel; do has "${GRUB}" "$s" || miss="${miss} $s"; done
    if [[ -z "${miss}" ]]; then ok "grubx64.efi geçerli bir UKI (.linux .initrd .cmdline .osrel)"
    else bad "grubx64.efi UKI değil — eksik bölüm:${miss}"; fi
fi

# --- 3. Kesilme testi ----------------------------------------------------
hdr "3. Bütünlük"
if [[ -s "${GRUB}" ]]; then
    fsz=$(stat -c %s "${GRUB}"); maxend=0
    while read -r _ _ size _ _ off _; do
        [[ "$size" =~ ^[0-9a-f]+$ && "$off" =~ ^[0-9a-f]+$ ]] || continue
        end=$(( 0x$off + 0x$size )); (( end > maxend )) && maxend=$end
    done < <(objdump -h "${GRUB}" 2>/dev/null | sed -n 's/^ *\([0-9]\+\) \+\(\.[a-z]*\) \+\([0-9a-f]\+\) \+\([0-9a-f]\+\) \+\([0-9a-f]\+\) \+\([0-9a-f]\+\).*/\1 \2 \3 \4 \5 \6/p')
    if (( maxend > 0 && fsz >= maxend )); then
        ok "grubx64.efi kesilmemiş (bölüm sonu ${maxend} ≤ dosya ${fsz})"
    else
        bad "grubx64.efi KESİLMİŞ — bölümler ${maxend} bayta gidiyor, dosya ${fsz}"
    fi
    lin=$(sec "${GRUB}" .linux  | wc -c)
    ini=$(sec "${GRUB}" .initrd | wc -c)
    (( lin > 1000000 )) && ok "gömülü çekirdek makul ($(numfmt --to=iec "$lin"))" \
                        || bad "gömülü çekirdek çok küçük ($lin bayt)"
    (( ini > 1000000 )) && ok "gömülü initramfs makul ($(numfmt --to=iec "$ini"))" \
                        || bad "gömülü initramfs çok küçük ($ini bayt)"
fi

# --- 4. Secure Boot imzası ----------------------------------------------
hdr "4. Secure Boot imzası"
if [[ ! -r "${CERT}" ]]; then
    bad "sertifika okunamadı: ${CERT}"
elif ! command -v sbverify >/dev/null 2>&1; then
    info "sbverify yok — imza kontrolü atlandı (sbsigntools kurun)"
else
    if sbverify --cert "${CERT}" "${GRUB}" >/dev/null 2>&1; then
        ok "grubx64.efi $(basename "${CERT}") ile imzalı"
    else
        bad "grubx64.efi imzasız veya imza sertifikayla eşleşmiyor — Secure Boot açıkken açılmaz"
    fi
fi

# --- 5. Gömülü cmdline ---------------------------------------------------
hdr "5. Gömülü kernel cmdline"
if [[ -s "${GRUB}" ]]; then
    cmd="$(sec "${GRUB}" .cmdline | tr -d '\0')"
    if [[ -z "${cmd}" ]]; then
        bad "cmdline boş — çekirdek canlı ortamı bulamaz"
    else
        info "${cmd}"
        idir="$(grep -oP '(?<=^install_dir=")[^"]+' "${PROFILE_DIR}/profiledef.sh" 2>/dev/null || echo maze)"
        grep -q "archisobasedir=${idir}" <<<"${cmd}" \
            && ok "archisobasedir=${idir} — profiledef ile uyumlu" \
            || bad "archisobasedir profiledef'teki install_dir='${idir}' ile uyuşmuyor"
        grep -q "archisosearchuuid=" <<<"${cmd}" \
            && ok "archisosearchuuid gömülü (medyum bulunabilir)" \
            || bad "archisosearchuuid yok — canlı medyum bulunamaz"
        [[ "$(printf '%s' "${cmd}" | wc -l)" -eq 0 ]] \
            && ok "cmdline tek satır" || bad "cmdline birden fazla satır"
    fi
fi

# --- 6. Gömülü çekirdek sürümü ------------------------------------------
hdr "6. Gömülü çekirdek"
if [[ -s "${GRUB}" ]]; then
    kver="$(sec "${GRUB}" .uname | tr -d '\0' | tr -d '[:space:]')"
    if [[ -n "${kver}" ]]; then ok "çekirdek ${kver}"
    else info "(.uname bölümü yok — ukify sürümüne göre normal olabilir)"; fi
fi

# --- 7. systemd-boot artığı kalmamış olmalı -----------------------------
hdr "7. Artık dosyalar"
if (( ISO_MODE )); then
    if bsdtar tf "${TARGET}" 2>/dev/null | grep -qi '^EFI/systemd/'; then
        bad "ESP'de EFI/systemd/ duruyor — _maze_sb_sign_esp systemd-boot'u silmemiş"
    else
        ok "systemd-boot ESP'den kaldırılmış"
    fi
else
    [[ -d "${ESP}/EFI/systemd" ]] \
        && bad "ESP'de EFI/systemd/ duruyor — systemd-boot silinmemiş" \
        || ok "systemd-boot ESP'den kaldırılmış"
fi

# --- Sonuç ---------------------------------------------------------------
echo
if (( FAIL == 0 )); then
    printf '\033[1;32m  ISO boot zinciri DOĞRULANDI.\033[0m\n'
    printf '  Not: bu kontrol ISO'"'"'nun ESP düzenini doğrular, kurulumun\n'
    printf '  doğruluğunu değil. Kurulum testi için VM denemesi gerekir.\n'
    exit 0
else
    printf '\033[1;31m  DOĞRULAMA BAŞARISIZ — bu ISO yayınlanmamalı.\033[0m\n'
    exit 1
fi
