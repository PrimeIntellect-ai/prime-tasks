#!/bin/bash
mkdir -p /logs/verifier

ORIGINAL_RAW=/tmp/raw_data.original.csv
cp /home/user/raw_data.csv "$ORIGINAL_RAW"
trap 'cp "$ORIGINAL_RAW" /home/user/raw_data.csv' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import hashlib

def test_run_pipeline_exists_and_executable():
    """Check that run_pipeline.sh exists and is executable."""
    path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(path), f"Script {path} does not exist."
    assert os.access(path, os.X_OK), f"Script {path} is not executable."

def get_expected_data():
    """Compute the expected deduplicated rows and anomalies from raw_data.csv."""
    raw_path = "/home/user/raw_data.csv"
    assert os.path.isfile(raw_path), f"Raw data file {raw_path} is missing."

    with open(raw_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, "raw_data.csv is empty."

    data_lines = lines[1:]

    seen_hashes = set()
    deduped_rows = []

    # Phase 1: Deduplication
    for line in data_lines:
        h = hashlib.md5(line.encode('utf-8')).hexdigest()
        if h not in seen_hashes:
            seen_hashes.add(h)
            deduped_rows.append((h, line))

    # Phase 2: Rolling Statistics & Anomaly Detection
    history = {}
    anomalies = []
    for h, line in deduped_rows:
        parts = line.split(',')
        timestamp, sensor, val_str = parts[0], parts[1], parts[2]
        val = float(val_str)

        sensor_hist = history.get(sensor, [])
        if len(sensor_hist) > 0:
            avg = sum(sensor_hist) / len(sensor_hist)
            if val > 2.0 * avg:
                anomalies.append(f"{timestamp},{sensor},{val_str},{avg:.2f}")

        sensor_hist.append(val)
        if len(sensor_hist) > 3:
            sensor_hist.pop(0)
        history[sensor] = sensor_hist

    return deduped_rows, anomalies

def test_deduped_csv():
    """Validate the contents of deduped.csv."""
    deduped_path = "/home/user/deduped.csv"
    assert os.path.isfile(deduped_path), f"File {deduped_path} not found."

    expected_deduped, _ = get_expected_data()

    with open(deduped_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, f"{deduped_path} is empty."
    assert lines[0] == "hash,timestamp,sensor_id,value", f"Incorrect header in {deduped_path}."

    actual_data = lines[1:]
    assert len(actual_data) == len(expected_deduped), f"Incorrect number of rows in {deduped_path}."

    for i, (expected_h, expected_line) in enumerate(expected_deduped):
        expected_row = f"{expected_h},{expected_line}"
        assert actual_data[i] == expected_row, f"Row {i+1} mismatch in {deduped_path}. Expected: {expected_row}, Got: {actual_data[i]}"

def test_anomalies_csv():
    """Validate the contents of anomalies.csv."""
    anomalies_path = "/home/user/anomalies.csv"
    assert os.path.isfile(anomalies_path), f"File {anomalies_path} not found."

    _, expected_anomalies = get_expected_data()

    with open(anomalies_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, f"{anomalies_path} is empty."
    assert lines[0] == "timestamp,sensor_id,value,rolling_avg", f"Incorrect header in {anomalies_path}."

    actual_data = lines[1:]
    assert len(actual_data) == len(expected_anomalies), f"Incorrect number of rows in {anomalies_path}. Expected {len(expected_anomalies)}, got {len(actual_data)}."

    for i, expected_row in enumerate(expected_anomalies):
        assert actual_data[i] == expected_row, f"Row {i+1} mismatch in {anomalies_path}. Expected: {expected_row}, Got: {actual_data[i]}"
TEST_EOF

run_and_test() {
    local failed=0
    cp /home/user/raw_data.csv /tmp/raw_data.before_run.csv
    rm -f /home/user/deduped.csv /home/user/anomalies.csv

    if ! /home/user/run_pipeline.sh; then
        failed=1
    fi

    # The pipeline is not supposed to rewrite its input.
    if ! cmp -s /tmp/raw_data.before_run.csv /home/user/raw_data.csv; then
        failed=1
    fi

    if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
        failed=1
    fi

    return "$failed"
}

overall_failed=0

# Exercise the submitted pipeline on an unpredictable additional sensor series.
python3 - <<'PY'
import secrets
path = "/home/user/raw_data.csv"
token = secrets.token_hex(8)
sensor = "V_" + token
rows = [
    f"{token}01,{sensor},10.0",
    f"{token}02,{sensor},12.0",
    f"{token}01,{sensor},10.0",
    f"{token}03,{sensor},100.0",
]
with open(path, "a") as f:
    for row in rows:
        f.write(row + "\n")
PY

if ! run_and_test; then
    overall_failed=1
fi

# Restore the supplied input and require a fresh successful run again.
cp "$ORIGINAL_RAW" /home/user/raw_data.csv
if ! run_and_test; then
    overall_failed=1
fi

if [ "$overall_failed" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
