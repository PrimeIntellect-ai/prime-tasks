#!/bin/bash
set -e
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import pwd
import random
import re
import secrets
import shutil
import socket
import subprocess
import time

BASE_DIR = "/home/user/auth_service"
LOG_FILE = os.path.join(BASE_DIR, "auth.log")
MAKEFILE = os.path.join(BASE_DIR, "Makefile")
MAIN_C = os.path.join(BASE_DIR, "main.c")
DS_C = os.path.join(BASE_DIR, "ds.c")
MATH_C = os.path.join(BASE_DIR, "math_utils.c")
NGINX_CONF = os.path.join(BASE_DIR, "nginx.conf")
BINARY = os.path.join(BASE_DIR, "auth_server")


def run(cmd, **kwargs):
    kwargs.setdefault("cwd", BASE_DIR)
    kwargs.setdefault("text", True)
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("timeout", 20)
    result = subprocess.run(cmd, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {' '.join(cmd)}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def variance(token):
    if not token:
        return 0.0
    values = [ord(c) for c in token]
    mean = sum(values) / len(values)
    return sum((v - mean) ** 2 for v in values) / len(values)


def user_preexec():
    account = pwd.getpwnam("user")
    def demote():
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)
    return demote


def test_build_and_original_file_assertions():
    assert os.path.isfile(MAKEFILE), f"Makefile {MAKEFILE} is missing."
    assert os.path.isfile(MAIN_C), f"main.c {MAIN_C} is missing."
    assert os.path.isfile(NGINX_CONF), f"nginx.conf {NGINX_CONF} is missing."

    with open(MAKEFILE) as f:
        make_content = f.read()
    assert "ds.o" in make_content, "Makefile does not link ds.o."
    assert "-lm" in make_content, "Makefile does not link the math library (-lm)."

    with open(MAIN_C) as f:
        main_content = f.read()
    match = re.search(r"char\s+token\[(\d+)\];", main_content)
    if match:
        assert int(match.group(1)) >= 128, "The token buffer is still too small."
    else:
        assert "char token[16];" not in main_content, "The vulnerable token buffer remains."

    with open(NGINX_CONF) as f:
        nginx_content = f.read()
    assert "proxy_pass" in nginx_content, "nginx.conf lacks proxy_pass."
    assert "9000" in nginx_content, "nginx.conf does not reference backend port 9000."

    run(["make", "clean"])
    run(["make"])
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "auth_server was not built."


def test_math_and_hash_set_behavior():
    library = "/tmp/libauth_submission.so"
    run(["gcc", "-shared", "-fPIC", "-Wall", "-Werror", "-o", library,
         DS_C, MATH_C, "-lm"])
    lib = ctypes.CDLL(library)
    lib.compute_token_variance.argtypes = [ctypes.c_char_p]
    lib.compute_token_variance.restype = ctypes.c_double
    lib.init_set.argtypes = []
    lib.init_set.restype = None
    lib.insert_and_check.argtypes = [ctypes.c_char_p]
    lib.insert_and_check.restype = ctypes.c_int

    samples = ["", "A", "AB", "SECRET123", "Token-" + secrets.token_hex(12)]
    rng = random.Random(int.from_bytes(os.urandom(8), "big"))
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    samples.extend("".join(rng.choice(alphabet) for _ in range(n)) for n in (3, 17, 63, 120))
    for token in samples:
        actual = lib.compute_token_variance(token.encode())
        assert math.isclose(actual, variance(token), rel_tol=1e-10, abs_tol=1e-10), (
            f"Incorrect variance for {token!r}: {actual}"
        )

    lib.init_set()
    # AB and BA deliberately have the same sum hash and require linear probing.
    for token in (b"AB", b"BA", b"CC", b"unique-token"):
        assert lib.insert_and_check(token) == 0, f"First insertion of {token!r} was called a replay."
    for token in (b"BA", b"AB", b"unique-token", b"CC"):
        assert lib.insert_and_check(token) == 1, f"Replay of {token!r} was not detected."
    lib.init_set()
    assert lib.insert_and_check(b"AB") == 0, "init_set did not clear the set."


def test_process_request_is_bounded_under_asan():
    harness = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
extern void process_request(const char *, FILE *);
extern void init_set(void);
int main(void) {
    FILE *f = fopen("/tmp/process_request.log", "w+");
    if (!f) return 2;
    char a[129]; memset(a, 'A', 128); a[128] = 0;
    char b[301]; memset(b, 'B', 300); b[300] = 0;
    char p1[512], p2[700];
    snprintf(p1, sizeof(p1), "POST / HTTP/1.1\r\nX-API-Token: %s\r\n\r\n", a);
    snprintf(p2, sizeof(p2), "POST / HTTP/1.1\r\nX-API-Token: %s\r\n\r\n", b);
    init_set();
    process_request(p1, f);
    process_request(p2, f);
    fclose(f);
    return 0;
}
'''
    with open("/tmp/process_harness.c", "w") as f:
        f.write(harness)
    run(["gcc", "-fsanitize=address", "-fno-omit-frame-pointer", "-g",
         "-Dmain=auth_server_program_main", "-c", MAIN_C, "-o", "/tmp/main_asan.o"])
    run(["gcc", "-fsanitize=address", "-fno-omit-frame-pointer", "-g",
         "/tmp/process_harness.c", "/tmp/main_asan.o", DS_C, MATH_C,
         "-lm", "-o", "/tmp/process_harness"])
    result = subprocess.run(
        ["/tmp/process_harness"], text=True, capture_output=True, timeout=15,
        env={**os.environ, "ASAN_OPTIONS": "detect_leaks=0:halt_on_error=1"}
    )
    assert result.returncode == 0, f"process_request is not memory-safe:\n{result.stderr}"
    with open("/tmp/process_request.log") as f:
        lines = f.readlines()
    assert len(lines) == 2, "process_request did not process both long-token requests."
    logged = []
    for line in lines:
        match = re.match(r"Token: (.*), Variance:", line.rstrip("\n"))
        assert match, f"Malformed process_request output: {line!r}"
        logged.append(match.group(1))
    assert logged[0] == "A" * 128, "A 128-character token was not handled intact."
    assert logged[1] == "B" * 128, "An oversized token was not gracefully truncated to 128 characters."


def raw_post(token):
    request = (
        "POST /api/auth HTTP/1.1\r\n"
        "Host: 127.0.0.1:8080\r\n"
        f"X-API-Token: {token}\r\n"
        "Content-Length: 0\r\n"
        "Connection: close\r\n\r\n"
    ).encode()
    with socket.create_connection(("127.0.0.1", 8080), timeout=3) as sock:
        sock.sendall(request)
        chunks = []
        while True:
            data = sock.recv(4096)
            if not data:
                break
            chunks.append(data)
    response = b"".join(chunks)
    assert response.startswith(b"HTTP/1.1 200"), f"Unexpected proxy response: {response[:200]!r}"


def test_live_backend_and_nginx_proxy_integration():
    subprocess.run(["pkill", "-x", "auth_server"], capture_output=True)
    subprocess.run(["pkill", "-x", "nginx"], capture_output=True)
    time.sleep(0.5)

    for path in (LOG_FILE, os.path.join(BASE_DIR, "logs/access.log"),
                 os.path.join(BASE_DIR, "logs/error.log"), os.path.join(BASE_DIR, "temp/nginx.pid")):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    backend_output = open("/tmp/auth_server.verify.out", "w")
    backend = subprocess.Popen([BINARY], cwd=BASE_DIR, stdout=backend_output,
                               stderr=subprocess.STDOUT, preexec_fn=user_preexec())

    nginx = shutil.which("nginx")
    assert nginx, "nginx is not installed."
    check = subprocess.run([nginx, "-t", "-c", NGINX_CONF, "-p", BASE_DIR + "/"],
                           text=True, capture_output=True, timeout=10,
                           preexec_fn=user_preexec())
    assert check.returncode == 0, f"Invalid nginx configuration:\n{check.stdout}\n{check.stderr}"
    start = subprocess.run([nginx, "-c", NGINX_CONF, "-p", BASE_DIR + "/"],
                           text=True, capture_output=True, timeout=10,
                           preexec_fn=user_preexec())
    assert start.returncode == 0, f"Nginx failed to start:\n{start.stdout}\n{start.stderr}"

    deadline = time.time() + 8
    while True:
        if backend.poll() is not None:
            raise AssertionError("auth_server exited before requests were sent.")
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.25):
                break
        except OSError:
            if time.time() >= deadline:
                raise AssertionError("Nginx did not begin listening on port 8080.")
            time.sleep(0.1)

    generated = "VERIFY_" + secrets.token_hex(10)
    for token in ("SECRET123", "SECRET123", generated, generated):
        raw_post(token)

    time.sleep(0.5)
    assert backend.poll() is None, "auth_server stopped during integration testing."
    pid_file = os.path.join(BASE_DIR, "temp/nginx.pid")
    assert os.path.isfile(pid_file), "Nginx pid file was not created."
    with open(pid_file) as f:
        nginx_pid = int(f.read().strip())
    os.kill(nginx_pid, 0)

    with open(LOG_FILE) as f:
        content = f.read()
    for token in ("SECRET123", generated):
        expected = f"{variance(token):.2f}"
        first = rf"Token:\s*{re.escape(token)},\s*Variance:\s*{re.escape(expected)},\s*Replay:\s*0"
        replay = rf"Token:\s*{re.escape(token)},\s*Variance:\s*{re.escape(expected)},\s*Replay:\s*1"
        assert re.search(first, content), f"First live request for {token!r} was not logged correctly."
        assert re.search(replay, content), f"Live replay for {token!r} was not detected."

    access_log = os.path.join(BASE_DIR, "logs/access.log")
    assert os.path.isfile(access_log), "Nginx did not create its access log."
    with open(access_log) as f:
        access = f.read()
    assert access.count("POST /api/auth") >= 4, "Requests were not observed traversing Nginx."

    account = pwd.getpwnam("user")
    with open(f"/proc/{backend.pid}/status") as f:
        assert re.search(rf"^Uid:\s+{account.pw_uid}\s", f.read(), re.MULTILINE), "Backend is not running as user."
    with open(f"/proc/{nginx_pid}/status") as f:
        assert re.search(rf"^Uid:\s+{account.pw_uid}\s", f.read(), re.MULTILINE), "Nginx is not running as user."


def test_auth_log_exists_and_correct():
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} is missing."
    with open(LOG_FILE) as f:
        content = f.read()
    expected_variance = f"{variance('SECRET123'):.2f}"
    expected_first = rf"Token:\s*SECRET123,\s*Variance:\s*{re.escape(expected_variance)},\s*Replay:\s*0"
    expected_replay = rf"Token:\s*SECRET123,\s*Variance:\s*{re.escape(expected_variance)},\s*Replay:\s*1"
    assert re.search(expected_first, content), "The first SECRET123 request was not logged correctly."
    assert re.search(expected_replay, content), "The SECRET123 replay was not detected."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
