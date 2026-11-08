#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import secrets
import shutil
import subprocess
import tempfile
import uuid

import pytest


def test_graph_tool_installed_and_fixed():
    """Check if graph_tool was installed, fixed, and is functional."""
    path = "/usr/local/bin/graph_tool"
    assert os.path.isfile(path), f"Executable {path} was not installed. Did you run 'make install'?"
    assert os.access(path, os.X_OK), f"Executable {path} is not executable."

    with open(path, "r") as f:
        content = f.read()

    assert "PYTHON_EXE=python3" in content, "The graph_tool executable wrapper was not fixed to use 'python3'."
    assert "PYTHON_EXE=python2" not in content, "The graph_tool executable wrapper still uses 'python2'."

    with tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False) as f:
        f.write("A,B,C\n1,2,3\n4,5,6\n")
        input_path = f.name
    try:
        proc = subprocess.run(
            [path, "--input", input_path],
            text=True,
            capture_output=True,
            timeout=20,
        )
        assert proc.returncode == 0, f"Installed graph_tool failed: {proc.stderr}"
        assert math.isclose(float(proc.stdout.strip()), 15.75, rel_tol=1e-12, abs_tol=1e-12), (
            f"Installed graph_tool returned the wrong value: {proc.stdout!r}"
        )
    finally:
        os.unlink(input_path)


def test_analyze_script_exists():
    """Check if the analyze.sh script was created."""
    path = "/home/user/analyze.sh"
    assert os.path.isfile(path), f"Script {path} does not exist."


def test_results_json_metric():
    """Retain the original check of the required N=500 execution result."""
    path = "/home/user/results.json"
    assert os.path.isfile(path), f"Results file {path} does not exist. Did the script run successfully?"

    with open(path, "r") as f:
        try:
            res = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    assert "ci_lower" in res, "Missing 'ci_lower' key in results.json."
    assert "ci_upper" in res, "Missing 'ci_upper' key in results.json."

    REF_LOWER = 45.1
    REF_UPPER = 52.8
    err_lower = abs(res["ci_lower"] - REF_LOWER) / REF_LOWER
    err_upper = abs(res["ci_upper"] - REF_UPPER) / REF_UPPER
    max_err = max(err_lower, err_upper)

    assert max_err <= 0.05, (
        "Confidence intervals are not within the 5% tolerance. "
        f"Max error: {max_err:.4f} (Threshold: <= 0.05). "
        f"Got ci_lower={res['ci_lower']}, ci_upper={res['ci_upper']}."
    )


def test_analyze_executes_real_bootstrap_and_computes_percentiles():
    """Execute analyze.sh and independently derive its expected CI from its tool calls."""
    tool = "/usr/local/bin/graph_tool"
    backup = f"/tmp/graph_tool.backup.{uuid.uuid4().hex}"
    work = tempfile.mkdtemp(prefix="bootstrap_verify_")
    source = os.path.join(work, f"signals_{uuid.uuid4().hex}.csv")
    log_path = os.path.join(work, f"calls_{uuid.uuid4().hex}.jsonl")

    rng = secrets.SystemRandom()
    values = rng.sample(range(10000, 90000), 9)
    with open(source, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["A", "B", "C"])
        for i, value in enumerate(values):
            writer.writerow([f"{value / 137.0:.12f}", f"{i + 0.125:.3f}", f"{-i / 11.0:.12f}"])

    interceptor = r'''#!/usr/bin/env python3
import argparse
import csv
import json
import os
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--input", required=True)
args = parser.parse_args()
source_path = os.environ["VERIFY_SOURCE_CSV"]
log_path = os.environ["VERIFY_CALL_LOG"]

record = {"valid": False, "duplicate": False}
try:
    with open(source_path, newline="") as f:
        src = list(csv.reader(f))
    with open(args.input, newline="") as f:
        sampled = list(csv.reader(f))

    src_header, src_rows = src[0], src[1:]
    header = sampled[0] if sampled else None
    rows = sampled[1:] if sampled else []
    allowed = {tuple(row) for row in src_rows}
    duplicate = len({tuple(row) for row in rows}) < len(rows)
    valid = (
        os.path.realpath(args.input) != os.path.realpath(source_path)
        and header == src_header
        and len(rows) == len(src_rows)
        and all(tuple(row) in allowed for row in rows)
    )
    record["valid"] = valid
    record["duplicate"] = duplicate
    if not valid:
        raise ValueError("sample is not a same-size with-replacement CSV with the original header")

    total = 0.0
    count = 0
    for row in rows:
        try:
            total += sum(float(x) for x in row)
            count += 1
        except ValueError:
            pass
    value = total / count * 1.5 if count else 0.0
    record["value"] = value
    with open(log_path, "a") as log:
        log.write(json.dumps(record, separators=(",", ":")) + "\n")
    print(value)
except Exception as exc:
    record["error"] = str(exc)
    with open(log_path, "a") as log:
        log.write(json.dumps(record, separators=(",", ":")) + "\n")
    sys.exit(91)
'''

    shutil.copy2(tool, backup)
    try:
        with open(tool, "w") as f:
            f.write(interceptor)
        os.chmod(tool, 0o755)

        env = os.environ.copy()
        env["VERIFY_SOURCE_CSV"] = source
        env["VERIFY_CALL_LOG"] = log_path
        proc = subprocess.run(
            ["bash", "/home/user/analyze.sh", source, "500"],
            text=True,
            capture_output=True,
            env=env,
            timeout=180,
        )
        assert proc.returncode == 0, (
            f"analyze.sh failed when executed: stdout={proc.stdout!r}, stderr={proc.stderr!r}"
        )

        assert os.path.isfile(log_path), "analyze.sh never invoked graph_tool."
        with open(log_path) as f:
            calls = [json.loads(line) for line in f if line.strip()]

        assert len(calls) == 500, f"Expected exactly 500 graph_tool calls, got {len(calls)}."
        assert all(call.get("valid") for call in calls), (
            "At least one graph_tool call did not receive a same-size sampled CSV with the original header."
        )
        assert any(call.get("duplicate") for call in calls), (
            "No sampled CSV contained duplicate rows; sampling appears to be without replacement."
        )

        observed = sorted(float(call["value"]) for call in calls)
        expected_lower = observed[12]
        expected_upper = observed[487]

        with open("/home/user/results.json") as f:
            result = json.load(f)
        assert set(result) == {"ci_lower", "ci_upper"}, "results.json must contain exactly the two CI keys."
        assert isinstance(result["ci_lower"], (int, float)) and not isinstance(result["ci_lower"], bool)
        assert isinstance(result["ci_upper"], (int, float)) and not isinstance(result["ci_upper"], bool)
        assert math.isfinite(result["ci_lower"]) and math.isfinite(result["ci_upper"])
        assert math.isclose(result["ci_lower"], expected_lower, rel_tol=1e-9, abs_tol=1e-9), (
            f"Wrong 13th sorted value: expected {expected_lower}, got {result['ci_lower']}"
        )
        assert math.isclose(result["ci_upper"], expected_upper, rel_tol=1e-9, abs_tol=1e-9), (
            f"Wrong 488th sorted value: expected {expected_upper}, got {result['ci_upper']}"
        )
    finally:
        if os.path.exists(backup):
            shutil.copy2(backup, tool)
            os.unlink(backup)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
