#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import re
import secrets
import shutil
import socket
import string
import struct
import subprocess
import tempfile

CHAT_DIR = "/home/user/app/chat-server"
NGINX_CONF = "/home/user/app/nginx/nginx.conf"
TOKEN = "secret-chat-token-123"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=60, **kwargs)


def test_ready_file():
    ready_path = "/home/user/app/ready.txt"
    assert os.path.isfile(ready_path), f"{ready_path} is missing"
    with open(ready_path, encoding="utf-8") as f:
        content = f.read().strip()
    assert content == "DONE", f"Expected 'DONE' in ready.txt, got {content!r}"


def _test_function_bodies(source):
    found = {}
    pattern = re.compile(r"func\s+(Test[A-Za-z0-9_]+)\s*\([^)]*\*testing\.T[^)]*\)\s*\{")
    for match in pattern.finditer(source):
        opening = source.find("{", match.start())
        depth = 0
        in_string = None
        escaped = False
        i = opening
        while i < len(source):
            ch = source[i]
            if in_string:
                if in_string != "`" and escaped:
                    escaped = False
                elif in_string != "`" and ch == "\\":
                    escaped = True
                elif ch == in_string:
                    in_string = None
            elif ch in ('"', "'", "`"):
                in_string = ch
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    found[match.group(1)] = source[opening:i + 1]
                    break
            i += 1
    return found


def _replace_parse_room_id_body(source):
    match = re.search(r"func\s+ParseRoomID\s*\(\s*path\s+string\s*\)\s*\(\s*string\s*,\s*error\s*\)\s*\{", source)
    assert match, "Could not find ParseRoomID(path string) (string, error) in router.go"
    opening = source.find("{", match.start())
    depth = 0
    in_string = None
    escaped = False
    for i in range(opening, len(source)):
        ch = source[i]
        if in_string:
            if in_string != "`" and escaped:
                escaped = False
            elif in_string != "`" and ch == "\\":
                escaped = True
            elif ch == in_string:
                in_string = None
        elif ch in ('"', "'", "`"):
            in_string = ch
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return source[:opening] + '{\n\treturn "", nil\n}' + source[i + 1:]
    raise AssertionError("Unterminated ParseRoomID function")


def test_go_tests_and_real_property_test_pass():
    assert os.path.isdir(CHAT_DIR), f"{CHAT_DIR} is missing"
    test_path = os.path.join(CHAT_DIR, "router_test.go")
    assert os.path.isfile(test_path), "router_test.go is missing"
    with open(test_path, encoding="utf-8") as f:
        source = f.read()

    result = run(["go", "test", "-v", "-count=1"], cwd=CHAT_DIR)
    assert result.returncode == 0, f"Go tests failed:\n{result.stdout}\n{result.stderr}"
    assert "testing/quick" in result.stdout or "testing/quick" in source, "testing/quick not found in tests"

    bodies = _test_function_bodies(source)
    property_tests = [
        name for name, body in bodies.items()
        if re.search(r"\bquick\.(?:Check|CheckEqual)\s*\(", body)
        and re.search(r"\bParseRoomID\s*\(", body)
    ]
    assert property_tests, "No Test function both calls testing/quick and exercises ParseRoomID"

    # A real extraction property must detect this deliberately broken implementation.
    with tempfile.TemporaryDirectory(prefix="chat-property-mutation-") as tmp:
        copied = os.path.join(tmp, "chat-server")
        shutil.copytree(CHAT_DIR, copied)
        router_path = os.path.join(copied, "router.go")
        with open(router_path, encoding="utf-8") as f:
            router = f.read()
        with open(router_path, "w", encoding="utf-8") as f:
            f.write(_replace_parse_room_id_body(router))
        names = "|".join(re.escape(name) for name in property_tests)
        mutated = run(["go", "test", "-count=1", "-run", f"^({names})$"], cwd=copied)
        assert mutated.returncode != 0, (
            "The testing/quick property still passes when ParseRoomID always returns an empty ID; "
            "it does not verify the required extraction property"
        )


def test_parse_room_id_on_verifier_generated_cases():
    alphabet = string.ascii_letters + string.digits
    cases = []
    for length in [1, 2, 5, 12, 31, 64]:
        cases.append("".join(secrets.choice(alphabet) for _ in range(length)))

    go_cases = ",".join(json.dumps(value) for value in cases)
    verifier_test = os.path.join(CHAT_DIR, "zz_verifier_generated_test.go")
    code = f'''package main
import "testing"
func TestVerifierGeneratedParseRoomID(t *testing.T) {{
    cases := []string{{{go_cases}}}
    for _, want := range cases {{
        got, err := ParseRoomID("/ws/room/" + want)
        if err != nil || got != want {{
            t.Fatalf("ParseRoomID generated case: want %q, got %q, err=%v", want, got, err)
        }}
    }}
    invalid := []string{{"/ws/room/", "/ws/room/a-b", "/ws/room/a_b", "/ws/room/a/b", "/other/room/abc"}}
    for _, path := range invalid {{
        if _, err := ParseRoomID(path); err == nil {{
            t.Fatalf("ParseRoomID accepted invalid path %q", path)
        }}
    }}
}}
'''
    try:
        with open(verifier_test, "w", encoding="utf-8") as f:
            f.write(code)
        result = run(["go", "test", "-count=1", "-run", "^TestVerifierGeneratedParseRoomID$"], cwd=CHAT_DIR)
        assert result.returncode == 0, f"ParseRoomID failed generated cases:\n{result.stdout}\n{result.stderr}"
    finally:
        try:
            os.remove(verifier_test)
        except FileNotFoundError:
            pass


def test_test_results_log():
    log_path = "/home/user/app/test_results.log"
    assert os.path.isfile(log_path), f"{log_path} is missing"
    with open(log_path, encoding="utf-8") as f:
        content = f.read()
    assert len(content.strip()) > 0, "test_results.log is empty"


def _recv_exact(sock, size):
    data = b""
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise RuntimeError("connection closed early")
        data += chunk
    return data


def websocket_request(port, path, token, message=None):
    sock = socket.create_connection(("127.0.0.1", port), timeout=5)
    sock.settimeout(5)
    key = base64.b64encode(secrets.token_bytes(16)).decode("ascii")
    request = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: 127.0.0.1:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
    )
    if token is not None:
        request += f"Authorization: Bearer {token}\r\n"
    request += "\r\n"
    sock.sendall(request.encode("ascii"))

    response = b""
    while b"\r\n\r\n" not in response and len(response) < 65536:
        response += sock.recv(4096)
    headers, _, remainder = response.partition(b"\r\n\r\n")
    status_line = headers.split(b"\r\n", 1)[0].decode("latin1", "replace")
    match = re.match(r"HTTP/\d(?:\.\d)?\s+(\d+)", status_line)
    assert match, f"Invalid HTTP response on port {port}: {status_line!r}"
    status = int(match.group(1))
    if status != 101 or message is None:
        sock.close()
        return status, headers.decode("latin1", "replace"), None

    expected_accept = base64.b64encode(
        hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()
    ).decode("ascii")
    assert re.search(rf"(?im)^Sec-WebSocket-Accept:\s*{re.escape(expected_accept)}\s*$", headers.decode("latin1")), \
        "Invalid Sec-WebSocket-Accept header"

    payload = message.encode("utf-8")
    frame = bytearray([0x81])
    if len(payload) < 126:
        frame.append(0x80 | len(payload))
    elif len(payload) <= 65535:
        frame.append(0x80 | 126)
        frame.extend(struct.pack(">H", len(payload)))
    else:
        frame.append(0x80 | 127)
        frame.extend(struct.pack(">Q", len(payload)))
    mask = secrets.token_bytes(4)
    frame.extend(mask)
    frame.extend(byte ^ mask[i % 4] for i, byte in enumerate(payload))
    sock.sendall(frame)

    buffered = bytearray(remainder)
    while len(buffered) < 2:
        buffered.extend(sock.recv(4096))
    first, second = buffered[0], buffered[1]
    del buffered[:2]
    assert first & 0x0F == 1, f"Expected text frame, opcode was {first & 0x0F}"
    length = second & 0x7F
    if length == 126:
        while len(buffered) < 2:
            buffered.extend(sock.recv(4096))
        length = struct.unpack(">H", bytes(buffered[:2]))[0]
        del buffered[:2]
    elif length == 127:
        while len(buffered) < 8:
            buffered.extend(sock.recv(4096))
        length = struct.unpack(">Q", bytes(buffered[:8]))[0]
        del buffered[:8]
    if second & 0x80:
        while len(buffered) < 4:
            buffered.extend(sock.recv(4096))
        response_mask = bytes(buffered[:4])
        del buffered[:4]
    else:
        response_mask = None
    while len(buffered) < length:
        buffered.extend(sock.recv(4096))
    data = bytes(buffered[:length])
    if response_mask:
        data = bytes(byte ^ response_mask[i % 4] for i, byte in enumerate(data))
    sock.close()
    return status, headers.decode("latin1", "replace"), data.decode("utf-8")


def test_websocket_echo_direct_and_nginx_on_generated_inputs():
    alphabet = string.ascii_letters + string.digits
    cases = []
    for length in [1, 7, 19, 37]:
        room = "".join(secrets.choice(alphabet) for _ in range(length))
        message_length = secrets.choice([3, 29, 130, 190])
        message = "msg-" + "".join(secrets.choice(string.ascii_letters + string.digits + " -_:.") for _ in range(message_length))
        cases.append((room, message))

    for port in (9000, 8080):
        for room, message in cases:
            status, _, response = websocket_request(port, f"/ws/room/{room}", TOKEN, message)
            assert status == 101, f"Expected WebSocket upgrade on port {port}, got HTTP {status}"
            expected = f"Room {room}: {message}"
            assert response == expected, f"Expected {expected!r} on port {port}, got {response!r}"


def test_websocket_unauthorized_and_invalid_routes():
    room = "R" + secrets.token_hex(8)
    wrong_token = "wrong-" + secrets.token_hex(12)
    for port in (9000, 8080):
        for token in (None, wrong_token, "", "Bearer " + TOKEN):
            status, _, _ = websocket_request(port, f"/ws/room/{room}", token, None)
            assert status == 401, f"Expected 401 for invalid authorization on port {port}, got {status}"
        for path in (f"/ws/room/{room}-bad", f"/ws/room/{room}/extra", "/ws/room/"):
            status, _, _ = websocket_request(port, path, TOKEN, None)
            assert status != 101, f"Invalid room path {path!r} upgraded on port {port}"


def _listener_pids(ip, port):
    wanted_ip = "".join(f"{int(part):02X}" for part in reversed(ip.split(".")))
    wanted = f"{wanted_ip}:{port:04X}"
    inodes = set()
    with open("/proc/net/tcp", encoding="ascii") as f:
        next(f)
        for line in f:
            fields = line.split()
            if fields[1] == wanted and fields[3] == "0A":
                inodes.add(fields[9])
    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(entry))
        except OSError:
            pass
    return pids


def _cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def test_services_running_and_are_expected_services():
    # Preserve the original open-port assertions.
    for port, name in ((6379, "Redis"), (9000, "Go service"), (8080, "Nginx")):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        result = sock.connect_ex(("127.0.0.1", port))
        sock.close()
        assert result == 0, f"{name} is not running on 127.0.0.1:{port}"

    # Verify Redis protocol identity rather than accepting an arbitrary listener.
    sock = socket.create_connection(("127.0.0.1", 6379), timeout=3)
    sock.sendall(b"*1\r\n$4\r\nPING\r\n")
    redis_reply = sock.recv(128)
    sock.close()
    assert redis_reply.startswith(b"+PONG\r\n"), f"Port 6379 is not a working Redis server: {redis_reply!r}"

    redis_pids = _listener_pids("127.0.0.1", 6379)
    assert redis_pids and any("redis-server" in _cmdline(pid) for pid in redis_pids), \
        "The process listening on 127.0.0.1:6379 is not redis-server"

    nginx_pids = _listener_pids("127.0.0.1", 8080)
    assert nginx_pids and any("nginx" in _cmdline(pid).lower() for pid in nginx_pids), \
        "The process listening on 127.0.0.1:8080 is not Nginx"

    go_pids = _listener_pids("127.0.0.1", 9000)
    assert go_pids, "No process owns the listener on 127.0.0.1:9000"
    go_binary = False
    details = []
    for pid in go_pids:
        result = run(["go", "version", "-m", f"/proc/{pid}/exe"])
        details.append(result.stdout + result.stderr)
        if result.returncode == 0 and re.search(r"\bgo1\.\d+", result.stdout + result.stderr):
            go_binary = True
    assert go_binary, "The process on port 9000 is not a Go-built service: " + "\n".join(details)


def test_nginx_configuration_is_valid_websocket_proxy():
    assert os.path.isfile(NGINX_CONF), f"{NGINX_CONF} is missing"
    checked = run(["nginx", "-t", "-c", NGINX_CONF])
    assert checked.returncode == 0, f"Nginx configuration is invalid:\n{checked.stdout}\n{checked.stderr}"
    with open(NGINX_CONF, encoding="utf-8") as f:
        raw = f.read()
    config = "\n".join(line.split("#", 1)[0] for line in raw.splitlines())
    assert re.search(r"\blisten\s+127\.0\.0\.1:8080\s*;", config), "Nginx must listen on 127.0.0.1:8080"
    assert re.search(r"\blocation\s+(?:\^~\s+)?/ws/", config), "Nginx has no active /ws/ location"
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:9000(?:/)?\s*;", config), \
        "Nginx does not proxy /ws/ traffic to 127.0.0.1:9000"
    assert re.search(r"\bproxy_http_version\s+1\.1\s*;", config), "Nginx WebSocket proxy must use HTTP/1.1"
    assert re.search(r"\bproxy_set_header\s+Upgrade\s+\$http_upgrade\s*;", config, re.I), \
        "Nginx does not forward the Upgrade header"
    assert re.search(r"\bproxy_set_header\s+Connection\s+(?:[\"']?upgrade[\"']?|\$[A-Za-z_][A-Za-z0-9_]*)\s*;", config, re.I), \
        "Nginx does not forward a WebSocket Connection header"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
