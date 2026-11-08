#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import glob
import math
import random
import subprocess
import tempfile
import uuid

import h5py
import numpy as np
import pytest

AGENT_SCRIPT = "/home/user/check_convergence.py"
CLEAN_CORPUS = "/app/corpora/clean"
EVIL_CORPUS = "/app/corpora/evil"
TOLERANCE = 1e-4

def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} is not a file"

def test_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS, "*.h5"))
    assert len(clean_files) > 0, f"No .h5 files found in {CLEAN_CORPUS}"

    failed_files = []
    for f in clean_files:
        res = subprocess.run(["python3", AGENT_SCRIPT, f], capture_output=True)
        if res.returncode != 0:
            failed_files.append(os.path.basename(f))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified (rejected): {', '.join(failed_files)}")

def test_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS, "*.h5"))
    assert len(evil_files) > 0, f"No .h5 files found in {EVIL_CORPUS}"

    bypassed_files = []
    for f in evil_files:
        res = subprocess.run(["python3", AGENT_SCRIPT, f], capture_output=True)
        # The prompt specifies that evil files should exit with 1
        if res.returncode != 1:
            bypassed_files.append(os.path.basename(f))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed (accepted): {', '.join(bypassed_files)}")

def expected_status(x, y):
    if not (math.isfinite(x) and math.isfinite(y)):
        return 1
    try:
        f1 = x ** 2 + y ** 2 - 4.0
        f2 = x * y - 1.0
    except (ArithmeticError, OverflowError):
        return 1
    if not (math.isfinite(f1) and math.isfinite(f2)):
        return 1
    return 0 if abs(f1) <= TOLERANCE and abs(f2) <= TOLERANCE else 1

def write_case(directory, x_final, y_final):
    path = os.path.join(directory, f"{uuid.uuid4().hex}.h5")
    length = random.randint(8, 40)
    x = np.random.default_rng().normal(size=length)
    y = np.random.default_rng().normal(size=length)
    x[-1] = x_final
    y[-1] = y_final
    with h5py.File(path, "w") as h5:
        h5.create_dataset("x", data=x)
        h5.create_dataset("y", data=y)
    return path

def test_generated_hidden_states():
    # Generate previously unseen states in one neutral, randomized directory. Labels
    # are recomputed from the equations rather than inferred from file paths.
    a = math.sqrt(2.0 + math.sqrt(3.0))
    b = 1.0 / a
    roots = [(a, b), (b, a), (-a, -b), (-b, -a)]
    cases = []

    # Exercise all four roots and randomized states safely inside the tolerance.
    accepted = list(roots)
    while len(accepted) < 16:
        rx, ry = random.choice(roots)
        candidate = (rx + random.uniform(-1e-5, 1e-5),
                     ry + random.uniform(-1e-5, 1e-5))
        if expected_status(*candidate) == 0:
            accepted.append(candidate)

    # Generate near-root and general finite failures, deriving every label directly.
    rejected = []
    while len(rejected) < 16:
        if len(rejected) < 10:
            rx, ry = random.choice(roots)
            candidate = (rx + random.uniform(-3e-3, 3e-3),
                         ry + random.uniform(-3e-3, 3e-3))
        else:
            candidate = (random.uniform(-20.0, 20.0),
                         random.uniform(-20.0, 20.0))
        if expected_status(*candidate) == 1:
            rejected.append(candidate)

    special_failures = [
        (float("nan"), 0.0),
        (0.0, float("nan")),
        (float("inf"), 1.0),
        (1.0, float("-inf")),
        (1e300, 1e300),
        (-1e300, 1e300),
    ]

    with tempfile.TemporaryDirectory(prefix=f"states_{uuid.uuid4().hex}_") as directory:
        for x_final, y_final in accepted + rejected + special_failures:
            expected = expected_status(x_final, y_final)
            cases.append((write_case(directory, x_final, y_final), expected))

        random.SystemRandom().shuffle(cases)
        failures = []
        for path, expected in cases:
            result = subprocess.run(
                ["python3", AGENT_SCRIPT, path],
                capture_output=True,
                timeout=10,
            )
            if result.returncode != expected:
                failures.append(
                    f"{os.path.basename(path)} expected {expected}, got {result.returncode}"
                )

        if failures:
            pytest.fail("Generated-state classification failures: " + "; ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
