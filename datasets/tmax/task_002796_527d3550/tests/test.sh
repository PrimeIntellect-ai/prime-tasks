#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import tempfile
from pathlib import Path

PROJECT = Path("/home/user/sim_project")
REPORT = Path("/home/user/diagnostic_report.txt")
TRAJECTORY = PROJECT / "trajectory.c"
REGRESSION = PROJECT / "test_regression.c"
RUNNER = PROJECT / "test_runner"
EXPECTED_PATH = "/tmp/sim_configs/client_a_config_8821.txt"
INITIAL_POS = 850000
VELOCITY = 4000
MODULUS = 1000003
CORRECTED_RESULT = (INITIAL_POS * VELOCITY) % MODULUS


def compile_c(output, *sources, sanitize=False):
    command = ["gcc", "-std=c11", "-O0", "-g", "-Wall", "-Wextra", "-I", str(PROJECT)]
    if sanitize:
        command += ["-fsanitize=undefined", "-fno-sanitize-recover=undefined"]
    command += [str(source) for source in sources]
    command += ["-o", str(output)]
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode == 0, f"Compilation failed:\n{result.stdout}{result.stderr}"


def run_successfully(executable, cwd=PROJECT):
    result = subprocess.run(
        [str(executable)], cwd=str(cwd), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    assert result.returncode == 0, (
        f"{executable} failed with status {result.returncode}:\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_diagnostic_report():
    assert REPORT.exists(), f"Diagnostic report {REPORT} is missing."
    content = REPORT.read_text()

    # Preserve the original field checks while requiring the strict four-line format.
    assert f"FAILING_FILE: {EXPECTED_PATH}" in content, "FAILING_FILE is incorrect or missing."
    assert f"PARAM_INITIAL_POS: {INITIAL_POS}" in content, "PARAM_INITIAL_POS is incorrect or missing."
    assert f"PARAM_VELOCITY: {VELOCITY}" in content, "PARAM_VELOCITY is incorrect or missing."
    assert f"CORRECTED_RESULT: {CORRECTED_RESULT}" in content, "CORRECTED_RESULT is incorrect or missing."
    assert content.splitlines() == [
        f"FAILING_FILE: {EXPECTED_PATH}",
        f"PARAM_INITIAL_POS: {INITIAL_POS}",
        f"PARAM_VELOCITY: {VELOCITY}",
        f"CORRECTED_RESULT: {CORRECTED_RESULT}",
    ], "diagnostic_report.txt does not have the required strict format."


def test_test_regression_c():
    assert REGRESSION.exists(), f"Regression test file {REGRESSION} is missing."
    content = REGRESSION.read_text()

    assert "trajectory.h" in content, "test_regression.c does not include trajectory.h."
    assert "calc_step" in content, "test_regression.c does not call calc_step."
    assert "850000" in content, "test_regression.c does not use the correct initial_pos."
    assert "4000" in content, "test_regression.c does not use the correct velocity_factor."

    # Link the submitted regression test to an instrumented calc_step. This proves
    # that its executed main actually calls calc_step with the discovered values.
    with tempfile.TemporaryDirectory(prefix="verify_regression_") as temp:
        temp = Path(temp)
        marker = temp / "called"
        shim = temp / "calc_shim.c"
        shim.write_text(f'''\
#include <stdio.h>
#include "trajectory.h"
int calc_step(int current, int velocity) {{
    if (current != {INITIAL_POS} || velocity != {VELOCITY}) return -123456789;
    FILE *f = fopen({json.dumps(str(marker))}, "w");
    if (f) {{ fputs("called", f); fclose(f); }}
    return {CORRECTED_RESULT};
}}
''')
        instrumented = temp / "instrumented_regression"
        compile_c(instrumented, REGRESSION, shim)
        run_successfully(instrumented)
        assert marker.exists(), "test_regression.c did not call calc_step(850000, 4000)."


def test_test_runner_executable():
    assert RUNNER.exists(), f"Compiled test runner {RUNNER} is missing."
    assert os.access(RUNNER, os.X_OK), f"Compiled test runner {RUNNER} is not executable."
    run_successfully(RUNNER)

    # Independently rebuild the requested sources so a dummy executable cannot pass.
    with tempfile.TemporaryDirectory(prefix="verify_runner_") as temp:
        rebuilt = Path(temp) / "test_runner"
        compile_c(rebuilt, REGRESSION, TRAJECTORY, sanitize=True)
        run_successfully(rebuilt)


def test_trajectory_c_fix():
    assert TRAJECTORY.exists(), f"Source file {TRAJECTORY} is missing."
    content = TRAJECTORY.read_text()

    # Preserve the original source assertion.
    assert "long long" in content or "int64_t" in content or "long" in content, \
        "trajectory.c does not appear to cast the intermediate calculation to a 64-bit integer."

    # Exercise the submitted implementation on unpredictable overflowing products.
    rng = random.SystemRandom()
    cases = [(INITIAL_POS, VELOCITY), (50000, 50000), (1000000, 9000)]
    cases += [(rng.randint(400000, 1000000), rng.randint(3000, 12000)) for _ in range(12)]

    checks = []
    for current, velocity in cases:
        expected = (current * velocity) % MODULUS
        checks.append(
            f"if (calc_step({current}, {velocity}) != {expected}) return {len(checks) + 1};"
        )

    with tempfile.TemporaryDirectory(prefix="verify_trajectory_") as temp:
        temp = Path(temp)
        harness = temp / "harness.c"
        harness.write_text(
            '#include "trajectory.h"\nint main(void) {\n    '
            + '\n    '.join(checks)
            + '\n    return 0;\n}\n'
        )
        executable = temp / "trajectory_harness"
        compile_c(executable, harness, TRAJECTORY, sanitize=True)
        run_successfully(executable)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
