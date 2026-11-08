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
import math
import os
import random
import sqlite3
import string
import subprocess
import time

import pytest
import requests

LIB_DIR = "/app/vendored/libjsonparse-1.2"
LIB_PATH = f"{LIB_DIR}/libjsonparse.a"
DB_PATH = "/home/user/analytics.db"
BASE_URL = "http://127.0.0.1:8080"


def post(path, data=None, timeout=10):
    try:
        return requests.post(f"{BASE_URL}{path}", data=data, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Request to POST {path} failed: {exc}")


def get(path, timeout=10):
    try:
        return requests.get(f"{BASE_URL}{path}", timeout=timeout)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Request to GET {path} failed: {exc}")


def read_average():
    response = get("/rolling_stats")
    assert response.status_code == 200, \
        f"Expected HTTP 200 for GET /rolling_stats, got {response.status_code}"
    try:
        value = response.json()
    except (ValueError, json.JSONDecodeError):
        pytest.fail(f"Invalid JSON returned by /rolling_stats: {response.text!r}")
    assert isinstance(value, dict), "Rolling statistics response must be a JSON object"
    assert set(value) == {"rolling_avg"}, \
        f"Rolling statistics response has unexpected fields: {value!r}"
    return float(value["rolling_avg"])


def find_listener_pid(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle)
                for line in handle:
                    fields = line.split()
                    local_port = int(fields[1].split(":")[1], 16)
                    if local_port == port and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

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
                    return int(entry)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return None


def test_libjsonparse_compiled_and_executable():
    """Retain the compilation assertion and exercise the repaired archive."""
    assert os.path.isfile(LIB_PATH), f"Library {LIB_PATH} was not compiled."

    make = subprocess.run(
        ["make", "clean", "all"], cwd=LIB_DIR,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert make.returncode == 0, f"The vendored Makefile cannot build the library:\n{make.stdout}"
    assert os.path.isfile(LIB_PATH), f"Library {LIB_PATH} was not produced by make."

    archive = subprocess.run(
        ["ar", "t", LIB_PATH], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert archive.returncode == 0 and "decoder.o" in archive.stdout, \
        f"libjsonparse.a is not a valid archive containing decoder.o: {archive.stderr}"

    source = r'''#include "jsonparse.h"
#include <exception>
#include <string>
int main() {
    try {
        jsonparse::parse(R"({"event_name":"caf\u00e9_\u00f1","other":"\u03bb"})");
        jsonparse::parse(R"({"event_name":"emoji_\uD83D\uDE03"})");
    } catch (...) {
        return 9;
    }
    return 0;
}
'''
    with open("/tmp/parser_probe.cpp", "w") as handle:
        handle.write(source)
    build = subprocess.run(
        ["g++", "-std=c++17", f"-I{LIB_DIR}/include", "/tmp/parser_probe.cpp",
         LIB_PATH, "-o", "/tmp/parser_probe"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
    )
    assert build.returncode == 0, f"Could not link against libjsonparse.a:\n{build.stdout}"
    run = subprocess.run(["/tmp/parser_probe"], timeout=10)
    assert run.returncode == 0, \
        "The compiled parser still throws or crashes on standard Unicode escapes"


def test_http_service_uses_library_and_full_workflow():
    # Verify that the process actually serving port 8080 is a native executable
    # linked with the vendored parser symbol, rather than an unrelated fake server.
    pid = find_listener_pid(8080)
    assert pid is not None, "No process is listening on port 8080"
    exe_path = f"/proc/{pid}/exe"
    assert os.path.exists(exe_path), "Could not inspect the HTTP server executable"
    nm = subprocess.run(
        ["nm", "-C", exe_path], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15
    )
    try:
        with open(exe_path, "rb") as handle:
            exe_bytes = handle.read()
    except OSError:
        exe_bytes = b""
    assert ("jsonparse::parse" in nm.stdout or b"_ZN9jsonparse5parse" in exe_bytes), \
        "The executable serving port 8080 does not contain the libjsonparse parse symbol"

    # Prevent a pre-created database from satisfying the export checks.
    if os.path.isfile(DB_PATH):
        conn = sqlite3.connect(DB_PATH)
        try:
            table = conn.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name='events'"
            ).fetchone()
            if table:
                conn.execute("DELETE FROM events")
                conn.commit()
        finally:
            conn.close()

    # Retain the original fixed workflow and assertions.
    original_payload = (
        '{"timestamp": 1, "value": 10.0, "event_name": "test1"}\n'
        '{"timestamp": 2, "value": 20.0, "event_name": "test\\u00e9"}\n'
        '{"timestamp": 3, "value": 30.0, "event_name": "test\\u00f1"}\n'
    )
    response = post("/ingest", original_payload)
    assert response.status_code in (200, 201, 202, 204), \
        f"Expected successful status code for POST /ingest, got {response.status_code}"
    assert read_average() == 20.0, "Expected rolling_avg to be 20.0"

    response = post("/export")
    assert response.status_code == 200, \
        f"Expected HTTP 200 for POST /export, got {response.status_code}"
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} was not created."

    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            "SELECT timestamp, value, event_name FROM events ORDER BY timestamp"
        ).fetchall()
        assert rows == [(1, 10.0, "test1"), (2, 20.0, "testé"), (3, 30.0, "testñ")], \
            f"Export did not contain exactly the originally ingested records: {rows!r}"
        count = conn.execute(
            "SELECT COUNT(*) FROM events WHERE event_name LIKE '%é%' OR event_name LIKE '%ñ%'"
        ).fetchone()[0]
        assert count >= 2, \
            f"Expected at least 2 events with unicode characters in the database, found {count}."
    finally:
        conn.close()

    # Exercise parsing, a rolling window exceeding ten records, Unicode decoding,
    # and a large export using values generated only after the agent has finished.
    nonce = random.SystemRandom().randrange(10**12, 8 * 10**12)
    token = "".join(random.SystemRandom().choice(string.ascii_letters) for _ in range(18))
    records = []
    lines = []
    for index in range(137):
        timestamp = nonce + index
        value = ((index * 7919 + nonce % 10007) % 200000 - 100000) / 37.0
        if index % 3 == 0:
            encoded_name = f"{token}_{index}_caf\\u00e9"
            decoded_name = f"{token}_{index}_café"
        elif index % 3 == 1:
            encoded_name = f"{token}_{index}_jalape\\u00f1o"
            decoded_name = f"{token}_{index}_jalapeño"
        else:
            encoded_name = f"{token}_{index}_λ"
            decoded_name = f"{token}_{index}_λ"
        lines.append(json.dumps(
            {"timestamp": timestamp, "value": value, "event_name": encoded_name},
            ensure_ascii=False
        ).replace("\\\\u", "\\u"))
        records.append((timestamp, value, decoded_name))

    response = post("/ingest", "\n".join(lines) + "\n", timeout=20)
    assert response.status_code in (200, 201, 202, 204), \
        f"Bulk ingest failed with status {response.status_code}: {response.text!r}"
    expected = sum(row[1] for row in records[-10:]) / 10.0
    assert math.isclose(read_average(), expected, rel_tol=1e-9, abs_tol=1e-9), \
        "Rolling average was not computed from the last ten dynamically generated records"

    # Malformed lines must not enter the successful-record window, while a following
    # valid UTF-8/escaped-Unicode record must still be accepted.
    tail = (nonce + 500, -1234.875, f"{token}_final_é雪")
    mixed_payload = (
        '{not-json}\n'
        '{"timestamp":"broken","value":oops,"event_name":"bad"}\n'
        + json.dumps(
            {"timestamp": tail[0], "value": tail[1], "event_name": f"{token}_final_\\u00e9雪"},
            ensure_ascii=False
        ).replace("\\\\u", "\\u") + "\n"
    )
    response = post("/ingest", mixed_payload)
    assert response.status_code in (200, 201, 202, 204), \
        f"Mixed ingest failed with status {response.status_code}"
    expected_tail_avg = (sum(row[1] for row in records[-9:]) + tail[1]) / 10.0
    assert math.isclose(read_average(), expected_tail_avg, rel_tol=1e-9, abs_tol=1e-9), \
        "Malformed lines affected the rolling window or the final valid record was ignored"

    response = post("/export", timeout=20)
    assert response.status_code == 200, \
        f"Expected HTTP 200 for POST /export, got {response.status_code}"

    expected_rows = records + [tail]
    conn = sqlite3.connect(DB_PATH)
    try:
        actual = conn.execute(
            "SELECT timestamp, value, event_name FROM events "
            "WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp",
            (nonce, nonce + 500)
        ).fetchall()
        assert len(actual) == len(expected_rows), \
            f"Expected {len(expected_rows)} dynamically ingested rows, found {len(actual)}"
        for got, wanted in zip(actual, expected_rows):
            assert got[0] == wanted[0]
            assert math.isclose(float(got[1]), wanted[1], rel_tol=1e-12, abs_tol=1e-12)
            assert got[2] == wanted[2], f"Exported event name differs: {got[2]!r} != {wanted[2]!r}"
    finally:
        conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
