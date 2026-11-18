#!/bin/bash
set +e
mkdir -p /logs/verifier

REAL=/app/.waf_engine.verifier.real
LOG=/tmp/waf_invocations.log

fail_setup() {
    echo "0" > /logs/verifier/reward.txt
    exit 0
}

[ -f /app/waf_engine ] || fail_setup
rm -f "$REAL" "$LOG"
mv /app/waf_engine "$REAL" || fail_setup
: > "$LOG" || fail_setup
chmod 666 "$LOG" || fail_setup

cat > /app/waf_engine << 'WRAPPER_EOF'
#!/bin/bash
tmp=$(mktemp /tmp/waf-input.XXXXXX) || exit 125
line=''
IFS= read -r line || true
printf '%s\n' "$line" > "$tmp"
hash=$(sha256sum "$tmp" | awk '{print $1}')
printf '%s|%s|%s|%s\n' "${WAF_MODE-}" "$#" "${1-}" "$hash" >> /tmp/waf_invocations.log
/app/.waf_engine.verifier.real "$@" < "$tmp"
rc=$?
rm -f "$tmp"
exit "$rc"
WRAPPER_EOF
chmod 755 /app/waf_engine || fail_setup

cleanup() {
    rm -f /app/waf_engine
    if [ -e "$REAL" ]; then
        mv "$REAL" /app/waf_engine
    fi
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import secrets
import socket
import struct
import subprocess
import time

import pytest
import requests

REAL_ENGINE = "/app/.waf_engine.verifier.real"
INVOCATION_LOG = "/tmp/waf_invocations.log"
SENT_INPUTS = []


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] != "0A":
                        continue
                    if int(fields[1].rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    found = set()
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
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    found.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


def pid_exe(pid):
    try:
        return os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        return ""


def pid_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def oracle(data):
    env = os.environ.copy()
    env["WAF_MODE"] = "strict"
    result = subprocess.run(
        [REAL_ENGINE, "--filter"], input=data, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, env=env, timeout=3, check=False
    )
    assert result.returncode == 0, result.stderr
    return result.stdout


def tcp_backend(data):
    expected = oracle(data)
    with socket.create_connection(("127.0.0.1", 9090), timeout=3) as s:
        s.settimeout(3)
        s.sendall(data)
        received = bytearray()
        while len(received) < len(expected):
            chunk = s.recv(4096)
            if not chunk:
                break
            received.extend(chunk)
    SENT_INPUTS.append(data)
    return bytes(received), expected


class BufferedSocket:
    def __init__(self, sock, initial=b""):
        self.sock = sock
        self.buf = bytearray(initial)

    def read_exact(self, count):
        while len(self.buf) < count:
            chunk = self.sock.recv(4096)
            assert chunk, "WebSocket connection closed unexpectedly"
            self.buf.extend(chunk)
        result = bytes(self.buf[:count])
        del self.buf[:count]
        return result


def websocket_roundtrip(port, data, authorized):
    s = socket.create_connection(("127.0.0.1", port), timeout=5)
    s.settimeout(5)
    key = base64.b64encode(secrets.token_bytes(16)).decode()
    auth = "Authorization: Bearer WAF-2024-SEC\r\n" if authorized else ""
    request = (
        "GET /api/waf HTTP/1.1\r\n"
        f"Host: 127.0.0.1:{port}\r\n"
        "Connection: Upgrade\r\n"
        "Upgrade: websocket\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        f"{auth}\r\n"
    ).encode()
    s.sendall(request)

    header_data = bytearray()
    while b"\r\n\r\n" not in header_data:
        chunk = s.recv(4096)
        assert chunk, "Connection closed during WebSocket upgrade"
        header_data.extend(chunk)
    headers, remainder = bytes(header_data).split(b"\r\n\r\n", 1)
    assert b"101 Switching Protocols" in headers, headers

    mask = secrets.token_bytes(4)
    frame = bytearray([0x81])
    length = len(data)
    if length < 126:
        frame.append(0x80 | length)
    elif length < 65536:
        frame.append(0x80 | 126)
        frame.extend(struct.pack("!H", length))
    else:
        frame.append(0x80 | 127)
        frame.extend(struct.pack("!Q", length))
    frame.extend(mask)
    frame.extend(b ^ mask[i % 4] for i, b in enumerate(data))
    s.sendall(frame)

    reader = BufferedSocket(s, remainder)
    first, second = reader.read_exact(2)
    assert first == 0x81, f"Expected Text frame (0x81), got {hex(first)}"
    assert not (second & 0x80), "Server-to-client frame must not be masked"
    length = second & 0x7f
    if length == 126:
        length = struct.unpack("!H", reader.read_exact(2))[0]
    elif length == 127:
        length = struct.unpack("!Q", reader.read_exact(8))[0]
    payload = reader.read_exact(length)
    s.close()
    SENT_INPUTS.append(data)
    return payload


def test_required_artifacts_and_listeners():
    assert os.path.isfile("/home/user/backend.c"), "Missing /home/user/backend.c"
    assert os.path.isfile("/home/user/backend"), "Missing /home/user/backend"
    assert os.access("/home/user/backend", os.X_OK), "Backend is not executable"
    with open("/home/user/backend", "rb") as f:
        assert f.read(4) == b"\x7fELF", "Backend must be a compiled native executable"
    with open(REAL_ENGINE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The supplied WAF engine is no longer an ELF binary"

    syntax = subprocess.run(
        ["gcc", "-fsyntax-only", "/home/user/backend.c"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert syntax.returncode == 0, syntax.stderr.decode(errors="replace")

    p9090 = listener_pids(9090)
    p9091 = listener_pids(9091)
    p8080 = listener_pids(8080)
    assert p9090, "Nothing is listening on port 9090"
    assert p9091, "Nothing is listening on port 9091"
    assert p8080, "Nothing is listening on port 8080"
    assert any(pid_exe(p) == "/home/user/backend" for p in p9090), \
        "Port 9090 is not served by /home/user/backend"
    assert any("nginx" in pid_exe(p).lower() or "nginx" in pid_cmdline(p).lower() for p in p8080), \
        "Port 8080 is not served by nginx"
    assert all(pid_exe(p) != "/home/user/backend" for p in p9091), \
        "Port 9091 must be a separate WebSocket translation service"


def test_unauthorized_requests():
    url = "http://127.0.0.1:8080/api/waf"
    try:
        r1 = requests.get(url, timeout=2)
        assert r1.status_code in (401, 403), \
            f"Expected 401 or 403 for missing auth, got {r1.status_code}"
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx on port 8080: {e}")

    r2 = requests.get(
        url, headers={"Authorization": "Bearer INVALID-TOKEN"}, timeout=2
    )
    assert r2.status_code in (401, 403), \
        f"Expected 401 or 403 for invalid auth, got {r2.status_code}"


def test_raw_backend_with_unpredictable_inputs():
    samples = [
        f"random-{secrets.token_hex(18)}\n".encode(),
        f"symbols !@#$%^&*() {secrets.token_hex(12)}\n".encode(),
        ("long-" + secrets.token_hex(90) + "\n").encode(),
    ]
    for sample in samples:
        actual, expected = tcp_backend(sample)
        assert actual == expected, f"Raw backend mismatch: expected {expected!r}, got {actual!r}"


def test_websocket_flow():
    payload = b"<script>alert(1)</script>\n"
    actual_payload = websocket_roundtrip(8080, payload, authorized=True)
    expected_payload = b"[WAF-SECURE] <script>alert(1)</script>\n"
    assert actual_payload == expected_payload, \
        f"WAF engine output mismatch. Expected: {expected_payload!r}; got: {actual_payload!r}"


def test_randomized_websocket_flows_and_translation_port():
    samples = [
        f"ws-{secrets.token_hex(25)}\n".encode(),
        ("extended-" + secrets.token_hex(80) + "\n").encode(),
    ]
    for sample in samples:
        assert websocket_roundtrip(8080, sample, authorized=True) == oracle(sample)

    direct = f"translator-{secrets.token_hex(24)}\n".encode()
    assert websocket_roundtrip(9091, direct, authorized=False) == oracle(direct)


def test_backend_actually_invoked_engine_correctly():
    deadline = time.time() + 2
    expected_hashes = {hashlib.sha256(data).hexdigest() for data in SENT_INPUTS}
    records = []
    while time.time() < deadline:
        try:
            with open(INVOCATION_LOG) as f:
                records = [line.strip().split("|") for line in f if line.strip()]
        except FileNotFoundError:
            records = []
        seen = {r[3] for r in records if len(r) == 4}
        if expected_hashes <= seen:
            break
        time.sleep(0.05)

    valid = [r for r in records if len(r) == 4 and r[0] == "strict" and r[1] == "1" and r[2] == "--filter"]
    seen = {r[3] for r in valid}
    assert expected_hashes <= seen, \
        "Backend did not invoke /app/waf_engine with WAF_MODE=strict, --filter, and each submitted input"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

exit 0
