#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import socket
import sqlite3
import subprocess
import tempfile
from pathlib import Path

import pytest
import requests

HTTP_URL = "http://127.0.0.1:8080/encode"
TCP_HOST = "127.0.0.1"
TCP_PORT = 9090
DB_PATH = "/home/user/service/data.db"
LIB_DIR = Path("/app/rle-c-1.0.0")
SERVICE_DIR = Path("/home/user/service")


def expected_rle(text):
    if not text:
        return ""
    result = []
    start = 0
    for i in range(1, len(text) + 1):
        if i == len(text) or text[i] != text[start]:
            result.append(text[start] + str(i - start))
            start = i
    return "".join(result)


def tcp_encode(text):
    with socket.create_connection((TCP_HOST, TCP_PORT), timeout=3) as sock:
        sock.settimeout(3)
        sock.sendall(text.encode("ascii") + b"\n")
        chunks = []
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
            if b"\n" in chunk:
                break
    return b"".join(chunks).decode("utf-8")


def test_http_endpoint():
    """Verify the HTTP endpoint works and handles long sequences without crashing."""
    try:
        resp1 = requests.post(HTTP_URL, json={"text": "AABBBCCCC"}, timeout=2)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP server: {e}")

    assert resp1.status_code == 200, f"Expected HTTP 200, got {resp1.status_code}"
    try:
        data1 = resp1.json()
    except json.JSONDecodeError:
        pytest.fail(f"Expected JSON response, got: {resp1.text}")

    assert "encoded" in data1, "Response JSON missing 'encoded' key"
    assert data1["encoded"] in ["2A3B4C", "A2B3C4", "A2B3C4", "2A3B4C"], f"Unexpected encoding format: {data1['encoded']}"

    try:
        resp2 = requests.post(HTTP_URL, json={"text": "AAAAAAAAAAAAAAAA"}, timeout=2)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP server for long sequence: {e}")

    assert resp2.status_code == 200, f"Expected HTTP 200, got {resp2.status_code}"
    data2 = resp2.json()
    assert "encoded" in data2, "Response JSON missing 'encoded' key"
    assert data2["encoded"] in ["16A", "A16"], f"Unexpected encoding format for long sequence: {data2['encoded']}"


def test_tcp_endpoint():
    """Verify the TCP endpoint works and returns the encoded string."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    try:
        s.connect((TCP_HOST, TCP_PORT))
        s.sendall(b"WWWWWWWWWWWW\n")
        data = s.recv(1024).decode("utf-8")
        assert data in ["12W\n", "W12\n"], f"Unexpected TCP response: {repr(data)}"
    except socket.error as e:
        pytest.fail(f"TCP connection or communication failed: {e}")
    finally:
        s.close()


def test_sqlite_database():
    """Verify the SQLite database contains the processed records."""
    assert os.path.exists(DB_PATH), f"Database not found at {DB_PATH}"

    conn = None
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT original, encoded FROM processed_data;")
        rows = cursor.fetchall()
    except sqlite3.Error as e:
        pytest.fail(f"Database query failed: {e}")
    finally:
        if conn is not None:
            conn.close()

    originals = [row[0] for row in rows]
    assert "AABBBCCCC" in originals, "Missing 'AABBBCCCC' in database"
    assert "AAAAAAAAAAAAAAAA" in originals, "Missing 'AAAAAAAAAAAAAAAA' in database"
    assert "WWWWWWWWWWWW" in originals, "Missing 'WWWWWWWWWWWW' in database"


def test_rle_c_library_built():
    """Verify the vendored C library was successfully built."""
    lib_path = "/app/rle-c-1.0.0/librle.a"
    assert os.path.exists(lib_path), f"Static library {lib_path} was not built."


def test_make_builds_real_working_archive():
    subprocess.run(["make", "clean"], cwd=LIB_DIR, check=True, timeout=20,
                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    build = subprocess.run(["make"], cwd=LIB_DIR, check=True, timeout=30,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    lib = LIB_DIR / "librle.a"
    assert lib.is_file() and lib.stat().st_size > 0, build.stdout

    members = subprocess.run(["ar", "t", str(lib)], check=True, timeout=10,
                             capture_output=True, text=True).stdout.splitlines()
    assert members, "librle.a has no object members"
    symbols = subprocess.run(["nm", "-g", str(lib)], check=True, timeout=10,
                             capture_output=True, text=True).stdout
    assert re.search(r"\b[Tt]\s+rle_encode\b", symbols), "archive does not define rle_encode"
    assert re.search(r"\b[Tt]\s+rle_free\b", symbols), "archive does not define rle_free"

    rng = random.SystemRandom()
    samples = ["", "A" * 16, "Z" * 10000, "AABBBCCCC", "AB" * 1000]
    alphabet = "ABCDEabcde012345"
    for _ in range(35):
        parts = []
        for _ in range(rng.randrange(1, 30)):
            parts.append(rng.choice(alphabet) * rng.randrange(1, 400))
        samples.append("".join(parts))

    checks = []
    for value in samples:
        checks.append(
            "check(%s, %s);" % (json.dumps(value), json.dumps(expected_rle(value)))
        )
    harness = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "rle.h"
static void check(const char *input, const char *expected) {
    char *actual = rle_encode(input);
    if (actual == NULL || strcmp(actual, expected) != 0) {
        fprintf(stderr, "bad result for input length %zu: expected %s, got %s\n",
                strlen(input), expected, actual ? actual : "(null)");
        exit(2);
    }
    rle_free(actual);
}
int main(void) {
%s
    return 0;
}
''' % "\n".join(checks)

    with tempfile.TemporaryDirectory() as td:
        source = Path(td) / "check.c"
        binary = Path(td) / "check"
        source.write_text(harness)
        subprocess.run([
            "gcc", "-std=c11", "-Wall", "-Wextra", "-fsanitize=address,undefined",
            "-fno-omit-frame-pointer", "-I", str(LIB_DIR), str(source), str(lib),
            "-o", str(binary)
        ], check=True, timeout=30, capture_output=True, text=True)
        run = subprocess.run([str(binary)], timeout=30, capture_output=True, text=True,
                             env={**os.environ, "ASAN_OPTIONS": "detect_leaks=1:halt_on_error=1"})
        assert run.returncode == 0, run.stdout + run.stderr


def test_go_cgo_wrapper_and_property_test_execute():
    main_go = SERVICE_DIR / "main.go"
    test_go = SERVICE_DIR / "rle_test.go"
    assert main_go.is_file(), "main.go is missing"
    assert test_go.is_file(), "rle_test.go is missing"

    go_files = list(SERVICE_DIR.glob("*.go"))
    non_test_sources = "\n".join(
        p.read_text(errors="replace") for p in go_files if not p.name.endswith("_test.go")
    )
    property_source = test_go.read_text(errors="replace")
    assert re.search(r'import\s+"C"', non_test_sources), "service has no cgo wrapper"
    assert "rle_encode" in non_test_sources, "cgo wrapper does not call the C encoder"
    assert "testing/quick" in property_source, "rle_test.go does not use testing/quick"
    assert re.search(r"quick\.(Check|CheckEqual)\s*\(", property_source), "property test never executes quick.Check"

    result = subprocess.run(["go", "test", "./..."], cwd=SERVICE_DIR, timeout=90,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                            env={**os.environ, "CGO_ENABLED": "1"})
    assert result.returncode == 0, result.stdout


def test_schema_and_randomized_live_requests_are_persisted():
    rng = random.SystemRandom()
    token = "Q" + "".join(rng.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(18))
    inputs = [
        token,
        token[0] * rng.randrange(1200, 2400),
        "".join(rng.choice("abcXYZ012") * rng.randrange(1, 80) for _ in range(40)),
    ]

    inserted = []
    for value in inputs:
        expected = expected_rle(value)
        response = requests.post(HTTP_URL, json={"text": value}, timeout=5)
        assert response.status_code == 200
        assert response.json() == {"encoded": expected}
        inserted.append((value, expected))

    tcp_value = token[::-1] + ("M" * rng.randrange(300, 700))
    tcp_expected = expected_rle(tcp_value)
    assert tcp_encode(tcp_value) == tcp_expected + "\n"
    inserted.append((tcp_value, tcp_expected))

    with sqlite3.connect(DB_PATH) as conn:
        columns = conn.execute("PRAGMA table_info(processed_data)").fetchall()
        assert [(c[1], c[2].upper(), c[5]) for c in columns] == [
            ("id", "INTEGER", 1), ("original", "TEXT", 0), ("encoded", "TEXT", 0)
        ]
        schema = conn.execute(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name='processed_data'"
        ).fetchone()
        assert schema and "AUTOINCREMENT" in schema[0].upper()
        for original, encoded in inserted:
            row = conn.execute(
                "SELECT encoded FROM processed_data WHERE original=? ORDER BY id DESC LIMIT 1",
                (original,)
            ).fetchone()
            assert row == (encoded,), f"request was not correctly persisted: {original[:40]!r}"


def listening_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])
    pids = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                target = os.readlink(fd)
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(proc.name))
        except (OSError, PermissionError):
            pass
    return pids


def test_active_listeners_are_go_programs():
    for port in (8080, 9090):
        pids = listening_pids(port)
        assert pids, f"no listening process found on port {port}"
        found_go = False
        diagnostics = []
        for pid in pids:
            exe = f"/proc/{pid}/exe"
            result = subprocess.run(["go", "version", "-m", exe], timeout=10,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            diagnostics.append(result.stdout)
            if result.returncode == 0 and re.search(r"\bgo1\d+\.", result.stdout):
                found_go = True
        assert found_go, f"listener on port {port} is not a Go executable: {diagnostics}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
