#!/bin/bash
set +e
mkdir -p /logs/verifier
reward=0
TARGET=/home/user/mcmc_svd_target.py
BACKUP=/tmp/mcmc_svd_target.py.verifier_backup
CALL_LOG=/tmp/mcmc_svd_calls.log
RUN_STATUS=/tmp/profile_run_status

cleanup() {
    if [ -f "$BACKUP" ]; then
        cp -p "$BACKUP" "$TARGET"
        rm -f "$BACKUP"
    fi
}
trap cleanup EXIT

if cp -p "$TARGET" "$BACKUP"; then
    cat > "$TARGET" <<'PROBE_EOF'
import sys

if len(sys.argv) != 2:
    sys.exit(1)
try:
    seed = int(sys.argv[1])
except ValueError:
    sys.exit(1)

with open("/tmp/mcmc_svd_calls.log", "a") as f:
    f.write(str(seed) + "\n")

# A deliberately skewed data set makes the non-parametric bootstrap CI
# distinguishable from a constant or simple normal-approximation answer.
value = 9.0 if seed == 17 else 1.0 + seed / 10000.0
print(f"{value:.4f}")
PROBE_EOF
    chmod +x "$TARGET"
    rm -f "$CALL_LOG" /home/user/runtimes.txt /home/user/ci_output.txt "$RUN_STATUS"

    if timeout 180 /home/user/profile.sh >/tmp/profile_stdout.log 2>/tmp/profile_stderr.log; then
        echo 1 > "$RUN_STATUS"
    else
        echo 0 > "$RUN_STATUS"
    fi

    cleanup

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
from collections import Counter
import pytest


def test_profile_sh_exists_and_executable():
    script_path = "/home/user/profile.sh"
    assert os.path.exists(script_path), f"File {script_path} is missing."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"File {script_path} is not executable."


def test_profile_script_runs_successfully():
    assert os.path.exists("/tmp/profile_run_status")
    with open("/tmp/profile_run_status") as f:
        status = f.read().strip()
    assert status == "1", "profile.sh did not complete successfully when invoked without arguments."


def test_target_was_run_once_for_each_seed():
    assert os.path.exists("/tmp/mcmc_svd_calls.log"), "The target application was never executed."
    with open("/tmp/mcmc_svd_calls.log") as f:
        raw = [line.strip() for line in f if line.strip()]
    assert len(raw) == 30, f"Target must be executed exactly 30 times; observed {len(raw)} calls."
    try:
        seeds = [int(x) for x in raw]
    except ValueError:
        pytest.fail(f"Target received a non-integer seed: {raw}")
    assert Counter(seeds) == Counter(range(1, 31)), (
        f"Target must be called once with every seed from 1 through 30; observed {seeds}."
    )


def test_runtimes_txt_valid():
    runtimes_path = "/home/user/runtimes.txt"
    assert os.path.exists(runtimes_path), f"File {runtimes_path} is missing."

    with open(runtimes_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 30, f"runtimes.txt should have exactly 30 entries, found {len(lines)}."

    runtimes = []
    for idx, line in enumerate(lines):
        try:
            runtimes.append(float(line))
        except ValueError:
            pytest.fail(f"Line {idx+1} in runtimes.txt is not a valid float: {line}")

    expected = [9.0 if seed == 17 else 1.0 + seed / 10000.0 for seed in range(1, 31)]
    assert sorted(runtimes) == pytest.approx(sorted(expected), abs=0.00001), (
        "runtimes.txt does not contain the values emitted by the 30 target executions."
    )


def test_ci_output_valid():
    ci_path = "/home/user/ci_output.txt"
    assert os.path.exists(ci_path), f"File {ci_path} is missing."

    with open(ci_path, "r") as f:
        content = f.read().strip()

    assert re.fullmatch(r"[-+]?\d+\.\d{3},[-+]?\d+\.\d{3}", content), (
        f"ci_output.txt must contain two values rounded to exactly 3 decimal places. Got: {content}"
    )
    parts = content.split(",")
    assert len(parts) == 2, f"ci_output.txt must be in format lower_bound,upper_bound. Got: {content}"

    try:
        lower = float(parts[0])
        upper = float(parts[1])
    except ValueError:
        pytest.fail(f"ci_output.txt contains invalid floats: {content}")

    assert lower <= upper, "Lower bound must be less than or equal to upper bound."


def test_bootstrap_logic():
    runtimes_path = "/home/user/runtimes.txt"
    ci_path = "/home/user/ci_output.txt"

    if not os.path.exists(runtimes_path) or not os.path.exists(ci_path):
        pytest.skip("Required files missing, cannot verify bootstrap logic.")

    with open(runtimes_path, "r") as f:
        runtimes = [float(line.strip()) for line in f.readlines() if line.strip()]

    with open(ci_path, "r") as f:
        content = f.read().strip()
        parts = content.split(",")
        try:
            lower = float(parts[0])
            upper = float(parts[1])
        except ValueError:
            pytest.skip("ci_output.txt format is invalid, skipping bootstrap logic check.")

    # Independently calculate a 10,000-resample non-parametric bootstrap CI.
    random.seed(42)
    means = []
    n = len(runtimes)
    for _ in range(10000):
        sample = [random.choice(runtimes) for _ in range(n)]
        means.append(sum(sample) / n)

    means.sort()

    def percentile(data, p):
        k = (len(data) - 1) * p
        f = int(k)
        c = f + 1
        if f == c or c >= len(data):
            return data[f]
        return data[f] + (k - f) * (data[c] - data[f])

    true_lower = percentile(means, 0.025)
    true_upper = percentile(means, 0.975)

    assert abs(lower - true_lower) <= 0.05, f"Lower bound {lower} differs from expected {true_lower:.3f} by > 0.05"
    assert abs(upper - true_upper) <= 0.05, f"Upper bound {upper} differs from expected {true_upper:.3f} by > 0.05"
TEST_EOF

    if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
        reward=1
    fi
fi

cleanup
echo "$reward" > /logs/verifier/reward.txt
exit 0
