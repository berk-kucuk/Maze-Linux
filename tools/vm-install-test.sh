#!/usr/bin/env bash
#
# vm-install-test.sh — install a Maze ISO into a QEMU/OVMF VM and audit it.
#
# test-boot.sh proves an ISO boots. This drives the step after that: a REAL
# Calamares install into a virtual disk, a reboot into the installed system,
# and maze-audit (shipped in maze-tools) run inside it. That is the loop
# MAZE-TAM-REFERANS.md §9.4 calls the single highest-value investment, and the
# eighth audit round confirmed why — every real bug came out of a real run.
#
# The install itself is interactive (Calamares is a GUI). This script only
# removes the friction around it:
#
#   install    create a fresh 40 GiB disk + OVMF vars, boot the ISO with a
#              display. You click through Calamares (LUKS + btrfs, a user),
#              then power the VM off.
#   boot       boot the installed disk (no ISO). Secure Boot is ON in the
#              firmware, so the first boot shows MokManager: Enroll key from
#              disk -> MOK.cer -> Continue -> Yes -> reboot, exactly as a real
#              machine would.
#   serve      serve ./tools over HTTP on the host (PUT uploads accepted) so the
#              VM can send its report back: curl -T /tmp/audit.txt http://10.0.2.2:8642/
#              (maze-audit itself ships in maze-tools since 1.1.0-37, nothing to fetch)
#   reset      delete the disk and vars to start over.
#
# Usage:
#   tools/vm-install-test.sh install [ISO]      (default ISO: newest in out/)
#   tools/vm-install-test.sh boot
#   tools/vm-install-test.sh serve
#   tools/vm-install-test.sh reset
#
# State lives in ${MAZE_VM_DIR:-/var/tmp/maze-vm}. No root needed (KVM group).

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="$(cd "${HERE}/.." && pwd)"
VMDIR="${MAZE_VM_DIR:-/var/tmp/maze-vm}"
DISK="${VMDIR}/maze-install.qcow2"
VARS="${VMDIR}/OVMF_VARS.4m.fd"
CODE=""
for c in /usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/OVMF/OVMF_CODE.secboot.fd; do
    [[ -f "$c" ]] && { CODE="$c"; break; }
done
VARS_SRC=""
for v in /usr/share/edk2/x64/OVMF_VARS.4m.fd /usr/share/OVMF/OVMF_VARS.fd; do
    [[ -f "$v" ]] && { VARS_SRC="$v"; break; }
done
MEM="${MAZE_VM_MEM:-6G}"
CPUS="${MAZE_VM_CPUS:-4}"
PORT=8642

die() { echo "vm-install-test: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing: $1"; }

qemu_common() {
    # -cpu host + KVM: the install compiles AUR packages and DKMS modules.
    # virtio disk/net, q35, the secboot OVMF: this is the strictest firmware
    # shape we can get without real hardware. SMM is what makes the secboot
    # build actually enforce Secure Boot.
    echo -machine q35,smm=on,accel=kvm -cpu host -smp "${CPUS}" -m "${MEM}" \
         -drive if=pflash,format=raw,readonly=on,file="${CODE}" \
         -drive if=pflash,format=raw,file="${VARS}" \
         -drive file="${DISK}",if=virtio,format=qcow2,discard=unmap \
         -device virtio-vga-gl -display gtk,gl=on \
         -device virtio-net-pci,netdev=n0 -netdev user,id=n0 \
         -device qemu-xhci -device usb-tablet \
         -audiodev pa,id=a0 -device intel-hda -device hda-output,audiodev=a0 \
         -rtc base=utc \
         -global driver=cfi.pflash01,property=secure,value=on
}

case "${1:-}" in
    install)
        need qemu-system-x86_64; need qemu-img
        [[ -n "${CODE}" && -n "${VARS_SRC}" ]] || die "OVMF firmware not found (install edk2-ovmf)"
        ISO="${2:-$(ls -t "${PROFILE}"/out/*.iso 2>/dev/null | head -1)}"
        [[ -f "${ISO}" ]] || die "no ISO given and none in ${PROFILE}/out"
        mkdir -p "${VMDIR}"
        if [[ -f "${DISK}" ]]; then
            echo "disk ${DISK} exists — run 'reset' first to start over, or 'boot' to boot it" >&2; exit 1
        fi
        qemu-img create -f qcow2 "${DISK}" 40G >/dev/null
        cp -f "${VARS_SRC}" "${VARS}"
        echo ">> ISO   : ${ISO}"
        echo ">> disk  : ${DISK} (40 GiB, fresh)"
        echo ">> fw    : ${CODE} (Secure Boot capable; enroll MOK.cer at first boot like real hardware)"
        echo ">> In the VM: the live desktop boots (MokManager first: Enroll key from disk -> MOK.cer)."
        echo ">>   Click 'Install Maze Linux' (first dock icon), choose Erase disk + LUKS,"
        echo ">>   create a user, finish, then shut the VM down. Then: $0 boot"
        exec qemu-system-x86_64 $(qemu_common) \
             -drive file="${ISO}",media=cdrom,readonly=on \
             -boot order=d,menu=on -name "Maze install test"
        ;;
    boot)
        need qemu-system-x86_64
        [[ -f "${DISK}" && -f "${VARS}" ]] || die "no VM yet — run: $0 install"
        echo ">> booting the installed disk (Secure Boot firmware). First boot: MokManager -> Enroll key from disk -> MOK.cer."
        echo ">> Inside the VM:  sudo maze-audit --deep --no-color --out /tmp/audit.txt"
        echo ">>   to get the report back:  $0 serve  (on the host), then in the VM:"
        echo ">>   curl -T /tmp/audit.txt http://10.0.2.2:${PORT}/"
        exec qemu-system-x86_64 $(qemu_common) -boot order=c,menu=on -name "Maze installed"
        ;;
    serve)
        need python3
        cd "${HERE}"
        echo ">> serving ${HERE} on http://0.0.0.0:${PORT} (VM reaches it as 10.0.2.2); PUT uploads land in ${VMDIR}/uploads"
        mkdir -p "${VMDIR}/uploads"
        exec python3 - "${PORT}" "${VMDIR}/uploads" <<'PY'
import http.server, sys, os, socketserver
port, updir = int(sys.argv[1]), sys.argv[2]
class H(http.server.SimpleHTTPRequestHandler):
    def do_PUT(self):
        n = int(self.headers.get('Content-Length', 0))
        name = os.path.basename(self.path) or 'upload'
        with open(os.path.join(updir, name), 'wb') as f: f.write(self.rfile.read(n))
        self.send_response(201); self.end_headers()
        print(f">> received {name} -> {updir}/{name}", flush=True)
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("0.0.0.0", port), H) as s: s.serve_forever()
PY
        ;;
    reset)
        rm -f "${DISK}" "${VARS}"; echo ">> removed ${DISK} and ${VARS}"
        ;;
    *)
        sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
