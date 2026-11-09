#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import signal
import socket
import subprocess
import tempfile
import time
import urllib.request


def wait_for_port_file(timeout=5.0):
    start_time = time.time()
    while time.time() - start_time < timeout:
        if os.path.exists("/home/user/active_port.txt"):
            with open("/home/user/active_port.txt", "r") as f:
                port = f.read().strip()
                if port:
                    return port
        time.sleep(0.1)
    return None


def ws_send_receive(port, message):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    s.connect(("127.0.0.1", int(port)))

    key = base64.b64encode(os.urandom(16)).decode("utf-8")
    req = (
        f"GET / HTTP/1.1\r\n"
        f"Host: 127.0.0.1:{port}\r\n"
        f"Upgrade: websocket\r\n"
        f"Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        f"Sec-WebSocket-Version: 13\r\n\r\n"
    )
    s.sendall(req.encode())
    resp = s.recv(4096)
    assert b"101 Switching Protocols" in resp, "WebSocket handshake failed"

    msg_bytes = message.encode("utf-8")
    assert len(msg_bytes) < 126
    header = bytearray([0x81, 0x80 | len(msg_bytes)])
    mask = os.urandom(4)
    header.extend(mask)
    payload = bytearray(msg_bytes[i] ^ mask[i % 4] for i in range(len(msg_bytes)))
    s.sendall(header + payload)

    resp = s.recv(4096)
    assert resp and resp[0] == 0x81, "Expected text frame from WebSocket server"
    length = resp[1] & 0x7F
    payload = resp[2:2 + length]
    s.close()
    return payload.decode("utf-8")


def stop_process(p):
    if p.poll() is None:
        p.send_signal(signal.SIGINT)
        try:
            p.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            p.kill()
            p.wait()


def start_agent(lib_path):
    if os.path.exists("/home/user/active_port.txt"):
        os.remove("/home/user/active_port.txt")
    env = os.environ.copy()
    env["TEST_LIB_PATH"] = lib_path
    return subprocess.Popen(["python3", "/home/user/qa_agent.py"], env=env)


def build_dynamic_libraries():
    rng = secrets.SystemRandom()
    workdir = tempfile.mkdtemp(prefix="qa_dynamic_")

    rc_number = rng.randint(2, 9999)
    legacy_version = f"2.0.0-rc.{rc_number}"
    salt = rng.randint(11, 97)
    multiplier = rng.randint(13, 73)
    offset = rng.randint(-500, 500)

    legacy_c = os.path.join(workdir, secrets.token_hex(10) + ".c")
    legacy_so = os.path.join(workdir, secrets.token_hex(12) + ".so")
    with open(legacy_c, "w") as f:
        f.write(
            f'const char* get_version(void) {{ return "{legacy_version}"; }}\n'
            'int calculate_hash(int input_val) { return input_val - 987654; }\n'
        )

    modern_c = os.path.join(workdir, secrets.token_hex(10) + ".c")
    modern_so = os.path.join(workdir, secrets.token_hex(12) + ".so")
    with open(modern_c, "w") as f:
        f.write(
            'const char* get_version(void) { return "2.0.0"; }\n'
            f'int calculate_hash(int input_val) '
            f'{{ return (input_val ^ {salt}) * {multiplier} + ({offset}); }}\n'
        )

    subprocess.check_call(["gcc", "-shared", "-fPIC", "-o", legacy_so, legacy_c])
    subprocess.check_call(["gcc", "-shared", "-fPIC", "-o", modern_so, modern_c])
    return legacy_so, legacy_version, modern_so, salt, multiplier, offset


DYNAMIC = build_dynamic_libraries()


def test_script_exists_and_executable():
    script_path = "/home/user/qa_agent.py"
    assert os.path.isfile(script_path), f"Script missing: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"


def test_legacy_lib_starts_http_server():
    if os.path.exists("/home/user/active_port.txt"):
        os.remove("/home/user/active_port.txt")

    env = os.environ.copy()
    env["TEST_LIB_PATH"] = "/home/user/libv1.so"

    p = subprocess.Popen(["python3", "/home/user/qa_agent.py"], env=env)
    try:
        port = wait_for_port_file()
        assert port == "8080", f"Expected port 8080 for v1, got {port}"

        time.sleep(1)
        req = urllib.request.urlopen("http://127.0.0.1:8080/", timeout=5.0)
        data = json.loads(req.read().decode())

        assert data.get("status") == "legacy", "Expected status 'legacy' in JSON response"
        assert data.get("version") == "1.8.5", "Expected version '1.8.5' in JSON response"
    finally:
        p.send_signal(signal.SIGINT)
        p.kill()
        p.wait()


def test_modern_lib_starts_ws_server():
    if os.path.exists("/home/user/active_port.txt"):
        os.remove("/home/user/active_port.txt")

    env = os.environ.copy()
    env["TEST_LIB_PATH"] = "/home/user/libv2.so"

    p = subprocess.Popen(["python3", "/home/user/qa_agent.py"], env=env)
    try:
        port = wait_for_port_file()
        assert port == "8081", f"Expected port 8081 for v2, got {port}"

        time.sleep(1)
        response = ws_send_receive(8081, "10")
        assert response == "427", f"Expected 427 from websocket server, got {response}"
    finally:
        p.send_signal(signal.SIGINT)
        p.kill()
        p.wait()


def test_randomized_prerelease_library_is_legacy_and_reports_loaded_version():
    legacy_so, legacy_version, _, _, _, _ = DYNAMIC
    p = start_agent(legacy_so)
    try:
        port = wait_for_port_file()
        assert port == "8080", f"Expected prerelease {legacy_version} on port 8080, got {port}"
        time.sleep(0.5)
        req = urllib.request.urlopen("http://127.0.0.1:8080/", timeout=5.0)
        assert req.status == 200
        data = json.loads(req.read().decode())
        assert data.get("status") == "legacy"
        assert data.get("version") == legacy_version
    finally:
        stop_process(p)


def test_randomized_library_hash_is_invoked_for_multiple_inputs():
    _, _, modern_so, salt, multiplier, offset = DYNAMIC
    rng = secrets.SystemRandom()
    values = {-rng.randint(20, 500), rng.randint(21, 500)}
    while len(values) < 5:
        candidate = rng.randint(-700, 700)
        if candidate != 10:
            values.add(candidate)

    p = start_agent(modern_so)
    try:
        port = wait_for_port_file()
        assert port == "8081", f"Expected exact target version on port 8081, got {port}"
        time.sleep(0.5)
        for value in values:
            expected = (value ^ salt) * multiplier + offset
            response = ws_send_receive(8081, str(value))
            assert response == str(expected), (
                f"calculate_hash result for {value} was {response}, expected {expected}"
            )
    finally:
        stop_process(p)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
