#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import subprocess

PROJECT_DIR = "/home/user/project"
APP_PATH = os.path.join(PROJECT_DIR, "app")
LOG_PATH = os.path.join(PROJECT_DIR, "test_results.log")
E2E_PATH = os.path.join(PROJECT_DIR, "e2e_test.py")
WEIGHTS = [2, 3, 5, 7, 11, 13, 17, 19]
EXPECTED_E2E_CASES = [(24, True), (4, False), (10, True), (100, False)]


def expected_subset_sum(target):
    reachable = {0}
    for weight in WEIGHTS:
        reachable |= {value + weight for value in tuple(reachable)}
    return target in reachable


def run_app(target):
    result = subprocess.run(
        [APP_PATH, str(target)],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"app failed for target {target}: stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    assert result.stderr == "", f"app wrote unexpected stderr for target {target}: {result.stderr!r}"
    return result.stdout.strip()


def test_app_binary_exists_and_executable():
    assert os.path.isfile(APP_PATH), f"The compiled binary does not exist at {APP_PATH}"
    assert os.access(APP_PATH, os.X_OK), f"The file at {APP_PATH} is not executable"
    with open(APP_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{APP_PATH} is not an ELF binary"
    metadata = subprocess.run(
        ["go", "version", "-m", APP_PATH], capture_output=True, text=True, timeout=10
    )
    assert metadata.returncode == 0, f"{APP_PATH} is not recognized as a Go binary: {metadata.stderr}"
    assert "go1." in metadata.stdout, f"Go build metadata is missing from {APP_PATH}"
    assert re.search(r"(?m)^\s*path\s+project\s*$", metadata.stdout), (
        f"{APP_PATH} was not built from the project main package: {metadata.stdout}"
    )


def test_test_results_log_contains_passed():
    assert os.path.isfile(LOG_PATH), f"The log file does not exist at {LOG_PATH}"
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        content = f.read()
    assert "E2E TESTS PASSED" in content, (
        f"The log file {LOG_PATH} does not contain 'E2E TESTS PASSED'"
    )


def test_go_build_success():
    # Verify that the circular import is fixed by running go build.
    result = subprocess.run(
        ["go", "build"],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"'go build' failed in {PROJECT_DIR}. Output: {result.stderr}"


def test_compiled_app_subset_sum_behavior():
    # Derive every expected answer independently for targets around the full
    # reachable range instead of trusting the submitted log or test script.
    for target in range(-5, sum(WEIGHTS) + 6):
        expected = str(expected_subset_sum(target)).lower()
        actual = run_app(target)
        assert actual == expected, (
            f"wrong subset-sum result for target {target}: expected {expected!r}, got {actual!r}"
        )


def test_solver_package_on_independent_inputs(tmp_path):
    # Exercise FindSubset with weight sets not used by main.go.
    test_file = os.path.join(PROJECT_DIR, "solver", "verifier_generated_test.go")
    source = r'''package solver

import "testing"

func bruteForce(weights []int, target int) bool {
    for mask := 0; mask < (1 << uint(len(weights))); mask++ {
        sum := 0
        for i, weight := range weights {
            if mask&(1<<uint(i)) != 0 {
                sum += weight
            }
        }
        if sum == target {
            return true
        }
    }
    return false
}

func TestVerifierIndependentInputs(t *testing.T) {
    cases := [][]int{
        {1, 4, 6},
        {3, 8, 10, 21},
        {2, 2, 5, 9},
        {7},
        {},
    }
    for _, weights := range cases {
        sum := 0
        for _, weight := range weights { sum += weight }
        for target := 0; target <= sum+3; target++ {
            want := bruteForce(weights, target)
            if got := FindSubset(weights, target); got != want {
                t.Fatalf("FindSubset(%v, %d) = %v, want %v", weights, target, got, want)
            }
        }
    }
}
'''
    assert not os.path.exists(test_file)
    try:
        with open(test_file, "w", encoding="utf-8") as f:
            f.write(source)
        result = subprocess.run(
            ["go", "test", "./solver"],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, f"solver behavior tests failed:\n{result.stdout}\n{result.stderr}"
    finally:
        if os.path.exists(test_file):
            os.remove(test_file)


def test_original_e2e_script_and_redirected_log():
    assert os.path.isfile(E2E_PATH), f"The end-to-end script does not exist at {E2E_PATH}"
    with open(E2E_PATH, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=E2E_PATH)

    found_cases = None
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if any(isinstance(target, ast.Name) and target.id == "tests" for target in targets):
                found_cases = ast.literal_eval(node.value)
                break
    assert found_cases == EXPECTED_E2E_CASES, (
        f"The inputs in e2e_test.py were changed: found {found_cases!r}"
    )

    result = subprocess.run(
        ["python3", E2E_PATH],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"e2e_test.py failed:\n{result.stdout}\n{result.stderr}"
    assert result.stderr == "", f"e2e_test.py wrote unexpected stderr: {result.stderr!r}"
    assert result.stdout == "E2E TESTS PASSED\n", f"Unexpected e2e output: {result.stdout!r}"

    with open(LOG_PATH, "r", encoding="utf-8") as f:
        logged = f.read()
    assert logged == result.stdout, (
        f"{LOG_PATH} does not exactly contain the stdout produced by e2e_test.py"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
