#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from datetime import datetime, timedelta

SCRIPT_PATH = "/home/user/clean_data.sh"
INPUT_PATH = "/home/user/sensor_logs.txt"
OUTPUT_PATH = "/home/user/clean_sensors.csv"
HEADER = "SensorID,Timestamp,X,Y,Distance"


def run_script():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        [SCRIPT_PATH], capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"Script failed to execute. stdout: {result.stdout} stderr: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} was not created."
    with open(OUTPUT_PATH, "r") as f:
        return f.read().strip()


def test_script_exists_and_executable():
    """Test if the clean_data.sh script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_output():
    """Retain the original fixture and exact-output assertion."""
    original_logs = """[DEBUG] Sensor-A1 reported at Jan 05 2024 14:30:00. Loc: (12, -5). All good.
[INFO] Sensor-B2 pinged on 2024/01/05 2:35 PM. Loc: (-10, 20). Battery low.
[ERROR] Sensor-C3 failed at 14:40 01-05-2024. Loc: (invalid, 9).
[INFO] Sensor-D4 active at 2024-01-05 14:45:00. Loc: (0, 0).
Corrupted line without proper info.
[WARN] Sensor-E5 offline at Jan 05 2024 10:15:00. Loc: (7, 8).
[INFO] Sensor-F6 at 2024-01-05 16:00:00. No location data.
"""
    with open(INPUT_PATH, "w") as f:
        f.write(original_logs)

    expected_csv = """SensorID,Timestamp,X,Y,Distance
Sensor-E5,2024-01-05T10:15:00,7,8,15
Sensor-A1,2024-01-05T14:30:00,12,-5,17
Sensor-B2,2024-01-05T14:35:00,-10,20,30
Sensor-D4,2024-01-05T14:45:00,0,0,0"""

    actual_csv = run_script()
    assert actual_csv == expected_csv, (
        f"Content of {OUTPUT_PATH} does not match expected output.\n"
        f"Expected:\n{expected_csv}\n\nActual:\n{actual_csv}"
    )


def make_dynamic_case(count):
    rng = secrets.SystemRandom()
    year = rng.randint(2023, 2028)
    base = datetime(
        year,
        rng.randint(1, 12),
        rng.randint(2, 18),
        rng.randint(1, 8),
        rng.randint(0, 20),
        0,
    )
    possible_ids = [f"{letter}{digit}" for letter in "GHIJKLMNOPQRSTUVWXYZ" for digit in range(10)]
    ids = rng.sample(possible_ids, count)
    records = []

    for i in range(count):
        dt = base + timedelta(minutes=(i + 1) * rng.randint(23, 41))
        format_kind = i % 3
        if format_kind == 0:
            dt = dt.replace(second=rng.randint(1, 58))
            timestamp = dt.strftime("%b %d %Y %H:%M:%S")
        elif format_kind == 1:
            dt = dt.replace(second=0)
            timestamp = dt.strftime("%Y/%m/%d %-I:%M %p")
        else:
            dt = dt.replace(second=rng.randint(1, 58))
            timestamp = dt.strftime("%Y-%m-%d %H:%M:%S")

        x = rng.randint(-80, 80)
        y = rng.randint(-80, 80)
        records.append((f"Sensor-{ids[i]}", dt, timestamp, x, y))

    lines = [
        f"[INFO] {sensor_id} reported at {timestamp}. Loc: ({x}, {y}). Reading accepted."
        for sensor_id, _, timestamp, x, y in records
    ]
    lines.extend([
        "[ERROR] Sensor-C3 failed at 2025-04-03 12:10:00. Loc: (invalid, 9).",
        "[WARN] Sensor-R8 reported at 2025-99-77 25:61:00. Loc: (4, 5).",
        "[INFO] Sensor-T6 reported at Jan 08 2025 10:00:00. No location data.",
        "[DEBUG] Device-Q7 reported at 2025-04-03 09:00:00. Loc: (2, 3).",
        "Corrupted line without proper info.",
    ])
    rng.shuffle(lines)

    expected_rows = []
    for sensor_id, dt, _, x, y in sorted(records, key=lambda item: item[1]):
        expected_rows.append(
            f"{sensor_id},{dt.strftime('%Y-%m-%dT%H:%M:%S')},{x},{y},{abs(x) + abs(y)}"
        )
    return "\n".join(lines) + "\n", HEADER + "\n" + "\n".join(expected_rows)


def test_script_processes_unseen_inputs_generically():
    """Exercise extraction, date normalization, validation, distance, and sorting on unseen data."""
    for count in (5, 7):
        logs, expected_csv = make_dynamic_case(count)
        with open(INPUT_PATH, "w") as f:
            f.write(logs)
        actual_csv = run_script()
        assert actual_csv == expected_csv, (
            "Script did not correctly process a generated sensor-log fixture.\n"
            f"Input:\n{logs}\nExpected:\n{expected_csv}\n\nActual:\n{actual_csv}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
