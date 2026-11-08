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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import csv
import json
import math
import os
import pathlib
import random
import re
import signal
import socket
import subprocess
import time
import uuid
from decimal import Decimal

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
AUTH_TOKEN = "Bearer super-secret-etl-token"
RAW_CSV = pathlib.Path("/home/user/raw_events.csv")
VENDORED = pathlib.Path("/app/vendored/etl-receiver-0.1.0")
FIELDS = ["event_id", "user_id", "text_utf8", "lang_code", "engagement_score"]


def read_rows(path=RAW_CSV):
    with path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == FIELDS, f"Unexpected CSV columns: {reader.fieldnames}"
        return list(reader)


def expected_sample(rows):
    groups = collections.OrderedDict()
    for row in rows:
        groups.setdefault(row["lang_code"], []).append(row)
    result = []
    for records in groups.values():
        records = sorted(records, key=lambda r: (-Decimal(r["engagement_score"]), r["event_id"]))
        result.extend(records[:math.ceil(len(records) * Decimal("0.10"))])
    return result


def normalized_record(record):
    assert isinstance(record, dict), f"Record is not an object: {record!r}"
    assert set(record) == set(FIELDS), f"Record does not contain exactly the CSV fields: {record!r}"
    return (
        str(record["event_id"]),
        str(record["user_id"]),
        str(record["text_utf8"]),
        str(record["lang_code"]),
        Decimal(str(record["engagement_score"])),
    )


def assert_complete_records(actual, expected):
    assert isinstance(actual, list), "Expected transaction data to be a list of records."
    actual_records = collections.Counter(normalized_record(r) for r in actual)
    expected_records = collections.Counter(normalized_record(r) for r in expected)
    assert actual_records == expected_records, (
        f"Stored records do not equal the complete mathematically selected CSV rows. "
        f"Expected {expected_records}, got {actual_records}."
    )


def dump():
    response = requests.get(f"{BASE_URL}/api/dump", timeout=2)
    assert response.status_code == 200
    return response.json()


def listening_processes(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            parts = line.split()
            if len(parts) > 9 and int(parts[1].split(":")[-1], 16) == port and parts[3] == "0A":
                inodes.add(parts[9])
    found = []
    for procdir in pathlib.Path("/proc").iterdir():
        if not procdir.name.isdigit():
            continue
        try:
            for fd in (procdir / "fd").iterdir():
                if os.readlink(fd) in {f"socket:[{inode}]" for inode in inodes}:
                    cmd = (procdir / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
                    cwd = os.readlink(procdir / "cwd")
                    found.append((procdir.name, cmd, cwd))
                    break
        except (OSError, PermissionError):
            pass
    return found


def test_server_is_running_and_dump_accessible():
    """Verify the server is running on the correct port and /api/dump works."""
    try:
        response = requests.get(f"{BASE_URL}/api/dump", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Server is not reachable on {BASE_URL}. Error: {e}")

    assert response.status_code == 200, f"Expected 200 OK from /api/dump, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response from /api/dump is not valid JSON.")
    assert isinstance(data, dict), "Expected dump to return a JSON object (dictionary)."

    owners = listening_processes(8080)
    assert owners, "Could not identify the process listening on port 8080."
    assert any(str(VENDORED) in cmd or os.path.realpath(cwd) == str(VENDORED) for _, cmd, cwd in owners), (
        f"The live service is not the vendored etl-receiver: {owners}"
    )


def test_initial_load_stratified_data():
    """Verify that the initial data load contains the correctly stratified sample."""
    data = dump()
    txn_id = "TXN-INITIAL-LOAD"
    assert txn_id in data, f"Transaction '{txn_id}' not found in server data. Did the script run and send data?"
    records = data[txn_id]
    assert isinstance(records, list), "Expected transaction data to be a list of records."

    event_ids = [record.get("event_id") for record in records]
    expected_event_ids = {"e1", "e13", "e12"}
    assert set(event_ids) == expected_event_ids, (
        f"Incorrect stratified sample. Expected event_ids {expected_event_ids}, but got {set(event_ids)}."
    )
    assert len(event_ids) == 3, f"Expected exactly 3 records, got {len(event_ids)}."

    # In addition to the original ID check, require every field from the selected CSV rows.
    assert_complete_records(records, expected_sample(read_rows()))


def test_retry_bug_is_fixed():
    """Verify that retrying a POST with the same Transaction-Id overwrites rather than appends."""
    headers = {
        "Authorization": AUTH_TOKEN,
        "Transaction-Id": "TXN-VERIFIER-TEST",
        "Content-Type": "application/json",
    }
    payload = [{"test": 1}]
    try:
        res1 = requests.post(f"{BASE_URL}/api/ingest", headers=headers, json=payload, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"POST /api/ingest failed: {e}")
    assert res1.status_code == 200, f"Expected 200 OK on first ingest, got {res1.status_code}"

    res2 = requests.post(f"{BASE_URL}/api/ingest", headers=headers, json=payload, timeout=2)
    assert res2.status_code == 200, f"Expected 200 OK on retry ingest, got {res2.status_code}"

    data = dump()
    assert "TXN-VERIFIER-TEST" in data, "Test transaction not found in dump."
    records = data["TXN-VERIFIER-TEST"]
    assert len(records) == 1, (
        "Server retry bug is not fixed! Expected 1 record in 'TXN-VERIFIER-TEST', "
        f"but found {len(records)}. The server is likely still appending data."
    )
    assert records == payload, "Stored data does not match the payload."


def test_unauthorized_ingest_rejected():
    """Verify that /api/ingest rejects requests with invalid or missing Authorization."""
    headers = {"Authorization": "Bearer wrong-token", "Transaction-Id": "TXN-AUTH-TEST"}
    payload = [{"test": 2}]
    res = requests.post(f"{BASE_URL}/api/ingest", headers=headers, json=payload, timeout=2)
    assert res.status_code == 401, f"Expected 401 Unauthorized for bad token, got {res.status_code}"


def find_processing_scripts():
    candidates = []
    excluded = {VENDORED / "server.py", pathlib.Path("/tmp/test_final_state.py")}
    for root in (pathlib.Path("/home/user"), pathlib.Path("/app"), pathlib.Path("/tmp")):
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if path in excluded or not path.is_file() or path.suffix.lower() not in {".py", ".rb", ".js", ".mjs", ".cjs"}:
                continue
            try:
                if path.stat().st_size > 2_000_000:
                    continue
                text = path.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            markers = sum(marker in text for marker in ("raw_events", "TXN-INITIAL-LOAD", "/api/ingest"))
            if markers >= 2:
                candidates.append(path)
    return sorted(set(candidates))


def command_for(path):
    if path.suffix.lower() == ".py":
        return ["python3", str(path)]
    if path.suffix.lower() == ".rb":
        return ["ruby", str(path)]
    return ["node", str(path)]


def make_dynamic_rows():
    token = uuid.uuid4().hex
    rows = []
    specs = [("ja", 11, "雪と猫"), ("ar", 4, "مرحبا بالعالم"), ("fr", 20, "élève café")]
    for lang, count, text in specs:
        for i in range(count):
            # Repeated scores exercise the event_id tie breaker, including at sample cutoffs.
            score = Decimal(100 - (i // 2) * 7) + Decimal("0.25")
            rows.append({
                "event_id": f"{token}-{lang}-{count-i:02d}",
                "user_id": f"user-{token[:8]}-{lang}-{i}",
                "text_utf8": f"{text} #{i} — {token[:6]}",
                "lang_code": lang,
                "engagement_score": str(score),
            })
    random.SystemRandom().shuffle(rows)
    return rows


def wait_for_sample(expected, timeout=3):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            records = dump().get("TXN-INITIAL-LOAD")
            assert_complete_records(records, expected)
            return True
        except Exception:
            time.sleep(0.1)
    return False


def test_processing_script_exists_and_recomputes_unseen_csv():
    scripts = find_processing_scripts()
    assert scripts, "No Python, Ruby, or Node data-processing script was found."

    original = RAW_CSV.read_bytes()
    dynamic_rows = make_dynamic_rows()
    expected_dynamic = expected_sample(dynamic_rows)
    successful = None
    errors = []
    try:
        with RAW_CSV.open("w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=FIELDS)
            writer.writeheader()
            writer.writerows(dynamic_rows)

        for script in scripts:
            try:
                result = subprocess.run(
                    command_for(script), cwd=str(script.parent), text=True,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20,
                )
                if result.returncode == 0 and wait_for_sample(expected_dynamic):
                    successful = script
                    break
                errors.append(f"{script}: exit={result.returncode}, output={result.stdout[-500:]}")
            except Exception as e:
                errors.append(f"{script}: {e}")
        assert successful is not None, (
            "No submitted processing script recomputed and uploaded the complete sample from an unseen CSV. "
            + " | ".join(errors)
        )
    finally:
        RAW_CSV.write_bytes(original)

    # Restore the required final initial load using the same demonstrated script.
    result = subprocess.run(
        command_for(successful), cwd=str(successful.parent), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20,
    )
    assert result.returncode == 0, f"Processing script failed while restoring the initial load: {result.stdout}"
    assert wait_for_sample(expected_sample(read_rows())), "Processing script did not restore the original stratified load."


def test_vendored_makefile_and_server_are_patched_and_executable():
    makefile = VENDORED / "Makefile"
    server_file = VENDORED / "server.py"
    assert makefile.is_file(), "Vendored Makefile is missing."
    assert server_file.is_file(), "Vendored server.py is missing."

    original_makefile = "PORT=80\nstart:\n\tpython3 server.py --port $(PORT)\n"
    original_server_fragment = "transactions[txn_id].extend(data)"
    assert makefile.read_text() != original_makefile, "The broken vendored Makefile was not patched."
    assert original_server_fragment not in server_file.read_text(), "The vendored append-on-retry logic was not patched."

    dry = subprocess.run(["make", "-n", "-C", str(VENDORED), "start"], text=True,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=5)
    assert dry.returncode == 0, f"Vendored Makefile start target is invalid: {dry.stdout}"
    assert "server.py" in dry.stdout, f"Makefile start target does not launch the vendored server: {dry.stdout}"
    assert not re.search(r"--port\s+80(?:\s|$)", dry.stdout), f"Makefile still defaults to privileged port 80: {dry.stdout}"

    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    env = os.environ.copy()
    env["AUTH_TOKEN"] = "vendored-verifier-token"
    proc = subprocess.Popen(
        ["runuser", "-u", "user", "--", "make", "-C", str(VENDORED), "start", f"PORT={port}"],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        preexec_fn=os.setsid,
    )
    base = f"http://127.0.0.1:{port}"
    try:
        deadline = time.time() + 6
        while time.time() < deadline:
            try:
                if requests.get(f"{base}/api/dump", timeout=.3).status_code == 200:
                    break
            except requests.RequestException:
                time.sleep(.1)
        else:
            output = proc.stdout.read() if proc.poll() is not None else ""
            pytest.fail(f"Patched vendored server did not start as non-root via Makefile: {output}")

        headers = {"Authorization": "Bearer vendored-verifier-token", "Transaction-Id": "fresh-retry"}
        first = [{"round": 1}, {"round": 1, "second": True}]
        second = [{"round": 2}]
        assert requests.post(f"{base}/api/ingest", headers=headers, json=first, timeout=2).status_code == 200
        assert requests.post(f"{base}/api/ingest", headers=headers, json=second, timeout=2).status_code == 200
        stored = requests.get(f"{base}/api/dump", timeout=2).json()
        assert stored["fresh-retry"] == second, "The executed vendored server still appends on retry."
        bad = {"Authorization": "Bearer wrong", "Transaction-Id": "bad-auth"}
        assert requests.post(f"{base}/api/ingest", headers=bad, json=[], timeout=2).status_code == 401
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
