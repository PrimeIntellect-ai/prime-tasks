#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import stat
import subprocess

SCRIPT = "/home/user/optimizer.sh"
OUTPUT = "/home/user/optimal_p.txt"
TOOL = "/usr/local/bin/run_workload"
TRACE = "/tmp/optimizer_workload_trace.txt"


def install_workload(a, center, base, trace=None):
    trace_line = ""
    if trace is not None:
        trace_line = f'''printf '%s\\n' "$p_val" >> "{trace}"\n'''
    content = f'''#!/usr/bin/env bash
while getopts "p:" opt; do
  case $opt in
    p) p_val=$OPTARG ;;
    *) exit 1 ;;
  esac
done
if [ -z "$p_val" ]; then
  echo "Missing -p argument"
  exit 1
fi
{trace_line}awk -v p="$p_val" 'BEGIN {{
  latency = {a:.12f} * (p - {center:.12f}) * (p - {center:.12f}) + {base:.12f};
  printf "%.4f\\n", latency;
}}'
'''
    with open(TOOL, "w") as f:
        f.write(content)
    os.chmod(TOOL, 0o755)


def run_optimizer():
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run(
        [SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"optimizer.sh exited with {result.returncode}. stderr: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"The output file {OUTPUT} does not exist."
    with open(OUTPUT) as f:
        return f.read().strip()


def rounded_latency(p, a, center, base):
    return float(f"{a * (p - center) ** 2 + base:.4f}")


def test_optimizer_script_and_behavior():
    assert os.path.isfile(SCRIPT), f"The script {SCRIPT} does not exist or is not a file."
    assert os.access(SCRIPT, os.X_OK), f"The script {SCRIPT} is not executable."
    with open(SCRIPT, "rb") as f:
        first_line = f.readline().decode("utf-8", "replace")
    assert first_line.startswith("#!") and "bash" in first_line, \
        "optimizer.sh must be a Bash script with a Bash shebang."

    original_bytes = open(TOOL, "rb").read() if os.path.exists(TOOL) else None
    original_mode = stat.S_IMODE(os.stat(TOOL).st_mode) if os.path.exists(TOOL) else None

    try:
        # Preserve the original correctness assertion, but derive it by actually
        # running the submitted optimizer against the specified workload.
        install_workload(1.2, 14.7, 25.0)
        content = run_optimizer()
        assert content == "14.68", \
            f"Expected {OUTPUT} to contain exactly '14.68', but got '{content}'."

        # Exercise the algorithm on a different curve so a hardcoded answer or
        # empty executable cannot pass. The curve varies between verifier runs.
        rng = random.SystemRandom()
        a = rng.uniform(0.75, 1.45)
        center = rng.uniform(7.0, 18.0)
        base = rng.uniform(10.0, 40.0)
        if os.path.exists(TRACE):
            os.unlink(TRACE)
        install_workload(a, center, base, TRACE)
        dynamic_content = run_optimizer()

        assert re.fullmatch(r"-?\d+\.\d{2}", dynamic_content), \
            "optimal_p.txt must contain a value rounded to exactly two decimal places."
        assert os.path.isfile(TRACE), "optimizer.sh did not invoke run_workload."
        with open(TRACE) as f:
            raw_calls = [line.strip() for line in f if line.strip()]
        assert len(raw_calls) == 100, \
            f"Expected two workload evaluations in each of 50 iterations, got {len(raw_calls)} calls."

        try:
            calls = [float(value) for value in raw_calls]
        except ValueError as exc:
            raise AssertionError(f"run_workload received a non-numeric -p value: {exc}")
        assert all(math.isfinite(value) for value in calls), \
            "run_workload received a non-finite parameter."

        expected_center = 0.0
        for iteration in range(50):
            x1, x2 = calls[2 * iteration:2 * iteration + 2]
            low, high = sorted((x1, x2))
            observed_center = (low + high) / 2.0
            assert abs(observed_center - expected_center) <= 0.002, \
                f"Iteration {iteration + 1} did not evaluate around the current p."
            assert abs((high - low) - 0.2) <= 0.0002, \
                f"Iteration {iteration + 1} did not use central-difference h=0.1."

            f_high = rounded_latency(high, a, center, base)
            f_low = rounded_latency(low, a, center, base)
            gradient = (f_high - f_low) / 0.2
            expected_center = observed_center - 0.05 * gradient

        expected_output = f"{expected_center:.2f}"
        assert dynamic_content == expected_output, \
            f"Expected final p {expected_output} after 50 gradient-descent iterations, got {dynamic_content}."

        # Leave the required output corresponding to the real workload and
        # re-check the original exact assertion after execution.
        install_workload(1.2, 14.7, 25.0)
        content = run_optimizer()
        assert content == "14.68", \
            f"Expected {OUTPUT} to contain exactly '14.68', but got '{content}'."
    finally:
        if original_bytes is None:
            if os.path.exists(TOOL):
                os.unlink(TOOL)
        else:
            with open(TOOL, "wb") as f:
                f.write(original_bytes)
            os.chmod(TOOL, original_mode)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
