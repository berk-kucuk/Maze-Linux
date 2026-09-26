#!/usr/bin/env python3
"""qga.py — run commands inside a QEMU VM through the QEMU guest agent.

The Maze live ISO and installed systems both start qemu-guest-agent on their
own whenever QEMU offers the agent's virtio port (the qemu-guest-agent package
ships a udev rule for that; nothing has to be enabled). test-boot.sh and
vm-install-test.sh attach the port as a UNIX socket, and this helper talks to it:

    qga.py SOCKET wait [SECONDS]            wait until the agent answers (exit 0),
                                            or give up after SECONDS (exit 1)
    qga.py SOCKET exec [--timeout N] -- CMD run CMD with /bin/sh -c in the guest,
                                            print its stdout (stderr to stderr) and
                                            exit with ITS exit code; 124 on timeout,
                                            125 when the agent is unreachable

Only the standard library; no root needed on the host.
"""
import base64
import json
import os
import socket
import sys
import time


class AgentError(Exception):
    pass


class Agent:
    def __init__(self, path, timeout=5.0):
        self.path = path
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(timeout)
        self.sock.connect(path)
        self.buf = b""
        self._sync()

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass

    def _send(self, obj):
        self.sock.sendall(json.dumps(obj).encode() + b"\n")

    def _read_msg(self):
        while b"\n" not in self.buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise AgentError("agent closed the connection")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        # guest-sync-delimited prefixes its reply with 0xFF; drop anything
        # before the JSON object.
        start = line.find(b"{")
        if start < 0:
            return None
        return json.loads(line[start:])

    def _sync(self):
        # A fresh connection may see a half-written reply left over from a
        # previous client; guest-sync-delimited flushes it and proves the agent
        # is really answering us.
        token = int(time.time() * 1000) & 0x7FFFFFFF
        self.sock.sendall(b"\xff")
        self._send({"execute": "guest-sync-delimited", "arguments": {"id": token}})
        deadline = time.time() + 10
        while time.time() < deadline:
            msg = self._read_msg()
            if msg and msg.get("return") == token:
                return
        raise AgentError("agent did not complete the sync handshake")

    def call(self, cmd, **args):
        req = {"execute": cmd}
        if args:
            req["arguments"] = args
        self._send(req)
        while True:
            msg = self._read_msg()
            if msg is None:
                continue
            if "error" in msg:
                raise AgentError(msg["error"].get("desc", str(msg["error"])))
            if "return" in msg:
                return msg["return"]

    def run(self, command, timeout):
        pid = self.call("guest-exec", path="/bin/sh", arg=["-c", command],
                        **{"capture-output": True})["pid"]
        deadline = time.time() + timeout
        while time.time() < deadline:
            st = self.call("guest-exec-status", pid=pid)
            if st.get("exited"):
                out = base64.b64decode(st.get("out-data", "")).decode(errors="replace")
                err = base64.b64decode(st.get("err-data", "")).decode(errors="replace")
                return st.get("exitcode", 0), out, err
            time.sleep(0.3)
        return None, "", ""


def wait(path, seconds):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if os.path.exists(path):
            try:
                a = Agent(path, timeout=3)
                a.call("guest-ping")
                a.close()
                return 0
            except (OSError, AgentError, ValueError):
                pass
        time.sleep(2)
    return 1


def main(argv):
    if len(argv) < 3 or argv[2] not in ("wait", "exec"):
        sys.stderr.write(__doc__)
        return 2
    path, mode = argv[1], argv[2]
    if mode == "wait":
        return wait(path, float(argv[3]) if len(argv) > 3 else 120)

    rest = argv[3:]
    timeout = 60.0
    if rest[:1] == ["--timeout"]:
        timeout = float(rest[1])
        rest = rest[2:]
    if rest[:1] == ["--"]:
        rest = rest[1:]
    if not rest:
        sys.stderr.write("qga.py exec: no command\n")
        return 2
    try:
        a = Agent(path, timeout=max(5.0, min(timeout, 30.0)))
        code, out, err = a.run(" ".join(rest), timeout)
        a.close()
    except (OSError, AgentError, ValueError) as e:
        sys.stderr.write(f"qga.py: guest agent unreachable: {e}\n")
        return 125
    sys.stdout.write(out)
    sys.stderr.write(err)
    return 124 if code is None else code


if __name__ == "__main__":
    sys.exit(main(sys.argv))
