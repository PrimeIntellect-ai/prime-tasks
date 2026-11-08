#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import hashlib
import os
import random
import socket
import string
import subprocess
import tempfile
import time

import pytest

ROOT = "/app/minilogd-1.0"
BINARY = os.path.join(ROOT, "minilogd")
LIBAUTH = os.path.join(ROOT, "lib/libauth.so")
TOKEN_FILE = "/home/user/admin_token.txt"
TOKEN = "s3cr3t_0ps_t0k3n_99"


def compile_cmd(args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert result.returncode == 0, result.stderr


def http_request(query, token, timeout=5.0):
    request = (
        f"GET /query?q={query} HTTP/1.1\r\n"
        "Host: 127.0.0.1:8081\r\n"
        f"Authorization: Bearer {token}\r\n"
        "Connection: close\r\n\r\n"
    ).encode("ascii")
    with socket.create_connection(("127.0.0.1", 8081), timeout=timeout) as sock:
        sock.settimeout(timeout)
        sock.sendall(request)
        chunks = []
        while True:
            data = sock.recv(4096)
            if not data:
                break
            chunks.append(data)
    raw = b"".join(chunks).decode("utf-8", errors="replace")
    status_line = raw.split("\r\n", 1)[0]
    parts = status_line.split()
    assert len(parts) >= 2 and parts[1].isdigit(), f"Malformed HTTP response: {raw!r}"
    body = raw.split("\r\n\r\n", 1)[1] if "\r\n\r\n" in raw else ""
    return int(parts[1]), body


def ingest(record):
    with socket.create_connection(("127.0.0.1", 8080), timeout=5.0) as sock:
        sock.sendall(record.encode("utf-8"))


def running_project_pids():
    expected = os.path.realpath(BINARY)
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            if os.path.realpath(f"/proc/{entry}/exe") == expected:
                found.append(entry)
        except OSError:
            pass
    return found


def test_admin_token_file():
    assert os.path.isfile(TOKEN_FILE), f"File {TOKEN_FILE} does not exist."
    with open(TOKEN_FILE, "r") as f:
        content = f.read().strip()
    assert content == TOKEN, f"Token file content is incorrect: {content}"


def test_libauth_is_original_and_used():
    assert os.path.isfile(LIBAUTH) and not os.path.islink(LIBAUTH)
    with tempfile.TemporaryDirectory() as td:
        source = os.path.join(td, "auth.c")
        expected = os.path.join(td, "libauth.so")
        with open(source, "w") as f:
            f.write('#include <string.h>\nint validate_token(const char* token) {\n    return strcmp(token, "s3cr3t_0ps_t0k3n_99") == 0;\n}\n')
        compile_cmd(["gcc", "-shared", "-fPIC", "-o", expected, source])
        actual_hash = hashlib.sha256(open(LIBAUTH, "rb").read()).digest()
        expected_hash = hashlib.sha256(open(expected, "rb").read()).digest()
        assert actual_hash == expected_hash, "lib/libauth.so was modified"

    auth = ctypes.CDLL(LIBAUTH)
    auth.validate_token.argtypes = [ctypes.c_char_p]
    auth.validate_token.restype = ctypes.c_int
    assert auth.validate_token(TOKEN.encode()) == 1
    for _ in range(8):
        bad = ("bad_" + os.urandom(12).hex()).encode()
        assert auth.validate_token(bad) == 0

    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)
    dynamic = subprocess.check_output(["readelf", "-d", BINARY], text=True)
    assert "libauth.so" in dynamic, "minilogd is not dynamically linked to libauth.so"

    pids = running_project_pids()
    assert pids, "The project minilogd executable is not running"
    expected_lib = os.path.realpath(LIBAUTH)
    assert any(
        expected_lib in open(f"/proc/{pid}/maps", errors="replace").read()
        for pid in pids
    ), "The running minilogd process has not loaded the supplied libauth.so"


def test_query_parser_terminates_on_nested_inputs():
    assert os.path.isfile(os.path.join(ROOT, "src/query.c"))
    with tempfile.TemporaryDirectory() as td:
        harness = os.path.join(td, "query_harness.c")
        executable = os.path.join(td, "query_harness")
        with open(harness, "w") as f:
            f.write(r'''#include <stdio.h>
#include <string.h>
void parse_expr(const char*);
int main(void) {
    char line[8192];
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n")] = 0;
        parse_expr(line);
    }
    return 0;
}
''')
        compile_cmd(["gcc", "-O0", "-o", executable, harness, os.path.join(ROOT, "src/query.c")])
        rng = random.SystemRandom()
        expressions = [
            "(level=ERROR)",
            "(level=ERROR AND (app=frontend OR app=backend))",
            "(" * 300 + "level=INFO" + ")" * 300,
        ]
        for _ in range(30):
            depth = rng.randint(2, 80)
            expressions.append("(" * depth + "level=" + rng.choice(["ERROR", "INFO", "WARN", "DEBUG"]) + ")" * depth)
        try:
            result = subprocess.run(
                [executable], input="\n".join(expressions) + "\n",
                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3
            )
        except subprocess.TimeoutExpired:
            pytest.fail("query parser hung on a nested-parentheses input")
        assert result.returncode == 0, result.stderr


def test_db_strict_level_matching():
    assert os.path.isfile(os.path.join(ROOT, "src/db.c"))
    with tempfile.TemporaryDirectory() as td:
        shared = os.path.join(td, "db_under_test.so")
        compile_cmd(["gcc", "-shared", "-fPIC", "-o", shared, os.path.join(ROOT, "src/db.c")])
        db = ctypes.CDLL(shared)
        db.add_log.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p]
        db.match_log.argtypes = [ctypes.c_int, ctypes.c_char_p]
        db.match_log.restype = ctypes.c_int
        count = ctypes.c_int.in_dll(db, "log_count")
        count.value = 0

        rng = random.SystemRandom()
        levels = ["ERROR", "INFO", "WARN", "DEBUG", "TRACE"]
        rng.shuffle(levels)
        for i, level in enumerate(levels):
            db.add_log(level.encode(), f"app{i}".encode(), os.urandom(8).hex().encode())
        for i, stored in enumerate(levels):
            for requested in levels:
                expected = 1 if stored == requested else 0
                actual = db.match_log(i, requested.encode())
                assert actual == expected, f"match_log({stored!r}, {requested!r}) returned {actual}"


def test_minilogd_service_and_logic():
    # Preserve the original fixed behavioral assertions, but send each record on
    # its own connection because the supplied ingest worker handles one record per connection.
    fixed_logs = [
        "[ERROR] app=frontend msg=Connection timeout\n",
        "[INFO] app=backend msg=Started worker\n",
        "[ERROR] app=database msg=Disk full\n",
    ]
    for record in fixed_logs:
        ingest(record)
    time.sleep(0.25)

    status, response_text = http_request("(level=ERROR)", TOKEN)
    assert status == 200, f"Expected HTTP 200 OK, got {status}. Response: {response_text}"
    assert "app=frontend" in response_text and "Connection timeout" in response_text
    assert "app=database" in response_text and "Disk full" in response_text
    assert "app=backend" not in response_text and "Started worker" not in response_text

    # Exercise authentication with unpredictable invalid credentials.
    for _ in range(5):
        bad_token = "invalid_" + os.urandom(16).hex()
        bad_status, _ = http_request("(level=ERROR)", bad_token)
        assert bad_status == 401, f"Invalid bearer token was accepted: {bad_token}"

    # Derive fresh records and expected results at verification time and query
    # several levels, including a nested-parentheses request.
    suffix = ''.join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(14))
    generated = []
    for i, level in enumerate(["ERROR", "INFO", "WARN", "DEBUG", "ERROR", "INFO"]):
        app = f"audit_{suffix}_{i}"
        msg = f"nonce_{os.urandom(12).hex()}"
        generated.append((level, app, msg))
        ingest(f"[{level}] app={app} msg={msg}\n")
    time.sleep(0.3)

    for level in ["ERROR", "INFO", "WARN", "DEBUG"]:
        query = f"((level={level}))" if level == "ERROR" else f"(level={level})"
        status, body = http_request(query, TOKEN)
        assert status == 200
        for stored_level, app, msg in generated:
            if stored_level == level:
                assert app in body and msg in body, f"Missing generated {level} record"
            else:
                assert app not in body and msg not in body, f"{stored_level} record leaked into {level} results"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
