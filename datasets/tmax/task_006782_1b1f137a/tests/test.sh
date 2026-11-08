#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/pipeline.sh"
DATASET_PATH = "/home/user/dataset.csv"
RESULTS_PATH = "/home/user/results.json"

FORBIDDEN_SOURCE = re.compile(
    r"\b(?:python(?:[0-9.]*)?|pypy(?:[0-9.]*)?|Rscript|perl|ruby|node|php|julia|lua)\b",
    re.IGNORECASE,
)
FORBIDDEN_TRACE = re.compile(
    r"(?im)^\++\s+.*(?:^|[\s/])(?:python(?:[0-9.]*)?|pypy(?:[0-9.]*)?|Rscript|perl|ruby|node|php|julia|lua)(?:\s|$)",
)


def parse_dataset(text):
    lines = text.splitlines()
    data = []
    for line in lines[1:]:
        parts = line.strip().split(',')
        if len(parts) == 2:
            data.append((float(parts[0]), float(parts[1])))
    assert len(data) == 100, f"Expected 100 data rows in dataset, got {len(data)}"
    return data


def expected_results(dataset_text):
    data = parse_dataset(dataset_text)
    train_data = data[:80]
    test_data = data[80:]

    train_x = [d[0] for d in train_data]
    train_y = [d[1] for d in train_data]
    test_x = [d[0] for d in test_data]
    test_y = [d[1] for d in test_data]

    mean_x = sum(train_x) / len(train_x)
    mean_y = sum(train_y) / len(train_y)
    std_x = math.sqrt(sum((x - mean_x) ** 2 for x in train_x) / len(train_x))
    std_y = math.sqrt(sum((y - mean_y) ** 2 for y in train_y) / len(train_y))

    train_x_scaled = [(x - mean_x) / std_x for x in train_x]
    train_y_scaled = [(y - mean_y) / std_y for y in train_y]
    test_x_scaled = [(x - mean_x) / std_x for x in test_x]
    test_y_scaled = [(y - mean_y) / std_y for y in test_y]

    sum_x2 = sum(x ** 2 for x in train_x_scaled)
    sum_xy = sum(x * y for x, y in zip(train_x_scaled, train_y_scaled))
    m = sum_xy / sum_x2
    b = (sum(train_y_scaled) - m * sum(train_x_scaled)) / len(train_x_scaled)
    preds = [m * x + b for x in test_x_scaled]
    mse = sum((actual - pred) ** 2 for actual, pred in zip(test_y_scaled, preds)) / len(test_y_scaled)

    return {
        "train_mean_X": mean_x,
        "train_std_X": std_x,
        "train_mean_Y": mean_y,
        "train_std_Y": std_y,
        "model_m": m,
        "model_b": b,
        "test_mse": mse,
    }


def make_dataset(kind):
    rows = ["Feature_X,Target_Y"]
    for i in range(1, 101):
        if kind == 1:
            x = -30.0 + i * 1.37 + ((i % 7) - 3) * 0.21
            y = -2.4 * x + 7.5 + (((i * 13) % 11) - 5) * 0.63
        else:
            x = ((i * 29) % 101) - 50 + i * 0.017
            y = 0.45 * x - 12.0 + math.sin(i * 0.7) * 8.0 + (i % 3) * 0.2
        rows.append(f"{x:.4f},{y:.4f}")
    return "\n".join(rows) + "\n"


def run_pipeline():
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)

    with tempfile.TemporaryFile(mode="w+b") as trace_file:
        env = os.environ.copy()
        env["BASH_XTRACEFD"] = str(trace_file.fileno())
        env["PS4"] = "+ "
        try:
            proc = subprocess.run(
                ["/bin/bash", "-x", SCRIPT_PATH],
                cwd="/home/user",
                env=env,
                pass_fds=(trace_file.fileno(),),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=15,
                check=False,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("pipeline.sh did not finish within 15 seconds")

        trace_file.flush()
        trace_file.seek(0)
        trace = trace_file.read().decode("utf-8", errors="replace")

    assert proc.returncode == 0, (
        "pipeline.sh exited unsuccessfully.\n"
        + proc.stderr.decode("utf-8", errors="replace")[-2000:]
    )
    assert not FORBIDDEN_TRACE.search(trace), (
        "pipeline.sh invoked a prohibited high-level scripting language"
    )
    assert os.path.isfile(RESULTS_PATH), f"Results file {RESULTS_PATH} does not exist."


def check_results(dataset_text):
    with open(RESULTS_PATH, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} is not valid JSON.")

    expected = expected_results(dataset_text)
    for key, expected_val in expected.items():
        assert key in results, f"Key '{key}' missing in results.json"
        try:
            actual_val = float(results[key])
        except (ValueError, TypeError):
            pytest.fail(f"Value for {key} in results.json is not a valid float: {results[key]}")
        assert abs(actual_val - expected_val) <= 0.0002, (
            f"Value for {key} expected ~{expected_val:.4f}, got {actual_val}"
        )


def test_pipeline_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "rb") as f:
        raw = f.read()
    assert b"\x00" not in raw, "pipeline.sh must be a text Bash script"
    source = raw.decode("utf-8", errors="strict")
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert first_line.startswith("#!") and re.search(r"\bbash\b", first_line), (
        "pipeline.sh must use a Bash shebang"
    )

    code_without_comment_lines = "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )
    assert not FORBIDDEN_SOURCE.search(code_without_comment_lines), (
        "pipeline.sh contains a prohibited high-level scripting language invocation"
    )

    syntax = subprocess.run(
        ["/bin/bash", "-n", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    assert syntax.returncode == 0, "pipeline.sh is not valid Bash syntax"


def test_results_json():
    assert os.path.isfile(DATASET_PATH), f"Dataset file {DATASET_PATH} missing."
    with open(DATASET_PATH, "r") as f:
        original_dataset = f.read()
    parse_dataset(original_dataset)

    cases = [make_dataset(1), make_dataset(2), original_dataset]
    try:
        for dataset_text in cases:
            with open(DATASET_PATH, "w") as f:
                f.write(dataset_text)
            run_pipeline()
            check_results(dataset_text)
    finally:
        with open(DATASET_PATH, "w") as f:
            f.write(original_dataset)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
