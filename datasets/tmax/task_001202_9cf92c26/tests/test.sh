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
import uuid

import matplotlib.image as mpimg
import numpy as np
import pytest

HOME = "/home/user"
FIXED_NS = [9, 19, 39, 79, 159]


def expected_values(N):
    h = 1.0 / (N + 1)
    amp = (math.pi**2 * h**2) / (2.0 * (1.0 - math.cos(math.pi * h)))
    error = abs(amp - 1.0) / math.sqrt(2.0)
    return h, amp, error


def validate_solution_file(N):
    path = f"{HOME}/solution_{N}.dat"
    assert os.path.isfile(path), f"Data file {path} is missing."
    with open(path, "r") as f:
        rows = [line.rstrip("\n") for line in f if line.strip()]

    assert len(rows) == N, f"Expected {N} data rows in {path}, found {len(rows)}."
    h, amp, _ = expected_values(N)
    for i, row in enumerate(rows, 1):
        fields = row.split("\t")
        assert len(fields) == 3, f"Row {i} of {path} is not three tab-separated columns."
        try:
            x, u_num, u_exact = map(float, fields)
        except ValueError:
            pytest.fail(f"Row {i} of {path} contains non-numeric data.")
        assert all(math.isfinite(v) for v in (x, u_num, u_exact))
        expected_x = i * h
        expected_exact = math.sin(math.pi * expected_x)
        expected_num = amp * expected_exact
        assert math.isclose(x, expected_x, rel_tol=0.0, abs_tol=2e-6)
        assert math.isclose(u_exact, expected_exact, rel_tol=0.0, abs_tol=2e-5)
        assert math.isclose(u_num, expected_num, rel_tol=0.0, abs_tol=2e-5)


def run_and_validate_solver(executable, N):
    data_path = f"{HOME}/solution_{N}.dat"
    if os.path.exists(data_path):
        os.remove(data_path)
    result = subprocess.run(
        [executable, str(N)], cwd=HOME, text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, result.stderr
    lines = [line for line in result.stdout.splitlines() if line.strip()]
    assert len(lines) == 1, "Solver must print exactly one non-empty output line."
    match = re.fullmatch(
        rf"N={N}, h=([0-9]+\.[0-9]{{6}}), error=([0-9]+\.[0-9]{{6}})",
        lines[0],
    )
    assert match, f"Incorrect solver output: {lines[0]!r}"
    h, _, error = expected_values(N)
    assert math.isclose(float(match.group(1)), h, rel_tol=0.0, abs_tol=5.1e-7)
    assert math.isclose(float(match.group(2)), error, rel_tol=0.0, abs_tol=5.1e-7)
    validate_solution_file(N)


def test_files_exist():
    """Verify that all required files exist."""
    required_files = [
        "/home/user/poisson1d.c",
        "/home/user/pipeline.sh",
        "/home/user/plot.py",
        "/home/user/convergence.log",
        "/home/user/solution_159.dat",
        "/home/user/convergence.png",
        "/home/user/solution.png"
    ]
    for file_path in required_files:
        assert os.path.exists(file_path), f"Required file {file_path} is missing."


def test_pipeline_is_executable():
    """Verify that pipeline.sh has execution permissions."""
    assert os.access("/home/user/pipeline.sh", os.X_OK), "/home/user/pipeline.sh is not executable."


def test_c_source_compiles_and_solver_handles_unseen_meshes():
    source = f"{HOME}/poisson1d.c"
    assert os.path.isfile(source) and os.path.getsize(source) > 0
    executable = f"/tmp/poisson1d-{uuid.uuid4().hex}"
    result = subprocess.run(
        ["gcc", source, "-o", executable, "-lm"],
        text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, f"C source did not compile:\n{result.stderr}"

    assert subprocess.run([executable], capture_output=True, timeout=5).returncode != 0
    assert subprocess.run([executable, "9", "extra"], capture_output=True, timeout=5).returncode != 0

    candidates = [n for n in range(11, 148) if n not in FIXED_NS]
    chosen = []
    while len(chosen) < 3:
        n = candidates[secrets.randbelow(len(candidates))]
        if n not in chosen:
            chosen.append(n)
    for N in chosen:
        run_and_validate_solver(executable, N)


def test_pipeline_rebuilds_and_runs_study():
    with open(f"{HOME}/pipeline.sh", "r") as f:
        script = f.read()
    assert re.search(r"\bgcc\b", script), "pipeline.sh does not invoke gcc."
    assert "-lm" in script, "pipeline.sh does not link with -lm."

    for path in [f"{HOME}/poisson1d", f"{HOME}/convergence.log"]:
        if os.path.exists(path):
            os.remove(path)
    for N in FIXED_NS:
        path = f"{HOME}/solution_{N}.dat"
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run(
        [f"{HOME}/pipeline.sh"], cwd=HOME, text=True, capture_output=True, timeout=60
    )
    assert result.returncode == 0, f"pipeline.sh failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(f"{HOME}/poisson1d")
    assert os.access(f"{HOME}/poisson1d", os.X_OK)
    for N in FIXED_NS:
        validate_solution_file(N)

    dynamic_n = 151 + secrets.randbelow(30)
    run_and_validate_solver(f"{HOME}/poisson1d", dynamic_n)


def test_convergence_log():
    """Verify the contents of convergence.log match the expected output."""
    log_path = "/home/user/convergence.log"
    assert os.path.exists(log_path), f"{log_path} is missing."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_Ns = [9, 19, 39, 79, 159]
    assert len(lines) == len(expected_Ns), f"Expected {len(expected_Ns)} lines in convergence.log, found {len(lines)}."

    for i, N in enumerate(expected_Ns):
        h = 1.0 / (N + 1)
        # Exact L2 error = (1/sqrt(2)) * | (pi^2 * h^2)/(2 * (1 - cos(pi * h))) - 1 |
        expected_error = (1.0 / math.sqrt(2.0)) * abs((math.pi**2 * h**2) / (2.0 * (1.0 - math.cos(math.pi * h))) - 1.0)

        line = lines[i]
        match = re.match(r"^N=(\d+),\s*h=([0-9.]+),\s*error=([0-9.]+)$", line)
        assert match, f"Line {i+1} in convergence.log is incorrectly formatted: '{line}'"

        parsed_N = int(match.group(1))
        parsed_h = float(match.group(2))
        parsed_error = float(match.group(3))

        assert parsed_N == N, f"Expected N={N} on line {i+1}, found N={parsed_N}."
        assert math.isclose(parsed_h, h, rel_tol=1e-4), f"Expected h={h:.6f} for N={N}, found {parsed_h}."
        assert math.isclose(parsed_error, expected_error, abs_tol=5e-6), f"Expected error near {expected_error:.6f} for N={N}, found {parsed_error}."


def test_solution_dat_files():
    """Verify that the solution data files are generated."""
    expected_Ns = [9, 19, 39, 79, 159]
    for N in expected_Ns:
        file_path = f"/home/user/solution_{N}.dat"
        assert os.path.exists(file_path), f"Data file {file_path} is missing."
        validate_solution_file(N)


def test_plot_script_executes_and_generates_real_pngs():
    plot_source = f"{HOME}/plot.py"
    with open(plot_source, "r") as f:
        source = f.read()
    tree = ast.parse(source, filename=plot_source)
    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module.split(".")[0])
    assert "numpy" in imported, "plot.py must use numpy."
    assert "matplotlib" in imported, "plot.py must use matplotlib."
    assert "convergence.log" in source and "solution_159.dat" in source

    outputs = [f"{HOME}/convergence.png", f"{HOME}/solution.png"]
    for path in outputs:
        if os.path.exists(path):
            os.remove(path)
    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    result = subprocess.run(
        ["python3", plot_source], cwd=HOME, env=env,
        text=True, capture_output=True, timeout=60
    )
    assert result.returncode == 0, f"plot.py failed:\n{result.stdout}\n{result.stderr}"

    for path in outputs:
        assert os.path.isfile(path), f"{path} was not generated."
        assert os.path.getsize(path) > 1000, f"{path} is empty or not a meaningful PNG."
        with open(path, "rb") as f:
            assert f.read(8) == b"\x89PNG\r\n\x1a\n", f"{path} is not a PNG."
        image = mpimg.imread(path)
        assert image.ndim in (2, 3)
        assert image.shape[0] >= 100 and image.shape[1] >= 100
        assert np.isfinite(image).all()
        assert float(np.std(image)) > 0.001, f"{path} appears blank."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
