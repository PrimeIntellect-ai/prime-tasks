#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import os
import re
import socket
import subprocess
import time

WAV = "/app/sequence_signal.wav"
HOST = "127.0.0.1"
PORT = 9000


def derive_expected():
    assert os.path.isfile(WAV), f"Missing input audio file: {WAV}"
    proc = subprocess.run(
        ["multimon-ng", "-a", "DTMF", "-t", "wav", WAV],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=20,
    )
    assert proc.returncode == 0, f"multimon-ng failed:\n{proc.stdout}"
    tones = re.findall(r"DTMF:\s*([1234])", proc.stdout)
    assert len(tones) >= 2, f"Could not decode a DNA sequence from the WAV:\n{proc.stdout}"

    mapping = {"1": "A", "2": "C", "3": "G", "4": "T"}
    sequence = "".join(mapping[tone] for tone in tones)
    bases = "ACGT"
    counts = {a + b: 0 for a in bases for b in bases}
    for a, b in zip(sequence, sequence[1:]):
        counts[a + b] += 1
    return ",".join(f"{pair}:{counts[pair]}" for pair in sorted(counts))


def listening_socket_inodes():
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    local, state = fields[1], fields[3]
                    address, port_hex = local.rsplit(":", 1)
                    if int(port_hex, 16) != PORT or state != "0A":
                        continue
                    # Require the requested 127.0.0.1 binding, not a wildcard bind.
                    if table.endswith("tcp") and address != "0100007F":
                        continue
                    if table.endswith("tcp6") and address not in {
                        "0000000000000000FFFF00000100007F",
                        "0000000000000000000000000100007F",
                    }:
                        continue
                    found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def socket_owners(inodes):
    owners = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.append(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return owners


def proc_info(pid):
    exe = os.path.realpath(f"/proc/{pid}/exe")
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    with open(f"/proc/{pid}/status") as f:
        status = f.read()
    match = re.search(r"^PPid:\s*(\d+)", status, re.MULTILINE)
    return exe, cmdline, int(match.group(1)) if match else 0


def assert_standard_utility_server():
    deadline = time.time() + 3
    owners = []
    while time.time() < deadline:
        owners = socket_owners(listening_socket_inodes())
        if owners:
            break
        time.sleep(0.05)
    assert owners, f"No process is listening on {HOST}:{PORT}"

    trusted_listener_paths = {
        "/usr/bin/nc.openbsd",
        "/usr/bin/socat",
        "/usr/bin/ncat",
        "/bin/busybox",
        "/usr/bin/busybox",
    }
    forbidden = re.compile(r"(^|[ /])(python[0-9.]*|node|perl|ruby|php|java)([ /]|$)", re.I)

    for owner in owners:
        exe, cmdline, ppid = proc_info(owner)
        assert exe in trusted_listener_paths, (
            "The listening server must be implemented with Bash and standard networking "
            f"utilities; listener PID {owner} runs {exe!r} ({cmdline!r})"
        )
        assert not forbidden.search(cmdline), f"High-level language found in listener command: {cmdline}"

        # Check the implementation chain up to its shell. This rejects, for example,
        # a Python process supervising nc/socat while allowing a Bash nc/socat loop.
        pid = ppid
        for _ in range(8):
            if pid <= 1:
                break
            try:
                parent_exe, parent_cmd, pid = proc_info(pid)
            except (FileNotFoundError, ProcessLookupError):
                break
            assert not forbidden.search(parent_cmd), (
                f"High-level language found in server process chain: {parent_cmd}"
            )
            if os.path.basename(parent_exe) in {"bash", "sh", "dash"}:
                break


def request_once(expected):
    deadline = time.time() + 3
    last_error = None
    while time.time() < deadline:
        try:
            sock = socket.create_connection((HOST, PORT), timeout=1)
            break
        except OSError as exc:
            last_error = exc
            time.sleep(0.05)
    else:
        raise AssertionError(f"Could not connect to server: {last_error}")

    with sock:
        sock.settimeout(3)
        sock.sendall(
            b"GET / HTTP/1.1\r\nHost: 127.0.0.1:9000\r\nConnection: close\r\n\r\n"
        )
        chunks = []
        while True:
            try:
                chunk = sock.recv(65536)
            except socket.timeout:
                raise AssertionError("Server did not finish or properly frame its HTTP response")
            if not chunk:
                break
            chunks.append(chunk)

    response = b"".join(chunks)
    assert b"\r\n\r\n" in response, "Response lacks a valid HTTP header/body separator"
    headers, body = response.split(b"\r\n\r\n", 1)
    status_line = headers.split(b"\r\n", 1)[0]
    assert status_line == b"HTTP/1.1 200 OK", (
        f"Expected status line b'HTTP/1.1 200 OK', got {status_line!r}"
    )
    actual = body.decode("utf-8").strip()
    assert actual == expected, f"Incorrect response body. Expected {expected!r}, got {actual!r}"


expected_body = derive_expected()

# Re-check the implementation and make several separated requests. A one-shot
# responder will fail, while a normal Bash loop around nc/socat remains valid.
for delay in (0, 0.2, 0.4, 0.8, 1.2):
    if delay:
        time.sleep(delay)
    assert_standard_utility_server()
    request_once(expected_body)
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
