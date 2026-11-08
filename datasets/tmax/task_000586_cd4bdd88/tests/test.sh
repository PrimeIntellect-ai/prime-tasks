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
import os
import re
import glob
import uuid
import sqlite3
import tempfile
import subprocess
from pathlib import Path

import pytest
import requests

DB_PATH = "/home/user/audit.db"
VIDEO_PATH = "/app/compliance_log.mp4"
BASE_URL = "http://127.0.0.1:9090"
HEADERS = {"X-Compliance-Key": "alpha-audit-99"}


def extract_expected_records():
    """Independently derive the transaction records from the supplied video."""
    with tempfile.TemporaryDirectory() as tmp:
        pattern = os.path.join(tmp, "frame-%03d.png")
        subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-i", VIDEO_PATH,
             "-vf", "fps=1/5", pattern],
            check=True,
        )
        records = set()
        for frame in sorted(glob.glob(os.path.join(tmp, "frame-*.png"))):
            result = subprocess.run(
                ["tesseract", frame, "stdout", "--psm", "7"],
                check=True, capture_output=True, text=True,
            )
            text = result.stdout.upper().replace(",", ".")
            match = re.search(
                r"TXN.*?(U[0-9O]+).*?(U[0-9O]+).*?([0-9]+(?:\.[0-9]+)?)\s*$",
                text,
            )
            if match:
                sender = match.group(1).replace("O", "0")
                receiver = match.group(2).replace("O", "0")
                records.add((sender, receiver, float(match.group(3))))
        assert records, "Verifier could not OCR any transaction records from the video"
        return records


def canonical_cycles(edges):
    cycles = set()
    adjacency = {}
    for sender, receiver in edges:
        adjacency.setdefault(sender, set()).add(receiver)
    for a in adjacency:
        for b in adjacency.get(a, ()):
            for c in adjacency.get(b, ()):
                if len({a, b, c}) == 3 and a in adjacency.get(c, ()):
                    rotations = [(a, b, c), (b, c, a), (c, a, b)]
                    cycles.add(min(rotations))
    return [list(cycle) for cycle in sorted(cycles, key=lambda c: (c[0], c[1], c[2]))]


def get_cycles():
    try:
        response = requests.get(f"{BASE_URL}/api/cycles", headers=HEADERS, timeout=10)
    except requests.exceptions.ConnectionError:
        pytest.fail("API service is not running or not reachable at 127.0.0.1:9090")
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    try:
        return response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")


def listener_source():
    """Collect source tied to the process listening on port 9090."""
    socket_inodes = set()
    for net_file in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(net_file).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and int(fields[1].split(":")[1], 16) == 9090 and fields[3] == "0A":
                socket_inodes.add(fields[9])
    assert socket_inodes, "No process is listening on TCP port 9090"

    listener_pids = []
    for proc in glob.glob("/proc/[0-9]*"):
        try:
            links = [os.readlink(fd) for fd in glob.glob(proc + "/fd/*")]
        except OSError:
            continue
        if any(link.startswith("socket:[") and link[8:-1] in socket_inodes for link in links):
            listener_pids.append(int(proc.rsplit("/", 1)[1]))
    assert listener_pids, "Could not identify the process serving port 9090"

    chunks = []
    files = set()
    for pid in listener_pids:
        proc = f"/proc/{pid}"
        try:
            raw_cmd = Path(proc + "/cmdline").read_bytes()
            cmd = raw_cmd.replace(b"\0", b" ").decode(errors="ignore")
            chunks.append(cmd)
            args = [x.decode(errors="ignore") for x in raw_cmd.split(b"\0") if x]
            cwd = os.readlink(proc + "/cwd")
            for arg in args:
                candidate = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
                if os.path.isfile(candidate):
                    files.add(candidate)
                module = arg.split(":", 1)[0]
                module_file = os.path.join(cwd, module.replace(".", "/") + ".py")
                if os.path.isfile(module_file):
                    files.add(module_file)
            try:
                env = Path(proc + "/environ").read_bytes().split(b"\0")
                for item in env:
                    if item.startswith((b"FLASK_APP=", b"APP_MODULE=")):
                        value = item.split(b"=", 1)[1].decode(errors="ignore").split(":", 1)[0]
                        candidate = value if os.path.isabs(value) else os.path.join(cwd, value)
                        if os.path.isfile(candidate):
                            files.add(candidate)
            except OSError:
                pass
            # Include local Python modules that the serving program may import.
            for candidate in glob.glob(os.path.join(cwd, "**", "*.py"), recursive=True):
                if os.path.isfile(candidate) and os.path.getsize(candidate) < 1_000_000:
                    files.add(candidate)
        except OSError:
            continue

    for filename in files:
        try:
            chunks.append(Path(filename).read_text(errors="ignore"))
        except OSError:
            pass
    return "\n".join(chunks)


def test_database_exists_and_contents():
    assert os.path.isfile(DB_PATH), f"Database file missing at {DB_PATH}"
    expected = extract_expected_records()

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='transactions'")
    table = cursor.fetchone()
    assert table is not None, "Table 'transactions' does not exist in the database."

    schema = cursor.execute("PRAGMA table_info(transactions)").fetchall()
    conn.close()
    assert [(row[1], row[2].upper()) for row in schema] == [
        ("tx_id", "TEXT"), ("sender", "TEXT"),
        ("receiver", "TEXT"), ("amount", "REAL")
    ], f"Incorrect transactions schema: {schema}"

    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute("SELECT sender, receiver, amount FROM transactions").fetchall()
    conn.close()
    actual = {(sender, receiver, float(amount)) for sender, receiver, amount in rows}
    assert len(rows) == len(expected), "Database must contain each extracted record exactly once"
    assert actual == expected, f"Database rows do not match records independently OCRed from the video: {actual}"


def test_service_contains_required_analysis_and_deadlock_logic():
    source = listener_source()
    lowered = source.lower()
    assert re.search(r"\bwith\s+recursive\b", lowered), "Running service does not contain a recursive SQLite CTE"
    assert "trigger_deadlock" in source, "Running service does not define trigger_deadlock()"
    assert "sqlite3" in lowered and "connect" in lowered, "Deadlock implementation does not use SQLite connections"
    assert any(token in lowered for token in ("thread", "multiprocessing", "concurrent")), \
        "Deadlock implementation does not use concurrent workers"
    assert "except" in lowered and ("operationalerror" in lowered or "locked" in lowered), \
        "Deadlock implementation does not catch a SQLite lock error"


def test_api_unauthorized():
    try:
        response = requests.get(f"{BASE_URL}/api/cycles", timeout=10)
    except requests.exceptions.ConnectionError:
        pytest.fail("API service is not running or not reachable at 127.0.0.1:9090")
    assert response.status_code in [401, 403], f"Expected 401 or 403 for unauthorized request, got {response.status_code}"

    response = requests.post(f"{BASE_URL}/api/deadlock", timeout=10)
    assert response.status_code in [401, 403], \
        f"Expected 401 or 403 for unauthorized deadlock request, got {response.status_code}"


def test_api_cycles_and_live_database_analysis():
    data = get_cycles()
    assert isinstance(data, list), "Response should be a JSON array"
    assert len(data) >= 1, "Expected at least one cycle in the response"
    expected_cycle = ["U101", "U102", "U103"]
    assert expected_cycle in data, f"Expected cycle {expected_cycle} not found in response: {data}"

    conn = sqlite3.connect(DB_PATH)
    original_edges = conn.execute("SELECT sender, receiver FROM transactions").fetchall()
    expected_before = canonical_cycles(original_edges)
    assert data == expected_before, f"API did not return all and only database cycles in order: {data}"

    suffix = uuid.uuid4().hex[:8].upper()
    nodes = [f"Z{suffix}A", f"Z{suffix}B", f"Z{suffix}C"]
    tx_ids = [f"VERIFY-{suffix}-{i}" for i in range(3)]
    inserted = [
        (tx_ids[0], nodes[0], nodes[1], 11.0),
        (tx_ids[1], nodes[1], nodes[2], 12.0),
        (tx_ids[2], nodes[2], nodes[0], 13.0),
    ]
    try:
        conn.executemany("INSERT INTO transactions(tx_id,sender,receiver,amount) VALUES (?,?,?,?)", inserted)
        conn.commit()
        expected_after = canonical_cycles(original_edges + [(r[1], r[2]) for r in inserted])
        changed = get_cycles()
        assert changed == expected_after, \
            f"/api/cycles is not derived from the current transactions table: {changed}"
        assert nodes in changed, "Dynamically inserted cycle was not discovered"
        assert [cycle[0] for cycle in changed] == sorted(cycle[0] for cycle in changed), \
            "Cycles are not ordered alphabetically by first ID"
    finally:
        conn.executemany("DELETE FROM transactions WHERE tx_id=?", [(x,) for x in tx_ids])
        conn.commit()
        conn.close()


def test_api_deadlock():
    try:
        response = requests.post(f"{BASE_URL}/api/deadlock", headers=HEADERS, timeout=20)
    except requests.exceptions.ConnectionError:
        pytest.fail("API service is not running or not reachable at 127.0.0.1:9090")
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")
    assert data.get("status") == "deadlocked", f"Expected status 'deadlocked', got {data.get('status')}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
