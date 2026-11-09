#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import ast
import os
import subprocess
import sys
import pytest

SCRIPT_PATH = '/home/user/vectorized_sim.py'
REPORT_PATH = '/home/user/report.txt'


def compute_expected():
    # We must use numpy to reproduce the exact random sequence requested by the prompt
    import numpy as np

    def test_dt(dt):
        np.random.seed(42)
        N = 10000
        T = 2.0
        steps = int(T / dt)

        X = np.random.randn(N)

        for _ in range(steps):
            Z = np.random.randn(N)
            X = X + (-X**3 + 2*X)*dt + np.sqrt(dt) * Z

        diverged = np.isnan(X).any() or np.isinf(X).any() or (np.abs(X) > 1000.0).any()
        return diverged, X

    for dt in [0.1, 0.05, 0.025, 0.01, 0.005, 0.001]:
        diverged, X = test_dt(dt)
        if not diverged:
            return dt, np.mean(X)
    return None, None


def _name_set(node):
    return {n.id for n in ast.walk(node) if isinstance(n, ast.Name)}


def _is_vector_size(node, particle_count_names):
    return (
        isinstance(node, ast.Constant) and node.value == 10000
    ) or (
        isinstance(node, ast.Name) and node.id in particle_count_names
    )


def test_vectorized_sim_exists():
    path = SCRIPT_PATH
    assert os.path.isfile(path), f"The file {path} does not exist. Please save your vectorized code there."

    with open(path, 'r', encoding='utf-8') as f:
        source = f.read()
    assert source.strip(), f"The file {path} is empty."

    try:
        tree = ast.parse(source, filename=path)
    except SyntaxError as exc:
        pytest.fail(f"The file {path} is not valid Python: {exc}")

    particle_count_names = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if isinstance(value, ast.Constant) and value.value == 10000:
                for target in targets:
                    if isinstance(target, ast.Name):
                        particle_count_names.add(target.id)

    vector_randn_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if node.func.attr == 'randn' and node.args and _is_vector_size(node.args[0], particle_count_names):
                vector_randn_calls.append(node)
    assert vector_randn_calls, (
        "The simulation must initialize/generate all 10,000 particle values with a vectorized np.random.randn call."
    )

    loops = [node for node in ast.walk(tree) if isinstance(node, (ast.For, ast.While))]
    assert loops, "The vectorized simulation must contain a time-step loop."
    assert any(
        any(call is descendant for descendant in ast.walk(loop))
        for loop in loops for call in vector_randn_calls
    ), "Noise for all 10,000 particles must be generated vectorially inside the time loop."

    # Reject loops whose iteration bound is the particle count, including common
    # range(len(X)) particle-loop formulations.
    for node in ast.walk(tree):
        if isinstance(node, (ast.For, ast.comprehension)):
            iterator = node.iter
            if isinstance(iterator, ast.Call) and isinstance(iterator.func, ast.Name) and iterator.func.id == 'range':
                assert not any(_is_vector_size(arg, particle_count_names) for arg in iterator.args), (
                    "A Python loop over the 10,000 particles is not allowed; update the particle array vectorially."
                )
                assert not any(
                    isinstance(arg, ast.Call)
                    and isinstance(arg.func, ast.Name)
                    and arg.func.id == 'len'
                    and arg.args
                    and isinstance(arg.args[0], ast.Name)
                    and arg.args[0].id.lower() in {'x', 'particles', 'particle', 'state', 'states'}
                    for arg in iterator.args
                ), "A Python loop over the particle array is not allowed."
        elif isinstance(node, ast.While):
            for comparison in [n for n in ast.walk(node.test) if isinstance(n, ast.Compare)]:
                bounds = [comparison.left] + list(comparison.comparators)
                assert not any(_is_vector_size(bound, particle_count_names) for bound in bounds), (
                    "A Python while-loop over the 10,000 particles is not allowed."
                )


def test_vectorized_script_executes_and_creates_report():
    # The report must be produced by the submitted executable artifact, rather
    # than being supplied independently alongside an empty or inert script.
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), (
        f"Executing {SCRIPT_PATH} must perform the profiling and create {REPORT_PATH}."
    )


def test_report_content():
    report_path = '/home/user/report.txt'
    assert os.path.isfile(report_path), f"The file {report_path} does not exist."

    with open(report_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) >= 2, f"The file {report_path} must contain at least two non-empty lines."

    expected_dt, expected_mean = compute_expected()

    # Check first line for optimal dt
    assert str(expected_dt) in lines[0], (
        f"The first line of {report_path} is incorrect. "
        f"Expected to find the optimal dt '{expected_dt}', but got: '{lines[0]}'."
    )

    # Check second line for mean rounded to 4 decimal places
    expected_mean_str = f"{expected_mean:.4f}"
    assert expected_mean_str in lines[1], (
        f"The second line of {report_path} is incorrect. "
        f"Expected to find the mean '{expected_mean_str}', but got: '{lines[1]}'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
