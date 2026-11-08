#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import re
import shutil
import statistics
import subprocess
import tempfile
import pytest

RECOVERED = b"""2023-10-01T12:00:00Z|1000042.12
2023-10-01T12:00:01Z,1000043.15 garbage
2023-10-01T12:00:02Z 1000041.99
2023-10-01T12:00:03Z|1000045.00
"""


def run_stable(values):
    script_path = "/home/user/stable_variance.sh"
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as tmp:
        for value in values:
            tmp.write(f"{value}\n")
        tmp_path = tmp.name
    try:
        return subprocess.run(
            ["bash", script_path, tmp_path],
            capture_output=True,
            text=True,
            check=False,
        )
    finally:
        os.remove(tmp_path)


def test_recovered_latency_log_exists():
    path = "/home/user/recovered_latency.log"
    assert os.path.exists(path), f"File {path} is missing."
    assert os.path.isfile(path), f"Path {path} is not a file."


def test_recovered_latency_log_contents():
    path = "/home/user/recovered_latency.log"
    with open(path, "rb") as recovered:
        actual = recovered.read()
    assert actual == RECOVERED, "The recovered file does not contain the deleted raw latency log."


def test_stable_variance_script_accuracy():
    script_path = "/home/user/stable_variance.sh"
    assert os.path.exists(script_path), f"Script {script_path} is missing."
    assert os.access(script_path, os.X_OK) or os.path.isfile(script_path), f"{script_path} must be a file."

    # Preserve the original hidden check.
    test_data = [
        5000000.001,
        5000000.002,
        5000000.003,
        5000000.005,
        5000000.008,
        5000000.013,
        5000000.021,
    ]
    true_variance = statistics.variance(test_data)
    result = run_stable(test_data)
    assert result.returncode == 0, f"{script_path} failed with return code {result.returncode} and stderr: {result.stderr}"
    output = result.stdout.strip()
    try:
        agent_variance = float(output)
    except ValueError:
        pytest.fail(f"Could not parse float from script output: '{output}'")
    error = abs(agent_variance - true_variance)
    assert error < 0.001, f"Absolute error {error} is >= 0.001. Agent output: {agent_variance}, True variance: {true_variance}"


def test_stable_variance_is_nonconstant_stable_and_formatted():
    datasets = [
        [1.0, 2.0, 3.0],
        [1000000001.0, 1000000002.0, 1000000004.0, 1000000008.0, 1000000016.0],
        [900000000001.0, 900000000003.0, 900000000006.0, 900000000010.0, 900000000015.0, 900000000021.0],
        [-7.5, -2.0, 4.25, 11.0],
    ]
    for values in datasets:
        result = run_stable(values)
        assert result.returncode == 0, f"stable_variance.sh failed for {values}: {result.stderr}"
        assert result.stderr == "", f"stable_variance.sh wrote unexpected stderr: {result.stderr!r}"
        assert re.fullmatch(r"-?\d+\.\d{4}\n?", result.stdout), \
            f"Output must contain only one variance formatted to four decimal places: {result.stdout!r}"
        expected = format(statistics.variance(values), ".4f")
        assert result.stdout.strip() == expected, \
            f"Incorrect sample variance for {values}: got {result.stdout.strip()}, expected {expected}"


def parse_numeric_file(path):
    values = []
    with open(path, "r", encoding="utf-8") as source:
        for line in source:
            text = line.strip()
            if not text:
                continue
            try:
                value = float(text)
            except ValueError:
                return None
            if not math.isfinite(value):
                return None
            values.append(value)
    return tuple(values)


def parse_single_float(path):
    try:
        with open(path, "r", encoding="utf-8") as source:
            text = source.read().strip()
        if not re.fullmatch(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", text):
            return None
        value = float(text)
        return value if math.isfinite(value) else None
    except (OSError, ValueError):
        return None


def test_regression_script_exists_and_succeeds():
    script_path = "/home/user/regression.sh"
    stable_path = "/home/user/stable_variance.sh"
    binary_path = "/app/variance_calc"
    assert os.path.exists(script_path), f"Script {script_path} is missing."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."
    assert os.path.getsize(script_path) > 0, f"Script {script_path} is empty."

    trace = "/tmp/regression_trace"
    stable_backup = "/tmp/verifier_agent_stable_variance.sh"
    binary_backup = "/tmp/verifier_original_variance_calc"
    shutil.rmtree(trace, ignore_errors=True)
    os.makedirs(trace)
    shutil.copy2(stable_path, stable_backup)
    shutil.copy2(binary_path, binary_backup)

    binary_wrapper = f'''#!/bin/bash
set -o pipefail
d=$(mktemp -d "{trace}/binary.XXXXXX")
cat > "$d/input"
"{binary_backup}" < "$d/input" | tee "$d/output"
rc=${{PIPESTATUS[0]}}
exit "$rc"
'''
    stable_wrapper = f'''#!/bin/bash
set -o pipefail
d=$(mktemp -d "{trace}/stable.XXXXXX")
if [ "$#" -ge 1 ] && [ -f "$1" ]; then
    cp -- "$1" "$d/input"
else
    : > "$d/input"
fi
bash "{stable_backup}" "$@" | tee "$d/output"
rc=${{PIPESTATUS[0]}}
exit "$rc"
'''

    try:
        with open(binary_path, "w", encoding="utf-8") as wrapper:
            wrapper.write(binary_wrapper)
        os.chmod(binary_path, 0o755)
        with open(stable_path, "w", encoding="utf-8") as wrapper:
            wrapper.write(stable_wrapper)
        os.chmod(stable_path, 0o755)

        result = subprocess.run(
            ["bash", script_path],
            capture_output=True,
            text=True,
            check=False,
            timeout=30,
        )
        assert result.returncode == 0, f"{script_path} failed with return code {result.returncode} and stderr: {result.stderr}"

        binary_runs = []
        for directory in glob.glob(f"{trace}/binary.*"):
            values = parse_numeric_file(os.path.join(directory, "input"))
            output = parse_single_float(os.path.join(directory, "output"))
            if values is not None and output is not None:
                binary_runs.append((values, output))

        stable_runs = []
        for directory in glob.glob(f"{trace}/stable.*"):
            values = parse_numeric_file(os.path.join(directory, "input"))
            output = parse_single_float(os.path.join(directory, "output"))
            if values is not None and output is not None:
                stable_runs.append((values, output))

        assert binary_runs, "regression.sh did not run /app/variance_calc on a numeric dataset."
        assert stable_runs, "regression.sh did not run /home/user/stable_variance.sh on a numeric dataset."

        demonstrated = False
        for binary_values, binary_output in binary_runs:
            if len(binary_values) < 2:
                continue
            for stable_values, stable_output in stable_runs:
                if stable_values != binary_values:
                    continue
                expected = statistics.variance(binary_values)
                stable_expected = float(format(expected, ".4f"))
                stable_ok = abs(stable_output - stable_expected) < 0.0000001
                binary_bad = abs(binary_output - expected) >= 0.001
                if stable_ok and binary_bad:
                    demonstrated = True
                    break
            if demonstrated:
                break
        assert demonstrated, \
            "regression.sh must use the same generated dataset to show that variance_calc is inaccurate while stable_variance.sh is correct."
    finally:
        if os.path.exists(stable_backup):
            shutil.copy2(stable_backup, stable_path)
        if os.path.exists(binary_backup):
            shutil.copy2(binary_backup, binary_path)
        shutil.rmtree(trace, ignore_errors=True)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
