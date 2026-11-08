#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import math
import os
import secrets
import stat
import subprocess
import sys
import tempfile
import pytest

SOLVER_PATH = "/home/user/service/solver.py"
MRE_PATH = "/home/user/mre.sh"


def run_solver(value, timeout=5):
    try:
        return subprocess.run(
            ["python3", SOLVER_PATH, format(value, ".17g")],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"solver.py timed out for input {value}, indicating unsafe termination.")


def expected_length(value):
    current = float(value)
    count = 0
    while current > 1e-5:
        count += 1
        current -= 0.1
        assert count < 100000
    return count + 1


def test_mre_script_exists():
    """Check if the MRE script exists and is executable."""
    assert os.path.exists(MRE_PATH), f"{MRE_PATH} does not exist."
    assert os.path.isfile(MRE_PATH), f"{MRE_PATH} is not a file."
    assert os.access(MRE_PATH, os.X_OK), f"{MRE_PATH} is not executable."


def test_mre_reproduces_original_failure():
    """Run the submitted MRE against the original defective behavior."""
    assert os.path.exists(SOLVER_PATH), f"{SOLVER_PATH} does not exist."
    with open(SOLVER_PATH, "rb") as f:
        repaired_source = f.read()
    repaired_mode = stat.S_IMODE(os.stat(SOLVER_PATH).st_mode)

    fd, marker_path = tempfile.mkstemp(prefix="mre_solver_executed_")
    os.close(fd)
    os.unlink(marker_path)
    defective_source = f'''import sys
sys.setrecursionlimit(400)

with open({marker_path!r}, "w") as marker:
    marker.write("executed")

def calculate_decay_path(x):
    if x == 0.0:
        return [0.0]
    path = calculate_decay_path(x - 0.1)
    path.insert(0, x)
    return path

if __name__ == "__main__":
    if len(sys.argv) > 1:
        val = float(sys.argv[1])
        try:
            result = calculate_decay_path(val)
            print(len(result))
        except Exception as e:
            print(f"Error: {{e}}")
            sys.exit(1)
'''

    try:
        with open(SOLVER_PATH, "w") as f:
            f.write(defective_source)
        os.chmod(SOLVER_PATH, 0o755)
        try:
            result = subprocess.run(
                ["/bin/bash", MRE_PATH],
                capture_output=True,
                text=True,
                timeout=8,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("mre.sh hung instead of producing the bounded original recursion failure.")

        assert os.path.exists(marker_path), "mre.sh did not execute /home/user/service/solver.py."
        combined = result.stdout + result.stderr
        exposed_failure = result.returncode != 0 or "maximum recursion depth" in combined.lower()
        assert exposed_failure, "mre.sh executed the solver but did not reproduce/expose its original recursion failure."
    finally:
        with open(SOLVER_PATH, "wb") as f:
            f.write(repaired_source)
        os.chmod(SOLVER_PATH, repaired_mode)
        if os.path.exists(marker_path):
            os.unlink(marker_path)


def test_answer_txt_content():
    """Check if the answer.txt contains the correct length."""
    answer_path = "/home/user/answer.txt"
    assert os.path.exists(answer_path), f"{answer_path} does not exist."
    with open(answer_path, "r") as f:
        content = f.read().strip()
    assert content == "21", f"Expected answer.txt to contain '21', but got '{content}'."


def test_solver_fixed_behavior():
    """Keep the original fixed-input behavior checks."""
    assert os.path.exists(SOLVER_PATH), f"{SOLVER_PATH} does not exist."

    result = run_solver(0.3)
    assert result.returncode == 0, f"solver.py failed with error: {result.stderr}"
    output = result.stdout.strip()
    assert output == "4", f"Expected solver.py 0.3 to output '4', but got '{output}'."

    result_2 = run_solver(2.0)
    assert result_2.returncode == 0, f"solver.py failed with error: {result_2.stderr}"
    output_2 = result_2.stdout.strip()
    assert output_2 == "21", f"Expected solver.py 2.0 to output '21', but got '{output_2}'."


def test_solver_dynamic_positive_inputs():
    """Exercise derived, non-fixed inputs including tolerance boundaries."""
    rng = secrets.SystemRandom()
    values = [
        1e-8,
        9.999e-6,
        1.001e-5,
        0.099999,
        0.100011,
        0.300009,
        0.300011,
        7.35,
        137.251,
    ]
    values.extend(rng.uniform(0.00002, 40.0) for _ in range(10))

    for value in values:
        result = run_solver(value, timeout=8)
        assert result.returncode == 0, (
            f"solver.py failed for positive input {value}: {result.stderr}"
        )
        output = result.stdout.strip()
        assert output.isdigit(), f"Expected a trajectory length for {value}, got {output!r}."
        assert int(output) == expected_length(value), (
            f"Wrong trajectory length for {value}: expected {expected_length(value)}, got {output}."
        )


def test_calculate_decay_path_returns_valid_trajectory():
    """Verify the core function returns the requested values and final 0.0."""
    rng = secrets.SystemRandom()
    values = [0.000001, 0.300009, 0.300011, 1.25]
    values.extend(rng.uniform(0.01, 12.0) for _ in range(5))

    helper = r'''
import importlib.util, json, math, sys
path = sys.argv[1]
values = json.loads(sys.argv[2])
spec = importlib.util.spec_from_file_location("submitted_solver", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert hasattr(module, "calculate_decay_path")
all_paths = []
for initial in values:
    path_result = module.calculate_decay_path(initial)
    assert isinstance(path_result, list)
    assert path_result
    assert path_result[-1] == 0.0
    current = float(initial)
    expected = []
    while current > 1e-5:
        expected.append(current)
        current -= 0.1
        assert len(expected) < 100000
    expected.append(0.0)
    assert len(path_result) == len(expected)
    for actual, wanted in zip(path_result, expected):
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool)
        assert math.isfinite(actual)
        assert math.isclose(float(actual), wanted, rel_tol=1e-10, abs_tol=1e-10)
    all_paths.append(len(path_result))
print("TRAJECTORIES_OK:" + json.dumps(all_paths))
'''
    try:
        result = subprocess.run(
            ["python3", "-c", helper, SOLVER_PATH, json.dumps(values)],
            capture_output=True,
            text=True,
            timeout=8,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("calculate_decay_path timed out on positive floating-point inputs.")

    assert result.returncode == 0, (
        "calculate_decay_path did not return valid decay lists: "
        + result.stdout + result.stderr
    )
    assert "TRAJECTORIES_OK:" in result.stdout
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
