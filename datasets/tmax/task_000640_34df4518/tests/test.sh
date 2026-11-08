#!/bin/bash
set -e
mkdir -p /logs/verifier

backup_dir=$(mktemp -d)
cp -a /home/user/simulate.py "$backup_dir/simulate.py"
cp -a /home/user/bootstrap_ci.R "$backup_dir/bootstrap_ci.R"
cp -a /home/user/baseline_mean.txt "$backup_dir/baseline_mean.txt"

restore_files() {
    cp -a "$backup_dir/simulate.py" /home/user/simulate.py
    cp -a "$backup_dir/bootstrap_ci.R" /home/user/bootstrap_ci.R
    cp -a "$backup_dir/baseline_mean.txt" /home/user/baseline_mean.txt
    rm -rf "$backup_dir"
}
trap restore_files EXIT

cat <<'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

import pytest

SCRIPT = "/home/user/run_regression.sh"
RUNS = "/home/user/current_runs.txt"
RESULT = "/home/user/regression_result.log"
BASELINE = "/home/user/baseline_mean.txt"
SIMULATE = "/home/user/simulate.py"
BOOTSTRAP = "/home/user/bootstrap_ci.R"
SIM_CALLS = "/home/user/.verifier_sim_calls"
R_CALLS = "/home/user/.verifier_r_calls"


def write_file(path, content, mode):
    with open(path, "w") as f:
        f.write(content)
    os.chmod(path, mode)


def install_controlled_inputs(lower, upper, baseline):
    write_file(
        SIMULATE,
        '''import os
with open("/home/user/.verifier_sim_calls", "a") as f:
    f.write(str(os.getpid()) + "\\n")
print("1.500000")
''',
        0o755,
    )

    write_file(
        BOOTSTRAP,
        f'''args <- commandArgs(trailingOnly = TRUE)
cat(paste(args, collapse=" "), "\\n", file="/home/user/.verifier_r_calls", append=TRUE, sep="")
if (length(args) != 1 || args[1] != "/home/user/current_runs.txt") {{
  quit(status=17)
}}
data <- suppressWarnings(as.numeric(readLines(args[1])))
if (length(data) != 50 || any(is.na(data)) || any(!is.finite(data)) || any(abs(data - 1.5) > 1e-12)) {{
  quit(status=18)
}}
cat(sprintf("%.6f %.6f\\n", {lower}, {upper}))
''',
        0o755,
    )

    write_file(BASELINE, f"{baseline}\n", 0o644)
    write_file(SIM_CALLS, "", 0o666)
    write_file(R_CALLS, "", 0o666)

    # A compliant script must create a new runs file rather than append to stale data.
    write_file(RUNS, "stale-data\n", 0o666)
    write_file(RESULT, "STALE\n", 0o666)


def execute_and_check(lower, upper, baseline, expected):
    install_controlled_inputs(lower, upper, baseline)

    proc = subprocess.run(
        ["su", "-", "user", "-c", SCRIPT],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert proc.returncode == 0, (
        f"Execution failed with return code {proc.returncode}. "
        f"stdout: {proc.stdout!r}; stderr: {proc.stderr!r}"
    )

    assert os.path.isfile(RUNS), f"{RUNS} was not created."
    with open(RUNS) as f:
        lines = f.read().splitlines()
    assert len(lines) == 50, f"Expected exactly 50 lines, found {len(lines)}."

    number = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")
    assert all(line.strip() and number.fullmatch(line.strip()) for line in lines), \
        "Every simulation output must be a numeric line."
    values = [float(line) for line in lines]
    assert all(math.isfinite(value) and value == 1.5 for value in values), \
        "current_runs.txt did not contain the controlled simulation outputs."

    with open(SIM_CALLS) as f:
        sim_calls = [line for line in f.read().splitlines() if line.strip()]
    assert len(sim_calls) == 50, \
        f"simulate.py must run exactly 50 times; observed {len(sim_calls)} executions."

    with open(R_CALLS) as f:
        r_calls = [line for line in f.read().splitlines() if line.strip()]
    assert r_calls == [RUNS], \
        f"bootstrap_ci.R must run exactly once with {RUNS}; observed {r_calls!r}."

    assert os.path.isfile(RESULT), f"{RESULT} was not created."
    with open(RESULT) as f:
        actual = f.read().strip()
    assert actual == expected, f"Expected {expected!r}, got {actual!r}."


def test_run_regression_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


@pytest.mark.parametrize(
    "lower,upper,baseline,expected",
    [
        (1.4, 1.6, 1.5, "PASS"),
        (1.5, 1.8, 1.5, "FAIL"),
        (1.2, 1.5, 1.5, "FAIL"),
        (1.6, 1.8, 1.5, "FAIL"),
        (-3.0, -1.0, -2.0, "PASS"),
    ],
)
def test_script_execution_and_outputs(lower, upper, baseline, expected):
    execute_and_check(lower, upper, baseline, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
