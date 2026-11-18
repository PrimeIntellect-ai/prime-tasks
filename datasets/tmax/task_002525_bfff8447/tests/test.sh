#!/bin/bash
set -u
mkdir -p /logs/verifier

backup_dir=$(mktemp -d)
for sensor in A B C; do
    cp "/home/user/data/sensor_${sensor}.csv" "$backup_dir/sensor_${sensor}.csv" 2>/dev/null || true
done
if [ -f /home/user/output/merged_sensors.csv ]; then
    cp /home/user/output/merged_sensors.csv "$backup_dir/merged_sensors.csv"
    touch "$backup_dir/had_output"
fi

cleanup() {
    for sensor in A B C; do
        if [ -f "$backup_dir/sensor_${sensor}.csv" ]; then
            cp "$backup_dir/sensor_${sensor}.csv" "/home/user/data/sensor_${sensor}.csv"
        fi
    done
    if [ -f "$backup_dir/had_output" ]; then
        cp "$backup_dir/merged_sensors.csv" /home/user/output/merged_sensors.csv
    else
        rm -f /home/user/output/merged_sensors.csv
    fi
    rm -rf "$backup_dir"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
from collections import defaultdict

def test_output_file_exists():
    output_path = "/home/user/output/merged_sensors.csv"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

def test_output_content_correct():
    output_path = "/home/user/output/merged_sensors.csv"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    sensor_files = {
        'A': "/home/user/data/sensor_A.csv",
        'B': "/home/user/data/sensor_B.csv",
        'C': "/home/user/data/sensor_C.csv"
    }

    buckets = defaultdict(lambda: {'A': [], 'B': [], 'C': []})

    for sensor, filepath in sensor_files.items():
        if not os.path.isfile(filepath):
            continue
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                parts = line.split(',')
                if len(parts) != 2:
                    continue
                try:
                    ts = int(parts[0])
                    val = float(parts[1])
                    bucket_ts = (ts // 60) * 60
                    buckets[bucket_ts][sensor].append(val)
                except ValueError:
                    continue

    expected_rows = []
    for bucket_ts in sorted(buckets.keys()):
        row = [str(bucket_ts)]
        for sensor in ['A', 'B', 'C']:
            vals = buckets[bucket_ts][sensor]
            if vals:
                avg = sum(vals) / len(vals)
                row.append(f"{avg:.2f}")
            else:
                row.append("-999.00")
        expected_rows.append(",".join(row))

    expected_header = "bucket_timestamp,avg_A,avg_B,avg_C"

    with open(output_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) > 0, "Output file is empty."
    assert actual_lines[0] == expected_header, f"Header is incorrect. Expected: {expected_header}, Got: {actual_lines[0]}"

    actual_data = actual_lines[1:]
    assert len(actual_data) == len(expected_rows), f"Expected {len(expected_rows)} data rows, but got {len(actual_data)}."

    for i, (expected, actual) in enumerate(zip(expected_rows, actual_data)):
        assert actual == expected, f"Row {i+1} mismatch. Expected: {expected}, Got: {actual}"
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/check_dynamic.py
import os
from collections import defaultdict

files = {
    "A": "/home/user/data/sensor_A.csv",
    "B": "/home/user/data/sensor_B.csv",
    "C": "/home/user/data/sensor_C.csv",
}
buckets = defaultdict(lambda: {"A": [], "B": [], "C": []})
for sensor, path in files.items():
    with open(path) as f:
        for raw in f:
            parts = raw.strip().split(",")
            if len(parts) != 2:
                continue
            try:
                timestamp = int(parts[0])
                value = float(parts[1])
            except ValueError:
                continue
            buckets[(timestamp // 60) * 60][sensor].append(value)

expected = ["bucket_timestamp,avg_A,avg_B,avg_C"]
for timestamp in sorted(buckets):
    row = [str(timestamp)]
    for sensor in ("A", "B", "C"):
        values = buckets[timestamp][sensor]
        row.append(f"{sum(values) / len(values):.2f}" if values else "-999.00")
    expected.append(",".join(row))

output = "/home/user/output/merged_sensors.csv"
assert os.path.isfile(output), "Program did not create merged_sensors.csv"
with open(output) as f:
    actual = [line.strip() for line in f if line.strip()]
assert actual == expected, f"Dynamic-input output mismatch. Expected {expected}, got {actual}"
DYNAMIC_EOF

run_verification() {
    [ -f /home/user/process_sensors.c ] || return 1
    [ ! -L /home/user/process_sensors.c ] || return 1
    gcc -std=c11 -O2 -Wall -Wextra /home/user/process_sensors.c -o /tmp/process_sensors_verifier -lm || return 1
    [ -x /tmp/process_sensors_verifier ] || return 1

    local hashes_before hashes_after
    hashes_before=$(sha256sum /home/user/data/sensor_A.csv /home/user/data/sensor_B.csv /home/user/data/sensor_C.csv) || return 1
    rm -f /home/user/output/merged_sensors.csv
    timeout 10s /tmp/process_sensors_verifier || return 1
    hashes_after=$(sha256sum /home/user/data/sensor_A.csv /home/user/data/sensor_B.csv /home/user/data/sensor_C.csv) || return 1
    [ "$hashes_before" = "$hashes_after" ] || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    cat > /home/user/data/sensor_A.csv <<'EOF'
120,1.0
179,3.0
180,5.0
360,-2.5
EOF
    cat > /home/user/data/sensor_B.csv <<'EOF'
121,10.0
240,20.0
259,22.0
EOF
    cat > /home/user/data/sensor_C.csv <<'EOF'
181,7.0
300,8.0
301,10.0
EOF

    hashes_before=$(sha256sum /home/user/data/sensor_A.csv /home/user/data/sensor_B.csv /home/user/data/sensor_C.csv) || return 1
    rm -f /home/user/output/merged_sensors.csv
    timeout 10s /tmp/process_sensors_verifier || return 1
    hashes_after=$(sha256sum /home/user/data/sensor_A.csv /home/user/data/sensor_B.csv /home/user/data/sensor_C.csv) || return 1
    [ "$hashes_before" = "$hashes_after" ] || return 1
    python3 /tmp/check_dynamic.py || return 1
}

if run_verification; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
