#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import signal
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.request
from fractions import Fraction

import pytest

APP_DIR = "/home/user/app"
C_DIR = os.path.join(APP_DIR, "c_eval")
CLEAN_DIR = os.path.join(APP_DIR, "corpora", "clean")
EVIL_DIR = os.path.join(APP_DIR, "corpora", "evil")
SUCCESS_LOG = os.path.join(APP_DIR, "success.log")
EVAL_URL = "http://localhost:8080/eval"


def request(expr, timeout=5):
    req = urllib.request.Request(EVAL_URL, data=expr.encode(), method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status, response.read().decode().strip()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode(errors="replace").strip()


def wait_port(port, listening=True, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                up = True
        except OSError:
            up = False
        if up == listening:
            return
        time.sleep(0.05)
    raise AssertionError(f"port {port} did not reach expected state listening={listening}")


def listener_pid(port):
    wanted = set()
    port_hex = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if fields[1].split(":")[-1].upper() == port_hex and fields[3] == "0A":
                wanted.add(fields[9])
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
                if target.startswith("socket:[") and target[8:-1] in wanted:
                    return int(entry)
        except OSError:
            pass
    return None


def stop_listener(port):
    pid = listener_pid(port)
    assert pid is not None, f"nothing is listening on port {port}"
    os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 3
    while time.time() < deadline:
        if listener_pid(port) is None:
            return pid
        time.sleep(0.05)
    os.kill(pid, signal.SIGKILL)
    wait_port(port, listening=False)
    return pid


def start_real_backend():
    proc = subprocess.Popen(
        [os.path.join(C_DIR, "eval_server")],
        cwd=C_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        env={k: v for k, v in os.environ.items() if k != "LD_LIBRARY_PATH"},
    )
    wait_port(8081)
    assert proc.poll() is None, "the freshly built eval_server exited"
    return proc


def assert_numeric_result(body, expected):
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)", body), \
        f"response is not a numeric evaluated result: {body!r}"
    assert Fraction(body) == expected, f"expected {expected}, got {body!r}"


def test_01_success_log_exists():
    assert os.path.isfile(SUCCESS_LOG), f"Expected success log at {SUCCESS_LOG} is missing."
    with open(SUCCESS_LOG) as f:
        content = f.read()
    assert "READY" in content, f"Expected 'READY' in {SUCCESS_LOG}, but found: {content}"


def test_02_original_adversarial_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.expr"))
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.expr"))
    assert clean_files, f"No clean corpus files found in {CLEAN_DIR}"
    assert evil_files, f"No evil corpus files found in {EVIL_DIR}"

    clean_failures = []
    for filepath in clean_files:
        status, _ = request(open(filepath).read())
        if status != 200:
            clean_failures.append(os.path.basename(filepath))

    evil_failures = []
    for filepath in evil_files:
        status, _ = request(open(filepath).read())
        if status != 400:
            evil_failures.append(os.path.basename(filepath))

    errors = []
    if clean_failures:
        errors.append(f"{len(clean_failures)} clean expressions failed: {', '.join(clean_failures)}")
    if evil_failures:
        errors.append(f"{len(evil_failures)} evil expressions bypassed: {', '.join(evil_failures)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_03_backend_build_linkage_and_services():
    built = subprocess.run(
        ["make", "-B"], cwd=C_DIR, text=True, capture_output=True, timeout=30
    )
    assert built.returncode == 0, f"make failed:\n{built.stdout}\n{built.stderr}"
    executable = os.path.join(C_DIR, "eval_server")
    library = os.path.join(C_DIR, "libmatheval.so")
    assert os.path.isfile(executable) and os.access(executable, os.X_OK)
    assert os.path.isfile(library)

    linked = subprocess.run(["ldd", executable], text=True, capture_output=True, timeout=10)
    assert linked.returncode == 0, linked.stderr
    assert "libmatheval.so" in linked.stdout, "eval_server is not linked to libmatheval.so"
    assert "libmatheval.so => not found" not in linked.stdout, linked.stdout

    pong = subprocess.run(["redis-cli", "-h", "127.0.0.1", "PING"], text=True,
                          capture_output=True, timeout=5)
    assert pong.returncode == 0 and pong.stdout.strip() == "PONG", "Redis is not running on port 6379"

    # Replace any stale pre-build process and execute the artifact just produced,
    # with no LD_LIBRARY_PATH assistance.
    stop_listener(8081)
    proc = start_real_backend()
    pid = listener_pid(8081)
    assert pid == proc.pid
    assert os.path.realpath(f"/proc/{pid}/exe") == os.path.realpath(executable)


def test_04_general_sanitizer_and_evaluated_results():
    rng = random.SystemRandom()
    valid = []
    for _ in range(10):
        a, b, c = (rng.randint(2, 40) for _ in range(3))
        if rng.randrange(2):
            valid.append((f"(({a} + {b}) * {c})", Fraction((a + b) * c)))
        else:
            valid.append((f"(({a} * {b}) / {b})", Fraction(a)))

    for expr, expected in valid:
        status, body = request(expr)
        assert status == 200, f"valid expression rejected: {expr!r}"
        assert_numeric_result(body, expected)

    n = rng.randint(50, 500)
    invalid = [
        f"9 / ({n} - {n})",
        "2 / (3 - (1 + 2))",
        f"unknown{rng.randint(1000,9999)} + 1",
        "((7 + 2)",
        "7 + 2)",
        "3 $ 4",
        "2 3",
        "()",
        "1 +",
        "3 */ 2",
    ]
    for expr in invalid:
        status, _ = request(expr)
        assert status == 400, f"invalid expression was accepted: {expr!r}"


def test_05_gateway_uses_redis_and_c_backend():
    flushed = subprocess.run(["redis-cli", "FLUSHDB"], text=True, capture_output=True, timeout=5)
    assert flushed.returncode == 0 and flushed.stdout.strip() == "OK"

    rng = random.SystemRandom()
    expr = f"({rng.randint(100000, 900000)} + {rng.randint(1000, 9000)})"
    status, _ = request(expr)
    assert status == 200
    dbsize = subprocess.run(["redis-cli", "DBSIZE"], text=True, capture_output=True, timeout=5)
    assert dbsize.returncode == 0 and int(dbsize.stdout.strip()) > 0, \
        "gateway request did not populate the Redis cache"

    # Substitute a one-shot backend returning a verifier-chosen nonce. The
    # gateway must relay that backend response rather than calculate or hardcode locally.
    stop_listener(8081)
    nonce = str(rng.randint(700001, 900000))
    probe_expr = f"({rng.randint(20000, 40000)} + {rng.randint(20000, 40000)})"
    subprocess.run(["redis-cli", "FLUSHDB"], capture_output=True, timeout=5)
    received = []
    ready = threading.Event()
    done = threading.Event()

    def fake_backend():
        srv = socket.socket()
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("127.0.0.1", 8081))
        srv.listen(5)
        srv.settimeout(5)
        ready.set()
        try:
            conn, _ = srv.accept()
            conn.settimeout(1)
            data = b""
            while True:
                try:
                    chunk = conn.recv(4096)
                except socket.timeout:
                    break
                if not chunk:
                    break
                data += chunk
                if b"\r\n\r\n" in data:
                    head, body = data.split(b"\r\n\r\n", 1)
                    match = re.search(br"(?i)content-length:\s*(\d+)", head)
                    if not match or len(body) >= int(match.group(1)):
                        break
            received.append(data)
            response = ("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: "
                        + str(len(nonce)) + "\r\nConnection: close\r\n\r\n" + nonce)
            conn.sendall(response.encode())
            conn.close()
        finally:
            srv.close()
            done.set()

    thread = threading.Thread(target=fake_backend, daemon=True)
    thread.start()
    ready.wait(2)
    try:
        status, body = request(probe_expr)
        assert status == 200
        assert body == nonce, f"gateway did not return the C backend's response; got {body!r}"
        done.wait(3)
        assert received and probe_expr.encode() in received[0], \
            "gateway did not send the requested expression to the C backend"
    finally:
        done.wait(1)
        if listener_pid(8081) is not None:
            stop_listener(8081)
        start_real_backend()

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
