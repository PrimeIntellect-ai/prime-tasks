#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess

MC_PATH = "/home/user/mc_regression.sh"
RUN_PATH = "/home/user/run_convergence.sh"
LOG_PATH = "/home/user/convergence_log.csv"


def run_command(argv, timeout=20):
    env = os.environ.copy()
    env["LC_ALL"] = "C"
    return subprocess.run(
        argv,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        env=env,
    )


def expected_regression(n, seed):
    program = r'''
BEGIN {
    srand(seed)
    for (i = 0; i < n; i++) {
        x = rand()
        noise = rand() - 0.5
        y = 3.5 * x + 2.0 + noise
        sx += x
        sy += y
        sxx += x * x
        sxy += x * y
    }
    denominator = n * sxx - sx * sx
    m = (n * sxy - sx * sy) / denominator
    c = (sy - m * sx) / n
    printf "%d, %.5f, %.5f\n", n, m, c
}
'''
    result = run_command(["awk", "-v", f"n={n}", "-v", f"seed={seed}", program])
    assert result.returncode == 0, result.stderr
    return result.stdout


def assert_shell_script(path, require_awk=False):
    with open(path, "rb") as f:
        data = f.read()
    assert data.startswith((b"#!/bin/bash", b"#!/usr/bin/env bash", b"#!/bin/sh")), \
        f"{path} must be a Bash/POSIX shell script."
    if require_awk:
        text = data.decode("utf-8", errors="replace")
        assert re.search(r"(^|[^A-Za-z0-9_])(?:g?awk)([^A-Za-z0-9_]|$)", text), \
            f"{path} does not use awk."


def test_mc_regression_script():
    script_path = MC_PATH
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."
    assert_shell_script(script_path, require_awk=True)

    cases = []
    while len(cases) < 4:
        case = (5 + secrets.randbelow(250), 1 + secrets.randbelow(1000000))
        if case not in cases:
            cases.append(case)

    for n, seed in cases:
        result = run_command([script_path, str(n), str(seed)])
        assert result.returncode == 0, \
            f"mc_regression.sh failed for N={n}, SEED={seed}: {result.stderr}"
        assert re.fullmatch(r"[0-9]+, -?[0-9]+\.[0-9]{5}, -?[0-9]+\.[0-9]{5}\n", result.stdout), \
            f"Incorrect output format for N={n}, SEED={seed}: {result.stdout!r}"
        expected = expected_regression(n, seed)
        assert result.stdout == expected, \
            f"Incorrect regression for N={n}, SEED={seed}: expected {expected!r}, got {result.stdout!r}"


def test_run_convergence_script():
    script_path = RUN_PATH
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."
    assert_shell_script(script_path)

    with open(MC_PATH, "rb") as f:
        original_data = f.read()
    original_mode = stat.S_IMODE(os.stat(MC_PATH).st_mode)
    calls_path = "/tmp/mc_regression_calls"
    try:
        if os.path.exists(calls_path):
            os.unlink(calls_path)
        probe = f'''#!/bin/bash
printf '%s,%s\\n' "$1" "$2" >> {calls_path}
printf '%s, 9.12345, -8.54321\\n' "$1"
'''
        with open(MC_PATH, "w") as f:
            f.write(probe)
        os.chmod(MC_PATH, 0o755)
        if os.path.exists(LOG_PATH):
            os.unlink(LOG_PATH)

        result = run_command([script_path])
        assert result.returncode == 0, f"run_convergence.sh failed: {result.stderr}"
        assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} was not created."

        with open(calls_path, "r") as f:
            calls = [line.strip() for line in f if line.strip()]
        expected_calls = [f"{n},42" for n in (10, 100, 1000, 10000, 100000)]
        assert calls == expected_calls, \
            f"run_convergence.sh did not invoke mc_regression.sh with the required inputs: {calls}"

        with open(LOG_PATH, "r") as f:
            probe_lines = [line.strip() for line in f if line.strip()]
        expected_probe_lines = [f"{n}, 9.12345, -8.54321" for n in (10, 100, 1000, 10000, 100000)]
        assert probe_lines == expected_probe_lines, \
            "run_convergence.sh did not save the combined mc_regression.sh output."
    finally:
        with open(MC_PATH, "wb") as f:
            f.write(original_data)
        os.chmod(MC_PATH, original_mode)


def test_convergence_log_contents():
    if os.path.exists(LOG_PATH):
        os.unlink(LOG_PATH)
    result = run_command([RUN_PATH], timeout=40)
    assert result.returncode == 0, f"run_convergence.sh failed: {result.stderr}"

    log_path = LOG_PATH
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."
    assert os.path.isfile(log_path), f"{log_path} is not a file."

    expected_values = [
        (10, 3.73801, 1.83921),
        (100, 3.42436, 2.04683),
        (1000, 3.52288, 1.99616),
        (10000, 3.49818, 2.00067),
        (100000, 3.49987, 2.00002)
    ]

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == len(expected_values), f"Expected {len(expected_values)} lines in {log_path}, found {len(lines)}."

    for i, (line, expected) in enumerate(zip(lines, expected_values)):
        parts = [p.strip() for p in line.split(",")]
        assert len(parts) == 3, f"Line {i+1} does not have exactly 3 comma-separated values: '{line}'"

        try:
            n = int(parts[0])
            m = float(parts[1])
            c = float(parts[2])
        except ValueError:
            assert False, f"Line {i+1} contains non-numeric values: '{line}'"

        exp_n, exp_m, exp_c = expected
        assert n == exp_n, f"Line {i+1}: Expected N={exp_n}, got N={n}"
        assert abs(m - exp_m) < 1e-5, f"Line {i+1}: Expected m={exp_m}, got m={m}"
        assert abs(c - exp_c) < 1e-5, f"Line {i+1}: Expected c={exp_c}, got c={c}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
