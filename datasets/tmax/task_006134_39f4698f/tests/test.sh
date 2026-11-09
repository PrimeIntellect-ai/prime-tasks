#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import math
import os
import re
import secrets
import subprocess

import numpy as np
import pytest

HOME = "/home/user"
GENERATOR = f"{HOME}/network_gen"
CSV_PATH = f"{HOME}/network.csv"
MODEL = f"{HOME}/model_fit.py"
OUTPUT = f"{HOME}/convergence_time.txt"
MARKER = "/tmp/solve_ivp_called"
INSTRUMENT = "/tmp/model_instrument"

EXPECTED_R = np.array([
    [-0.5, 0.0, 0.0, 0.0],
    [0.5, -0.3, 0.0, 0.0],
    [0.0, 0.3, -0.1, 0.0],
    [0.0, 0.0, 0.1, 0.0],
])


def instrumented_environment():
    os.makedirs(INSTRUMENT, exist_ok=True)
    with open(os.path.join(INSTRUMENT, "sitecustomize.py"), "w") as f:
        f.write(r'''import os
import scipy.integrate
_original_solve_ivp = scipy.integrate.solve_ivp

def _recording_solve_ivp(*args, **kwargs):
    marker = os.environ.get("SOLVE_IVP_MARKER")
    if marker:
        with open(marker, "a") as out:
            out.write("called\n")
    return _original_solve_ivp(*args, **kwargs)

scipy.integrate.solve_ivp = _recording_solve_ivp
''')
    env = os.environ.copy()
    env["SOLVE_IVP_MARKER"] = MARKER
    old_pythonpath = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = INSTRUMENT + (os.pathsep + old_pythonpath if old_pythonpath else "")
    return env


def run_model():
    if os.path.exists(MARKER):
        os.remove(MARKER)
    subprocess.run(["python3", MODEL], cwd=HOME, env=instrumented_environment(), check=True)
    assert os.path.isfile(MARKER), "model_fit.py did not call scipy.integrate.solve_ivp"


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(GENERATOR), f"The executable {GENERATOR} is missing. Did you compile network_gen.c?"
    assert os.access(GENERATOR, os.X_OK), f"The file {GENERATOR} is not executable."
    with open(GENERATOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "network_gen is not a compiled executable"

    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    subprocess.run([GENERATOR], cwd=HOME, check=True)
    assert os.path.isfile(CSV_PATH), "Running network_gen did not create network.csv"
    generated = np.loadtxt(CSV_PATH, delimiter=",")
    assert generated.shape == (4, 4)
    assert np.allclose(generated, EXPECTED_R), "network_gen produced the wrong transition matrix"

    assert os.path.isfile(MODEL), f"The script {MODEL} is missing."
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    run_model()


def test_network_gen_executable():
    """Verify that network_gen was compiled and is executable."""
    path = "/home/user/network_gen"
    assert os.path.exists(path), f"The executable {path} is missing. Did you compile network_gen.c?"
    assert os.path.isfile(path), f"{path} is not a file."
    assert os.access(path, os.X_OK), f"The file {path} is not executable."


def test_network_csv_exists():
    """Verify that network.csv was generated."""
    path = "/home/user/network.csv"
    assert os.path.exists(path), f"The file {path} is missing. Did you run the network generator?"
    assert os.path.isfile(path), f"{path} is not a file."


def test_model_fit_py_exists():
    """Verify that the Python script model_fit.py exists."""
    path = "/home/user/model_fit.py"
    assert os.path.exists(path), f"The script {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."

    with open(path, "r") as f:
        tree = ast.parse(f.read(), filename=path)
    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module.split(".")[0])
    assert "numpy" in imported, "model_fit.py must rely on numpy"
    assert "scipy" in imported, "model_fit.py must rely on scipy"


def test_convergence_time_txt():
    """Verify that convergence_time.txt contains the correct convergence time."""
    path = "/home/user/convergence_time.txt"
    assert os.path.exists(path), f"The output file {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."

    with open(path, "r") as f:
        content = f.read().strip()

    assert re.fullmatch(r"[0-9]+\.[0-9]", content), "Convergence time must be formatted to exactly one decimal place."
    assert content == "75.4", f"Expected convergence time to be '75.4', but got '{content}'."


def test_model_uses_loaded_matrix_and_discrete_threshold():
    rng = secrets.SystemRandom()
    while True:
        rate = rng.uniform(0.15, 0.45)
        crossing = math.log(10000.0 * rate) / rate
        position = crossing % 0.1
        if 0.03 < position < 0.07:
            break

    expected_time = (math.floor(crossing * 10.0) + 1) / 10.0
    challenge = np.diag([-rate, -0.7, -0.4, -0.25])

    try:
        np.savetxt(CSV_PATH, challenge, delimiter=",", fmt="%.17g")
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        run_model()
        assert os.path.isfile(OUTPUT), "model_fit.py did not write convergence_time.txt"
        with open(OUTPUT, "r") as f:
            content = f.read().strip()
        assert content == f"{expected_time:.1f}", (
            "model_fit.py did not compute convergence from the matrix loaded from network.csv "
            "using the strict threshold on the 0.1 time grid"
        )
    finally:
        subprocess.run([GENERATOR], cwd=HOME, check=True)
        run_model()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
