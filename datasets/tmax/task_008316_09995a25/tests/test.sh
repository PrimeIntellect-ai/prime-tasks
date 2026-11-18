#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile

import pytest

INCIDENT_DIR = "/home/user/incident"
RECOVER_PY = os.path.join(INCIDENT_DIR, "recover.py")
WAL_FILE = os.path.join(INCIDENT_DIR, "db.wal")
JSON_FILE = os.path.join(INCIDENT_DIR, "recovered_db.json")
IP_FILE = "/home/user/attacker_ip.txt"


def independently_parse_wal(path):
    with open(path, "rb") as f:
        data = f.read()

    assert data.startswith(b"WAL\x01"), "The supplied WAL has invalid magic bytes."
    records = []
    offset = 4
    while offset + 4 <= len(data):
        length = int.from_bytes(data[offset:offset + 4], "big")
        offset += 4
        assert offset + length <= len(data), "The supplied WAL contains a truncated record."
        records.append(json.loads(data[offset:offset + length].decode("utf-8")))
        offset += length
    assert offset == len(data), "The supplied WAL has trailing bytes."
    return records


@pytest.fixture(scope="session", autouse=True)
def execute_and_validate_recovery_script():
    assert os.path.isfile(RECOVER_PY), f"Recovery script {RECOVER_PY} does not exist."
    with open(RECOVER_PY, "r", encoding="utf-8") as f:
        source = f.read()
    assert "while offset + 4 < len(data):" not in source, \
        "recover.py still contains the original faulty boundary condition."

    # Exercise the exact boundary where only a complete four-byte length header
    # remains. The fixed loop must inspect it and report that its payload is truncated;
    # the original '<' loop silently skips it.
    with tempfile.TemporaryDirectory() as td:
        boundary_wal = os.path.join(td, "boundary.wal")
        boundary_json = os.path.join(td, "boundary.json")
        with open(boundary_wal, "wb") as f:
            f.write(b"WAL\x01")
            f.write((7).to_bytes(4, "big"))

        runner = (
            "import importlib.util,sys; "
            "s=importlib.util.spec_from_file_location('submitted_recover',sys.argv[1]); "
            "m=importlib.util.module_from_spec(s); s.loader.exec_module(m); "
            "m.recover_wal(sys.argv[2],sys.argv[3])"
        )
        result = subprocess.run(
            [sys.executable, "-c", runner, RECOVER_PY, boundary_wal, boundary_json],
            cwd=INCIDENT_DIR,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=10,
        )
        assert result.returncode == 0, f"recover_wal failed on a boundary input:\n{result.stdout}"
        assert "truncated" in result.stdout.lower(), \
            "recover_wal did not inspect a length header at the exact end boundary."
        assert os.path.isfile(boundary_json), "recover_wal did not create its requested output file."
        with open(boundary_json, "r", encoding="utf-8") as f:
            assert json.load(f) == [], "A truncated payload must not be emitted as a record."

    # Remove any fabricated/stale output and execute the submitted artifact itself.
    if os.path.exists(JSON_FILE):
        os.remove(JSON_FILE)
    result = subprocess.run(
        [sys.executable, RECOVER_PY],
        cwd=INCIDENT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10,
    )
    assert result.returncode == 0, f"Running recover.py failed:\n{result.stdout}"
    assert os.path.isfile(JSON_FILE), "Running recover.py did not create recovered_db.json."


def test_attacker_ip_file():
    assert os.path.isfile(IP_FILE), f"File {IP_FILE} does not exist. Did you write the extracted IP to this location?"

    with open(IP_FILE, "r") as f:
        ip = f.read().strip()

    assert ip == "192.168.137.42", f"Expected IP '192.168.137.42', got '{ip}'. The wrong IP was extracted."

    expected = independently_parse_wal(WAL_FILE)
    crash_records = [r for r in expected if r.get("action") == "SYSTEM_CRASH"]
    assert len(crash_records) == 1
    assert ip == crash_records[0].get("source_ip"), \
        "attacker_ip.txt does not contain the source_ip recovered for SYSTEM_CRASH."


def test_recovered_db_json():
    assert os.path.isfile(JSON_FILE), f"File {JSON_FILE} does not exist. Did you run the fixed recover.py script?"

    with open(JSON_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_FILE} does not contain valid JSON.")

    assert isinstance(data, list), f"Expected JSON array in {JSON_FILE}, got {type(data).__name__}."
    assert len(data) == 3, f"Expected 3 records in {JSON_FILE}, got {len(data)}. The off-by-one error might not be fully fixed."
    assert data[-1].get("action") == "SYSTEM_CRASH", \
        "The last record is missing or incorrect. It should be the SYSTEM_CRASH event."
    assert data == independently_parse_wal(WAL_FILE), \
        "recovered_db.json does not exactly match the records encoded in db.wal."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
