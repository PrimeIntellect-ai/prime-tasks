#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import shutil
import subprocess
import tempfile

import pytest

FIXED_BIN = "/home/user/bin/train_model_fixed"
SOURCE = "/home/user/src/train_model.c"
DATASET = "/home/user/data/dataset.csv"
METRICS = "/home/user/metrics.txt"
ORACLE = "/app/oracle_pipeline"

FLOAT_RE = re.compile(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?")


def get_true_mse():
    """Run the oracle, retaining the original verifier's fallback."""
    if os.path.isfile(ORACLE) and os.access(ORACLE, os.X_OK):
        try:
            result = subprocess.run(
                [ORACLE], capture_output=True, text=True, check=True, timeout=10
            )
            floats = FLOAT_RE.findall(result.stdout)
            if floats:
                return float(floats[-1])
        except Exception:
            pass
    return 2.4512


def run_pipeline(path):
    result = subprocess.run(
        [path], cwd="/home/user", capture_output=True, text=True,
        timeout=15, check=True
    )
    matches = re.findall(
        r"OOB\s+MSE\s*:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)",
        result.stdout,
        flags=re.IGNORECASE,
    )
    assert matches, f"Pipeline did not print an 'OOB MSE: <value>' result. Output: {result.stdout!r}"
    value = float(matches[-1])
    assert math.isfinite(value), "Pipeline produced a non-finite OOB MSE"
    return value


def strip_c_comments(source):
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    return re.sub(r"//[^\n]*", "", source)


def test_fixed_binary_exists():
    assert os.path.isfile(FIXED_BIN), f"Fixed binary is missing: {FIXED_BIN}"
    assert os.access(FIXED_BIN, os.X_OK), f"Fixed binary is not executable: {FIXED_BIN}"
    with open(FIXED_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Fixed pipeline must be a compiled ELF binary"
    if os.path.isfile(ORACLE):
        assert not shutil._samefile(FIXED_BIN, ORACLE)
        with open(FIXED_BIN, "rb") as submitted, open(ORACLE, "rb") as reference:
            assert submitted.read() != reference.read(), "Submitted binary is a copy of the oracle"


def test_source_contains_requested_fix():
    assert os.path.isfile(SOURCE), f"Modified C source is missing: {SOURCE}"
    with open(SOURCE, encoding="utf-8", errors="replace") as f:
        source = strip_c_comments(f.read())

    assert re.search(r"\bsrand\s*\(\s*42\s*\)", source), "srand(42) must be retained"
    assert re.search(r"\brand\s*\(", source), "Bootstrap sampling must use rand()"
    assert re.search(r"\b100\b", source), "The implementation must perform 100 bootstraps"
    assert re.search(r"\bfor\s*\(", source), "Bootstrap processing loop is missing"
    assert re.search(r"\bmean\w*\b", source, re.IGNORECASE), "Training-sample means are not implemented"
    assert re.search(r"\b(?:std\w*|stdev\w*|sqrt\s*\()", source, re.IGNORECASE), "Training-sample standard deviations are not implemented"
    assert re.search(r"\boob\w*\b", source, re.IGNORECASE), "OOB evaluation logic is missing"
    assert "dataset.csv" in source, "The pipeline must read the requested dataset"


def test_metrics_file_and_accuracy_and_executed_artifact():
    assert os.path.isfile(METRICS), f"Metrics file is missing: {METRICS}"
    with open(METRICS, "r") as f:
        content = f.read().strip()

    assert re.fullmatch(
        r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", content
    ), f"Metrics file does not contain a single valid float. Found: {content!r}"
    agent_val = float(content)
    assert math.isfinite(agent_val), "Metrics file contains a non-finite value"

    true_val = get_true_mse()
    diff = abs(agent_val - true_val)
    threshold = 0.05
    assert diff <= threshold, (
        f"Agent MSE ({agent_val}) differs from True MSE ({true_val}) "
        f"by {diff}, which exceeds the threshold of {threshold}."
    )

    # Execute the submitted artifact and require metrics.txt to report its result.
    submitted_val = run_pipeline(FIXED_BIN)
    assert abs(submitted_val - agent_val) <= 0.05, (
        f"metrics.txt reports {agent_val}, but the submitted pipeline outputs {submitted_val}"
    )
    repeated_val = run_pipeline(FIXED_BIN)
    assert abs(repeated_val - submitted_val) <= 1e-6, "srand(42) output is not reproducible"

    # Independently compile the submitted C and ensure the installed artifact is derived from it.
    rebuilt = os.path.join(tempfile.mkdtemp(prefix="verify-build-"), "train_model_fixed")
    compile_result = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", rebuilt, "-lm"],
        capture_output=True, text=True, timeout=20
    )
    assert compile_result.returncode == 0, f"Submitted C source does not compile:\n{compile_result.stderr}"
    rebuilt_val = run_pipeline(rebuilt)
    assert abs(rebuilt_val - submitted_val) <= 0.05, (
        "Installed binary does not behave like a fresh compilation of train_model.c"
    )

    # Exercise both binaries on a derived input. For ordinary linear regression,
    # doubling every target doubles residuals and therefore quadruples MSE.
    with open(DATASET, "rb") as f:
        original_dataset = f.read()
    try:
        text = original_dataset.decode("utf-8")
        rows = list(csv.reader(text.splitlines()))
        assert len(rows) >= 2 and rows[0][-1].strip().lower() == "target", "Unexpected dataset format"
        for row in rows[1:]:
            row[-1] = format(float(row[-1]) * 2.0, ".17g")
        with open(DATASET, "w", newline="") as f:
            csv.writer(f).writerows(rows)

        submitted_probe = run_pipeline(FIXED_BIN)
        rebuilt_probe = run_pipeline(rebuilt)
        expected_probe = submitted_val * 4.0
        tolerance = max(0.05, abs(expected_probe) * 0.02)
        assert abs(submitted_probe - expected_probe) <= tolerance, (
            f"Pipeline does not process changed target data correctly: expected about "
            f"{expected_probe}, got {submitted_probe}"
        )
        assert abs(rebuilt_probe - submitted_probe) <= tolerance, (
            "Installed binary and rebuilt source disagree on the probe dataset"
        )
    finally:
        with open(DATASET, "wb") as f:
            f.write(original_dataset)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
