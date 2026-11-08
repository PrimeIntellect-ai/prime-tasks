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
import re
import shutil
import sqlite3
import subprocess
import tempfile
import time
from pathlib import Path

import pytest
import requests

SQL_PATH = "/home/user/optimized_graph.sql"
DB_PATH = "/home/user/backups.db"
VIDEO_PATH = "/app/backup_run.mp4"
URL = "http://127.0.0.1:9090/impacted_backups"


def read_sql():
    assert os.path.isfile(SQL_PATH), f"Optimized SQL file {SQL_PATH} is missing."
    content = Path(SQL_PATH).read_text().strip()
    assert content, f"SQL file {SQL_PATH} is empty."
    return content


def normalize_ids(rows):
    assert all(len(row) == 1 for row in rows), "SQL query must return one job_id column."
    values = [row[0] for row in rows]
    assert all(isinstance(value, int) for value in values), "SQL results must be integer job_ids."
    return sorted(values)


def downstream(edges, seeds):
    adjacency = {}
    for source, target in edges:
        adjacency.setdefault(source, []).append(target)
    seen = set(seeds)
    result = set()
    stack = list(seeds)
    while stack:
        source = stack.pop()
        for target in adjacency.get(source, []):
            if target not in seen:
                seen.add(target)
                result.add(target)
                stack.append(target)
    return sorted(result)


def execute_sql_on_graph(sql, node_ids, edges):
    conn = sqlite3.connect(":memory:")
    try:
        conn.execute("CREATE TABLE nodes (job_id INTEGER PRIMARY KEY, status TEXT)")
        conn.execute("CREATE TABLE edges (source_id INTEGER, target_id INTEGER)")
        # Statuses deliberately do not identify the video-derived seeds.
        conn.executemany(
            "INSERT INTO nodes(job_id, status) VALUES (?, ?)",
            [(job_id, "CORRUPT" if job_id == 777 else "OK") for job_id in node_ids],
        )
        conn.executemany("INSERT INTO edges(source_id, target_id) VALUES (?, ?)", edges)
        cursor = conn.cursor()
        cursor.execute(sql)
        return normalize_ids(cursor.fetchall())
    finally:
        conn.close()


def request_payload():
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the HTTP service at {URL}: {exc}")
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}."
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON. Got: {response.text}")
    assert "corrupted_jobs" in data, "JSON response missing 'corrupted_jobs' key."
    assert "impacted_downstream_jobs" in data, "JSON response missing 'impacted_downstream_jobs' key."
    assert set(data) == {"corrupted_jobs", "impacted_downstream_jobs"}, "JSON response has unexpected keys."
    assert isinstance(data["corrupted_jobs"], list)
    assert isinstance(data["impacted_downstream_jobs"], list)
    return data


def derive_corrupted_seconds():
    duration = float(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", VIDEO_PATH
    ], text=True).strip())
    hits = []
    with tempfile.TemporaryDirectory() as tmp:
        for second in range(int(duration)):
            frame = os.path.join(tmp, f"frame-{second}.png")
            subprocess.run([
                "ffmpeg", "-loglevel", "error", "-ss", str(second), "-i", VIDEO_PATH,
                "-frames:v", "1", "-y", frame
            ], check=True)
            text = subprocess.check_output(
                ["tesseract", frame, "stdout"], text=True, stderr=subprocess.DEVNULL
            ).upper()
            if "CORRUPT" in text:
                hits.append(second)
    # A displayed alert spans multiple frames; its timestamp is the whole-second
    # start of each contiguous appearance.
    return [value for index, value in enumerate(hits) if index == 0 or value != hits[index - 1] + 1]


def listening_program():
    wanted_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        for line in Path(table).read_text().splitlines()[1:]:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            address, port = local.rsplit(":", 1)
            if state == "0A" and port.upper() == "2382":
                if table.endswith("tcp"):
                    assert address.upper() == "0100007F", "Service is not bound to 127.0.0.1."
                wanted_inodes.add(fields[9])
    assert wanted_inodes, "No process is listening on port 9090."

    deadline = time.time() + 2
    while time.time() < deadline:
        for proc in Path("/proc").iterdir():
            if not proc.name.isdigit():
                continue
            try:
                links = [os.readlink(fd) for fd in (proc / "fd").iterdir()]
                if not any(link.startswith("socket:[") and link[8:-1] in wanted_inodes for link in links):
                    continue
                cmdline = (proc / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
                exe = os.path.basename(os.readlink(proc / "exe"))
                combined = f"{exe} {cmdline}".lower()
                assert re.search(r"(^|[ /])(nc|netcat|nc\.openbsd|socat)([ ./$]|$)", combined), \
                    f"Port 9090 listener is not nc/netcat or socat: {combined}"
                return combined
            except (FileNotFoundError, PermissionError, ProcessLookupError):
                pass
        time.sleep(0.05)
    pytest.fail("Could not identify the nc/socat process listening on port 9090.")


def replace_graph(conn, node_ids, edges):
    conn.execute("BEGIN IMMEDIATE")
    conn.execute("DELETE FROM edges")
    conn.execute("DELETE FROM nodes")
    conn.executemany(
        "INSERT INTO nodes(job_id, status) VALUES (?, ?)",
        [(job_id, "CORRUPT" if job_id in (3, 8) else "OK") for job_id in node_ids],
    )
    conn.executemany("INSERT INTO edges(source_id, target_id) VALUES (?, ?)", edges)
    conn.commit()


def test_sql_file_exists_and_valid():
    sql = read_sql()

    # Keep the original validity check against the supplied database.
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute(sql)
        results = cursor.fetchall()
    except sqlite3.Error as exc:
        pytest.fail(f"Executing the SQL query failed with error: {exc}")
    finally:
        conn.close()

    scrubbed = re.sub(r"--[^\n]*|/\*.*?\*/", " ", sql, flags=re.S)
    assert not re.search(r"\bCROSS\s+JOIN\b", scrubbed, flags=re.I), "Query must avoid CROSS JOIN."
    assert not re.search(r"\bFROM\s+[^;]*?,\s*[A-Za-z_(]", scrubbed, flags=re.I), \
        "Query must not use an implicit comma cross join."

    cases = [
        (
            [3, 8, 20, 21, 22, 30, 31, 777],
            [(3, 20), (20, 21), (21, 22), (8, 30), (30, 31), (777, 22)],
        ),
        (
            [3, 8, 40, 41, 42, 43, 50, 51, 777],
            [(3, 40), (40, 41), (8, 42), (42, 43), (50, 51), (777, 51)],
        ),
    ]
    for nodes, edges in cases:
        expected = downstream(edges, [3, 8])
        assert execute_sql_on_graph(sql, nodes, edges) == expected, \
            "Optimized SQL did not compute the downstream transitive closure."


def test_http_service_response_and_live_traversal():
    expected_corrupt = derive_corrupted_seconds()
    assert expected_corrupt == [3, 8], f"Unexpected OCR result from supplied video: {expected_corrupt}"

    # Keep all original response assertions.
    data = request_payload()
    corrupted_jobs = sorted(data["corrupted_jobs"])
    impacted_jobs = sorted(data["impacted_downstream_jobs"])
    assert corrupted_jobs == [3, 8], f"Expected corrupted_jobs to be [3, 8], got {corrupted_jobs}"
    assert impacted_jobs == [4, 5, 9, 10], \
        f"Expected impacted_downstream_jobs to be [4, 5, 9, 10], got {impacted_jobs}"
    assert corrupted_jobs == expected_corrupt
    listening_program()

    original = sqlite3.connect(":memory:")
    live = sqlite3.connect(DB_PATH, timeout=5)
    live.backup(original)
    try:
        cases = [
            ([1, 2, 3, 5, 8, 10, 60], [(3, 1), (1, 2), (2, 10), (8, 5), (60, 10)]),
            ([3, 8, 70, 71, 72, 80, 81], [(3, 70), (70, 71), (71, 72), (8, 80), (80, 81)]),
        ]
        for nodes, edges in cases:
            replace_graph(live, nodes, edges)
            expected_impacted = downstream(edges, expected_corrupt)
            changed = request_payload()
            assert sorted(changed["corrupted_jobs"]) == expected_corrupt
            assert sorted(changed["impacted_downstream_jobs"]) == expected_impacted, \
                "HTTP service returned a fixed payload instead of traversing the current graph."
    finally:
        original.backup(live)
        live.close()
        original.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
