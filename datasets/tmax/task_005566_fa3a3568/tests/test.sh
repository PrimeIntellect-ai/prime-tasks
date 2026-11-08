#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
import tempfile
import pytest


def test_failure_line():
    failure_file = "/home/user/failure_line.txt"
    assert os.path.exists(failure_file), f"{failure_file} does not exist."

    # Run original script to find the expected failure line
    try:
        out = subprocess.check_output(["/home/user/calc_variance.sh", "/home/user/mem_stats.log"], text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Original script failed to run: {e}")

    expected_failure_line = None
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 2:
            n = int(parts[0])
            var = float(parts[1])
            if var < 0:
                expected_failure_line = n
                break

    assert expected_failure_line is not None, "Original script did not produce a negative variance."

    with open(failure_file, "r") as f:
        content = f.read().strip()

    assert content.isdigit(), f"{failure_file} must contain only the line number."
    assert int(content) == expected_failure_line, f"Expected failure line {expected_failure_line}, but got {content}."


def expected_welford(log_file):
    expected_vars = []
    n_count = 0
    mean = 0.0
    M2 = 0.0
    with open(log_file, "r") as f:
        for line in f:
            val = float(line.strip())
            n_count += 1
            delta = val - mean
            mean += delta / n_count
            M2 += delta * (val - mean)
            expected_vars.append((n_count, M2 / n_count))
    return expected_vars


def assert_variance_output(out, expected_vars):
    lines = out.strip().splitlines()
    assert len(lines) == len(expected_vars), f"Expected {len(expected_vars)} lines of output, got {len(lines)}."

    for i, line in enumerate(lines):
        parts = line.split()
        assert len(parts) == 2, f"Line {i+1} of output is malformed: '{line}'"

        n_out = int(parts[0])
        var_out = float(parts[1])
        expected_n, expected_var = expected_vars[i]

        assert n_out == expected_n, f"Line {i+1}: expected n={expected_n}, got {n_out}."
        assert var_out >= 0, f"Line {i+1}: variance is negative ({var_out})."
        assert math.isclose(var_out, expected_var, rel_tol=1e-5, abs_tol=1e-5), \
            f"Line {i+1}: expected variance {expected_var}, got {var_out}."


def test_fixed_calc_variance():
    fixed_script = "/home/user/fixed_calc_variance.sh"
    log_file = "/home/user/mem_stats.log"

    assert os.path.exists(fixed_script), f"{fixed_script} does not exist."
    assert os.path.isfile(fixed_script), f"{fixed_script} is not a file."
    assert os.access(fixed_script, os.X_OK), f"{fixed_script} is not executable."

    expected_vars = expected_welford(log_file)

    try:
        out = subprocess.check_output([fixed_script, log_file], text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Fixed script failed to run: {e}")

    assert_variance_output(out, expected_vars)


def test_fixed_calc_variance_hidden_input_and_awk_only():
    fixed_script = "/home/user/fixed_calc_variance.sh"

    with open(fixed_script, "r", errors="replace") as f:
        source = f.read()

    assert re.search(r"\b(?:g?awk)\b", source), "The corrected Bash script must implement the calculation in awk."
    assert not re.search(r"\b(?:python(?:2|3)?|perl|ruby|node|php|lua|bc|Rscript)\b", source, re.IGNORECASE), \
        "The corrected script may not use another language or calculator."

    # Do not permit absolute invocations of external binaries other than the shell and awk.
    for match in re.finditer(r"/(?:usr/(?:local/)?)?(?:s?bin)/([A-Za-z0-9_.+-]+)", source):
        assert match.group(1) in {"bash", "env", "awk", "gawk"}, \
            f"External tool '{match.group(1)}' is not permitted; use awk."

    # Generate an unpredictable, numerically adversarial input after the agent has run.
    baseline = 10**12 + secrets.randbelow(10**6)
    values = [baseline + secrets.randbelow(4001) - 2000 for _ in range(317)]
    values[0:5] = [baseline, baseline + 1, baseline - 1, baseline + 1999, baseline - 2000]

    with tempfile.TemporaryDirectory() as td:
        hidden_log = os.path.join(td, "hidden_mem_stats.log")
        with open(hidden_log, "w") as f:
            for value in values:
                f.write(f"{value}\n")

        expected_vars = expected_welford(hidden_log)

        # Restrict command lookup to Bash and awk so normal invocations of forbidden
        # external tools cannot participate in producing the answer.
        tool_dir = os.path.join(td, "bin")
        os.mkdir(tool_dir)
        os.symlink("/bin/bash", os.path.join(tool_dir, "bash"))
        os.symlink("/usr/bin/awk", os.path.join(tool_dir, "awk"))
        os.symlink("/usr/bin/gawk", os.path.join(tool_dir, "gawk"))
        env = os.environ.copy()
        env["PATH"] = tool_dir
        env.pop("BASH_ENV", None)
        env.pop("ENV", None)

        result = subprocess.run(
            [fixed_script, hidden_log], text=True, capture_output=True, env=env
        )
        assert result.returncode == 0, \
            f"Fixed script failed on hidden input (exit {result.returncode}): {result.stderr}"
        assert result.stderr == "", f"Fixed script wrote errors on hidden input: {result.stderr}"
        assert_variance_output(result.stdout, expected_vars)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
