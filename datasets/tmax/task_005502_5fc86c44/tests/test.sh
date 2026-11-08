#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess

import h5py
import numpy as np
from scipy.stats import wasserstein_distance

HOME = "/home/user"
EXECUTABLE = os.path.join(HOME, "generate_data")
DATA = os.path.join(HOME, "data.h5")
RESULT = os.path.join(HOME, "result.txt")


def test_01_original_assertions():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing. Did you compile the C file?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    assert os.path.isfile(DATA), f"Data file {DATA} is missing. Did you run the compiled executable?"
    assert os.path.isfile(RESULT), f"Result file {RESULT} is missing."

    with open(RESULT, "r") as f:
        content = f.read().strip()
    assert content == "0.7321", f"Expected result '0.7321', but got '{content}'."


def test_02_executable_is_compiled_and_generates_valid_hdf5():
    mode = os.stat(EXECUTABLE).st_mode
    assert stat.S_ISREG(mode), "generate_data must be a regular compiled executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "generate_data is not a compiled ELF executable."

    if os.path.exists(DATA):
        os.unlink(DATA)
    completed = subprocess.run(
        [EXECUTABLE], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=30, check=False
    )
    assert completed.returncode == 0, completed.stderr.decode(errors="replace")
    assert os.path.isfile(DATA), "Running generate_data did not create /home/user/data.h5."

    expected_a = (np.arange(1000, dtype=np.float64) ** 2) / 1000.0
    expected_b = expected_a + 0.7321
    with h5py.File(DATA, "r") as h5:
        assert "dist_A" in h5 and "dist_B" in h5, "Required HDF5 datasets are missing."
        actual_a = h5["dist_A"][...]
        actual_b = h5["dist_B"][...]
    assert actual_a.shape == (1000,)
    assert actual_b.shape == (1000,)
    np.testing.assert_allclose(actual_a, expected_a, rtol=0, atol=1e-12)
    np.testing.assert_allclose(actual_b, expected_b, rtol=0, atol=1e-12)


def _python_scripts():
    scripts = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for name in files:
            path = os.path.join(root, name)
            if path.endswith(".py"):
                scripts.append(path)
                continue
            try:
                with open(path, "rb") as f:
                    first_line = f.readline(256).lower()
                if first_line.startswith(b"#!") and b"python" in first_line:
                    scripts.append(path)
            except (OSError, UnicodeError):
                pass
    return sorted(set(scripts))


def _write_challenge(a, b):
    with h5py.File(DATA, "w") as h5:
        h5.create_dataset("dist_A", data=a)
        h5.create_dataset("dist_B", data=b)


def _script_answer(script, expected):
    if os.path.exists(RESULT):
        os.unlink(RESULT)
    completed = subprocess.run(
        ["python3", script], cwd=HOME, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=30, check=False, text=True
    )
    if completed.returncode != 0:
        return False

    answers = []
    if os.path.isfile(RESULT):
        with open(RESULT, "r") as f:
            answers.append(f.read().strip())
    answers.append(completed.stdout.strip())
    return expected in answers


def test_03_python_script_computes_wasserstein_distance_from_hdf5():
    scripts = _python_scripts()
    assert scripts, "No Python script was written under /home/user."

    with open(DATA, "rb") as f:
        canonical_data = f.read()
    with open(RESULT, "rb") as f:
        original_result = f.read()

    seed = int.from_bytes(os.urandom(16), "big")
    rng = np.random.default_rng(seed)
    cases = [
        (rng.normal(-0.4, 1.3, 1000), rng.normal(1.1, 0.7, 1000)),
        (rng.uniform(-3.0, 2.0, 1000), rng.gamma(2.3, 0.8, 1000) - 1.0),
    ]

    working_script = None
    try:
        for script in scripts:
            passed = True
            for a, b in cases:
                _write_challenge(a, b)
                expected = f"{wasserstein_distance(a, b):.4f}"
                if not _script_answer(script, expected):
                    passed = False
                    break
            if passed:
                working_script = script
                break
    finally:
        with open(DATA, "wb") as f:
            f.write(canonical_data)
        with open(RESULT, "wb") as f:
            f.write(original_result)

    assert working_script is not None, (
        "No submitted Python script correctly read dynamically generated dist_A/dist_B "
        "datasets and computed their 1st Wasserstein distance to four decimal places."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
