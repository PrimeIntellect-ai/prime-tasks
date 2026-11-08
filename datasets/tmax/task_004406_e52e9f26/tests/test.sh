#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess

import pytest

DATA_PATH = "/home/user/data/sensors.csv"
OUTPUT_PATH = "/home/user/output.jsonl"
PROCESS_PATH = "/home/user/process.go"

ORIGINAL_CSV = '''timestamp,sensor_id,temperature,notes
100,S1,20.0,"Start of
run"
120,S1,24.0,"OK"
110,S1,,"Missing
value"
130,S1,22.0,"End"
105,S2,15.0,"S2 start"
115,S2,15.5,"S2 ok"
'''


def run_process():
    assert os.path.isfile(PROCESS_PATH), f"Go source file {PROCESS_PATH} is missing."
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    try:
        result = subprocess.run(
            ["go", "run", PROCESS_PATH],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("process.go did not finish within 30 seconds.")
    assert result.returncode == 0, (
        f"go run failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."


def load_output():
    records = []
    with open(OUTPUT_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    pytest.fail(f"Invalid JSON line in {OUTPUT_PATH}: {line}")
    return records


@pytest.fixture(scope="session", autouse=True)
def restore_original_feed():
    os.makedirs(os.path.dirname(DATA_PATH), exist_ok=True)
    with open(DATA_PATH, "w", newline="") as f:
        f.write(ORIGINAL_CSV)
    yield
    with open(DATA_PATH, "w", newline="") as f:
        f.write(ORIGINAL_CSV)
    try:
        run_process()
    except BaseException:
        pass


def test_output_jsonl_exists_and_correct():
    with open(DATA_PATH, "w", newline="") as f:
        f.write(ORIGINAL_CSV)
    run_process()
    records = load_output()

    # Group by sensor_id
    sensors = {}
    for r in records:
        sid = r.get("sensor_id")
        if sid not in sensors:
            sensors[sid] = []
        sensors[sid].append(r)

    assert "S1" in sensors, "Missing sensor S1 data in output."
    assert "S2" in sensors, "Missing sensor S2 data in output."

    s1_data = sensors["S1"]
    s2_data = sensors["S2"]

    # Verify S1
    assert len(s1_data) == 4, "Expected 4 records for S1."
    assert s1_data[0]["timestamp"] == 100
    assert float(s1_data[0]["temperature"]) == 20.0
    assert float(s1_data[0]["moving_avg"]) == 20.0

    assert s1_data[1]["timestamp"] == 110
    assert float(s1_data[1]["temperature"]) == 22.0
    assert float(s1_data[1]["moving_avg"]) == 21.0

    assert s1_data[2]["timestamp"] == 120
    assert float(s1_data[2]["temperature"]) == 24.0
    assert float(s1_data[2]["moving_avg"]) == 22.0

    assert s1_data[3]["timestamp"] == 130
    assert float(s1_data[3]["temperature"]) == 22.0
    assert round(float(s1_data[3]["moving_avg"]), 2) in (22.66, 22.67)

    # Verify S2
    assert len(s2_data) == 2, "Expected 2 records for S2."
    assert s2_data[0]["timestamp"] == 105
    assert float(s2_data[0]["temperature"]) == 15.0
    assert float(s2_data[0]["moving_avg"]) == 15.0

    assert s2_data[1]["timestamp"] == 115
    assert float(s2_data[1]["temperature"]) == 15.5
    assert float(s2_data[1]["moving_avg"]) == 15.25


def test_process_handles_unseen_csv_data():
    sid_a = "A_" + secrets.token_hex(6)
    sid_b = "B_" + secrets.token_hex(6)
    start = 1000 + secrets.randbelow(500000)
    base_a = 10 + secrets.randbelow(40)
    base_b = 60 + secrets.randbelow(30)

    rows = [
        [start, sid_a, str(base_a), "first line\ncontinues, with comma"],
        [start + 7, sid_a, str(base_a + 2), 'quoted "note"'],
        [start + 14, sid_a, "", "missing\nreading"],
        [start + 21, sid_a, str(base_a + 6), "after missing"],
        [start + 28, sid_a, str(base_a + 8), "last"],
        [start + 3, sid_b, str(base_b), "sensor B\nstart"],
        [start + 13, sid_b, "", "B missing, value"],
        [start + 23, sid_b, str(base_b + 4), "B third"],
        [start + 33, sid_b, str(base_b + 8), "B fourth"],
    ]
    secrets.SystemRandom().shuffle(rows)

    with open(DATA_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "sensor_id", "temperature", "notes"])
        writer.writerows(rows)

    run_process()
    records = load_output()
    assert len(records) == len(rows), "Output must contain exactly one record per CSV record."

    grouped = {}
    for record in records:
        assert all(k in record for k in ("timestamp", "sensor_id", "temperature", "moving_avg"))
        grouped.setdefault(record["sensor_id"], []).append(record)

    expected = {
        sid_a: [
            (start, base_a),
            (start + 7, base_a + 2),
            (start + 14, base_a + 4),
            (start + 21, base_a + 6),
            (start + 28, base_a + 8),
        ],
        sid_b: [
            (start + 3, base_b),
            (start + 13, base_b + 2),
            (start + 23, base_b + 4),
            (start + 33, base_b + 8),
        ],
    }
    assert set(grouped) == set(expected), "Output contains missing or unexpected sensor groups."

    for sid, expected_values in expected.items():
        actual = grouped[sid]
        assert len(actual) == len(expected_values)
        for i, (expected_ts, expected_temp) in enumerate(expected_values):
            assert int(actual[i]["timestamp"]) == expected_ts, "Records are not sorted chronologically."
            assert float(actual[i]["temperature"]) == pytest.approx(expected_temp, abs=0.01)
            window = [temp for _, temp in expected_values[max(0, i - 2):i + 1]]
            expected_avg = sum(window) / len(window)
            assert float(actual[i]["moving_avg"]) == pytest.approx(expected_avg, abs=0.011)


def test_crontab_exists_and_correct():
    crontab_path = "/home/user/crontab.txt"
    assert os.path.isfile(crontab_path), f"Crontab file {crontab_path} is missing."

    with open(crontab_path, "r") as f:
        content = f.read().strip()

    assert "*/15 * * * *" in content or "0,15,30,45 * * * *" in content, "Crontab does not have the correct schedule (every 15 minutes)."
    assert "go run /home/user/process.go" in content, "Crontab does not execute the correct command."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
