#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import sys
import tempfile

import h5py
import numpy as np
from scipy.integrate import solve_ivp

SCRIPT_PATH = '/home/user/find_damping.py'
LOG_PATH = '/home/user/best_c.log'
REFERENCE_PATH = '/home/user/reference.h5'
CANDIDATES = [0.1, 0.5, 1.0, 1.5, 2.0]
T = np.linspace(0, 10, 100)


def test_find_damping_script_exists():
    """Check if the find_damping.py script was created."""
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing. You must create it."


def test_best_c_log_exists_and_correct():
    """Check if best_c.log exists and contains the correct value."""
    assert os.path.isfile(LOG_PATH), f"The log file {LOG_PATH} is missing."

    with open(LOG_PATH, 'r') as f:
        content = f.read().strip()

    expected_content = "BEST_C=0.5"
    assert content == expected_content, f"The file {LOG_PATH} contains '{content}', but expected '{expected_content}'."


def solve_candidate(c):
    def rhs(t, state):
        y, v = state
        return [v, -c * v - 10.0 * y]

    result = solve_ivp(
        rhs,
        (0.0, 10.0),
        [1.0, 0.0],
        t_eval=T,
        rtol=1e-11,
        atol=1e-13,
    )
    assert result.success
    return result.y[0]


def test_script_executes_and_selects_from_reference_data():
    """Run the submitted artifact against hidden references and verify its choices."""
    with open(SCRIPT_PATH, 'rb') as f:
        source = f.read()
    assert source.strip(), f"The script {SCRIPT_PATH} is empty."
    compile(source, SCRIPT_PATH, 'exec')

    solutions = {c: solve_candidate(c) for c in CANDIDATES}
    hidden_targets = secrets.SystemRandom().sample([0.1, 1.0, 1.5, 2.0], 2)

    with tempfile.TemporaryDirectory() as tmpdir:
        reference_backup = os.path.join(tmpdir, 'reference.h5')
        log_backup = os.path.join(tmpdir, 'best_c.log')
        shutil.copy2(REFERENCE_PATH, reference_backup)
        shutil.copy2(LOG_PATH, log_backup)

        try:
            for target in hidden_targets:
                rng = np.random.default_rng(secrets.randbits(128))
                y_ref = solutions[target] + rng.normal(0.0, 1e-7, T.shape)
                expected = min(
                    CANDIDATES,
                    key=lambda c: float(np.mean((solutions[c] - y_ref) ** 2)),
                )

                with h5py.File(REFERENCE_PATH, 'w') as f:
                    f.create_dataset('y_ref', data=y_ref)
                if os.path.exists(LOG_PATH):
                    os.remove(LOG_PATH)

                completed = subprocess.run(
                    [sys.executable, SCRIPT_PATH],
                    cwd='/home/user',
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=60,
                )
                assert completed.returncode == 0, (
                    f"Executing {SCRIPT_PATH} failed with exit code {completed.returncode}.\n"
                    f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
                )
                assert os.path.isfile(LOG_PATH), (
                    f"Executing {SCRIPT_PATH} did not create {LOG_PATH}."
                )
                with open(LOG_PATH, 'r') as f:
                    actual = f.read().strip()
                expected_content = f"BEST_C={expected:.1f}"
                assert actual == expected_content, (
                    f"For a hidden reference whose independently calculated best damping "
                    f"is {expected:.1f}, the script wrote '{actual}' instead of "
                    f"'{expected_content}'."
                )
        finally:
            shutil.copy2(reference_backup, REFERENCE_PATH)
            shutil.copy2(log_backup, LOG_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
