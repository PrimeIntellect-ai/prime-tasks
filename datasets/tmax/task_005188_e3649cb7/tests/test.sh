#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess

VENV = "/home/user/venv"
PYTHON = os.path.join(VENV, "bin", "python")
SCRIPT = "/home/user/scripts/analyze.py"
PDB = "/home/user/data/protein.pdb"
RESULTS = "/home/user/results/coefficients.txt"


def run_script():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    env = os.environ.copy()
    env.pop("PYTHONPATH", None)
    env.pop("PYTHONHOME", None)
    env["PYTHONNOUSERSITE"] = "1"
    completed = subprocess.run(
        [PYTHON, "-I", SCRIPT],
        cwd="/tmp",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert completed.returncode == 0, (
        f"analyze.py failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULTS), "Running analyze.py did not create coefficients.txt"


def read_coefficients():
    with open(RESULTS, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 3, f"Expected exactly 3 coefficients in the results file, found {len(lines)}"
    try:
        values = [float(line) for line in lines]
    except ValueError:
        assert False, "Results file contains non-numeric values."
    assert all(math.isfinite(value) for value in values), "Results contain a non-finite coefficient"
    return values


def solve_linear_system(matrix, vector):
    n = len(vector)
    aug = [list(map(float, matrix[i])) + [float(vector[i])] for i in range(n)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda row: abs(aug[row][col]))
        assert abs(aug[pivot][col]) > 1e-12
        aug[col], aug[pivot] = aug[pivot], aug[col]
        divisor = aug[col][col]
        aug[col] = [value / divisor for value in aug[col]]
        for row in range(n):
            if row == col:
                continue
            factor = aug[row][col]
            aug[row] = [aug[row][j] - factor * aug[col][j] for j in range(n + 1)]
    return [aug[i][-1] for i in range(n)]


def expected_coefficients(coords):
    n = len(coords)
    degrees = [0] * n
    for i in range(n):
        for j in range(i + 1, n):
            distance = math.sqrt(sum((coords[i][k] - coords[j][k]) ** 2 for k in range(3)))
            if distance < 7.0:
                degrees[i] += 1
                degrees[j] += 1
    centrality = [degree / (n - 1) for degree in degrees]
    centroid = [sum(point[k] for point in coords) / n for k in range(3)]
    distances = [
        math.sqrt(sum((point[k] - centroid[k]) ** 2 for k in range(3)))
        for point in coords
    ]
    features = [[1.0, distance, distance * 2.0] for distance in distances]
    lhs = [[0.0] * 3 for _ in range(3)]
    rhs = [0.0] * 3
    for row, target in zip(features, centrality):
        for i in range(3):
            rhs[i] += row[i] * target
            for j in range(3):
                lhs[i][j] += row[i] * row[j]
    for i in range(3):
        lhs[i][i] += 1.0
    return solve_linear_system(lhs, rhs)


def write_pdb(coords):
    with open(PDB, "w") as f:
        for index, (x, y, z) in enumerate(coords, 1):
            f.write(
                f"ATOM  {index:5d}  CA  ALA A{index:4d}    "
                f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C  \n"
            )


def assert_formatted_coefficients(actual, expected):
    rounded_expected = [float(f"{value:.4f}") for value in expected]
    for i, (got, wanted) in enumerate(zip(actual, rounded_expected)):
        assert abs(got - wanted) < 0.000051, (
            f"Coefficient {i + 1} is incorrect for a verifier-generated PDB: "
            f"expected {wanted:.4f}, got {got}"
        )


def test_venv_exists_and_dependencies_are_installed():
    assert os.path.isdir(VENV), f"Virtual environment directory not found at {VENV}"
    assert os.path.isfile(PYTHON), f"Python executable not found in venv at {PYTHON}"
    assert os.access(PYTHON, os.X_OK), f"Venv Python is not executable at {PYTHON}"
    assert os.path.isfile(os.path.join(VENV, "pyvenv.cfg")), "The requested directory is not a Python virtual environment"

    probe = r'''
import json, os, sys
import numpy, Bio, networkx, sklearn
print(json.dumps({
    "prefix": os.path.realpath(sys.prefix),
    "modules": [numpy.__file__, Bio.__file__, networkx.__file__, sklearn.__file__],
}))
'''
    env = os.environ.copy()
    env.pop("PYTHONPATH", None)
    env.pop("PYTHONHOME", None)
    env["PYTHONNOUSERSITE"] = "1"
    completed = subprocess.run(
        [PYTHON, "-I", "-c", probe], env=env, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert completed.returncode == 0, f"Required dependencies are not importable in the venv: {completed.stderr}"
    info = json.loads(completed.stdout.strip())
    venv_real = os.path.realpath(VENV)
    assert info["prefix"] == venv_real, "The executable does not run inside /home/user/venv"
    for module_path in info["modules"]:
        assert module_path and os.path.commonpath([venv_real, os.path.realpath(module_path)]) == venv_real, (
            f"Dependency was not installed in the requested virtual environment: {module_path}"
        )


def test_script_fixed():
    assert os.path.isfile(SCRIPT), f"Script not found at {SCRIPT}"
    with open(SCRIPT, "r") as f:
        content = f.read()
    assert "np.linalg.inv" not in content, "The buggy OLS implementation (np.linalg.inv) was not removed."
    assert "Ridge" in content, "Ridge regression from scikit-learn was not found in the script."
    assert "alpha=1.0" in content.replace(" ", ""), "Ridge regression must be initialized with alpha=1.0."
    assert "fit_intercept=False" in content.replace(" ", ""), "Ridge regression must be initialized with fit_intercept=False."


def test_script_executes_and_computes_results():
    with open(PDB, "rb") as f:
        original_pdb = f.read()

    run_script()
    coeffs = read_coefficients()
    expected_original = [0.2117, 0.0195, 0.0389]
    for i, (actual, expected) in enumerate(zip(coeffs, expected_original)):
        assert abs(actual - expected) < 0.001, f"Coefficient {i+1} is incorrect. Expected ~{expected}, got {actual}"

    rng = secrets.SystemRandom()
    try:
        for _ in range(3):
            coords = [
                tuple(rng.randrange(-12000, 12001) / 1000.0 for _axis in range(3))
                for _point in range(6)
            ]
            write_pdb(coords)
            run_script()
            assert_formatted_coefficients(read_coefficients(), expected_coefficients(coords))
    finally:
        with open(PDB, "wb") as f:
            f.write(original_pdb)
        run_script()

    restored = read_coefficients()
    for i, (actual, expected) in enumerate(zip(restored, expected_original)):
        assert abs(actual - expected) < 0.001, f"Restored coefficient {i+1} is incorrect. Expected ~{expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
