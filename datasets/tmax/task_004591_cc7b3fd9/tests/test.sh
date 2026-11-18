#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import signal
import socket
import subprocess
import time

import pytest

BINARY = "/app/math_eval/math_eval"
BUILD_DIR = "/app/math_eval"
SERVER_SCRIPT = "/app/server.sh"
HOST = "127.0.0.1"
PORT = 8080


def send_to_server(payload: str, chunks=None) -> str:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5.0)
        s.connect((HOST, PORT))
        encoded = payload.encode("utf-8")
        if chunks is None:
            s.sendall(encoded)
        else:
            offset = 0
            for size in chunks:
                if offset >= len(encoded):
                    break
                s.sendall(encoded[offset:offset + size])
                offset += size
                time.sleep(0.03)
            if offset < len(encoded):
                s.sendall(encoded[offset:])
        s.shutdown(socket.SHUT_WR)
        response = bytearray()
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            response.extend(chunk)
    return response.decode("utf-8").strip()


def redis_get(key: str):
    result = subprocess.run(
        ["redis-cli", "--raw", "GET", key],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.rstrip("\n")


def redis_set(key: str, value: str):
    subprocess.run(
        ["redis-cli", "SET", key, value],
        capture_output=True,
        text=True,
        check=True,
    )


def redis_delete(key: str):
    subprocess.run(
        ["redis-cli", "DEL", key],
        capture_output=True,
        text=True,
        check=True,
    )


def cache_key(payload: str) -> str:
    return hashlib.md5(payload.rstrip().encode("utf-8")).hexdigest()


def run_backend(payload: str) -> str:
    result = subprocess.run(
        [BINARY],
        input=payload,
        capture_output=True,
        text=True,
        timeout=5,
        check=True,
    )
    return result.stdout.strip()


def listening_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        if int(fields[1].split(":")[-1], 16) == PORT:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

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
        except (FileNotFoundError, PermissionError):
            pass
    return owners


def stop_existing_server():
    victims = set(listening_pids())
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        try:
            cmdline = open(f"/proc/{name}/cmdline", "rb").read().replace(b"\0", b" ")
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if b"/app/server.sh" in cmdline:
            victims.add(int(name))

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listening_pids():
        time.sleep(0.05)
    for pid in listening_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_server(timeout=6.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.2)
            if s.connect_ex((HOST, PORT)) == 0:
                return
        time.sleep(0.05)
    pytest.fail("TCP server is not listening on 127.0.0.1:8080")


def test_01_makefile_builds_real_executable():
    for name in ("math_eval", "main.o", "eval.o"):
        try:
            os.remove(os.path.join(BUILD_DIR, name))
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ["make"], cwd=BUILD_DIR, capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert os.path.isfile(BINARY), f"Binary {BINARY} does not exist"
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Makefile did not produce a compiled ELF executable"


def test_02_backend_direct_varied_evaluation_and_growth():
    rng = secrets.SystemRandom()
    for _ in range(10):
        a, b, c, d = [rng.randint(-30, 30) for _ in range(4)]
        payload = (
            f"PUSH {a}\nPUSH {b}\nMUL\n"
            f"PUSH {c}\nADD\nPUSH {d}\nMUL\nPRINT\n"
        )
        assert run_backend(payload) == str((a * b + c) * d)

    count = rng.randint(210, 330)
    values = [rng.randint(-100000, 100000) for _ in range(count)]
    payload = "".join(f"PUSH {value}\n" for value in values) + "PRINT\n"
    assert run_backend(payload) == str(values[-1])


def test_03_server_script_exists_and_is_actually_started():
    assert os.path.isfile(SERVER_SCRIPT), f"Script {SERVER_SCRIPT} does not exist"
    assert os.access(SERVER_SCRIPT, os.X_OK), f"Script {SERVER_SCRIPT} is not executable"
    with open(SERVER_SCRIPT, "rb") as f:
        first_line = f.readline().lower()
    assert first_line.startswith(b"#!") and b"bash" in first_line, "server.sh is not a Bash executable"

    stop_existing_server()
    subprocess.Popen(
        [SERVER_SCRIPT],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_for_server()

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(2.0)
        assert s.connect_ex((HOST, PORT)) == 0


def test_04_original_evaluation_and_caching_assertions():
    payload = "PUSH 5\nPUSH 7\nADD\nPUSH 2\nMUL\nPRINT\n"
    expected = "24"
    key = cache_key(payload)
    redis_delete(key)

    assert send_to_server(payload) == expected
    assert redis_get(key) == expected
    assert send_to_server(payload) == expected


def test_05_server_cache_hit_uses_md5_of_trimmed_input():
    nonce = secrets.token_hex(12)
    a = secrets.SystemRandom().randint(40, 90)
    payload = f"PUSH {a}\nPUSH 3\nADD\nPRINT\n   \t\n"
    key = cache_key(payload)
    cached = f"cached-{nonce}"
    redis_set(key, cached)
    assert send_to_server(payload, chunks=[2, 5, 1, 7]) == cached


def test_06_cache_miss_invokes_required_backend_and_stores_output():
    marker = "backend-" + secrets.token_hex(16)
    payload = f"PUSH {secrets.SystemRandom().randint(1000, 9000)}\nPRINT\n"
    key = cache_key(payload)
    redis_delete(key)
    backup = BINARY + ".verifier-backup"

    os.replace(BINARY, backup)
    try:
        with open(BINARY, "w") as f:
            f.write("#!/bin/bash\ncat >/dev/null\nprintf '%s\\n' " + marker + "\n")
        os.chmod(BINARY, 0o755)
        assert send_to_server(payload, chunks=[1, 3, 2, 4]) == marker
        assert redis_get(key) == marker
    finally:
        try:
            os.remove(BINARY)
        except FileNotFoundError:
            pass
        os.replace(backup, BINARY)


def test_07_varied_server_evaluation_and_sequential_connections():
    rng = secrets.SystemRandom()
    for _ in range(8):
        a, b, c = [rng.randint(-25, 25) for _ in range(3)]
        payload = f"PUSH {a}\nPUSH {b}\nADD\nPUSH {c}\nMUL\nPRINT\n"
        expected = str((a + b) * c)
        key = cache_key(payload)
        redis_delete(key)
        assert send_to_server(payload, chunks=[1, 2, 4, 3, 5]) == expected
        assert redis_get(key) == expected


def test_08_original_stack_overflow_assertion():
    payload_lines = [f"PUSH {i}" for i in range(200)]
    payload_lines.append("PRINT")
    payload = "\n".join(payload_lines) + "\n"
    key = cache_key(payload)
    redis_delete(key)
    assert send_to_server(payload) == "199"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
