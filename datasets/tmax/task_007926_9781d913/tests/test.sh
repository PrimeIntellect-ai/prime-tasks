#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

import pytest

SCRIPT_PATH = "/home/user/calc_energy.sh"
LOG_PATH = "/home/user/energy.log"


@pytest.fixture(scope="session", autouse=True)
def run_submitted_script():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a regular file."
    assert not os.path.islink(SCRIPT_PATH), f"The path {SCRIPT_PATH} must not be a symbolic link."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "rb") as f:
        assert f.read(2) == b"#!", "calc_energy.sh is not a shell script with a shebang."

    # A pre-created answer must not be accepted. Run the submitted artifact and
    # require this invocation to produce a fresh successful result.
    if os.path.lexists(LOG_PATH):
        if os.path.isdir(LOG_PATH) and not os.path.islink(LOG_PATH):
            pytest.fail(f"The output path {LOG_PATH} is a directory.")
        os.unlink(LOG_PATH)

    try:
        result = subprocess.run(
            ["/bin/bash", "-x", SCRIPT_PATH],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            env={**os.environ, "BASH_ENV": ""},
        )
    except subprocess.TimeoutExpired:
        pytest.fail("calc_energy.sh did not terminate within 30 seconds.")

    assert result.returncode == 0, (
        "calc_energy.sh did not complete successfully.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(LOG_PATH), "Running calc_energy.sh did not create energy.log."

    # The trace must show that the iterative integrator actually evaluated more
    # than one approximation and increased N, rather than merely printing a
    # hard-coded Converged line.
    n_values = [
        int(m.group(1))
        for line in result.stderr.splitlines()
        if (m := re.match(r"^\++\s+N=([0-9]+)\s*$", line))
    ]
    val_assignments = [
        line for line in result.stderr.splitlines()
        if re.match(r"^\++\s+val=", line)
    ]
    assert len(n_values) >= 2, "No adaptive update of N was observed while running the script."
    assert all(n > 0 for n in n_values), "N collapsed to zero during execution."
    assert any(b > a for a, b in zip(n_values, n_values[1:])), (
        f"N was never increased by the adaptation logic: {n_values}"
    )
    assert len(val_assignments) >= 2, "The script did not compute multiple integral approximations."


def test_energy_log_exists():
    log_path = "/home/user/energy.log"
    assert os.path.exists(log_path), f"The log file {log_path} does not exist. Did you run the script?"
    assert os.path.isfile(log_path), f"The path {log_path} is not a file."


def test_energy_log_content():
    log_path = "/home/user/energy.log"
    with open(log_path, 'r') as f:
        content = f.read().strip()

    assert content.startswith("Converged:"), f"The log file does not indicate successful convergence. Content: '{content}'"

    match = re.search(r"Converged:\s*([0-9.]+)", content)
    assert match is not None, "Could not parse the converged value from the log file."

    val_str = match.group(1)
    try:
        val = float(val_str)
    except ValueError:
        raise AssertionError(f"The converged value '{val_str}' is not a valid float.")

    # Preserve the original expected-value assertion.
    expected_val = 2.5066
    tolerance = 0.005
    assert abs(val - expected_val) <= tolerance, (
        f"The converged value {val} is not close enough to the expected integral value (~2.5066). "
        "Check your integration logic or bounds."
    )

    # Independently derive the exact finite-bound Gaussian integral.
    derived_expected = math.sqrt(2.0 * math.pi) * math.erf(5.0 / math.sqrt(2.0))
    assert math.isfinite(val)
    assert abs(val - derived_expected) <= tolerance, (
        f"The converged value {val} does not match the independently derived integral "
        f"{derived_expected}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
