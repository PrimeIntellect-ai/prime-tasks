#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import glob
import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import tempfile
import threading
import time

PROJECT = "/home/user/project"


def test_sources_were_not_modified():
    expected_c = """int process_data(int* data, int len) {
    int sum = 0;
    for(int i=0; i<len; i++) { sum += data[i]; }
    return sum;
}
"""
    expected_rs = """extern \"C\" {
    fn process_data(data: *const i32, len: usize) -> i32;
}
fn main() {
    println!(\"Server running\");
}
"""
    with open(os.path.join(PROJECT, "src/c_src/processor.c")) as f:
        assert f.read() == expected_c, "processor.c was modified."
    with open(os.path.join(PROJECT, "src/main.rs")) as f:
        assert f.read() == expected_rs, "main.rs was modified."


def test_build_script_cross_compilation():
    build_script = os.path.join(PROJECT, "build.sh")
    assert os.path.isfile(build_script), "build.sh is missing."

    with open(build_script, "r") as f:
        content = f.read()

    assert "aarch64-linux-gnu-gcc" in content, "build.sh does not use aarch64-linux-gnu-gcc for compilation."
    assert "aarch64-linux-gnu-ar" in content, "build.sh does not use aarch64-linux-gnu-ar for archiving."

    # Force the script to recreate its outputs, rather than accepting stale files.
    for pattern in ("**/libprocessor.a", "**/processor.o"):
        for path in glob.glob(os.path.join(PROJECT, pattern), recursive=True):
            if os.path.isfile(path):
                os.remove(path)
    cargo_config = os.path.join(PROJECT, ".cargo/config.toml")
    if os.path.lexists(cargo_config):
        os.remove(cargo_config)

    wrappers = tempfile.mkdtemp(prefix="build-tools-")
    log_path = os.path.join(wrappers, "calls.log")

    def wrapper(name, body):
        path = os.path.join(wrappers, name)
        with open(path, "w") as f:
            f.write("#!/bin/bash\nset -e\n")
            f.write("printf '%s\\t%s\\n' '" + name + "' \"$*\" >> " + repr(log_path) + "\n")
            f.write(body)
        os.chmod(path, 0o755)

    wrapper("aarch64-linux-gnu-gcc", "exec /usr/bin/aarch64-linux-gnu-gcc \"$@\"\n")
    wrapper("aarch64-linux-gnu-ar", "exec /usr/bin/aarch64-linux-gnu-ar \"$@\"\n")
    # The image has no aarch64 Rust standard library. Run real Cargo validation while
    # recording that build.sh requested the required cross-target Cargo build.
    wrapper("cargo", "exec /usr/bin/cargo check --manifest-path /home/user/project/Cargo.toml\n")

    env = os.environ.copy()
    env["PATH"] = wrappers + os.pathsep + env["PATH"]
    result = subprocess.run(
        ["/bin/bash", build_script], cwd=PROJECT, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60
    )
    assert result.returncode == 0, "build.sh did not exit 0:\n" + result.stdout

    with open(log_path) as f:
        calls = f.read().splitlines()
    assert any(line.startswith("aarch64-linux-gnu-gcc\t") and "processor.c" in line and "-c" in line for line in calls), \
        "build.sh did not actually invoke aarch64-linux-gnu-gcc to compile processor.c."
    assert any(line.startswith("aarch64-linux-gnu-ar\t") and "libprocessor.a" in line for line in calls), \
        "build.sh did not actually invoke aarch64-linux-gnu-ar to create libprocessor.a."
    assert any(line.startswith("cargo\t") and re.search(r"(^| )build( |$)", line) and "--target" in line and "aarch64-unknown-linux-gnu" in line for line in calls), \
        "build.sh did not invoke Cargo to build for aarch64-unknown-linux-gnu."

    archives = glob.glob(os.path.join(PROJECT, "**/libprocessor.a"), recursive=True)
    assert archives, "build.sh did not create libprocessor.a."
    archive = archives[0]
    listing = subprocess.run(
        ["/usr/bin/aarch64-linux-gnu-ar", "t", archive],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert listing.returncode == 0 and listing.stdout.strip(), "libprocessor.a is not a valid nonempty static archive."

    with tempfile.TemporaryDirectory() as extract_dir:
        extracted = subprocess.run(
            ["/usr/bin/aarch64-linux-gnu-ar", "x", archive], cwd=extract_dir,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert extracted.returncode == 0, "libprocessor.a could not be extracted."
        objects = glob.glob(os.path.join(extract_dir, "*.o"))
        assert objects, "libprocessor.a contains no object files."
        for obj in objects:
            info = subprocess.run(["readelf", "-h", obj], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            assert info.returncode == 0 and re.search(r"Machine:\s+AArch64", info.stdout), \
                "libprocessor.a contains an object that is not AArch64."


def test_cargo_config_linker():
    cargo_config = os.path.join(PROJECT, ".cargo/config.toml")
    assert os.path.isfile(cargo_config), ".cargo/config.toml is missing."

    with open(cargo_config, "r") as f:
        content = f.read()

    assert "target.aarch64-unknown-linux-gnu" in content, ".cargo/config.toml does not configure target.aarch64-unknown-linux-gnu."
    assert "linker" in content and "aarch64-linux-gnu-gcc" in content, ".cargo/config.toml does not set the correct linker."

    import tomllib
    with open(cargo_config, "rb") as f:
        parsed = tomllib.load(f)
    target = parsed.get("target", {}).get("aarch64-unknown-linux-gnu", {})
    assert target.get("linker") == "aarch64-linux-gnu-gcc", \
        ".cargo/config.toml does not functionally configure the required target linker."


def _decode_ws_frames(data):
    messages = []
    pos = 0
    while pos + 2 <= len(data):
        b1, b2 = data[pos], data[pos + 1]
        pos += 2
        length = b2 & 0x7f
        if length == 126:
            if pos + 2 > len(data): break
            length = int.from_bytes(data[pos:pos + 2], "big")
            pos += 2
        elif length == 127:
            if pos + 8 > len(data): break
            length = int.from_bytes(data[pos:pos + 8], "big")
            pos += 8
        masked = bool(b2 & 0x80)
        mask = b""
        if masked:
            if pos + 4 > len(data): break
            mask = data[pos:pos + 4]
            pos += 4
        if pos + length > len(data): break
        payload = bytearray(data[pos:pos + length])
        pos += length
        if masked:
            for i in range(len(payload)):
                payload[i] ^= mask[i % 4]
        if (b1 & 0x0f) in (1, 2, 0):
            messages.append(bytes(payload))
    return messages


def test_test_ws_script():
    test_script = os.path.join(PROJECT, "test_ws.sh")
    assert os.path.isfile(test_script), "test_ws.sh is missing."
    assert os.access(test_script, os.X_OK), "test_ws.sh is not executable."

    with open(test_script, "r") as f:
        content = f.read()

    assert "curl" in content, "test_ws.sh does not use curl."
    assert "Upgrade: websocket" in content or "upgrade: websocket" in content.lower(), "test_ws.sh does not contain WebSocket upgrade headers."
    assert "ws://localhost:8080/stream" in content, "test_ws.sh does not target the correct WebSocket URL."

    payload = '{"command": "process", "payload": [1, 2, 3, 4]}'
    compact_payload = payload.replace(" ", "")
    compact_content = content.replace(" ", "")
    assert compact_payload in compact_content, "test_ws.sh does not send the correct JSON payload."
    assert "/home/user/ws_test_output.log" in content, "test_ws.sh does not save output to /home/user/ws_test_output.log."

    output_path = "/home/user/ws_test_output.log"
    if os.path.lexists(output_path):
        os.remove(output_path)

    captured = {}
    ready = threading.Event()
    server_errors = []
    response_marker = b"WS_VERIFIER_RESPONSE_7f3a"

    def server():
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as srv:
                srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                srv.bind(("127.0.0.1", 8080))
                srv.listen(1)
                ready.set()
                conn, _ = srv.accept()
                with conn:
                    conn.settimeout(2)
                    data = b""
                    while b"\r\n\r\n" not in data and len(data) < 65536:
                        chunk = conn.recv(4096)
                        if not chunk: break
                        data += chunk
                    head, sep, tail = data.partition(b"\r\n\r\n")
                    captured["head"] = head
                    lines = head.split(b"\r\n")
                    headers = {}
                    for line in lines[1:]:
                        if b":" in line:
                            k, v = line.split(b":", 1)
                            headers[k.strip().lower()] = v.strip()
                    length = int(headers.get(b"content-length", b"0") or b"0")
                    while len(tail) < length:
                        chunk = conn.recv(4096)
                        if not chunk: break
                        tail += chunk
                    key = headers.get(b"sec-websocket-key", b"")
                    accept = base64.b64encode(hashlib.sha1(key + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest())
                    response = (b"HTTP/1.1 101 Switching Protocols\r\n"
                                b"Upgrade: websocket\r\nConnection: Upgrade\r\n"
                                b"Sec-WebSocket-Accept: " + accept + b"\r\n"
                                b"X-Verifier: ws-pipeline\r\n\r\n")
                    frame = b"\x81" + bytes([len(response_marker)]) + response_marker
                    conn.sendall(response + frame)
                    end = time.time() + 1.5
                    while time.time() < end:
                        try:
                            chunk = conn.recv(4096)
                            if not chunk: break
                            tail += chunk
                        except socket.timeout:
                            break
                    captured["tail"] = tail
                    captured["headers"] = headers
        except Exception as exc:
            server_errors.append(exc)
            ready.set()

    thread = threading.Thread(target=server, daemon=True)
    thread.start()
    assert ready.wait(3), "mock WebSocket server did not start."
    result = subprocess.run(
        ["/bin/bash", test_script], cwd=PROJECT,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=15
    )
    thread.join(4)
    assert not server_errors, "mock WebSocket server failed: " + repr(server_errors)
    assert result.returncode == 0, "test_ws.sh did not exit successfully:\n" + result.stdout

    head = captured.get("head", b"")
    lines = head.split(b"\r\n")
    assert lines and re.match(br"GET\s+/stream(?:\s|\?)", lines[0]), "test_ws.sh did not make a WebSocket GET request to /stream."
    headers = captured.get("headers", {})
    assert headers.get(b"upgrade", b"").lower() == b"websocket", "WebSocket Upgrade header was not sent."
    assert b"upgrade" in headers.get(b"connection", b"").lower(), "Connection: Upgrade header was not sent."
    assert headers.get(b"sec-websocket-key"), "Sec-WebSocket-Key header was not sent."
    assert headers.get(b"sec-websocket-version") == b"13", "Sec-WebSocket-Version: 13 was not sent."

    request_parts = [captured.get("tail", b"")] + _decode_ws_frames(captured.get("tail", b""))
    found_payload = False
    for part in request_parts:
        try:
            text = part.decode("utf-8", errors="ignore")
            for candidate in re.findall(r'\{[^{}]*\}', text):
                if json.loads(candidate) == {"command": "process", "payload": [1, 2, 3, 4]}:
                    found_payload = True
        except (ValueError, TypeError):
            pass
    assert found_payload, "test_ws.sh did not actually transmit the required JSON payload."

    assert os.path.isfile(output_path) and not os.path.islink(output_path), "test_ws.sh did not create the required output log as a regular file."
    with open(output_path, "rb") as f:
        output = f.read()
    assert b"101 Switching Protocols" in output and b"Upgrade: websocket" in output, \
        "The output log does not contain the response headers."
    assert response_marker in output, "The output log does not contain the response body."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
