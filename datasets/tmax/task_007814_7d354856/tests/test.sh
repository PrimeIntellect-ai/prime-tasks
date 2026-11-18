#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import tempfile

import pytest

SCRIPT = "/home/user/fit_mcmc.sh"
DATA = "/home/user/decay_data.tsv"
TRACE = "/home/user/trace.txt"
MEAN = "/home/user/k_mean.txt"

REFERENCE_AWK = r'''
BEGIN { srand(42) }
NR > 1 { observed[$1] = $2 }
END {
    k = 0.1
    current_sse = calc_sse(k)
    total = 0

    for (iteration = 1; iteration <= 1000; iteration++) {
        proposed_k = k + (rand() - 0.5) * 0.1
        proposed_sse = calc_sse(proposed_k)

        if (proposed_sse < current_sse) {
            k = proposed_k
            current_sse = proposed_sse
        } else {
            p = exp((current_sse - proposed_sse) / 100.0)
            r = rand()
            if (r < p) {
                k = proposed_k
                current_sse = proposed_sse
            }
        }

        print k > trace_path
        if (iteration > 500)
            total += k
    }

    printf "%.4f\n", total / 500.0 > mean_path
}
function calc_sse(candidate,    simulated,error,t) {
    simulated = 100
    error = 0
    for (t = 1; t <= 10; t++) {
        simulated = simulated - candidate * simulated
        error += (simulated - observed[t]) ^ 2
    }
    return error
}
'''


def test_script_exists_and_is_an_awk_shell_script():
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."
    with open(SCRIPT, "rb") as f:
        raw = f.read()
    assert raw, f"{SCRIPT} is empty."
    assert b"\x00" not in raw, f"{SCRIPT} is not a text shell script."
    text = raw.decode("utf-8", errors="replace")
    assert re.search(r"(^|[^A-Za-z0-9_])g?awk([^A-Za-z0-9_]|$)", text), (
        "fit_mcmc.sh must use awk to perform the computation."
    )


def reference_results(dataset_bytes):
    with tempfile.TemporaryDirectory() as td:
        data_path = os.path.join(td, "data.tsv")
        trace_path = os.path.join(td, "trace.txt")
        mean_path = os.path.join(td, "mean.txt")
        with open(data_path, "wb") as f:
            f.write(dataset_bytes)
        subprocess.run(
            ["gawk", "-v", f"trace_path={trace_path}",
             "-v", f"mean_path={mean_path}", REFERENCE_AWK, data_path],
            check=True, timeout=10, env={**os.environ, "LC_ALL": "C"},
        )
        with open(trace_path) as f:
            trace = [float(x) for x in f.read().strip().splitlines()]
        with open(mean_path) as f:
            mean_text = f.read().strip()
        return trace, mean_text


def run_submission(dataset_bytes):
    with open(DATA, "wb") as f:
        f.write(dataset_bytes)
    for path in (TRACE, MEAN):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ["/bin/bash", SCRIPT], cwd="/home/user", timeout=20,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        env={**os.environ, "LC_ALL": "C"},
    )
    assert result.returncode == 0, (
        f"fit_mcmc.sh exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.exists(TRACE), f"Trace file {TRACE} does not exist."
    with open(TRACE) as f:
        lines = f.read().strip().split("\n")
    assert len(lines) == 1000, (
        f"Expected exactly 1000 lines in trace.txt, but got {len(lines)}."
    )

    trace = []
    for i, line in enumerate(lines):
        try:
            value = float(line)
        except ValueError:
            pytest.fail(f"Line {i+1} in trace.txt is not a valid float: '{line}'")
        assert math.isfinite(value), f"Line {i+1} is not finite: '{line}'"
        trace.append(value)

    assert os.path.exists(MEAN), f"Mean file {MEAN} does not exist."
    with open(MEAN) as f:
        mean_content = f.read().strip()
    try:
        mean_value = float(mean_content)
    except ValueError:
        pytest.fail(f"k_mean.txt does not contain a valid float: '{mean_content}'")
    assert math.isfinite(mean_value), "k_mean.txt must contain a finite value."
    assert re.fullmatch(r"[+-]?(?:\d+\.\d{4}|\.\d{4})", mean_content), (
        "k_mean.txt must be formatted with exactly four digits after the decimal point."
    )

    calculated_mean = sum(trace[500:1000]) / 500.0
    assert abs(mean_value - calculated_mean) < 1e-3, (
        f"k_mean.txt value ({mean_value}) does not match the calculated mean "
        f"of the last 500 trace values ({calculated_mean})."
    )
    return trace, mean_content, mean_value


def assert_matches_algorithm(dataset_bytes, require_original_range=False):
    expected_trace, expected_mean = reference_results(dataset_bytes)
    actual_trace, actual_mean, actual_mean_value = run_submission(dataset_bytes)

    if require_original_range:
        assert 0.25 <= actual_mean_value <= 0.35, (
            f"Expected k_mean to be between 0.25 and 0.35, but got {actual_mean_value}."
        )

    assert len(expected_trace) == len(actual_trace) == 1000
    for i, (actual, expected) in enumerate(zip(actual_trace, expected_trace), 1):
        assert abs(actual - expected) <= 2e-5, (
            f"Trace differs from the specified seeded Metropolis-Hastings algorithm "
            f"at iteration {i}: got {actual}, expected {expected}."
        )
    assert actual_mean == expected_mean, (
        f"Incorrect last-500 mean: got {actual_mean}, expected {expected_mean}."
    )


def test_executed_script_implements_euler_mcmc():
    with open(DATA, "rb") as f:
        original = f.read()

    # A second valid dataset prevents a precomputed constant trace from passing.
    values = []
    y = 100.0
    noise = [0.4, -0.3, 0.2, -0.1, 0.35, -0.25, 0.15, -0.2, 0.1, -0.05]
    for t in range(1, 11):
        y = y * 0.82
        values.append(f"{t}\t{y + noise[t-1]:.6f}\n")
    alternate = ("t\ty\n" + "".join(values)).encode()

    try:
        assert_matches_algorithm(original, require_original_range=True)
        assert_matches_algorithm(alternate)
        # Leave the required outputs corresponding to the real experimental data.
        assert_matches_algorithm(original, require_original_range=True)
    finally:
        with open(DATA, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
