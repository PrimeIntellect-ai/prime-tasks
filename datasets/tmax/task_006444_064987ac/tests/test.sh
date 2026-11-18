#!/bin/bash
set -u
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

ok=1
script=/home/user/prepare_data.sh
if [[ ! -f "$script" || ! -x "$script" ]]; then
    ok=0
fi

audit_log=$(mktemp /tmp/bootstrap_audit.XXXXXX)
wrapper_dir=$(mktemp -d /tmp/verifier-bin.XXXXXX)

cat > "$wrapper_dir/shuf" <<'PY_EOF'
#!/usr/bin/python3
import json
import os
import subprocess
import sys

LOG_PATH = "__AUDIT_LOG__"
args = sys.argv[1:]
repeat = False
count = None
positionals = []
i = 0
while i < len(args):
    arg = args[i]
    if arg in ("-r", "--repeat"):
        repeat = True
    elif arg in ("-n", "--head-count"):
        i += 1
        if i < len(args):
            try:
                count = int(args[i])
            except ValueError:
                pass
    elif arg.startswith("--head-count="):
        try:
            count = int(arg.split("=", 1)[1])
        except ValueError:
            pass
    elif arg.startswith("-n") and len(arg) > 2:
        try:
            count = int(arg[2:])
        except ValueError:
            pass
    elif arg == "--":
        positionals.extend(args[i + 1:])
        break
    elif not arg.startswith("-"):
        positionals.append(arg)
    i += 1

stdin_data = None
source_data = b""
if len(positionals) == 0:
    stdin_data = sys.stdin.buffer.read()
    source_data = stdin_data
elif len(positionals) == 1:
    try:
        with open(positionals[0], "rb") as f:
            source_data = f.read()
    except OSError:
        source_data = b""

proc = subprocess.run(
    ["/usr/bin/shuf"] + args,
    input=stdin_data,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
sys.stdout.buffer.write(proc.stdout)
sys.stderr.buffer.write(proc.stderr)

source_lines = source_data.decode("utf-8", "replace").splitlines()
output_lines = proc.stdout.decode("utf-8", "replace").splitlines()
try:
    with open("/home/user/engineered.csv", "r") as f:
        engineered_rows = f.read().strip().splitlines()[1:]
except OSError:
    engineered_rows = []

record = {
    "repeat": repeat,
    "count": count,
    "source": source_lines,
    "output": output_lines,
    "valid_source": source_lines == engineered_rows,
    "returncode": proc.returncode,
}
with open(LOG_PATH, "a") as f:
    f.write(json.dumps(record) + "\n")

sys.exit(proc.returncode)
PY_EOF
sed -i "s|__AUDIT_LOG__|$audit_log|g" "$wrapper_dir/shuf"
chmod 755 "$wrapper_dir/shuf"

if [[ "$ok" -eq 1 ]]; then
    rm -f /home/user/engineered.csv /home/user/bootstrap_means.txt /home/user/confidence_interval.txt
    if ! env PATH="$wrapper_dir:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" "$script"; then
        ok=0
    fi
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import pytest


def test_prepare_script():
    path = "/home/user/prepare_data.sh"
    assert os.path.isfile(path), f"File {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_engineered_csv():
    """Test the feature engineering output."""
    sensor_path = "/home/user/sensor_data.csv"
    engineered_path = "/home/user/engineered.csv"

    assert os.path.isfile(engineered_path), f"File {engineered_path} does not exist."
    assert os.path.isfile(sensor_path), f"File {sensor_path} does not exist."

    with open(sensor_path, "r") as f:
        sensor_lines = f.read().strip().splitlines()

    assert len(sensor_lines) > 1, "sensor_data.csv is empty or missing data."
    header = sensor_lines[0].split(',')

    v1_idx = header.index("v1")
    v2_idx = header.index("v2")
    v1_values = [float(line.split(',')[v1_idx]) for line in sensor_lines[1:]]
    max_v1 = max(v1_values)

    with open(engineered_path, "r") as f:
        eng_lines = f.read().strip().splitlines()

    assert len(eng_lines) == len(sensor_lines), "engineered.csv does not have the same number of rows as sensor_data.csv"
    assert eng_lines[0] == "id,v1,v2,v1_norm,v_diff", f"Incorrect header in engineered.csv: {eng_lines[0]}"

    for i in range(1, len(sensor_lines)):
        s_parts = sensor_lines[i].split(',')
        e_parts = eng_lines[i].split(',')

        assert len(e_parts) == 5, f"Row {i} in engineered.csv does not have 5 columns."
        assert e_parts[0:3] == s_parts[0:3], f"Row {i} original columns do not match."

        v1 = float(s_parts[v1_idx])
        v2 = float(s_parts[v2_idx])

        expected_v1_norm = f"{v1 / max_v1:.4f}"
        expected_v_diff = f"{v2 - v1:.4f}"

        assert e_parts[3] == expected_v1_norm, f"Row {i} v1_norm mismatch: expected {expected_v1_norm}, got {e_parts[3]}"
        assert e_parts[4] == expected_v_diff, f"Row {i} v_diff mismatch: expected {expected_v_diff}, got {e_parts[4]}"


def test_bootstrap_means():
    """Test the bootstrap means against the rows actually emitted by shuf."""
    means_path = "/home/user/bootstrap_means.txt"
    assert os.path.isfile(means_path), f"File {means_path} does not exist."

    with open(means_path, "r") as f:
        lines = f.read().strip().splitlines()

    assert len(lines) == 100, f"bootstrap_means.txt should have exactly 100 lines, but has {len(lines)}."

    for i, line in enumerate(lines):
        assert re.fullmatch(r"[+-]?(?:\d+\.\d{4}|\.\d{4})", line), \
            f"Line {i+1} is not formatted to exactly 4 decimal places: {line}"
        try:
            value = float(line)
            assert math.isfinite(value)
        except (ValueError, AssertionError):
            pytest.fail(f"Line {i+1} in bootstrap_means.txt is not a valid finite number: {line}")

    with open("/home/user/engineered.csv", "r") as f:
        engineered_rows = f.read().strip().splitlines()[1:]
    n = len(engineered_rows)

    with open(os.environ["AUDIT_LOG"], "r") as f:
        calls = [json.loads(line) for line in f if line.strip()]

    assert len(calls) == 100, f"Expected exactly 100 shuf calls, got {len(calls)}."
    for i, (call, reported) in enumerate(zip(calls, lines), 1):
        assert call["returncode"] == 0, f"shuf call {i} failed."
        assert call["repeat"], f"shuf call {i} did not use replacement (-r)."
        assert call["count"] == n, f"shuf call {i} did not request N={n} rows."
        assert call["valid_source"], f"shuf call {i} did not sample the engineered data rows."
        assert len(call["output"]) == n, f"shuf call {i} did not emit N={n} rows."
        try:
            expected = sum(float(row.split(',')[3]) for row in call["output"]) / n
        except (IndexError, ValueError):
            pytest.fail(f"shuf call {i} emitted a malformed engineered row.")
        assert abs(float(reported) - expected) <= 0.000051, \
            f"Bootstrap mean {i} was not calculated from its sampled rows: expected {expected:.4f}, got {reported}"


def test_confidence_interval():
    """Test the confidence_interval.txt file based on bootstrap_means.txt."""
    means_path = "/home/user/bootstrap_means.txt"
    ci_path = "/home/user/confidence_interval.txt"

    assert os.path.isfile(ci_path), f"File {ci_path} does not exist."
    assert os.path.isfile(means_path), f"File {means_path} does not exist."

    with open(means_path, "r") as f:
        means = [float(line) for line in f.read().strip().splitlines()]

    assert len(means) == 100, "bootstrap_means.txt does not have 100 valid numbers."

    sorted_means = sorted(means)

    with open(ci_path, "r") as f:
        ci_lines = f.read().strip().splitlines()

    assert len(ci_lines) == 2, f"confidence_interval.txt should have exactly 2 lines, got {len(ci_lines)}."

    try:
        lower = float(ci_lines[0])
        upper = float(ci_lines[1])
    except ValueError:
        pytest.fail("confidence_interval.txt contains non-numeric values.")

    expected_lower = sorted_means[2]
    expected_upper = sorted_means[97]

    assert abs(lower - expected_lower) < 1e-4, f"Lower bound mismatch: expected {expected_lower}, got {lower}"
    assert abs(upper - expected_upper) < 1e-4, f"Upper bound mismatch: expected {expected_upper}, got {upper}"
TEST_EOF

if [[ "$ok" -eq 1 ]] && AUDIT_LOG="$audit_log" python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

rm -rf "$wrapper_dir" "$audit_log"
