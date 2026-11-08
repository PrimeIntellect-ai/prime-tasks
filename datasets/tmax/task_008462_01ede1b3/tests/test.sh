#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import fcntl
import json
import os
import subprocess
import time
import uuid

SCRIPT = "/home/user/extract_data.py"
WAL = "/home/user/sensor_data.wal"
CSV = "/home/user/clean_data.csv"


def test_extract_script_exists_and_uses_flock():
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."

    with open(SCRIPT, "r") as f:
        code = f.read()

    assert "fcntl" in code, "The script does not import or use the fcntl module."
    assert "flock" in code, "The script does not use fcntl.flock to acquire a lock."
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable."


def test_wal_file_truncated():
    assert os.path.exists(WAL), f"WAL file {WAL} is missing. It should be truncated, not deleted."
    assert os.path.getsize(WAL) == 0, f"WAL file {WAL} was not truncated to 0 bytes."


def test_clean_data_csv_content():
    assert os.path.exists(CSV), f"Output file {CSV} does not exist."

    with open(CSV, "r") as f:
        csv_content = f.read().strip()

    expected_csv = (
        "sensor_id,timestamp,reading\n"
        "S1,2023-10-01T10:00:00Z,42.5\n"
        "S3,2023-10-01T10:00:02Z,41.9\n"
        "S1,2023-10-01T10:00:03Z,42.0"
    )

    assert csv_content == expected_csv, (
        f"CSV content does not match expected output.\n"
        f"Expected:\n{expected_csv}\n\n"
        f"Got:\n{csv_content}"
    )


def run_script():
    result = subprocess.run(
        [SCRIPT], cwd="/home/user", capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Script exited with {result.returncode}.\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )


def read_rows():
    with open(CSV, newline="") as f:
        return list(csv.reader(f))


def test_script_executes_on_new_wal_and_handles_csv_lifecycle():
    token = uuid.uuid4().hex
    first = {
        "sensor_id": f"sensor,{token}",
        "timestamp": f"dynamic-{token}-1",
        "reading": 17.25,
    }
    second = {
        "sensor_id": f"sensor-{token}-2",
        "timestamp": f"dynamic-{token}-2",
        "reading": -3.0,
        "extra": "allowed",
    }
    extra_line = {
        "sensor_id": f"reject-{token}",
        "timestamp": "reject-extra-line",
        "reading": 999,
    }

    fixture = "\n".join([
        "unrelated garbage",
        "---BEGIN_ENTRY---",
        json.dumps(first),
        "---END_ENTRY---",
        "---BEGIN_ENTRY---",
        "{malformed json",
        "---END_ENTRY---",
        "---BEGIN_ENTRY---",
        json.dumps(extra_line),
        "unexpected fourth line",
        "---END_ENTRY---",
        "---BEGIN_ENTRY---",
        '{"sensor_id":"incomplete"}',
        "---BEGIN_ENTRY---",
        json.dumps(second),
        "---END_ENTRY---",
        "",
    ])

    if os.path.exists(CSV):
        os.remove(CSV)
    with open(WAL, "w") as f:
        f.write(fixture)

    run_script()

    assert os.path.exists(WAL), "The WAL must be truncated, not deleted."
    assert os.path.getsize(WAL) == 0, "The newly processed WAL was not truncated."
    expected = [
        ["sensor_id", "timestamp", "reading"],
        [first["sensor_id"], first["timestamp"], "17.25"],
        [second["sensor_id"], second["timestamp"], "-3.0"],
    ]
    assert read_rows() == expected

    third = {
        "sensor_id": f"append-{token}",
        "timestamp": f"dynamic-{token}-3",
        "reading": 8,
    }
    with open(WAL, "w") as f:
        f.write("---BEGIN_ENTRY---\n" + json.dumps(third) + "\n---END_ENTRY---\n")

    run_script()
    expected.append([third["sensor_id"], third["timestamp"], "8"])
    assert read_rows() == expected, "Records were not appended correctly."
    with open(CSV) as f:
        assert sum(line.rstrip("\r\n") == "sensor_id,timestamp,reading" for line in f) == 1
    assert os.path.getsize(WAL) == 0


def test_script_waits_for_exclusive_wal_lock():
    token = uuid.uuid4().hex
    record = {
        "sensor_id": f"locked-{token}",
        "timestamp": f"locked-time-{token}",
        "reading": 61.5,
    }
    wal_data = "---BEGIN_ENTRY---\n" + json.dumps(record) + "\n---END_ENTRY---\n"
    with open(WAL, "w") as f:
        f.write(wal_data)

    with open(CSV, "rb") as f:
        csv_before = f.read()

    lock_file = open(WAL, "r+")
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    process = subprocess.Popen(
        [SCRIPT], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    time.sleep(0.5)
    still_running = process.poll() is None
    with open(WAL) as f:
        wal_unchanged = f.read() == wal_data
    with open(CSV, "rb") as f:
        csv_unchanged = f.read() == csv_before
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
    lock_file.close()

    if not still_running:
        stdout, stderr = process.communicate()
        raise AssertionError(
            f"Script did not wait for the WAL lock. stdout: {stdout}; stderr: {stderr}"
        )
    assert wal_unchanged, "The script read or truncated the WAL before acquiring its lock."
    assert csv_unchanged, "The script wrote CSV output before acquiring its WAL lock."

    try:
        stdout, stderr = process.communicate(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.communicate()
        raise AssertionError("Script did not finish after the WAL lock was released.")

    assert process.returncode == 0, f"Script failed after lock release: {stdout}\n{stderr}"
    assert os.path.exists(WAL) and os.path.getsize(WAL) == 0
    assert read_rows()[-1] == [record["sensor_id"], record["timestamp"], "61.5"]
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
