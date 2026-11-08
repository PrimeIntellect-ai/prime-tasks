#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.metadata
import importlib.util
import math
import os
import re
import subprocess

from packaging.requirements import Requirement

REPO_DIR = "/home/user/solver_repo"
REQ_FILE = os.path.join(REPO_DIR, "requirements.txt")
SOLVER_FILE = os.path.join(REPO_DIR, "solver.py")
SOLUTION_FILE = "/home/user/solution.txt"


def load_solver():
    spec = importlib.util.spec_from_file_location("submitted_solver", SOLVER_FILE)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_solver(calibration=None):
    env = os.environ.copy()
    env.pop("CALIB_CONST", None)
    if calibration is not None:
        env["CALIB_CONST"] = str(calibration)
    return subprocess.run(
        ["python3", SOLVER_FILE],
        cwd=REPO_DIR,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=15,
    )


def output_root(result):
    assert result.returncode == 0, result.stdout
    match = re.search(r"Converged root:\s*([-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)", result.stdout)
    assert match, f"solver.py did not print a converged root: {result.stdout!r}"
    return float(match.group(1))


def test_requirements_fixed():
    assert os.path.isfile(REQ_FILE), f"File {REQ_FILE} does not exist."
    with open(REQ_FILE, "r") as f:
        content = f.read()
    assert "scipy" in content, "scipy dependency not fixed in requirements.txt."
    assert "scipppy" not in content, "Typo 'scipppy' still present in requirements.txt."

    requirements = []
    for line in content.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            requirements.append(Requirement(line))
    scipy_reqs = [req for req in requirements if req.name.lower() == "scipy"]
    assert scipy_reqs, "requirements.txt does not declare the scipy package."

    # Every declared dependency must actually be installed at a compatible version.
    for req in requirements:
        if req.marker is not None and not req.marker.evaluate():
            continue
        try:
            installed = importlib.metadata.version(req.name)
        except importlib.metadata.PackageNotFoundError:
            raise AssertionError(f"Dependency {req.name} is declared but not installed.")
        assert not req.specifier or installed in req.specifier, (
            f"Installed {req.name} version {installed} does not satisfy {req.specifier}."
        )


def test_solver_preserves_model_and_assertions():
    assert os.path.isfile(SOLVER_FILE), f"File {SOLVER_FILE} does not exist."
    with open(SOLVER_FILE, "r") as f:
        tree = ast.parse(f.read(), filename=SOLVER_FILE)
    assert any(isinstance(node, ast.Assert) for node in ast.walk(tree)), (
        "solver.py's internal assertion was removed."
    )

    solver = load_solver()
    for x, c in [(-2.25, 2.0), (-0.5, -1.75), (0.0, 3.25), (1.75, 0.4)]:
        assert math.isclose(solver.f(x, c), x ** 3 - 2 * x + c, rel_tol=0, abs_tol=1e-12)
        assert math.isclose(solver.df(x), 3 * x ** 2 - 2, rel_tol=0, abs_tol=1e-12)


def test_solver_requires_calibration_environment_variable():
    result = run_solver()
    assert result.returncode != 0, "solver.py succeeded without CALIB_CONST."


def test_repaired_solver_executes_and_converges():
    # Exercise the executable with the recovered historical constant and another
    # independently checked input, rather than trusting solution.txt alone.
    for calibration in (2.0, 3.0):
        root = output_root(run_solver(calibration))
        residual = root ** 3 - 2 * root + calibration
        assert abs(residual) < 1e-5, (
            f"solver.py returned {root} for CALIB_CONST={calibration}; residual={residual}."
        )
        assert root < 0, "solver.py did not select the intended negative root."


def test_solution_file_exists_and_correct():
    assert os.path.isfile(SOLUTION_FILE), f"Solution file {SOLUTION_FILE} does not exist."
    with open(SOLUTION_FILE, "r") as f:
        content = f.read().strip()

    # Preserve the original required final-state assertion.
    assert content == "-1.769292", f"Expected solution to be '-1.769292', but got '{content}'."
    assert re.fullmatch(r"-?\d+\.\d{6}", content), "solution.txt is not rounded to exactly 6 decimal places."

    executed_root = output_root(run_solver(2.0))
    assert content == f"{executed_root:.6f}", (
        "solution.txt does not match the root produced by the repaired solver."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
