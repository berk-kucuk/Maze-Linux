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
#   boot       boot the installed disk (no ISO). With virt-fw-vars installed
#              (virt-firmware package) the NVRAM gets the Microsoft keys and
#              Secure Boot is ENFORCED, so the first boot shows MokManager:
#              Enroll key from disk -> MOK.cer -> Continue -> Yes -> reboot,
#              exactly as a real machine would. Without it the firmware stays in
#              setup mode and Secure Boot is NOT enforced (a warning says so).
#   audit      while the installed VM is running ('boot'), run maze-audit --deep
#              inside it through the QEMU guest agent and save the report to
#              ${MAZE_VM_DIR}/audit-<time>.txt — no network, no copy/paste.
#   check      same channel, quick: system state + failed units.
#   serve      serve ./tools over HTTP on the host's loopback (PUT uploads
#              accepted, 100 MiB max) so the VM can send its report back:
#              curl -T /tmp/audit.txt http://10.0.2.2:8642/ — QEMU user-mode
#              networking maps 10.0.2.2 to the host's 127.0.0.1, so nothing is
#              exposed to the LAN.
#              (maze-audit itself ships in maze-tools since 1.1.0-37, nothing to fetch)
#   reset      delete the disk and vars to start over.
#
# Usage:
#   tools/vm-install-test.sh install [ISO]      (default ISO: newest in out/)
#   tools/vm-install-test.sh boot
#   tools/vm-install-test.sh audit              (while 'boot' is running)
#   tools/vm-install-test.sh check
#   tools/vm-install-test.sh serve
#   tools/vm-install-test.sh reset
#
# State lives in ${MAZE_VM_DIR:-/var/tmp/maze-vm}. No root needed (KVM group).
#
# TPM: with swtpm installed (sudo pacman -S swtpm) the VM gets a TPM 2.0 whose
# state persists in ${MAZE_VM_DIR}/tpm across install and boots — like a real
# laptop. TPM-dependent problems (systemd-tpm2-setup, NvPCRs) only show up then.

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
TPMDIR="${VMDIR}/tpm"
QGA_SOCK="${VMDIR}/qga.sock"

die() { echo "vm-install-test: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing: $1"; }

# Start swtpm for this VM (if installed). --terminate: it exits when QEMU closes
# the connection, so nothing is left running after the VM powers off.
start_tpm() {
    if ! command -v swtpm >/dev/null 2>&1; then
        echo ">> NOTE: swtpm not installed — the VM has NO TPM (sudo pacman -S swtpm to add one)." >&2
        return 1
    fi
    mkdir -p "${TPMDIR}"
    rm -f "${VMDIR}/swtpm.sock"
    swtpm socket --tpm2 --tpmstate "dir=${TPMDIR}" \
        --ctrl "type=unixio,path=${VMDIR}/swtpm.sock" --terminate --daemon \
        --log "file=${VMDIR}/swtpm.log" || die "swtpm failed to start (see ${VMDIR}/swtpm.log)"
    for _ in $(seq 1 20); do [[ -S "${VMDIR}/swtpm.sock" ]] && return 0; sleep 0.25; done
    die "swtpm socket did not appear"
}
tpm_args() {
    [[ -S "${VMDIR}/swtpm.sock" ]] || return 0
    echo -chardev socket,id=chrtpm,path="${VMDIR}/swtpm.sock" \
         -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-crb,tpmdev=tpm0
}

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
         -global driver=cfi.pflash01,property=secure,value=on \
         -chardev socket,path="${QGA_SOCK}",server=on,wait=off,id=qga0 \
         -device virtio-serial -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0
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
        # Microsoft KEK/db + SecureBoot=1, so shim is verified by the firmware
        # and the MokManager enrollment path is exercised for real. Maze.cer is
        # deliberately NOT put in db: enrolling it is part of what is tested.
        if command -v virt-fw-vars >/dev/null 2>&1; then
            virt-fw-vars --input "${VARS_SRC}" --output "${VARS}" --enroll-redhat --secure-boot >/dev/null \
                || die "virt-fw-vars could not prepare ${VARS}"
            echo ">> nvram : Microsoft keys enrolled — Secure Boot ENFORCED"
        else
            cp -f "${VARS_SRC}" "${VARS}"
            echo ">> WARNING: virt-fw-vars (virt-firmware) not found — the firmware stays in setup mode," >&2
            echo ">>          Secure Boot is NOT enforced and the MOK enrollment path is NOT tested." >&2
        fi
        echo ">> ISO   : ${ISO}"
        echo ">> disk  : ${DISK} (40 GiB, fresh)"
        echo ">> fw    : ${CODE}"
        echo ">> In the VM: the live desktop boots (MokManager first: Enroll key from disk -> MOK.cer)."
        echo ">>   Click 'Install Maze Linux' (first dock icon), choose Erase disk + LUKS,"
        echo ">>   create a user, finish, then shut the VM down. Then: $0 boot"
        start_tpm && echo ">> tpm   : TPM 2.0 (swtpm), state in ${TPMDIR}" || true
        exec qemu-system-x86_64 $(qemu_common) $(tpm_args) \
             -drive file="${ISO}",media=cdrom,readonly=on \
             -boot order=d,menu=on -name "Maze install test"
        ;;
    boot)
        need qemu-system-x86_64
        [[ -f "${DISK}" && -f "${VARS}" ]] || die "no VM yet — run: $0 install"
        echo ">> booting the installed disk (Secure Boot firmware). First boot: MokManager -> Enroll key from disk -> MOK.cer."
        echo ">> Once logged in, from another host terminal:  $0 audit   (full report)  or  $0 check"
        start_tpm && echo ">> tpm   : TPM 2.0 (swtpm), state in ${TPMDIR}" || true
        exec qemu-system-x86_64 $(qemu_common) $(tpm_args) -boot order=c,menu=on -name "Maze installed"
        ;;
    serve)
        need python3
        cd "${HERE}"
        echo ">> serving ${HERE} on http://127.0.0.1:${PORT} (VM reaches it as 10.0.2.2); PUT uploads land in ${VMDIR}/uploads"
        mkdir -p "${VMDIR}/uploads"
        exec python3 - "${PORT}" "${VMDIR}/uploads" <<'PY'
import http.server, sys, os, socketserver
port, updir = int(sys.argv[1]), sys.argv[2]
MAX_UPLOAD = 100 * 1024 * 1024
class H(http.server.SimpleHTTPRequestHandler):
    def do_PUT(self):
        try:
            n = int(self.headers.get('Content-Length', ''))
        except ValueError:
            self.send_error(411, "Content-Length required"); return
        if n < 0 or n > MAX_UPLOAD:
            self.send_error(413, f"upload limit is {MAX_UPLOAD} bytes"); return
        name = os.path.basename(self.path) or 'upload'
        with open(os.path.join(updir, name), 'wb') as f: f.write(self.rfile.read(n))
        self.send_response(201); self.end_headers()
        print(f">> received {name} -> {updir}/{name}", flush=True)
socketserver.TCPServer.allow_reuse_address = True
# Loopback only: QEMU's user-mode network delivers the guest's 10.0.2.2 here.
with socketserver.TCPServer(("127.0.0.1", port), H) as s: s.serve_forever()
PY
        ;;
    audit|check)
        need python3
        [[ -S "${QGA_SOCK}" ]] || die "no running VM (start it with: $0 boot)"
        python3 "${HERE}/qga.py" "${QGA_SOCK}" wait 30 \
            || die "the guest agent does not answer — is the installed system booted past the LUKS prompt?"
        if [[ "$1" == check ]]; then
            python3 "${HERE}/qga.py" "${QGA_SOCK}" exec --timeout 60 -- \
                "echo \"state: \$(systemctl is-system-running)\"; echo failed units:; systemctl --failed --no-legend --plain; echo; echo install summary:; cat /var/log/maze-install-summary.txt 2>/dev/null | tail -n 5"
            exit $?
        fi
        out="${VMDIR}/audit-$(date +%Y%m%d-%H%M%S).txt"
        echo ">> running maze-audit --deep inside the VM (a few minutes)…"
        python3 "${HERE}/qga.py" "${QGA_SOCK}" exec --timeout 900 -- \
            "maze-audit --deep --no-color 2>&1" > "${out}"
        rc=$?
        tail -n 25 "${out}"
        echo ">> full report: ${out}"
        exit "${rc}"
        ;;
    reset)
        rm -f "${DISK}" "${VARS}"; rm -rf "${TPMDIR}"
        echo ">> removed ${DISK}, ${VARS} and the VM's TPM state"
        ;;
    *)
        sed -n '2,47p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
