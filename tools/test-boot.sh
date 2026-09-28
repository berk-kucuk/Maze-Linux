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
# Ekran açıldı diye sistem sağlıklı değildir. Bu yüzden VM'e QEMU misafir
# ajanı portu da takılır (canlı ISO ajanı kendiliğinden başlatır) ve içeriden
# kontrol edilir: sistem "running" durumuna geliyor mu, başarısız birim var mı,
# canlı çekirdek satırı doğru mu, giriş ekranı ayakta mı, canlı ortam TPM'e
# yazmadı mı. Ajan cevap vermezse (eski ISO) yalnızca ekran testi yapılır.
#
# Sanal TPM: swtpm kuruluysa VM'e bir TPM 2.0 takılır (gerçek dizüstüler gibi).
# TPM'e bağlı sorunlar (systemd-tpm2-setup, NvPCR) ancak böyle görünür.
#
# Kullanım:
#     tools/test-boot.sh out/mazelinux-*.iso
#     tools/test-boot.sh --timeout 180 --keep-shots /tmp/shots out/*.iso
#     tools/test-boot.sh --secboot out/*.iso      # Secure Boot GERCEKTEN acik
#     tools/test-boot.sh --no-tpm out/*.iso       # sanal TPM takma
#     tools/test-boot.sh --no-checks out/*.iso    # sadece ekran testi
#     tools/test-boot.sh --no-net out/*.iso       # VM'e ag verme
#
# --secboot: OVMF_VARS'a Microsoft anahtarlari (KEK/db) + Maze.crt (db) yazilir
# ve firmware SMM ile calistirilir; boylece Secure Boot zorlanir: shim'in
# Microsoft imzasi ve UKI'nin Maze imzasi firmware/shim tarafindan dogrulanir.
# (Anahtarsiz OVMF_VARS "setup mode"dadir ve Secure Boot'u HIC uygulamaz.)
# Gerekli: virt-fw-vars (virt-firmware paketi).
#
# --tpm / --no-tpm: sanal TPM (swtpm). Varsayılan: swtpm kuruluysa takılır.
#
set -uo pipefail

PROFILE_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
TARGET=""; TIMEOUT=150; MEM=4096; INTERVAL=15; SHOTDIR=""; SECBOOT=0
TPM="auto"; CHECKS=1; NET=1
CERT="${PROFILE_DIR}/keys/secureboot/Maze.crt"
# db girdisinin sahibi (owner) GUID'i — herhangi sabit bir GUID olabilir.
MAZE_OWNER_GUID="6b2d9c1e-4f3a-4d8b-9a7e-2c5f1e8d3b40"
TMP=""; QEMU_PID=""; SWTPM_PID=""; SCREEN_PID=""

ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[1;31m✗\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$*"; }

cleanup() {
    [[ -n "${QEMU_PID}" ]] && kill "${QEMU_PID}" 2>/dev/null
    [[ -n "${QEMU_PID}" ]] && wait "${QEMU_PID}" 2>/dev/null
    [[ -n "${SCREEN_PID}" ]] && kill "${SCREEN_PID}" 2>/dev/null
    [[ -n "${SWTPM_PID}" ]] && kill "${SWTPM_PID}" 2>/dev/null
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
        --tpm)        TPM="yes"; shift ;;
        --no-tpm)     TPM="no"; shift ;;
        --no-checks)  CHECKS=0; shift ;;
        --no-net)     NET=0; shift ;;
        --cert)       CERT="$2"; shift 2 ;;
        -h|--help)    sed -n '2,39p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
if (( SECBOOT )); then
    command -v virt-fw-vars >/dev/null 2>&1 || {
        echo "--secboot icin virt-fw-vars gerekli (virt-firmware paketi)." >&2
        echo "Anahtarsiz OVMF_VARS ile Secure Boot uygulanmaz; test anlamsiz olurdu." >&2
        exit 2
    }
    [[ -r "${CERT}" ]] || { echo "sertifika okunamadi: ${CERT}" >&2; exit 2; }
fi

TMP="$(mktemp -d)"
if (( SECBOOT )); then
    # Microsoft KEK/db (shim'i dogrulamak icin) + Maze.crt db'de (shim, UKI'yi
    # db'ye karsi da dogrular — MokManager ekrani cikmadan zincir test edilir).
    if ! virt-fw-vars --input "${VARS}" --output "${TMP}/vars.fd" \
            --enroll-redhat --secure-boot \
            --add-db "${MAZE_OWNER_GUID}" "${CERT}" >"${TMP}/vars.log" 2>&1; then
        echo "OVMF_VARS hazirlanamadi:" >&2; sed 's/^/  /' "${TMP}/vars.log" >&2; exit 2
    fi
else
    cp "${VARS}" "${TMP}/vars.fd"      # NVRAM yazilabilir bir kopya olmali
fi
[[ -n "${SHOTDIR}" ]] && mkdir -p "${SHOTDIR}"
QGA="${PROFILE_DIR}/tools/qga.py"

# --- Sanal TPM -------------------------------------------------------------
if [[ "${TPM}" == "auto" ]]; then
    command -v swtpm >/dev/null 2>&1 && TPM="yes" || TPM="no"
fi
if [[ "${TPM}" == "yes" ]]; then
    command -v swtpm >/dev/null 2>&1 || { echo "--tpm icin swtpm gerekli (sudo pacman -S swtpm)" >&2; exit 2; }
    mkdir -p "${TMP}/tpm"
    swtpm socket --tpm2 --tpmstate "dir=${TMP}/tpm" \
        --ctrl "type=unixio,path=${TMP}/swtpm.sock" --flags startup-clear \
        >"${TMP}/swtpm.log" 2>&1 &
    SWTPM_PID=$!
    for _ in $(seq 1 20); do [[ -S "${TMP}/swtpm.sock" ]] && break; sleep 0.25; done
    [[ -S "${TMP}/swtpm.sock" ]] || { echo "swtpm baslamadi:" >&2; sed 's/^/  /' "${TMP}/swtpm.log" >&2; exit 2; }
fi

hdr "Boot testi"
info "hedef    : ${TARGET} ($(du -h "${TARGET}" | cut -f1))"
info "firmware : $(basename "${CODE}")$( ((SECBOOT)) && echo '  [Secure Boot]' )"
info "sure     : ${TIMEOUT}s, ${INTERVAL}s araliklarla ekran olcumu"
info "tpm      : $([[ "${TPM}" == yes ]] && echo "sanal TPM 2.0 (swtpm)" || echo "yok (swtpm kurulu degil ya da --no-tpm)")"
info "kontrol  : $( ((CHECKS)) && echo "misafir ajani ile VM icinden" || echo "kapali (--no-checks)")"

# --- QEMU'yu baslat ------------------------------------------------------
MACHINE="q35"
(( SECBOOT )) && MACHINE="q35,smm=on"   # secboot OVMF, SMM olmadan calismaz
QEMU_ARGS=(
    -machine "${MACHINE}"
    -m "${MEM}"
    -smp 2
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=${CODE}"
    -drive "if=pflash,format=raw,unit=1,file=${TMP}/vars.fd"
    -display none
    -qmp "unix:${TMP}/qmp.sock,server,nowait"
    -no-reboot
    # QEMU misafir ajanı portu: canlı ISO ve kurulu sistem ajanı udev ile
    # kendiliğinden başlatır; kontroller bu soket üzerinden yapılır.
    -chardev "socket,path=${TMP}/qga.sock,server=on,wait=off,id=qga0"
    -device virtio-serial
    -device "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"
)
# Ağ: QEMU user-mode NAT — VM dışarı çıkabilir (NTP, ayna), dışarıdan VM'e
# hiçbir şey ulaşamaz. Gerçek bir kurulum ortamı gibi; ağsız canlı ortamda saat
# eşitlemesi hiç bitmediği için sistem "starting"te kalır.
if (( NET )); then
    QEMU_ARGS+=(-nic "user,model=virtio-net-pci")
else
    QEMU_ARGS+=(-net none)
fi
[[ "${TPM}" == "yes" ]] && QEMU_ARGS+=(
    -chardev "socket,id=chrtpm,path=${TMP}/swtpm.sock"
    -tpmdev "emulator,id=tpm0,chardev=chrtpm"
    -device "tpm-crb,tpmdev=tpm0"
)
# SMM'nin NVRAM'i gercekten korumasi (Secure Boot degiskenleri isletim
# sisteminden degistirilemesin) icin pflash "secure" olmali.
(( SECBOOT )) && QEMU_ARGS+=(-global "driver=cfi.pflash01,property=secure,value=on")
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
python3 - "${TMP}/qmp.sock" "${TIMEOUT}" "${INTERVAL}" "${TMP}" "${SHOTDIR}" >"${TMP}/screen.out" 2>&1 <<'PYQMP' &
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
SCREEN_PID=$!

# --- Misafir ajanı ile VM içinden kontroller --------------------------------
# Ekran ölçümü arka planda sürerken çalışır. Sonuç satırları: durum|mesaj.
CHK_FAIL=0
CHK_LINES=()
chk() { CHK_LINES+=("$1|$2"); [[ "$1" == bad ]] && CHK_FAIL=1; return 0; }
g() { python3 "${QGA}" "${TMP}/qga.sock" exec --timeout "${2:-30}" -- "$1"; }
if (( CHECKS )); then
    if python3 "${QGA}" "${TMP}/qga.sock" wait "$(( TIMEOUT > 30 ? TIMEOUT - 20 : TIMEOUT ))"; then
        # --wait blocks until boot finishes; bounded so a stuck job still yields
        # the CURRENT state ("starting") instead of no answer at all.
        state="$(g "timeout 150 systemctl is-system-running --wait >/dev/null 2>&1; systemctl is-system-running 2>/dev/null || true" 170 | tr -d '[:space:]')"
        failed="$(g "systemctl --failed --no-legend --plain | awk '{print \$1}'" | tr '\n' ' ')"
        case "${state}" in
            running)  chk ok "sistem durumu: running" ;;
            degraded) chk bad "sistem durumu: degraded — basarisiz birimler: ${failed}" ;;
            starting)
                if (( NET )); then
                    chk bad "sistem 2 dakikada acilisi bitiremedi (starting) — bekleyen isler: $(g "systemctl list-jobs --no-legend | awk '{print \$2}'" | tr '\n' ' ')"
                else
                    chk info "sistem 'starting' — agsiz VM'de saat esitlemesi bitmez (--no-net), beklenen"
                fi ;;
            *)        chk bad "sistem durumu: '${state:-yanitsiz}' (running bekleniyordu) ${failed:+— basarisiz: ${failed}}" ;;
        esac
        [[ -z "${failed// /}" ]] && chk ok "basarisiz systemd birimi yok"
        cmd="$(g "cat /proc/cmdline")"
        if grep -q "archisobasedir=" <<<"${cmd}"; then
            # Canlı ortam
            for p in copytoram=n systemd.tpm2_measured_os=0; do
                grep -qw -- "${p}" <<<"${cmd}" && chk ok "canli cmdline: ${p}" || chk bad "canli cmdline'da ${p} yok"
            done
            if [[ "${TPM}" == "yes" ]]; then
                g "test -e /dev/tpmrm0" >/dev/null && chk ok "TPM VM'de gorunuyor (/dev/tpmrm0)" || chk bad "TPM takildi ama VM'de /dev/tpmrm0 yok"
                g "test ! -e /run/systemd/tpm2-srk-public-key.pem" >/dev/null \
                    && chk ok "canli ortam TPM'e yazmadi (SRK kurulumu calismadi)" \
                    || chk bad "canli ortam TPM'de SRK kurdu — tpm2_measured_os=0 etkisiz"
            fi
            g "test -x /usr/bin/calamares" >/dev/null && chk ok "kurulum programi (calamares) mevcut" || chk bad "calamares yok"
        fi
        # NetworkManager is Maze's one network manager. systemd's preset turns
        # systemd-networkd on at first boot (every live boot); with a wired VM
        # NIC both then "work", so check the enablement itself — on Wi-Fi the
        # duplicate held network-online.target for 2 minutes.
        nd="$(g "systemctl is-enabled systemd-networkd.service 2>/dev/null || true" | tr -d '[:space:]')"
        [[ "${nd}" == enabled ]] && chk bad "systemd-networkd de acik — NetworkManager ile ayni arayuzleri yonetiyor" \
                                 || chk ok "tek ag yoneticisi: NetworkManager (systemd-networkd ${nd:-yok})"
        g "systemctl is-active --quiet display-manager" >/dev/null && chk ok "giris ekrani (display-manager) calisiyor" || chk bad "display-manager calismiyor"
        if (( SECBOOT )); then
            g "mokutil --sb-state 2>/dev/null" | grep -qi "enabled" && chk ok "VM icinde Secure Boot acik" || chk bad "VM icinde Secure Boot acik gorunmuyor"
        fi
    else
        chk info "misafir ajani cevap vermedi — VM ici kontroller atlandi (eski ISO ya da sifre ekraninda bekleyen kurulu disk)"
    fi
fi

wait "${SCREEN_PID}" 2>/dev/null
SCREEN_PID=""
RESULT="$(cat "${TMP}/screen.out")"

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

if (( CHECKS )); then
    hdr "VM içi kontroller"
    for l in "${CHK_LINES[@]}"; do
        case "${l%%|*}" in
            ok)   ok "${l#*|}" ;;
            bad)  bad "${l#*|}" ;;
            *)    info "${l#*|}" ;;
        esac
    done
    (( CHK_FAIL )) && rc=1
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
