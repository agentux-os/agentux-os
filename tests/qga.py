#!/usr/bin/env python3
"""Talks to a QEMU VM's guest agent (qemu-ga) or monitor (QMP) over their
Unix sockets; used by tests/live-vm.sh.

  qga.py ping QGA_SOCK                    exit 0 if the guest agent answers
  qga.py exec QGA_SOCK TIMEOUT SCRIPT     run SCRIPT with bash as root in the
                                          guest; prints its output and exits
                                          with its status (124 on timeout)
  qga.py qmp QMP_SOCK JSON                one QMP command
"""
import base64
import json
import random
import socket
import sys
import time


def connect(path, timeout=10):
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(timeout)
    s.connect(path)
    return s


class Agent:
    def __init__(self, path):
        self.sock = connect(path)
        self.buf = b""
        # Drop whatever an earlier client left unread: guest-sync answers
        # with our id, and everything before that answer is stale.
        sync_id = random.randrange(1, 2**31)
        self.send({"execute": "guest-sync", "arguments": {"id": sync_id}})
        while True:
            reply = self.recv()
            if reply.get("return") == sync_id:
                break

    def send(self, cmd):
        self.sock.sendall(json.dumps(cmd).encode() + b"\n")

    def recv(self):
        while b"\n" not in self.buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("guest agent closed the connection")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        line = line.strip().lstrip(b"\xff")
        if not line:
            return self.recv()
        return json.loads(line)

    def call(self, name, **arguments):
        cmd = {"execute": name}
        if arguments:
            cmd["arguments"] = arguments
        self.send(cmd)
        reply = self.recv()
        if "error" in reply:
            raise RuntimeError(f"{name}: {reply['error'].get('desc', reply['error'])}")
        return reply.get("return")


def ping(path):
    try:
        Agent(path).call("guest-ping")
    except (OSError, ConnectionError, RuntimeError, ValueError):
        return 1
    return 0


def run(path, timeout, script):
    agent = Agent(path)
    env = ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin", "LANG=C.UTF-8", "HOME=/root"]
    pid = agent.call("guest-exec", path="/usr/bin/bash", arg=["-c", script],
                     env=env, **{"capture-output": True})["pid"]
    deadline = time.monotonic() + timeout
    while True:
        status = agent.call("guest-exec-status", pid=pid)
        if status.get("exited"):
            break
        if time.monotonic() > deadline:
            agent.call("guest-exec", path="/usr/bin/kill", arg=["-KILL", str(pid)])
            print(f"qga: timed out after {timeout}s", file=sys.stderr)
            return 124
        time.sleep(1)
    for key, stream in (("out-data", sys.stdout), ("err-data", sys.stderr)):
        if key in status:
            stream.write(base64.b64decode(status[key]).decode(errors="replace"))
            stream.flush()
    if status.get("out-truncated") or status.get("err-truncated"):
        print("qga: output truncated", file=sys.stderr)
    if "signal" in status:
        return 128 + status["signal"]
    return status.get("exitcode", 1)


def qmp(path, command):
    s = connect(path)
    f = s.makefile("rw")
    json.loads(f.readline())
    for cmd in ({"execute": "qmp_capabilities"}, json.loads(command)):
        f.write(json.dumps(cmd) + "\n")
        f.flush()
        while True:
            reply = json.loads(f.readline())
            if "event" in reply:
                continue
            if "error" in reply:
                print(reply["error"].get("desc", "QMP error"), file=sys.stderr)
                return 1
            break
    return 0


def main(argv):
    if len(argv) == 3 and argv[1] == "ping":
        return ping(argv[2])
    if len(argv) == 5 and argv[1] == "exec":
        return run(argv[2], int(argv[3]), argv[4])
    if len(argv) == 4 and argv[1] == "qmp":
        return qmp(argv[2], argv[3])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
