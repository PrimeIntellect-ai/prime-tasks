#!/bin/bash
mkdir -p /logs/verifier

run_checks() {
    local script=/home/user/process_benchmarks.sh

    [ -f "$script" ] || { echo "Missing $script" >&2; return 1; }
    [ -x "$script" ] || { echo "$script is not executable" >&2; return 1; }

    cp /home/user/device_info.csv /tmp/device_info.original.csv || return 1
    cp /home/user/inference_logs.csv /tmp/inference_logs.original.csv || return 1

    rm -f /home/user/metrics.csv /home/user/bootstrap_arm64.txt
    (cd /home/user && ./process_benchmarks.sh) || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import pytest

def test_metrics_csv_exists_and_content():
    file_path = "/home/user/metrics.csv"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."

    with open(file_path, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, f"{file_path} is empty."

    headers = rows[0]
    expected_headers = ["DeviceID", "Architecture", "MatrixSize", "InferenceTimeMS", "GigaFLOPS"]
    assert headers == expected_headers, f"Headers in {file_path} do not match expected. Got: {headers}"

    data_rows = rows[1:]
    assert len(data_rows) == 7, f"Expected 7 valid data rows in {file_path}, but got {len(data_rows)}."

    expected_data = {
        ("DEV1", "ARM64", "1024", "15.5", "138.547"),
        ("DEV2", "x86", "2048", "120.0", "143.166"),
        ("DEV3", "ARM64", "512", "2.1", "127.826"),
        ("DEV1", "ARM64", "1024", "16.2", "132.561"),
        ("DEV4", "RISCV", "256", "0.8", "41.943"),
        ("DEV5", "ARM64", "1024", "14.9", "144.126"),
        ("DEV5", "ARM64", "2048", "125.4", "137.001")
    }

    actual_data = set(tuple(row) for row in data_rows)
    missing = expected_data - actual_data
    extra = actual_data - expected_data

    assert not missing, f"Missing expected rows in {file_path}: {missing}"
    assert not extra, f"Unexpected extra rows in {file_path}: {extra}"

def test_bootstrap_arm64_exists_and_content():
    file_path = "/home/user/bootstrap_arm64.txt"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content, f"{file_path} is empty."

    try:
        bootstrap_mean = float(content)
    except ValueError:
        pytest.fail(f"Content of {file_path} is not a valid float: '{content}'")

    lower_bound = 136.012 - 1.5
    upper_bound = 136.012 + 1.5
    assert lower_bound <= bootstrap_mean <= upper_bound, \
        f"Bootstrap mean {bootstrap_mean} is outside the acceptable range [{lower_bound}, {upper_bound}]."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    cat << 'DYNAMIC_EOF' > /tmp/test_dynamic.py
import csv
import os
import subprocess
from collections import Counter

script = "/home/user/process_benchmarks.sh"
device_path = "/home/user/device_info.csv"
log_path = "/home/user/inference_logs.csv"
metrics_path = "/home/user/metrics.csv"
bootstrap_path = "/home/user/bootstrap_arm64.txt"

devices = [
    ["DeviceID", "Architecture", "BaseMemory"],
    ["EDGE_A", "ARM64", "3GB"],
    ["EDGE_B", "ARM64", "5GB"],
    ["EDGE_X", "x86", "7GB"],
    ["EDGE_R", "RISCV", "1GB"],
]
logs = [
    ["LogID", "DeviceID", "MatrixSize", "InferenceTimeMS"],
    ["Q1", "EDGE_A", "100", "0.2"],
    ["Q2", "EDGE_B", "100", "0.1960784314"],
    ["Q3", "EDGE_X", "50", "0.5"],
    ["Q4", "EDGE_R", "25", "0.25"],
    ["BAD_ZERO", "EDGE_A", "0", "1.0"],
    ["BAD_NEG_TIME", "EDGE_B", "64", "-3.0"],
    ["UNMATCHED", "NO_DEVICE", "128", "1.0"],
]

def render(rows):
    return "".join(",".join(row) + "\n" for row in rows)

device_text = render(devices)
log_text = render(logs)
with open(device_path, "w", newline="") as f:
    f.write(device_text)
with open(log_path, "w", newline="") as f:
    f.write(log_text)

# Derive the expected result independently before executing the submitted artifact.
architectures = {row[0]: row[1] for row in devices[1:]}
expected = []
for _, device_id, matrix_text, time_text in logs[1:]:
    if device_id not in architectures:
        continue
    matrix = float(matrix_text)
    elapsed = float(time_text)
    if matrix <= 0 or elapsed <= 0:
        continue
    gflops = (2 * matrix ** 3) / (elapsed * 1_000_000)
    expected.append((device_id, architectures[device_id], matrix_text, time_text, f"{gflops:.3f}"))

for path in (metrics_path, bootstrap_path):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass

subprocess.run([script], cwd="/home/user", check=True, timeout=30)

# Inputs are read-only sources for this task.
assert open(device_path).read() == device_text, "The script modified device_info.csv"
assert open(log_path).read() == log_text, "The script modified inference_logs.csv"
assert os.path.isfile(metrics_path), "metrics.csv was not generated"
assert os.path.isfile(bootstrap_path), "bootstrap_arm64.txt was not generated"

with open(metrics_path, newline="") as f:
    rows = list(csv.reader(f))
assert rows, "metrics.csv is empty"
assert rows[0] == ["DeviceID", "Architecture", "MatrixSize", "InferenceTimeMS", "GigaFLOPS"]
actual = [tuple(row) for row in rows[1:]]
assert Counter(actual) == Counter(expected), f"Dynamic metrics mismatch: expected {expected}, got {actual}"

content = open(bootstrap_path).read().strip()
assert content, "bootstrap_arm64.txt is empty"
try:
    bootstrap_mean = float(content)
except ValueError as exc:
    raise AssertionError(f"Bootstrap output is not a single valid float: {content!r}") from exc

arm_values = [float(row[4]) for row in expected if row[1] == "ARM64"]
true_mean = sum(arm_values) / len(arm_values)
assert true_mean - 1.5 <= bootstrap_mean <= true_mean + 1.5, \
    f"Dynamic bootstrap mean {bootstrap_mean} is not within 1.5 of {true_mean}"
DYNAMIC_EOF

    python3 /tmp/test_dynamic.py || return 1
    return 0
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

# Restore the supplied inputs after verification.
if [ -f /tmp/device_info.original.csv ]; then
    cp /tmp/device_info.original.csv /home/user/device_info.csv
fi
if [ -f /tmp/inference_logs.original.csv ]; then
    cp /tmp/inference_logs.original.csv /home/user/inference_logs.csv
fi
