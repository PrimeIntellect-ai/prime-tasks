#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import signal
import socket
import struct
import subprocess
import time

import pytest
import redis
import requests

CI_SCRIPT = "/home/user/ci_verify.sh"
LOG_PATH = "/home/user/build_result.log"
SOURCE = "/home/user/build_tools/checksum_engine.cpp"
ORACLE = "/app/oracle/checksum_reference.bin"
ASAN_BINARY = "/tmp/verifier_checksum_engine_asan"
EXPECTED_TARGET = "mobile_app_v2"


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[3] == "0A":
                try:
                    local_port = int(fields[1].rsplit(":", 1)[1], 16)
                except ValueError:
                    continue
                if local_port == port:
                    inodes.add(fields[9])

    owners = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(name))
        except OSError:
            pass
    return owners


def stop_port(port):
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
    deadline = time.time() + 4
    while listener_pids(port) and time.time() < deadline:
        time.sleep(0.1)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass


def wait_port(port, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"Port {port} did not become available")


def oracle_output(data):
    proc = subprocess.run([ORACLE], input=data, capture_output=True, timeout=5)
    assert proc.returncode == 0, proc.stderr.decode(errors="replace")
    return proc.stdout.strip()


def cgi_body(output):
    if b"\r\n\r\n" in output:
        return output.split(b"\r\n\r\n", 1)[1].strip()
    if b"\n\n" in output:
        return output.split(b"\n\n", 1)[1].strip()
    return output.strip()


def body_has_checksum(body, expected):
    if body.strip() == expected:
        return True
    try:
        obj = json.loads(body)
    except Exception:
        return False

    def contains(value):
        if isinstance(value, dict):
            return any(contains(v) for v in value.values())
        if isinstance(value, list):
            return any(contains(v) for v in value)
        if isinstance(value, str):
            return value.encode() == expected
        return False

    return contains(obj)


def enc_len(n):
    return bytes([n]) if n < 128 else struct.pack("!I", n | 0x80000000)


def fcgi_record(record_type, request_id, content=b""):
    padding = (-len(content)) % 8
    header = struct.pack("!BBHHBB", 1, record_type, request_id, len(content), padding, 0)
    return header + content + (b"\0" * padding)


def fcgi_request(port, data, uri="/checksum"):
    request_id = 1
    begin = struct.pack("!HB5x", 1, 0)
    params = {
        b"REQUEST_METHOD": b"POST",
        b"REQUEST_URI": uri.encode(),
        b"SCRIPT_NAME": uri.encode(),
        b"SERVER_PROTOCOL": b"HTTP/1.1",
        b"CONTENT_TYPE": b"application/octet-stream",
        b"CONTENT_LENGTH": str(len(data)).encode(),
    }
    encoded_params = b"".join(
        enc_len(len(k)) + enc_len(len(v)) + k + v for k, v in params.items()
    )
    payload = fcgi_record(1, request_id, begin)
    payload += fcgi_record(4, request_id, encoded_params)
    payload += fcgi_record(4, request_id)
    for offset in range(0, len(data), 65535):
        payload += fcgi_record(5, request_id, data[offset:offset + 65535])
    payload += fcgi_record(5, request_id)

    stdout = bytearray()
    with socket.create_connection(("127.0.0.1", port), timeout=3) as sock:
        sock.settimeout(10)
        sock.sendall(payload)
        while True:
            header = b""
            while len(header) < 8:
                chunk = sock.recv(8 - len(header))
                assert chunk, "FastCGI connection closed before a complete response"
                header += chunk
            version, kind, rid, length, padding, _ = struct.unpack("!BBHHBB", header)
            assert version == 1 and rid == request_id
            content = b""
            while len(content) < length:
                content += sock.recv(length - len(content))
            remaining = padding
            while remaining:
                chunk = sock.recv(remaining)
                assert chunk
                remaining -= len(chunk)
            if kind == 6:
                stdout.extend(content)
            elif kind == 3:
                break
    return cgi_body(bytes(stdout))


def test_ci_verify_script_exists():
    assert os.path.isfile(CI_SCRIPT), f"Missing CI script: {CI_SCRIPT}"
    assert os.access(CI_SCRIPT, os.X_OK), f"CI script is not executable: {CI_SCRIPT}"


def test_source_builds_cleanly_and_is_asan_clean():
    assert os.path.isfile(SOURCE), f"Missing repaired source: {SOURCE}"
    assert os.path.isfile(ORACLE), f"Missing oracle: {ORACLE}"

    build = subprocess.run(
        ["g++", "-O2", "-fsanitize=address", "-Wall", "-Wextra",
         "-Wpedantic", "-Werror", SOURCE, "-o", ASAN_BINARY, "-lfcgi"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"ASAN build failed or warned:\n{build.stdout}\n{build.stderr}"
    assert build.stderr.strip() == "", f"Compiler emitted warnings/errors:\n{build.stderr}"

    rng = random.Random(7319)
    inputs = [b"", bytes(range(256)), os.urandom(65537),
              bytes(rng.getrandbits(8) for _ in range(1000000))]
    for index, data in enumerate(inputs):
        expected = oracle_output(data)
        env = os.environ.copy()
        env.update({
            "REQUEST_METHOD": "POST",
            "REQUEST_URI": "/checksum",
            "SCRIPT_NAME": "/checksum",
            "CONTENT_TYPE": "application/octet-stream",
            "CONTENT_LENGTH": str(len(data)),
            "ASAN_OPTIONS": "detect_leaks=1:halt_on_error=1:exitcode=99",
            "LSAN_OPTIONS": "exitcode=99",
        })
        proc = subprocess.run(
            [ASAN_BINARY], input=data, capture_output=True, env=env, timeout=15
        )
        stderr = proc.stderr.decode(errors="replace")
        assert proc.returncode == 0, (
            f"ASAN engine failed for input {index} ({len(data)} bytes):\n{stderr}"
        )
        assert "AddressSanitizer" not in stderr and "LeakSanitizer" not in stderr, stderr
        assert body_has_checksum(cgi_body(proc.stdout), expected), (
            f"Checksum mismatch for input {index} ({len(data)} bytes)"
        )


def test_ci_pipeline_end_to_end():
    for port in (8001, 8002, 6379):
        stop_port(port)
    try:
        os.remove(LOG_PATH)
    except FileNotFoundError:
        pass

    run = subprocess.run(
        [CI_SCRIPT], cwd="/home/user", capture_output=True, text=True, timeout=45
    )
    assert run.returncode == 0, f"CI script failed:\nSTDOUT:\n{run.stdout}\nSTDERR:\n{run.stderr}"

    for port in (6379, 8002, 8001):
        wait_port(port)

    client = redis.Redis(host="127.0.0.1", port=6379, socket_timeout=2)
    assert client.ping() is True, "Redis is not responding on port 6379"

    assert os.path.isfile(LOG_PATH), f"Missing build result log: {LOG_PATH}"
    with open(LOG_PATH) as f:
        logged = json.load(f)
    assert isinstance(logged, dict), "Log content is not a JSON object"

    response = requests.post(
        "http://127.0.0.1:8001/resolve",
        json={"target": EXPECTED_TARGET},
        timeout=10,
    )
    assert response.status_code == 200, response.text
    live = response.json()
    assert isinstance(live, dict)
    assert logged == live, "build_result.log is not the resolver's JSON response"
    assert live.get("status") == "ok", f"Resolver did not report success: {live}"

    expected = oracle_output(b"mobile_app_v2")
    assert body_has_checksum(json.dumps(live).encode(), expected), (
        f"Resolver response does not contain the reference checksum: {live}"
    )

    engine_data = os.urandom(131123)
    engine_expected = oracle_output(engine_data)
    engine_body = fcgi_request(8002, engine_data)
    assert body_has_checksum(engine_body, engine_expected), (
        f"FastCGI checksum response mismatch: {engine_body[:200]!r}"
    )

    engine_owners = listener_pids(8002)
    assert engine_owners, "No process owns the FastCGI listening socket"
    engine_exes = []
    for pid in engine_owners:
        try:
            engine_exes.append(os.path.realpath(f"/proc/{pid}/exe"))
        except OSError:
            pass
    native_engines = [p for p in engine_exes if os.path.isfile(p) and open(p, "rb").read(4) == b"\x7fELF"]
    assert native_engines, f"Port 8002 is not served by a native checksum engine: {engine_exes}"
    with open(ORACLE, "rb") as f:
        oracle_bytes = f.read()
    assert any(open(path, "rb").read() != oracle_bytes for path in native_engines), (
        "The submitted service executable is byte-identical to the vendor oracle"
    )

    cached = bytearray()
    for key in client.scan_iter(match="*"):
        cached.extend(key)
        try:
            dumped = client.dump(key)
            if dumped:
                cached.extend(dumped)
        except redis.RedisError:
            pass
    assert EXPECTED_TARGET.encode() in cached, "Redis does not contain the resolved target state"
    assert engine_expected in cached, "Redis does not contain the artifact checksum"

    # A cold resolver request must depend on the checksum service rather than a hard-coded reply.
    for pid in engine_owners:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 4
    while listener_pids(8002) and time.time() < deadline:
        time.sleep(0.1)
    assert not listener_pids(8002), "Checksum engine did not stop for dependency test"
    client.flushdb()
    try:
        failed = requests.post(
            "http://127.0.0.1:8001/resolve",
            json={"target": EXPECTED_TARGET},
            timeout=5,
        )
        assert failed.status_code >= 400 or not body_has_checksum(failed.content, expected), (
            "Resolver returns the reference checksum even with an empty cache and no checksum engine"
        )
    except requests.RequestException:
        pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
