#!/usr/bin/env bash
#
# test-boot.sh — Bir ISO'yu (veya kurulmuş disk imajını) QEMU/OVMF içinde
# gerçekten boot edip açıldığını kanıtlar. Root GEREKTİRMEZ, hiçbir şeyi
# değiştirmez, headless çalışır, CI'a uygundur.
#
# Neden var: verify-iso.sh ESP düzeninin DOĞRU KURULDUĞUNU doğrular — ama
# firmware'in o zinciri gerçekten yürütebildiğini değil. shim'in UKI'yi
# chainload edememesi, UKI'nin firmware tarafından reddedilmesi ya da
# initramfs'in root'u bulamaması ancak gerçek bir boot denemesiyle görülür.
#
# Nasıl ölçer: QEMU'yu ekransız başlatır, QMP üzerinden düzenli aralıklarla
# ekran görüntüsü alır ve karesel içeriği ölçer. Boot edemeyen bir imaj
# siyah ekranda (ya da UEFI shell'de) kalır; açılan bir imaj Plymouth
# splash'ı ve ardından giriş ekranını çizer.
#
# Kullanım:
#     tools/test-boot.sh out/mazelinux-*.iso
#     tools/test-boot.sh --timeout 180 --keep-shots /tmp/shots out/*.iso
#     tools/test-boot.sh --secboot out/*.iso      # OVMF secboot firmware ile
#
set -uo pipefail

TARGET=""; TIMEOUT=150; MEM=4096; INTERVAL=15; SHOTDIR=""; SECBOOT=0
TMP=""; QEMU_PID=""

ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[1;31m✗\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$*"; }

cleanup() {
    [[ -n "${QEMU_PID}" ]] && kill "${QEMU_PID}" 2>/dev/null
    [[ -n "${QEMU_PID}" ]] && wait "${QEMU_PID}" 2>/dev/null
    [[ -n "${TMP}" && -d "${TMP}" ]] && rm -rf "${TMP}"
    return 0
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout)    TIMEOUT="$2"; shift 2 ;;
        --memory)     MEM="$2";     shift 2 ;;
        --interval)   INTERVAL="$2"; shift 2 ;;
        --keep-shots) SHOTDIR="$2"; shift 2 ;;
        --secboot)    SECBOOT=1; shift ;;
        -h|--help)    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            TARGET="$1"; shift ;;
    esac
done
[[ -n "${TARGET}" && -e "${TARGET}" ]] || { echo "kullanim: $0 <iso|disk-imaji> [secenekler]" >&2; exit 2; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "qemu-system-x86_64 yok" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 yok (QMP icin gerekli)" >&2; exit 2; }

# --- OVMF firmware'ini bul ----------------------------------------------
CODE=""; VARS=""
if (( SECBOOT )); then
    for c in /usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd /usr/share/OVMF/OVMF_CODE.secboot.fd; do
        [[ -f "$c" ]] && { CODE="$c"; break; }
    done
else
    for c in /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd; do
        [[ -f "$c" ]] && { CODE="$c"; break; }
    done
fi
for v in /usr/share/edk2/x64/OVMF_VARS.4m.fd /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd; do
    [[ -f "$v" ]] && { VARS="$v"; break; }
done
[[ -n "${CODE}" && -n "${VARS}" ]] || { echo "OVMF bulunamadi (edk2-ovmf kurun)" >&2; exit 2; }

TMP="$(mktemp -d)"
cp "${VARS}" "${TMP}/vars.fd"          # NVRAM yazilabilir bir kopya olmali
[[ -n "${SHOTDIR}" ]] && mkdir -p "${SHOTDIR}"

hdr "Boot testi"
info "hedef    : ${TARGET} ($(du -h "${TARGET}" | cut -f1))"
info "firmware : $(basename "${CODE}")$( ((SECBOOT)) && echo '  [Secure Boot]' )"
info "sure     : ${TIMEOUT}s, ${INTERVAL}s araliklarla ekran olcumu"

# --- QEMU'yu baslat ------------------------------------------------------
QEMU_ARGS=(
    -machine q35
    -m "${MEM}"
    -smp 2
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=${CODE}"
    -drive "if=pflash,format=raw,unit=1,file=${TMP}/vars.fd"
    -display none
    -qmp "unix:${TMP}/qmp.sock,server,nowait"
    -no-reboot
    -net none
)
[[ -w /dev/kvm ]] && QEMU_ARGS+=(-enable-kvm -cpu host) || info "uyari: KVM yok, yazilim emulasyonu (yavas)"
# Ekran adaptoru: QEMU derlemeleri farkli setlerle geliyor (virtio her zaman
# yok). Desteklenen ilkini sec — ekran goruntusu icin hepsi yeterli.
VGA=""
for v in virtio std qxl vmware cirrus; do
    if qemu-system-x86_64 -vga help 2>&1 | grep -qw "$v"; then VGA="$v"; break; fi
done
[[ -n "${VGA}" ]] && QEMU_ARGS+=(-vga "${VGA}") || info "uyari: bilinen VGA yok, varsayilan kullanilacak"
info "vga      : ${VGA:-varsayilan}"
case "${TARGET}" in
    *.iso) QEMU_ARGS+=(-cdrom "${TARGET}" -boot d) ;;
    *)     QEMU_ARGS+=(-drive "file=${TARGET},format=raw,if=virtio") ;;
esac

qemu-system-x86_64 "${QEMU_ARGS[@]}" >"${TMP}/qemu.log" 2>&1 &
QEMU_PID=$!
sleep 3
if ! kill -0 "${QEMU_PID}" 2>/dev/null; then
    bad "QEMU hemen sonlandi:"; sed 's/^/      /' "${TMP}/qemu.log" >&2; exit 1
fi

# --- QMP ile ekran olcumu ------------------------------------------------
# PPM (P6) cozumlenip siyah olmayan piksel orani hesaplanir. Boot edemeyen
# imaj siyah kalir; acilan imaj splash/giris ekrani cizer.
RESULT="$(python3 - "${TMP}/qmp.sock" "${TIMEOUT}" "${INTERVAL}" "${TMP}" "${SHOTDIR}" <<'PYQMP'
import json, os, socket, sys, time

sock_path, timeout, interval, tmp, shotdir = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]

def connect(deadline):
    while time.time() < deadline:
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.connect(sock_path); return s
        except OSError:
            time.sleep(0.5)
    return None

deadline = time.time() + timeout
s = connect(time.time() + 20)
if s is None:
    print("ERR|QMP soketine baglanilamadi"); sys.exit(0)
f = s.makefile("rw", encoding="utf-8", newline="\n")
f.readline()                                   # greeting
f.write(json.dumps({"execute": "qmp_capabilities"}) + "\n"); f.flush(); f.readline()

def cmd(c, **args):
    f.write(json.dumps({"execute": c, "arguments": args} if args else {"execute": c}) + "\n")
    f.flush()
    while True:
        line = f.readline()
        if not line: return None
        m = json.loads(line)
        if "event" in m: continue
        return m

def ink(path):
    """PPM'de siyah olmayan piksel orani (%) ve ayirt edici renk sayisi."""
    with open(path, "rb") as fh: data = fh.read()
    if not data.startswith(b"P6"): return None
    # baslik: P6 <w> <h> <maxval>, aralarinda bosluk/yorum
    idx, fields = 2, []
    while len(fields) < 3:
        while idx < len(data) and data[idx:idx+1].isspace(): idx += 1
        if data[idx:idx+1] == b"#":
            while data[idx:idx+1] not in (b"\n", b""): idx += 1
            continue
        start = idx
        while idx < len(data) and not data[idx:idx+1].isspace(): idx += 1
        fields.append(int(data[start:idx]))
    idx += 1
    px = data[idx:]
    total = len(px) // 3
    if total == 0: return None
    lit, colors = 0, set()
    step = max(1, total // 20000)              # ornekleme: hizli ve yeterli
    n = 0
    for i in range(0, total, step):
        r, g, b = px[i*3], px[i*3+1], px[i*3+2]
        n += 1
        if r > 24 or g > 24 or b > 24:
            lit += 1; colors.add((r >> 4, g >> 4, b >> 4))
    return (100.0 * lit / n if n else 0.0), len(colors), fields[0], fields[1]

obs, best = [], 0.0
while time.time() < deadline:
    time.sleep(interval)
    shot = os.path.join(tmp, "shot.ppm")
    if os.path.exists(shot): os.remove(shot)
    r = cmd("screendump", filename=shot)
    if r is None or "error" in (r or {}):
        obs.append("?|QMP screendump basarisiz"); break
    for _ in range(20):
        if os.path.exists(shot) and os.path.getsize(shot) > 0: break
        time.sleep(0.25)
    m = ink(shot) if os.path.exists(shot) else None
    el = int(time.time() - (deadline - timeout))
    if m is None:
        obs.append(f"{el}s|okunamadi")
    else:
        pct, ncol, w, h = m
        best = max(best, pct)
        obs.append(f"{el}s|{w}x{h} dolu:%{pct:.1f} renk:{ncol}")
        if shotdir:
            os.replace(shot, os.path.join(shotdir, f"shot-{el:04d}s.ppm"))
st = cmd("query-status") or {}
running = st.get("return", {}).get("running", False)
print("OBS|" + ";".join(obs))
print(f"BEST|{best:.1f}")
print(f"RUNNING|{running}")
PYQMP
)"

# --- Sonuç ---------------------------------------------------------------
hdr "Gözlemler"
best=0; running="False"
while IFS='|' read -r tag rest; do
    case "${tag}" in
        OBS)  IFS=';' read -ra items <<< "${rest}"; for i in "${items[@]}"; do info "${i//|/  }"; done ;;
        BEST) best="${rest}" ;;
        RUNNING) running="${rest}" ;;
        ERR)  bad "${rest}" ;;
    esac
done <<< "${RESULT}"

hdr "Sonuç"
rc=0
if [[ "${running}" == "True" ]]; then ok "VM sure boyunca calisir durumda kaldi (panik/kapanma yok)"
else bad "VM calismiyor — cekirdek panigi veya erken kapanma"; rc=1; fi

# %2 esigi: OVMF'in kendi acilis ekrani bile bunun altinda kalir; Plymouth
# splash ve giris ekrani belirgin sekilde ustundedir.
if awk "BEGIN{exit !(${best} > 2.0)}"; then
    ok "ekrana anlamli icerik cizildi (en yuksek dolu oran %${best})"
else
    bad "ekran bos kaldi (en yuksek dolu oran %${best}) — boot zinciri yurumedi"
    info "shim UKI'yi chainload edemiyor olabilir; verify-iso.sh ile ESP duzenini kontrol edin"
    rc=1
fi

echo
if (( rc == 0 )); then
    printf '\033[1;32m  BOOT TESTI GECTI.\033[0m\n'
    printf '  Not: bu test imajin ACILDIGINI gosterir; kurulumun dogrulugunu degil.\n'
else
    printf '\033[1;31m  BOOT TESTI BASARISIZ.\033[0m\n'
fi
[[ -n "${SHOTDIR}" ]] && info "ekran goruntuleri: ${SHOTDIR}"
exit "${rc}"
