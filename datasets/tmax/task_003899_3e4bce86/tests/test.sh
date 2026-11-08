#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import re
import subprocess

import pytest

PYTHON_SCRIPT = '/home/user/parallel_integrate.py'
STUDY_SCRIPT = '/home/user/run_study.sh'
RESULTS_FILE = '/home/user/convergence_results.json'


def expected_value(N):
    return (1.0 / N**2) * (1.0 / math.tan(math.pi / (2 * N)))**2


def run_as_user(command, timeout=120):
    env = os.environ.copy()
    env['HOME'] = '/home/user'
    env['OMPI_MCA_rmaps_base_oversubscribe'] = '1'
    return subprocess.run(
        ['runuser', '-u', 'user', '--'] + command,
        cwd='/home/user',
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


def test_files_exist():
    """Verify that the required files have been created."""
    required_files = [PYTHON_SCRIPT, STUDY_SCRIPT, RESULTS_FILE]
    for file_path in required_files:
        assert os.path.exists(file_path), f"Required file {file_path} is missing."
        assert os.path.isfile(file_path), f"Required path {file_path} is not a regular file."


def test_integrator_implementation_and_dynamic_execution():
    """Check the requested MPI structure and execute it on non-study meshes."""
    with open(PYTHON_SCRIPT, 'r', encoding='utf-8') as f:
        source = f.read()

    try:
        tree = ast.parse(source, filename=PYTHON_SCRIPT)
    except SyntaxError as exc:
        pytest.fail(f"parallel_integrate.py is not valid Python: {exc}")

    imports_numpy = any(
        (isinstance(node, ast.Import) and any(a.name == 'numpy' for a in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == 'numpy')
        for node in ast.walk(tree)
    )
    imports_mpi4py = any(
        (isinstance(node, ast.Import) and any(a.name.startswith('mpi4py') for a in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module and node.module.startswith('mpi4py'))
        for node in ast.walk(tree)
    )
    assert imports_numpy, "parallel_integrate.py must use numpy."
    assert imports_mpi4py, "parallel_integrate.py must import mpi4py."
    assert '--N' in source, "parallel_integrate.py must accept the --N option."

    attrs = [node.attr for node in ast.walk(tree) if isinstance(node, ast.Attribute)]
    assert 'reduce' in attrs, "The implementation must call comm.reduce."
    assert ('Get_rank' in attrs or 'rank' in attrs), "The implementation must obtain the MPI rank."
    assert ('Get_size' in attrs or 'size' in attrs), "The implementation must obtain the MPI communicator size."
    assert 'sin' in attrs or any(
        isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == 'sin'
        for node in ast.walk(tree)
    ), "The integrand must be evaluated with sin."
    assert 'pi' in attrs or any(
        isinstance(node, ast.Name) and node.id == 'pi' for node in ast.walk(tree)
    ), "The integrand must use pi."

    reduce_results = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            if isinstance(value, ast.Call) and isinstance(value.func, ast.Attribute) and value.func.attr == 'reduce':
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                for target in targets:
                    if isinstance(target, ast.Name):
                        reduce_results.add(target.id)
    assert reduce_results, "The result returned by comm.reduce must be retained."

    printed_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == 'print':
            printed_names.update(n.id for arg in node.args for n in ast.walk(arg) if isinstance(n, ast.Name))
    assert reduce_results & printed_names, "Rank 0 must print the result produced by comm.reduce."

    # Use meshes not listed in the convergence study and varying process counts.
    for process_count, N in [(2, 37), (3, 73)]:
        proc = run_as_user(
            ['mpirun', '-np', str(process_count), 'python3', PYTHON_SCRIPT, '--N', str(N)],
            timeout=90,
        )
        assert proc.returncode == 0, (
            f"MPI integrator failed for N={N}, np={process_count}.\n"
            f"stdout: {proc.stdout}\nstderr: {proc.stderr}"
        )
        lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
        assert len(lines) == 1, f"Integrator must print only one result from Rank 0; got: {proc.stdout!r}"
        try:
            actual = float(lines[0])
        except ValueError:
            pytest.fail(f"Integrator output is not a float: {lines[0]!r}")
        assert math.isfinite(actual)
        assert abs(actual - expected_value(N)) < 1e-10, (
            f"Incorrect trapezoidal integral for N={N}: expected {expected_value(N)}, got {actual}"
        )


def test_run_study_executes_mpi_and_regenerates_json():
    """Execute the submitted study and verify its expanded MPI commands."""
    if os.path.exists(RESULTS_FILE):
        os.remove(RESULTS_FILE)

    proc = run_as_user(['bash', '-x', STUDY_SCRIPT], timeout=240)
    assert proc.returncode == 0, (
        f"run_study.sh failed.\nstdout: {proc.stdout}\nstderr: {proc.stderr}"
    )
    assert os.path.isfile(RESULTS_FILE), "run_study.sh did not regenerate convergence_results.json."

    trace_lines = [line for line in proc.stderr.splitlines() if 'mpirun' in line]
    for N in [100, 200, 400, 800]:
        matching = [
            line for line in trace_lines
            if re.search(r'(^|\s)-np\s+4(\s|$)', line)
            and re.search(r'(^|\s)--N(?:\s+|=)' + str(N) + r'(\s|$)', line)
            and 'parallel_integrate.py' in line
        ]
        assert matching, f"run_study.sh did not execute parallel_integrate.py with mpirun -np 4 --N {N}."


def test_convergence_results():
    """Verify the contents of convergence_results.json match the expected mathematical values."""
    json_path = RESULTS_FILE
    assert os.path.exists(json_path), "convergence_results.json is missing."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    assert isinstance(data, dict), "convergence_results.json must contain a JSON object."
    assert set(data.keys()) == {'100', '200', '400', '800'}, "JSON must contain exactly the four requested mesh resolutions."

    expected = {}
    for N in [100, 200, 400, 800]:
        val = (1.0 / N**2) * (1.0 / math.tan(math.pi / (2 * N)))**2
        expected[str(N)] = val

    for k, v in expected.items():
        assert k in data, f"Missing key '{k}' in convergence_results.json."
        try:
            actual_val = float(data[k])
        except (ValueError, TypeError):
            pytest.fail(f"Value for key '{k}' is not a valid float.")

        assert abs(actual_val - v) < 1e-10, f"Value for {k} incorrect. Expected {v}, got {actual_val}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
