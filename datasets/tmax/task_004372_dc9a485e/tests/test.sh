#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
import pytest

BACKEND = "/home/user/sim_backend"
SOURCE = "/home/user/sim_backend.cpp"
CONTROLLER = "/home/user/controller.py"
RESULTS = "/home/user/convergence_results.json"
COMPILED_COPY = "/tmp/verifier_sim_backend"

EXPECTED_CONTROLLER = b'''import subprocess
import json
import sys
import os

def run_sim():
    history = []

    # The simulation iteratively runs from depth 10 down to -4.
    # It expects the backend to safely handle negative depths (e.g., returning the base value).
    for i in range(10, -5, -1):
        try:
            res = subprocess.check_output(["/home/user/sim_backend", str(i)], stderr=subprocess.STDOUT)
            val = float(res.decode('utf-8').strip())
            history.append(val)
        except subprocess.CalledProcessError as e:
            print(f"Backend crashed at iteration {i}!")
            sys.exit(1)
        except ValueError:
            print("Invalid output from backend!")
            sys.exit(1)

    with open("/home/user/convergence_results.json", "w") as f:
        json.dump({"status": "converged", "history": history}, f)
    print("Simulation converged successfully.")

if __name__ == "__main__":
    if not os.path.exists("/home/user/sim_backend"):
        print("Backend executable not found!")
        sys.exit(1)
    run_sim()
'''


def assert_controller_unchanged():
    assert os.path.isfile(CONTROLLER), "The controller is missing."
    with open(CONTROLLER, "rb") as f:
        assert f.read() == EXPECTED_CONTROLLER, "Do not modify /home/user/controller.py."


def expected_value(depth):
    value = 100.0 if depth <= 0 else 100.0 * (0.9 ** depth)
    return float(f"{value:.4f}")


def run_and_check(executable, depth):
    try:
        result = subprocess.run(
            [executable, str(depth)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=3,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{executable} did not terminate for depth {depth}; the recursion base case is still defective.")

    assert result.returncode == 0, (
        f"{executable} failed for depth {depth} with return code {result.returncode}: {result.stderr}"
    )
    output = result.stdout.strip()
    try:
        value = float(output)
    except ValueError:
        pytest.fail(f"{executable} produced non-numeric output for depth {depth}: {output!r}")
    assert math.isfinite(value), f"{executable} produced a non-finite value for depth {depth}."
    assert abs(value - expected_value(depth)) < 0.000051, (
        f"Incorrect result for depth {depth}: expected {expected_value(depth):.4f}, got {value}."
    )


def test_sim_backend_executable_exists():
    executable_path = "/home/user/sim_backend"
    assert os.path.isfile(executable_path), f"The compiled executable {executable_path} does not exist."
    assert os.access(executable_path, os.X_OK), f"The file {executable_path} is not executable."
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable_path} is not a compiled ELF executable."


def test_fixed_source_compiles_and_backend_behaves_correctly():
    assert_controller_unchanged()
    assert os.path.isfile(SOURCE), f"The backend source {SOURCE} does not exist."

    build = subprocess.run(
        ["g++", "-O2", SOURCE, "-o", COMPILED_COPY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )
    assert build.returncode == 0, f"The submitted C++ source does not compile:\n{build.stderr}"

    # Exercise every input used by the controller on both the submitted binary
    # and a fresh build of the submitted source. Extra negative values verify
    # that negative depth is handled as a terminating base case.
    depths = list(range(10, -5, -1)) + [-25, -1000]
    for executable in (BACKEND, COMPILED_COPY):
        for depth in depths:
            run_and_check(executable, depth)

    assert_controller_unchanged()


def test_convergence_results_exists_and_valid():
    assert_controller_unchanged()

    # A pre-fabricated diagnostics file must not satisfy the task. Re-run the
    # real, unmodified controller against the submitted backend.
    try:
        os.unlink(RESULTS)
    except FileNotFoundError:
        pass

    try:
        completed = subprocess.run(
            ["python3", CONTROLLER],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The controller timed out; the backend likely still has non-terminating recursion.")

    assert completed.returncode == 0, (
        f"The controller failed with return code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert_controller_unchanged()

    results_path = "/home/user/convergence_results.json"
    assert os.path.isfile(results_path), f"The expected output file {results_path} does not exist. Did you run the controller?"

    with open(results_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {results_path} does not contain valid JSON.")

    assert "status" in data, "The 'status' field is missing from the JSON output."
    assert data["status"] == "converged", f"Expected status 'converged', but got '{data['status']}'."

    assert "history" in data, "The 'history' field is missing from the JSON output."
    assert isinstance(data["history"], list), "The 'history' field should be a list."
    assert len(data["history"]) == 15, f"Expected 15 elements in the history array, but got {len(data['history'])}."

    expected_history = [expected_value(i) for i in range(10, -5, -1)]
    assert data["history"] == expected_history, (
        f"The controller history is incorrect. Expected {expected_history}, got {data['history']}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
