#!/bin/bash
set -u
mkdir -p /logs/verifier
passed=1

RAW=/home/user/raw_sensors.csv
OUTPUT=/home/user/processed_sensors.csv
SCRIPT=/home/user/process_data.sh
BACKUP=/root/raw_sensors.verifier_backup

if [ -e "$RAW" ]; then
    cp -a "$RAW" "$BACKUP"
else
    rm -f "$BACKUP"
fi

cleanup() {
    if [ -e "$BACKUP" ]; then
        cp -a "$BACKUP" "$RAW"
    else
        rm -f "$RAW"
    fi
}
trap cleanup EXIT

cat > "$RAW" <<'EOF'
Timestamp,R1_Temp,R1_Hum,R2_Temp,R2_Hum
1000,22.0,45.0,23.5,42.0
1060,22.1,45.2,23.6,42.1
1120,22.5,45.1,23.7,42.0
1180,28.0,46.0,23.6,42.2
1240,22.2,45.5,23.8,42.1
EOF
chmod 666 "$RAW"
rm -f "$OUTPUT"

if ! runuser -u user -- bash -c 'cd /home/user && timeout 20s ./process_data.sh'; then
    passed=0
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import pytest

PROCESSED_CSV = "/home/user/processed_sensors.csv"
SCRIPT_PATH = "/home/user/process_data.sh"

EXPECTED_DATA = [
    ["1000", "Rack1", "Humidity", "45.0", "45.00", "0.00"],
    ["1060", "Rack1", "Humidity", "45.2", "45.10", "0.10"],
    ["1120", "Rack1", "Humidity", "45.1", "45.10", "0.00"],
    ["1180", "Rack1", "Humidity", "46.0", "45.43", "0.57"],
    ["1240", "Rack1", "Humidity", "45.5", "45.53", "0.03"],
    ["1000", "Rack1", "Temperature", "22.0", "22.00", "0.00"],
    ["1060", "Rack1", "Temperature", "22.1", "22.05", "0.05"],
    ["1120", "Rack1", "Temperature", "22.5", "22.20", "0.30"],
    ["1180", "Rack1", "Temperature", "28.0", "24.20", "3.80"],
    ["1240", "Rack1", "Temperature", "22.2", "24.23", "2.03"],
    ["1000", "Rack2", "Humidity", "42.0", "42.00", "0.00"],
    ["1060", "Rack2", "Humidity", "42.1", "42.05", "0.05"],
    ["1120", "Rack2", "Humidity", "42.0", "42.03", "0.03"],
    ["1180", "Rack2", "Humidity", "42.2", "42.10", "0.10"],
    ["1240", "Rack2", "Humidity", "42.1", "42.10", "0.00"],
    ["1000", "Rack2", "Temperature", "23.5", "23.50", "0.00"],
    ["1060", "Rack2", "Temperature", "23.6", "23.55", "0.05"],
    ["1120", "Rack2", "Temperature", "23.7", "23.60", "0.10"],
    ["1180", "Rack2", "Temperature", "23.6", "23.63", "0.03"],
    ["1240", "Rack2", "Temperature", "23.8", "23.70", "0.10"]
]

def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

def test_processed_csv_exists():
    assert os.path.exists(PROCESSED_CSV), f"Output file {PROCESSED_CSV} does not exist."
    assert os.path.isfile(PROCESSED_CSV), f"Output path {PROCESSED_CSV} is not a file."

def test_processed_csv_format_and_content():
    with open(PROCESSED_CSV, "r", newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"File {PROCESSED_CSV} is empty.")

        expected_header = ["Timestamp", "RackID", "Metric", "Value", "MovingAvg", "Distance"]
        assert header == expected_header, f"Header mismatch. Expected {expected_header}, got {header}"
        rows = list(reader)

    assert len(rows) == len(EXPECTED_DATA), f"Expected {len(EXPECTED_DATA)} rows, but got {len(rows)}."

    for i, (actual_row, expected_row) in enumerate(zip(rows, EXPECTED_DATA)):
        assert len(actual_row) == 6, f"Row {i+1} does not have exactly 6 columns: {actual_row}"
        assert actual_row[0] == expected_row[0], f"Row {i+1} Timestamp mismatch: expected {expected_row[0]}, got {actual_row[0]}"
        assert actual_row[1] == expected_row[1], f"Row {i+1} RackID mismatch: expected {expected_row[1]}, got {actual_row[1]}"
        assert actual_row[2] == expected_row[2], f"Row {i+1} Metric mismatch: expected {expected_row[2]}, got {actual_row[2]}"

        try:
            actual_val = float(actual_row[3])
            expected_val = float(expected_row[3])
            assert abs(actual_val - expected_val) < 1e-5, f"Row {i+1} Value mismatch: expected {expected_val}, got {actual_val}"
        except ValueError:
            pytest.fail(f"Row {i+1} Value '{actual_row[3]}' is not a valid float.")

        assert "." in actual_row[4] and len(actual_row[4].split(".")[1]) == 2, f"Row {i+1} MovingAvg '{actual_row[4]}' not formatted to 2 decimal places."
        assert "." in actual_row[5] and len(actual_row[5].split(".")[1]) == 2, f"Row {i+1} Distance '{actual_row[5]}' not formatted to 2 decimal places."

        try:
            actual_ma = float(actual_row[4])
            expected_ma = float(expected_row[4])
            assert abs(actual_ma - expected_ma) < 1e-2, f"Row {i+1} MovingAvg mismatch: expected {expected_ma}, got {actual_ma}"
            actual_dist = float(actual_row[5])
            expected_dist = float(expected_row[5])
            assert abs(actual_dist - expected_dist) < 1e-2, f"Row {i+1} Distance mismatch: expected {expected_dist}, got {actual_dist}"
        except ValueError:
            pytest.fail(f"Row {i+1} MovingAvg/Distance contains invalid floats.")
TEST_EOF

if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    passed=0
fi

DYNAMIC_ORACLE=/root/verifier_dynamic_raw.csv
if ! python3 - <<'PY'
import csv
import os
import secrets

path = "/root/verifier_dynamic_raw.csv"
base = 200000 + secrets.randbelow(500000)
timestamps = []
current = base
for _ in range(7):
    current += 11 + secrets.randbelow(79)
    timestamps.append(current)

rows = []
bases = [1800, 3500, 2100, 3900]
for ts in timestamps:
    values = [(b + 2 * secrets.randbelow(500)) / 100 for b in bases]
    rows.append([str(ts)] + [f"{v:.2f}" for v in values])

# The input is deliberately not chronological, so the script must sort each group.
secrets.SystemRandom().shuffle(rows)
with open(path, "w", newline="") as f:
    writer = csv.writer(f, lineterminator="\n")
    writer.writerow(["Timestamp", "R1_Temp", "R1_Hum", "R2_Temp", "R2_Hum"])
    writer.writerows(rows)
os.chmod(path, 0o600)
PY
then
    passed=0
fi

if [ -f "$DYNAMIC_ORACLE" ]; then
    cp "$DYNAMIC_ORACLE" "$RAW"
    chmod 666 "$RAW"
    rm -f "$OUTPUT"
    if ! runuser -u user -- bash -c 'cd /home/user && timeout 20s ./process_data.sh'; then
        passed=0
    fi
else
    passed=0
fi

cat <<'DYNAMIC_EOF' > /tmp/test_dynamic_state.py
import csv
import os
import re
from collections import defaultdict
from decimal import Decimal, ROUND_HALF_UP

SOURCE = "/root/verifier_dynamic_raw.csv"
OUTPUT = "/home/user/processed_sensors.csv"
HEADER = ["Timestamp", "RackID", "Metric", "Value", "MovingAvg", "Distance"]
TWO_PLACES = re.compile(r"^-?\d+\.\d{2}$")

def rounded(value):
    return value.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

def derive_expected():
    groups = defaultdict(list)
    with open(SOURCE, newline="") as f:
        reader = csv.reader(f)
        source_header = next(reader)
        columns = []
        for index, name in enumerate(source_header[1:], 1):
            match = re.fullmatch(r"R([12])_(Temp|Hum)", name)
            assert match is not None
            rack = "Rack" + match.group(1)
            metric = {"Temp": "Temperature", "Hum": "Humidity"}[match.group(2)]
            columns.append((index, rack, metric))
        for row in reader:
            for index, rack, metric in columns:
                groups[(rack, metric)].append((int(row[0]), row[0], row[index], Decimal(row[index])))

    expected = []
    for rack, metric in sorted(groups):
        history = []
        for _, timestamp, value_text, value in sorted(groups[(rack, metric)]):
            history.append(value)
            window = history[-3:]
            average = sum(window, Decimal("0")) / Decimal(len(window))
            distance = abs(value - average)
            expected.append((timestamp, rack, metric, value_text, rounded(average), rounded(distance)))
    return expected

def test_dynamic_output_is_derived_from_new_input():
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} does not exist after executing the script."
    assert os.path.isfile(OUTPUT), f"Output path {OUTPUT} is not a file."
    with open(OUTPUT, newline="") as f:
        reader = csv.reader(f)
        actual_header = next(reader, None)
        actual = list(reader)

    assert actual_header == HEADER
    expected = derive_expected()
    assert len(actual) == len(expected)

    for number, (row, wanted) in enumerate(zip(actual, expected), 1):
        assert len(row) == 6, f"Dynamic row {number} does not have exactly 6 columns: {row}"
        timestamp, rack, metric, value_text, moving_avg, distance = wanted
        assert row[0] == timestamp, f"Dynamic row {number} timestamp/order mismatch"
        assert row[1] == rack, f"Dynamic row {number} RackID/order mismatch"
        assert row[2] == metric, f"Dynamic row {number} metric/order mismatch"
        assert abs(Decimal(row[3]) - Decimal(value_text)) < Decimal("0.00001")
        assert TWO_PLACES.fullmatch(row[4]), f"Dynamic row {number} MovingAvg is not formatted to two places"
        assert TWO_PLACES.fullmatch(row[5]), f"Dynamic row {number} Distance is not formatted to two places"
        assert abs(Decimal(row[4]) - moving_avg) < Decimal("0.0051"), f"Dynamic row {number} MovingAvg mismatch"
        assert abs(Decimal(row[5]) - distance) < Decimal("0.0051"), f"Dynamic row {number} Distance mismatch"
DYNAMIC_EOF

if ! python3 -m pytest /tmp/test_dynamic_state.py -x --tb=short 2>&1; then
    passed=0
fi

if [ "$passed" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
