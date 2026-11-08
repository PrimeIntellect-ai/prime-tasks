#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import argparse
import json
import math
import os
import secrets
import subprocess

import pytest

WORKSPACE = "/home/user/workspace"
BENCHMARK = os.path.join(WORKSPACE, "benchmark.py")
RUN_SCRIPT = os.path.join(WORKSPACE, "run_experiments.sh")
TRACKING_FILE = "/home/user/results/tracking.jsonl"


def get_expected_trace(N, seed):
    """Compute the expected trace independently using numpy."""
    script = f"""
import numpy as np
np.random.seed({seed})
A = np.random.rand({N}, {N})
B = A @ A.T
print(float(np.trace(B)))
"""
    result = subprocess.run(
        ["python3", "-c", script], capture_output=True, text=True, check=True
    )
    return float(result.stdout.strip())


def assert_valid_png(path):
    assert os.path.isfile(path), f"Plot file {path} is missing."
    assert os.path.getsize(path) > 8, f"Plot file {path} is empty or truncated."
    with open(path, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", f"Plot file {path} is not a PNG."

    check = subprocess.run(
        [
            "python3",
            "-c",
            "import matplotlib.image as m; import sys; "
            "a=m.imread(sys.argv[1]); "
            "assert a.ndim in (2,3) and a.shape[0] > 0 and a.shape[1] > 0",
            path,
        ],
        capture_output=True,
        text=True,
    )
    assert check.returncode == 0, f"Plot file {path} is not a readable PNG: {check.stderr}"


def test_run_experiments_script_exists_and_executable():
    assert os.path.isfile(RUN_SCRIPT), f"Bash script {RUN_SCRIPT} is missing."
    assert os.access(RUN_SCRIPT, os.X_OK), f"Bash script {RUN_SCRIPT} is not executable."


def test_benchmark_executes_on_unseen_inputs():
    assert os.path.isfile(BENCHMARK), f"Benchmark script {BENCHMARK} is missing."

    # These cases are selected at verification time and exclude the pipeline's fixed sizes.
    cases = []
    while len(cases) < 3:
        case = (secrets.randbelow(45) + 6, secrets.randbelow(2_000_000_000))
        if case[0] not in (100, 200, 300) and case not in cases:
            cases.append(case)

    for batch_size, seed in cases:
        plot_path = os.path.join(WORKSPACE, "plots", f"plot_{batch_size}.png")
        if os.path.exists(plot_path):
            os.remove(plot_path)

        result = subprocess.run(
            [
                "runuser", "-u", "user", "--",
                "python3", BENCHMARK,
                "--batch_size", str(batch_size),
                "--seed", str(seed),
            ],
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert result.returncode == 0, (
            f"benchmark.py failed for N={batch_size}, seed={seed}: {result.stderr}"
        )
        lines = result.stdout.splitlines()
        assert len(lines) == 1 and lines[0].strip(), (
            f"benchmark.py must print exactly one JSON line, got: {result.stdout!r}"
        )
        try:
            data = json.loads(lines[0])
        except json.JSONDecodeError as exc:
            pytest.fail(f"benchmark.py output is not valid JSON: {exc}: {lines[0]!r}")

        assert set(data) == {"batch_size", "seed", "time", "trace"}
        assert data["batch_size"] == batch_size
        assert data["seed"] == seed
        assert isinstance(data["time"], (int, float)) and not isinstance(data["time"], bool)
        assert math.isfinite(data["time"]) and data["time"] >= 0
        assert isinstance(data["trace"], (int, float)) and not isinstance(data["trace"], bool)
        expected = get_expected_trace(batch_size, seed)
        assert math.isclose(data["trace"], expected, rel_tol=1e-5), (
            f"Trace {data['trace']} does not match expected {expected}"
        )
        assert_valid_png(plot_path)


def test_execute_pipeline_as_user_and_capture_benchmark_outputs():
    os.makedirs(os.path.dirname(TRACKING_FILE), exist_ok=True)
    if os.path.exists(TRACKING_FILE):
        os.remove(TRACKING_FILE)
    for batch_size in (100, 200, 300):
        path = os.path.join(WORKSPACE, "plots", f"plot_{batch_size}.png")
        if os.path.exists(path):
            os.remove(path)

    backup = BENCHMARK + ".verifier-original"
    log_path = f"/tmp/benchmark-invocations-{secrets.token_hex(12)}.jsonl"
    assert not os.path.exists(backup), f"Unexpected verifier backup path already exists: {backup}"

    os.replace(BENCHMARK, backup)
    wrapper = f'''#!/usr/bin/env python3
import json
import subprocess
import sys

result = subprocess.run(
    [sys.executable, {backup!r}] + sys.argv[1:],
    capture_output=True,
    text=True,
)
with open({log_path!r}, "a") as f:
    f.write(json.dumps({{
        "argv": sys.argv[1:],
        "stdout": result.stdout,
        "returncode": result.returncode,
    }}) + "\\n")
sys.stdout.write(result.stdout)
sys.stderr.write(result.stderr)
raise SystemExit(result.returncode)
'''
    try:
        with open(BENCHMARK, "w") as f:
            f.write(wrapper)
        os.chmod(BENCHMARK, 0o755)
        result = subprocess.run(
            ["runuser", "-u", "user", "--", "/bin/bash", RUN_SCRIPT],
            cwd=WORKSPACE,
            capture_output=True,
            text=True,
            timeout=180,
        )
    finally:
        if os.path.exists(BENCHMARK):
            os.remove(BENCHMARK)
        os.replace(backup, BENCHMARK)

    assert result.returncode == 0, (
        f"run_experiments.sh failed when run as user: stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    assert os.path.isfile(log_path), "The pipeline did not invoke benchmark.py."
    with open(log_path) as f:
        records = [json.loads(line) for line in f if line.strip()]
    os.remove(log_path)

    assert len(records) == 3, f"Expected 3 benchmark.py invocations, found {len(records)}."
    expected_pairs = [(100, 123), (200, 123), (300, 123)]
    benchmark_outputs = []
    for i, record in enumerate(records):
        parser = argparse.ArgumentParser(add_help=False)
        parser.add_argument("--batch_size", type=int, required=True)
        parser.add_argument("--seed", type=int, required=True)
        args = parser.parse_args(record["argv"])
        assert (args.batch_size, args.seed) == expected_pairs[i]
        assert record["returncode"] == 0
        output_lines = record["stdout"].splitlines()
        assert len(output_lines) == 1 and output_lines[0].strip()
        benchmark_outputs.append(json.loads(output_lines[0]))

    assert os.path.isfile(TRACKING_FILE), f"Tracking file {TRACKING_FILE} is missing."
    with open(TRACKING_FILE) as f:
        tracked = [json.loads(line) for line in f if line.strip()]
    assert tracked == benchmark_outputs, (
        "tracking.jsonl must contain the JSON outputs produced by the three benchmark runs."
    )


def test_plots_created():
    plot_dir = os.path.join(WORKSPACE, "plots")
    assert os.path.isdir(plot_dir), f"Plots directory {plot_dir} is missing."

    for batch_size in [100, 200, 300]:
        plot_file = os.path.join(plot_dir, f"plot_{batch_size}.png")
        assert os.path.isfile(plot_file), f"Plot file {plot_file} is missing."
        assert_valid_png(plot_file)


def test_tracking_jsonl_content():
    assert os.path.isfile(TRACKING_FILE), f"Tracking file {TRACKING_FILE} is missing."

    with open(TRACKING_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {TRACKING_FILE}, found {len(lines)}."

    expected_batch_sizes = [100, 200, 300]
    expected_seed = 123

    for i, line in enumerate(lines):
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} in {TRACKING_FILE} is not valid JSON: {line}")

        assert "batch_size" in data, f"Missing 'batch_size' in JSON line {i+1}."
        assert "seed" in data, f"Missing 'seed' in JSON line {i+1}."
        assert "time" in data, f"Missing 'time' in JSON line {i+1}."
        assert "trace" in data, f"Missing 'trace' in JSON line {i+1}."

        batch_size = data["batch_size"]
        assert batch_size == expected_batch_sizes[i], (
            f"Expected batch_size {expected_batch_sizes[i]} in line {i+1}, got {batch_size}."
        )

        seed = data["seed"]
        assert seed == expected_seed, (
            f"Expected seed {expected_seed} in line {i+1}, got {seed}."
        )

        trace = data["trace"]
        expected_trace = get_expected_trace(batch_size, seed)
        assert math.isclose(trace, expected_trace, rel_tol=1e-5), (
            f"Trace value {trace} for batch_size {batch_size} does not match expected {expected_trace}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
