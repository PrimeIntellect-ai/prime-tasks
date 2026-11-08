#!/bin/bash
mkdir -p /logs/verifier

WORKSPACE=/home/user/workspace
DATA_BACKUP=$(mktemp)
cp "$WORKSPACE/data.csv" "$DATA_BACKUP"

cleanup() {
    cp "$DATA_BACKUP" "$WORKSPACE/data.csv" 2>/dev/null || true
    rm -f "$DATA_BACKUP" "$WORKSPACE/verifier_normalize"
}
trap cleanup EXIT

run_checks() {
    cd "$WORKSPACE" || return 1
    test -f normalize.c || return 1

    # Remove any pre-fabricated artifacts, then compile and execute the submitted C source.
    rm -f inference_normalized.csv experiment_log.txt verifier_normalize
    gcc -O3 normalize.c -o verifier_normalize -lm || return 1
    timeout 10s ./verifier_normalize || return 1

    # Preserve and run the original assertions against the standard dataset.
    cat > /tmp/test_original_outputs.py <<'PY'
import os
import re
import math
import pytest

WORKSPACE_DIR = "/home/user/workspace"
LOG_FILE = os.path.join(WORKSPACE_DIR, "experiment_log.txt")
INFERENCE_CSV = os.path.join(WORKSPACE_DIR, "inference_normalized.csv")

def test_experiment_log_exists_and_format():
    assert os.path.isfile(LOG_FILE), f"File {LOG_FILE} does not exist."
    with open(LOG_FILE, 'r') as f:
        lines = f.read().strip().split('\n')
    assert len(lines) >= 1, f"Log file {LOG_FILE} is empty."
    last_line = lines[-1].strip()
    pattern = r"^TRAIN_MEAN:\s*400\.5000,\s*TRAIN_STD:\s*230\.9400,\s*INFERENCE_TIME_US:\s*\d+$"
    assert re.match(pattern, last_line) is not None, \
        f"Log line '{last_line}' does not match expected format or values (expected mean 400.5000, std 230.9400)."

def test_inference_normalized_csv_contents():
    assert os.path.isfile(INFERENCE_CSV), f"File {INFERENCE_CSV} does not exist."
    with open(INFERENCE_CSV, 'r') as f:
        lines = f.read().strip().split('\n')
    assert len(lines) == 200, f"Expected 200 lines in {INFERENCE_CSV}, got {len(lines)}."
    mean = 400.5
    std = math.sqrt(((800**2) - 1) / 12)
    for i, line in enumerate(lines):
        try:
            val = float(line)
        except ValueError:
            pytest.fail(f"Line {i} in {INFERENCE_CSV} is not a valid float: '{line}'")
        expected = (801 + i - mean) / std
        assert abs(val - expected) < 1e-3, \
            f"Line {i} mismatch: expected {expected:.4f}, got {val}"
PY
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_original_outputs.py -x --tb=short || return 1

    # Replace the dataset with unpredictable values and derive the expected answers.
    python3 - <<'PY' || return 1
import json
import math
import secrets
import struct

workspace = "/home/user/workspace"
rng = secrets.SystemRandom()
raw = [rng.randint(-2000000, 3000000) / 1000.0 for _ in range(1000)]
with open(workspace + "/data.csv", "w") as f:
    for value in raw:
        f.write(f"{value:.3f}\n")

# normalize.c stores inputs as float, so derive expectations from float32 values.
def f32(value):
    return struct.unpack("f", struct.pack("f", value))[0]

data = [f32(value) for value in raw]
mean = sum(data[:800]) / 800.0
variance = sum((value - mean) * (value - mean) for value in data[:800]) / 800.0
std = math.sqrt(variance)
expected = [(value - mean) / std for value in data[800:]]
with open("/tmp/dynamic_expected.json", "w") as f:
    json.dump({"mean": format(mean, ".4f"), "std": format(std, ".4f"), "values": expected}, f)
PY

    rm -f inference_normalized.csv
    printf 'PREEXISTING_RECORD\n' > experiment_log.txt
    timeout 10s ./verifier_normalize || return 1

    python3 - <<'PY' || return 1
import json
import math
import os
import re

workspace = "/home/user/workspace"
output_path = workspace + "/inference_normalized.csv"
log_path = workspace + "/experiment_log.txt"

assert os.path.isfile(output_path), "Program did not create inference_normalized.csv"
assert os.path.isfile(log_path), "Program did not create experiment_log.txt"
with open("/tmp/dynamic_expected.json") as f:
    expected = json.load(f)

with open(output_path, "r") as f:
    text = f.read()
lines = text.splitlines()
assert len(lines) == 200, f"Expected 200 inference rows, got {len(lines)}"
assert text.endswith("\n"), "Each output value must be written as a line"
for i, (line, wanted) in enumerate(zip(lines, expected["values"])):
    assert re.fullmatch(r"-?\d+\.\d{4}", line), \
        f"Inference row {i} is not formatted with exactly four decimal places: {line!r}"
    actual = float(line)
    assert math.isfinite(actual) and abs(actual - wanted) <= 5.1e-5, \
        f"Inference row {i} mismatch: expected {wanted:.4f}, got {line}"

with open(log_path, "r") as f:
    log_lines = f.read().splitlines()
assert len(log_lines) == 2 and log_lines[0] == "PREEXISTING_RECORD", \
    "The experiment record must be appended without replacing existing log contents"
pattern = re.compile(
    r"^TRAIN_MEAN: (-?\d+\.\d{4}), TRAIN_STD: (-?\d+\.\d{4}), INFERENCE_TIME_US: (\d+)$"
)
match = pattern.fullmatch(log_lines[1])
assert match, f"Experiment record has the wrong format: {log_lines[1]!r}"
assert match.group(1) == expected["mean"], \
    f"Wrong dynamic training mean: expected {expected['mean']}, got {match.group(1)}"
assert match.group(2) == expected["std"], \
    f"Wrong dynamic training standard deviation: expected {expected['std']}, got {match.group(2)}"
PY
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
