#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import secrets
import subprocess
import time

import pytest

SCRIPT_PATH = "/home/user/fast_sweep.sh"
RESULTS_PATH = "/home/user/best_results.txt"
SAMPLES_PATH = "/home/user/samples.txt"
SIMULATE_PATH = "/home/user/simulate.sh"
CALL_LOG = "/tmp/simulate_calls.log"


def test_fast_sweep_end_to_end():
    # Preserve the original script assertions.
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable. Did you forget to chmod +x?"

    # Use a fresh sample set so a precomputed best_results.txt cannot pass.
    rng = secrets.SystemRandom()
    samples = [(rng.randint(0, 10000), rng.randint(0, 10000)) for _ in range(1000)]
    with open(SAMPLES_PATH, "w") as f:
        for x, y in samples:
            f.write(f"{x} {y}\n")

    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    if os.path.exists(CALL_LOG):
        os.remove(CALL_LOG)

    # Instrument the required simulator path. Each invocation records its input
    # and whether xargs or GNU parallel appears in its live process ancestry.
    wrapper = r'''#!/bin/bash
x=$1
y=$2
parallel_parent=0
p=$PPID
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -n "$p" ] || break
    [ "$p" -gt 1 ] 2>/dev/null || break
    comm=$(cat "/proc/$p/comm" 2>/dev/null || true)
    case "$comm" in
        xargs|parallel) parallel_parent=1 ;;
    esac
    p=$(awk '/^PPid:/ {print $2}' "/proc/$p/status" 2>/dev/null || true)
done
(
    flock -x 9
    printf '%s\t%s\t%s\n' "$x" "$y" "$parallel_parent" >&9
) 9>>/tmp/simulate_calls.log
sleep 0.05
cost=$(( (x - 42) * (x - 42) + (y - 73) * (y - 73) ))
echo "$x $y $cost"
'''
    with open(SIMULATE_PATH, "w") as f:
        f.write(wrapper)
    os.chmod(SIMULATE_PATH, 0o755)

    started = time.monotonic()
    try:
        completed = subprocess.run(
            [SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("fast_sweep.sh did not complete within 10 seconds")
    elapsed = time.monotonic() - started

    assert completed.returncode == 0, (
        f"fast_sweep.sh exited with status {completed.returncode}. "
        f"stdout: {completed.stdout!r}; stderr: {completed.stderr!r}"
    )
    assert elapsed < 10, f"fast_sweep.sh took {elapsed:.3f} seconds; expected under 10 seconds."

    assert os.path.isfile(CALL_LOG), "fast_sweep.sh never executed /home/user/simulate.sh."
    calls = []
    with open(CALL_LOG) as f:
        for line_number, line in enumerate(f, 1):
            parts = line.rstrip("\n").split("\t")
            assert len(parts) == 3, f"Malformed simulator call record on line {line_number}: {line!r}"
            try:
                x, y = int(parts[0]), int(parts[1])
            except ValueError:
                pytest.fail(f"Simulator was called with invalid arguments on line {line_number}: {line!r}")
            assert parts[2] == "1", (
                f"simulate.sh call for X={x}, Y={y} was not launched through xargs or GNU parallel."
            )
            calls.append((x, y))

    assert collections.Counter(calls) == collections.Counter(samples), (
        "fast_sweep.sh must execute simulate.sh exactly once for every point in samples.txt. "
        f"Expected {len(samples)} calls, observed {len(calls)}."
    )

    # Preserve the original output correctness assertions.
    assert os.path.exists(RESULTS_PATH), f"The output file {RESULTS_PATH} does not exist."
    assert os.path.isfile(RESULTS_PATH), f"{RESULTS_PATH} is not a file."
    assert os.path.exists(SAMPLES_PATH), f"The samples file {SAMPLES_PATH} is missing."

    parsed_samples = []
    with open(SAMPLES_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                x_str, y_str = line.split()
                parsed_samples.append((int(x_str), int(y_str)))

    all_costs = sorted([(x - 42) ** 2 + (y - 73) ** 2 for x, y in parsed_samples])
    expected_top_3_costs = all_costs[:3]

    with open(RESULTS_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {RESULTS_PATH}, found {len(lines)}."

    actual_costs = []
    for i, line in enumerate(lines):
        parts = line.split(',')
        assert len(parts) == 3, f"Line {i + 1} in {RESULTS_PATH} does not match 'X,Y,cost' format: '{line}'"
        try:
            x, y, cost = int(parts[0]), int(parts[1]), int(parts[2])
        except ValueError:
            pytest.fail(f"Line {i + 1} in {RESULTS_PATH} contains non-integer values: '{line}'")

        expected_cost = (x - 42) ** 2 + (y - 73) ** 2
        assert cost == expected_cost, f"Reported cost {cost} for X={x}, Y={y} is incorrect. Expected {expected_cost}."
        assert (x, y) in parsed_samples, f"The point X={x}, Y={y} was not found in {SAMPLES_PATH}."
        actual_costs.append(cost)

    assert actual_costs == sorted(actual_costs), "Results are not sorted by cost in ascending order."
    assert sorted(actual_costs) == expected_top_3_costs, (
        f"The extracted configurations do not have the lowest possible costs. "
        f"Expected costs: {expected_top_3_costs}, found: {sorted(actual_costs)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
