#!/usr/bin/env bash
#
# gen-sb-keys.sh — Generate the Maze Linux Secure Boot signing key used to sign
# the LIVE ISO's Unified Kernel Image (shim's second stage, grubx64.efi).
#
# This is the SHARED, distro-wide key. Its public certificate (Maze.cer) is what
# a user enrolls once via MokManager when booting the live ISO with UEFI Secure
# Boot enabled. Because the ISO ships pre-signed, the private key necessarily
# lives in the build tree — keep keys/secureboot/Maze.key out of public hands.
#
# The INSTALLED system does NOT use this key; the installer generates a fresh
# per-machine key at install time (see deploy-to-target.sh:setup_secure_boot).
#
# Run once (idempotent): existing keys are kept so every build stays consistent
# and users never have to re-enroll. Pass -f to force regeneration.
#
#     ./tools/gen-sb-keys.sh
#     ./tools/gen-sb-keys.sh -e   protect the EXISTING key with a passphrase
#                                 (same key, nobody re-enrolls; build.sh then
#                                 asks for it once per build). Losing the
#                                 passphrase means a new key and every user
#                                 re-enrolling — store it in a password manager.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYDIR="${ROOT}/keys/secureboot"
FORCE=0
ENCRYPT=0

while getopts ':feh' opt; do
    case "${opt}" in
        f) FORCE=1 ;;
        e) ENCRYPT=1 ;;
        h) sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "usage: $0 [-f | -e]" >&2; exit 1 ;;
    esac
done

command -v openssl >/dev/null 2>&1 || { echo "Error: openssl not found." >&2; exit 1; }

mkdir -p "${KEYDIR}"

KEY="${KEYDIR}/Maze.key"
CRT="${KEYDIR}/Maze.crt"
CER="${KEYDIR}/Maze.cer"

if [[ "${ENCRYPT}" -eq 1 ]]; then
    [[ -f "${KEY}" ]] || { echo "Error: ${KEY} does not exist." >&2; exit 1; }
    if grep -q 'ENCRYPTED' "${KEY}"; then
        echo ">> ${KEY} is already passphrase-protected"
        exit 0
    fi
    tmp="${KEY}.enc.$$"
    trap 'rm -f "${tmp}"' EXIT
    echo ">> Protecting ${KEY} with a passphrase (asked twice)"
    ( umask 077; openssl pkey -in "${KEY}" -aes256 -out "${tmp}" ) \
        || { echo "Error: encryption failed; ${KEY} is unchanged." >&2; exit 1; }
    # Prove the passphrase opens it AND that it is the same key, before the
    # plain copy is replaced: a typo here would otherwise cost the key.
    echo ">> Type the passphrase once more to confirm it opens the key"
    if [[ "$(openssl pkey -in "${tmp}" -pubout 2>/dev/null)" != "$(openssl pkey -in "${KEY}" -pubout 2>/dev/null)" ]]; then
        echo "Error: the protected copy did not open to the same key; ${KEY} is unchanged." >&2
        exit 1
    fi
    chmod 600 "${tmp}"
    mv -f "${tmp}" "${KEY}"
    echo ">> Done. ${KEY} is passphrase-protected; build.sh asks for it once per build."
    echo "   Other plain copies (old backups, e.g. maze-build-backup-*.tar.zst) are NOT touched."
    exit 0
fi

if [[ -f "${KEY}" && -f "${CRT}" && -f "${CER}" && "${FORCE}" -eq 0 ]]; then
    echo ">> Maze Secure Boot key already present in ${KEYDIR} (use -f to regenerate)"
    exit 0
fi

echo ">> Generating Maze Linux Secure Boot key in ${KEYDIR}"
openssl req -newkey rsa:2048 -nodes \
    -keyout "${KEY}" \
    -new -x509 -sha256 -days 3650 \
    -subj "/CN=Maze Linux Secure Boot/" \
    -out "${CRT}"

# DER form for MokManager "Enroll key from disk" and mokutil.
openssl x509 -outform DER -in "${CRT}" -out "${CER}"

chmod 600 "${KEY}"
chmod 644 "${CRT}" "${CER}"

echo ">> Done."
echo "   Private key : ${KEY}   (keep secret; signs the ISO's UKI)"
echo "   Certificate : ${CRT}"
echo "   Enroll cert : ${CER}   (shipped on the ISO ESP for MokManager)"
