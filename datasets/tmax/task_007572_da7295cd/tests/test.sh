#!/bin/bash
set +e
mkdir -p /logs/verifier

BACKUP_DIR="$(mktemp -d)"
INPUTS_BACKED_UP=0

restore_inputs() {
    if [ "$INPUTS_BACKED_UP" -eq 1 ]; then
        cp "$BACKUP_DIR/raw_sensors.csv" /home/user/raw_sensors.csv
        cp "$BACKUP_DIR/calibrations.json" /home/user/calibrations.json
    fi
}

cleanup() {
    restore_inputs
    rm -rf "$BACKUP_DIR"
}
trap cleanup EXIT

run_checks() {
    [ -f /home/user/process_data.cpp ] && [ ! -L /home/user/process_data.cpp ] || return 1
    [ -f /home/user/raw_sensors.csv ] || return 1
    [ -f /home/user/calibrations.json ] || return 1

    cp /home/user/raw_sensors.csv "$BACKUP_DIR/raw_sensors.csv" || return 1
    cp /home/user/calibrations.json "$BACKUP_DIR/calibrations.json" || return 1
    INPUTS_BACKED_UP=1

    cd /home/user || return 1
    rm -f process_data
    g++ -O3 -std=c++17 process_data.cpp -o process_data || return 1
    [ -f /home/user/process_data ] && [ -x /home/user/process_data ] || return 1

    # Exercise the freshly compiled program on unpredictable inputs so static
    # output files or a program hardcoded for the image's sample cannot pass.
    python3 - <<'PY' || return 1
import csv
import json
import secrets

sid1 = "X" + secrets.token_hex(6)
sid2 = "Y" + secrets.token_hex(6)
missing = "M" + secrets.token_hex(6)
base = 1700000000 + secrets.randbelow(1000000)

# Binary-exact fractions avoid cross-language rounding ambiguity while still
# testing double-valued scales, offsets, and raw readings.
scale1 = (secrets.randbelow(25) + 3) / 8.0
offset1 = (secrets.randbelow(65) - 32) / 16.0
scale2 = (secrets.randbelow(17) + 1) / 8.0
offset2 = (secrets.randbelow(49) - 24) / 16.0

rows = [
    (str(base), sid1, (secrets.randbelow(161) - 80) / 4.0),
    (str(base + 1), missing, (secrets.randbelow(81) - 40) / 4.0),
    (str(base + 2), sid2, (secrets.randbelow(161) - 80) / 4.0),
    (str(base + 3), sid1, (secrets.randbelow(161) - 80) / 4.0),
    (str(base + 4), sid2, (secrets.randbelow(161) - 80) / 4.0),
]
calibs = {
    sid1: {"scale": scale1, "offset": offset1},
    sid2: {"scale": scale2, "offset": offset2},
}

with open("/home/user/raw_sensors.csv", "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["timestamp", "sensor_id", "raw_value"])
    for timestamp, sensor_id, raw_value in rows:
        w.writerow([timestamp, sensor_id, str(raw_value)])

with open("/home/user/calibrations.json", "w") as f:
    json.dump(calibs, f)

expected = [["timestamp", "sensor_id", "corrected_value"]]
for timestamp, sensor_id, raw_value in rows:
    if sensor_id in calibs:
        c = raw_value * calibs[sensor_id]["scale"] + calibs[sensor_id]["offset"]
        expected.append([timestamp, sensor_id, f"{c:.4f}"])

with open("/tmp/pipeline_expected.json", "w") as f:
    json.dump({"rows": expected, "count": len(expected) - 1}, f)
PY

    rm -f /home/user/processed.csv /home/user/metrics.txt
    timeout 20s /home/user/process_data || return 1

    python3 - <<'PY' || return 1
import csv
import json
import os

assert os.path.isfile("/home/user/processed.csv"), "Program did not create processed.csv"
assert os.path.isfile("/home/user/metrics.txt"), "Program did not create metrics.txt"

with open("/tmp/pipeline_expected.json") as f:
    expected = json.load(f)
with open("/home/user/processed.csv", newline="") as f:
    actual_rows = list(csv.reader(f))
with open("/home/user/metrics.txt") as f:
    actual_metrics = f.read().strip()

assert actual_rows == expected["rows"], f"Dynamic processed.csv mismatch: {actual_rows!r}"
assert actual_metrics == f"Total valid records: {expected['count']}", f"Dynamic metrics mismatch: {actual_metrics!r}"
PY

    # Restore the supplied inputs, execute the compiled artifact on them, and
    # retain the original verifier's output assertions.
    restore_inputs || return 1
    rm -f /home/user/processed.csv /home/user/metrics.txt
    timeout 20s /home/user/process_data || return 1

    cat <<'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
import pytest

def get_expected_data():
    raw_csv_path = "/home/user/raw_sensors.csv"
    calib_json_path = "/home/user/calibrations.json"

    if not os.path.exists(raw_csv_path) or not os.path.exists(calib_json_path):
        # Fallback to default if inputs are missing/moved
        return [
            ["timestamp", "sensor_id", "corrected_value"],
            ["1620000000", "S1", "12.1000"],
            ["1620000001", "S2", "21.7580"],
            ["1620000002", "S1", "12.2200"],
            ["1620000004", "S2", "21.6600"]
        ], 4

    with open(calib_json_path, "r") as f:
        calibs = json.load(f)

    expected_rows = [["timestamp", "sensor_id", "corrected_value"]]
    valid_count = 0

    with open(raw_csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            sensor_id = row["sensor_id"]
            if sensor_id in calibs:
                raw_val = float(row["raw_value"])
                scale = float(calibs[sensor_id]["scale"])
                offset = float(calibs[sensor_id]["offset"])
                corrected = (raw_val * scale) + offset
                expected_rows.append([row["timestamp"], sensor_id, f"{corrected:.4f}"])
                valid_count += 1

    return expected_rows, valid_count

def test_processed_csv_content():
    processed_path = "/home/user/processed.csv"
    assert os.path.isfile(processed_path), f"Missing output file: {processed_path}"

    expected_rows, _ = get_expected_data()

    with open(processed_path, "r") as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in {processed_path}, got {len(actual_rows)}"

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}"

def test_metrics_txt_content():
    metrics_path = "/home/user/metrics.txt"
    assert os.path.isfile(metrics_path), f"Missing output file: {metrics_path}"

    _, expected_count = get_expected_data()
    expected_text = f"Total valid records: {expected_count}"

    with open(metrics_path, "r") as f:
        content = f.read().strip()

    assert content == expected_text, f"Content of {metrics_path} does not match expected. Expected '{expected_text}', got '{content}'"
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1
    return 0
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
