#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import secrets
import shutil
import subprocess

HOME = "/home/user"
RESULTS = f"{HOME}/results"
VENV = f"{HOME}/sim_env"
FIXED_NS = [16, 32, 64, 128]


def get_expected_error(N):
    """Independently compute the requested finite-difference L2 error."""
    h = 1.0 / N
    n = N - 1
    x_int = [i * h for i in range(1, N)]
    u_exact = [math.sin(2 * math.pi * x) for x in x_int]
    b = [4 * math.pi**2 * math.sin(2 * math.pi * x) for x in x_int]
    a = -1.0 / h**2
    d = 2.0 / h**2
    c = -1.0 / h**2

    c_prime = [0.0] * n
    d_prime = [0.0] * n
    c_prime[0] = c / d
    d_prime[0] = b[0] / d
    for i in range(1, n):
        denom = d - a * c_prime[i - 1]
        if i < n - 1:
            c_prime[i] = c / denom
        d_prime[i] = (b[i] - a * d_prime[i - 1]) / denom

    u_num = [0.0] * n
    u_num[-1] = d_prime[-1]
    for i in range(n - 2, -1, -1):
        u_num[i] = d_prime[i] - c_prime[i] * u_num[i + 1]

    return math.sqrt(h * sum((u_num[i] - u_exact[i])**2 for i in range(n)))


def assert_close(actual, expected, label):
    assert math.isfinite(actual), f"{label} is not finite"
    rel_diff = abs(actual - expected) / expected
    assert rel_diff <= 1e-7, (
        f"{label} is incorrect. Expected approx {expected:.6e}, got {actual:.6e}"
    )


def notebook_source(cell):
    source = cell.get("source", "")
    return "".join(source) if isinstance(source, list) else source


def test_complete_workflow():
    # Retain the original existence assertions and verify that the environment is real.
    assert os.path.isdir(VENV), "Virtual environment directory missing at /home/user/sim_env"
    assert os.path.exists(f"{HOME}/solver.py"), "solver.py is missing"
    assert os.path.exists(f"{HOME}/template.ipynb"), "template.ipynb is missing"
    assert os.path.exists(f"{HOME}/run_study.sh"), "run_study.sh is missing"
    assert os.path.isfile(f"{HOME}/solver.py"), "solver.py is not a regular file"
    assert os.path.isfile(f"{HOME}/template.ipynb"), "template.ipynb is not a regular file"
    assert os.path.isfile(f"{HOME}/run_study.sh"), "run_study.sh is not a regular file"
    assert os.path.isfile(f"{VENV}/pyvenv.cfg"), "sim_env is not a Python virtual environment"
    vpython = f"{VENV}/bin/python"
    papermill = f"{VENV}/bin/papermill"
    assert os.path.isfile(vpython), "Virtual-environment Python is missing"
    assert os.path.isfile(papermill), "Virtual-environment papermill is missing"
    subprocess.run(
        [vpython, "-c", "import numpy, scipy, jupyter, papermill; import sys; assert sys.prefix == '/home/user/sim_env'"],
        check=True,
        cwd=HOME,
        timeout=60,
    )

    # Check the required notebook parameter cell rather than accepting an arbitrary file.
    with open(f"{HOME}/template.ipynb", "r", encoding="utf-8") as f:
        template = json.load(f)
    assert template.get("nbformat") == 4, "template.ipynb is not a valid v4 notebook"
    cells = template.get("cells", [])
    parameter_cells = [
        c for c in cells
        if "parameters" in c.get("metadata", {}).get("tags", [])
    ]
    assert len(parameter_cells) == 1, "Notebook must have exactly one parameters-tagged cell"
    tree = ast.parse(notebook_source(parameter_cells[0]))
    assert len(tree.body) == 1 and isinstance(tree.body[0], ast.Assign), (
        "The parameters cell must define only N = 10"
    )
    assignment = tree.body[0]
    assert len(assignment.targets) == 1 and isinstance(assignment.targets[0], ast.Name)
    assert assignment.targets[0].id == "N"
    assert isinstance(assignment.value, ast.Constant) and assignment.value.value == 10

    os.makedirs(RESULTS, exist_ok=True)
    rng = secrets.SystemRandom()

    # Exercise solver.py on unpredictable mesh sizes, not just the four CSV values.
    dynamic_ns = rng.sample([n for n in range(7, 91) if n not in FIXED_NS], 4)
    for N in dynamic_ns:
        proc = subprocess.run(
            [vpython, "-c", f"import solver; print(float(solver.get_l2_error({N})))"],
            check=True,
            cwd=HOME,
            text=True,
            capture_output=True,
            timeout=60,
        )
        actual = float(proc.stdout.strip())
        assert_close(actual, get_expected_error(N), f"solver.get_l2_error({N})")

    # Execute the submitted template through the submitted environment's papermill.
    hidden_n = rng.choice([n for n in range(11, 89) if n not in FIXED_NS and n not in dynamic_ns])
    hidden_error = f"{RESULTS}/error_{hidden_n}.txt"
    hidden_output = f"/tmp/verified_out_{hidden_n}.ipynb"
    for path in (hidden_error, hidden_output):
        if os.path.exists(path):
            os.remove(path)
    env = os.environ.copy()
    env["PATH"] = f"{VENV}/bin:" + env.get("PATH", "")
    subprocess.run(
        [papermill, f"{HOME}/template.ipynb", hidden_output, "-p", "N", str(hidden_n)],
        check=True,
        cwd=HOME,
        env=env,
        timeout=180,
    )
    assert os.path.isfile(hidden_output), "Papermill did not create an output notebook"
    assert os.path.isfile(hidden_error), "Executed notebook did not create its error file"
    with open(hidden_error, "r", encoding="utf-8") as f:
        assert_close(float(f.read().strip()), get_expected_error(hidden_n), "Notebook L2 error")
    with open(hidden_output, "r", encoding="utf-8") as f:
        hidden_nb = json.load(f)
    assert isinstance(hidden_nb.get("metadata", {}).get("papermill"), dict), (
        "Output notebook lacks papermill execution metadata"
    )
    os.remove(hidden_error)

    # Remove fixed outputs and actually execute the requested orchestration script.
    for N in FIXED_NS:
        for name in (f"out_{N}.ipynb", f"error_{N}.txt"):
            path = f"{RESULTS}/{name}"
            if os.path.lexists(path):
                if os.path.isdir(path) and not os.path.islink(path):
                    shutil.rmtree(path)
                else:
                    os.remove(path)
    csv_path = f"{RESULTS}/convergence.csv"
    if os.path.lexists(csv_path):
        os.remove(csv_path)
    subprocess.run(
        ["bash", f"{HOME}/run_study.sh"],
        check=True,
        cwd=HOME,
        env=env,
        timeout=600,
    )

    # Retain and strengthen the original intermediate-output assertions.
    for N in FIXED_NS:
        out_path = f"{RESULTS}/out_{N}.ipynb"
        err_path = f"{RESULTS}/error_{N}.txt"
        assert os.path.exists(out_path), f"out_{N}.ipynb missing"
        assert os.path.exists(err_path), f"error_{N}.txt missing"
        assert os.path.isfile(out_path), f"out_{N}.ipynb is not a file"
        assert os.path.isfile(err_path), f"error_{N}.txt is not a file"
        with open(err_path, "r", encoding="utf-8") as f:
            assert_close(float(f.read().strip()), get_expected_error(N), f"error_{N}.txt")
        with open(out_path, "r", encoding="utf-8") as f:
            out_nb = json.load(f)
        assert out_nb.get("nbformat") == 4, f"out_{N}.ipynb is not a valid v4 notebook"
        assert isinstance(out_nb.get("metadata", {}).get("papermill"), dict), (
            f"out_{N}.ipynb lacks papermill metadata"
        )
        assert any(
            "injected-parameters" in c.get("metadata", {}).get("tags", [])
            for c in out_nb.get("cells", [])
        ), f"out_{N}.ipynb does not show papermill parameter injection"

    # Retain the original independent convergence.csv checks.
    assert os.path.exists(csv_path), f"File {csv_path} does not exist"
    with open(csv_path, "r", newline="") as f:
        rows = list(csv.reader(f))
    assert len(rows) >= 5, "CSV should contain a header and 4 rows of data"
    assert rows[0] == ["N", "L2_error"], f"CSV header is incorrect, found: {rows[0]}"

    data_dict = {}
    for row in rows[1:]:
        assert len(row) == 2, f"Invalid row format: {row}"
        try:
            n_val = int(row[0].strip())
            err_val = float(row[1].strip())
            data_dict[n_val] = err_val
        except ValueError:
            assert False, f"Could not parse row values as numbers: {row}"

    for N in FIXED_NS:
        assert N in data_dict, f"Missing results for N={N} in CSV"
        assert_close(data_dict[N], get_expected_error(N), f"L2 error for N={N}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
