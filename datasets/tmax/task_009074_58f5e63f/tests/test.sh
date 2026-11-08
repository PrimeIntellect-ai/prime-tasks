#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
import statistics
import subprocess

PIPELINE = "/home/user/pipeline.sh"
PROCESS = "/home/user/process.py"
DATA_DIR = "/home/user/data"
RESULTS = "/home/user/results.txt"


def read_values(path):
    with open(path, newline="") as f:
        return [float(row[0]) for row in csv.reader(f)]


def expected_line(path):
    values = read_values(path)
    variance = statistics.variance(values) if len(values) >= 2 else 0.0
    return f"{path}: {variance:.4f}"


def run_process(path):
    completed = subprocess.run(
        ["python3", PROCESS, path], text=True, capture_output=True, timeout=10
    )
    assert completed.returncode == 0, completed.stderr
    assert completed.stderr == "", completed.stderr
    return completed.stdout


def run_pipeline():
    completed = subprocess.run(
        [PIPELINE], text=True, capture_output=True, timeout=15
    )
    assert completed.returncode == 0, completed.stderr


def result_lines():
    assert os.path.exists(RESULTS), "results.txt does not exist. Did you run pipeline.sh?"
    with open(RESULTS) as f:
        return [line.strip() for line in f if line.strip()]


def test_scripts_and_final_results():
    assert os.path.isfile(PIPELINE), "pipeline.sh is missing or is not a regular file"
    assert os.access(PIPELINE, os.X_OK), "pipeline.sh is not executable"
    assert os.path.isfile(PROCESS), "process.py is missing or is not a regular file"

    with open(PROCESS) as f:
        tree = ast.parse(f.read(), filename=PROCESS)
    assertions = [node for node in ast.walk(tree) if isinstance(node, ast.Assert)]
    assert assertions, "process.py must keep an assertion that variance is non-negative"
    assert any(
        isinstance(node.test, ast.Compare)
        and any(isinstance(op, (ast.GtE, ast.LtE)) for op in node.test.ops)
        and any(isinstance(part, ast.Constant) and part.value == 0
                for part in [node.test.left, *node.test.comparators])
        for node in assertions
    ), "process.py must keep the variance >= 0 assertion"

    unstable_path = "/tmp/large close values.csv"
    with open(unstable_path, "w") as f:
        f.write("1000000000000.1\n1000000000000.2\n1000000000000.3\n1000000000000.4\n")
    assert run_process(unstable_path) == expected_line(unstable_path) + "\n"

    probe_path = os.path.join(DATA_DIR, "special $name [x];*.csv")
    with open(probe_path, "w") as f:
        f.write("7\n9\n11\n")

    with open(RESULTS, "w") as f:
        f.write("stale content\n")
    run_pipeline()
    expected_with_probe = {
        expected_line(os.path.join(DATA_DIR, "dataset 1.csv")),
        expected_line(os.path.join(DATA_DIR, "dataset 2.csv")),
        expected_line(probe_path),
    }
    assert set(result_lines()) == expected_with_probe, (
        "pipeline.sh did not correctly process every CSV filename, including the special filename"
    )

    os.remove(probe_path)
    run_pipeline()

    lines = result_lines()
    assert len(lines) == 2, f"results.txt should contain exactly 2 lines, but found {len(lines)}."

    expected = {
        "/home/user/data/dataset 1.csv: 0.0100",
        "/home/user/data/dataset 2.csv: 1.2292",
    }
    actual = set(lines)
    assert actual == expected, f"Output mismatch in results.txt. Expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
