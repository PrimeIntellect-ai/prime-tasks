#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

REPO_DIR = "/home/user/math-solver"
RESOLUTION_FILE = "/home/user/resolution.txt"
BUGGY_COMMIT_FILE = "/tests/.buggy_commit"
SOLVER_FILE = os.path.join(REPO_DIR, "solver.go")
SOLVER_TEST_FILE = os.path.join(REPO_DIR, "solver_test.go")


def test_resolution_file():
    assert os.path.isfile(RESOLUTION_FILE), f"Resolution file {RESOLUTION_FILE} does not exist."

    with open(RESOLUTION_FILE, "r") as f:
        raw = f.read()
    lines = raw.splitlines()

    assert len(lines) == 2, f"Expected exactly 2 lines in {RESOLUTION_FILE}, found {len(lines)}."
    assert all(line == line.strip() and line for line in lines), "Resolution lines must be nonempty and contain no surrounding whitespace."

    assert os.path.isfile(BUGGY_COMMIT_FILE), "Verifier oracle for the buggy commit is missing."
    with open(BUGGY_COMMIT_FILE, "r") as f:
        expected_commit = f.read().strip()

    assert re.fullmatch(r"[0-9a-f]{40}", lines[0]), "Line 1 must be a full 40-character Git commit hash."
    assert lines[0] == expected_commit, f"Line 1 of {RESOLUTION_FILE} is incorrect. Expected the buggy commit hash."

    expected_root = "2.094551"
    assert lines[1] == expected_root, f"Line 2 of {RESOLUTION_FILE} is incorrect. Expected {expected_root}, got {lines[1]}."


def test_solver_test_minimized():
    assert os.path.isfile(SOLVER_TEST_FILE), f"Test file {SOLVER_TEST_FILE} is missing."

    with open(SOLVER_TEST_FILE, "r") as f:
        content = f.read()

    assert "func TestFindRoot(" in content, "TestFindRoot must be present in solver_test.go."
    assert "func TestAdd(" not in content, "TestAdd should have been removed from solver_test.go."
    assert "func TestAddZero(" not in content, "TestAddZero should have been removed from solver_test.go."
    test_functions = re.findall(r"(?m)^\s*func\s+(Test\w+)\s*\(", content)
    assert test_functions == ["TestFindRoot"], f"solver_test.go must contain only TestFindRoot; found {test_functions}."


def test_precision_fix_and_behavior():
    assert os.path.isfile(SOLVER_FILE), f"Solver file {SOLVER_FILE} is missing."
    with open(SOLVER_FILE, "r") as f:
        source = f.read()

    assert re.search(r"func\s+FindRoot\s*\(\s*guess\s+float64\s*,\s*epsilon\s+float64\s*\)\s+float64", source), "FindRoot's required signature was changed."
    assert not re.search(r"\bfloat32\b", source), "FindRoot must use float64 for all intermediate calculations."

    verifier_test = os.path.join(REPO_DIR, "zz_verifier_precision_test.go")
    test_source = r'''package solver

import (
    "math"
    "testing"
)

func verifierReference(guess, epsilon float64) float64 {
    x := guess
    for i := 0; i < 1000; i++ {
        fx := x*x*x - 2*x - 5
        dfx := 3*x*x - 2
        step := fx / dfx
        xNext := x - step
        if math.Abs(xNext-x) < epsilon {
            return xNext
        }
        x = xNext
    }
    return math.NaN()
}

func TestVerifierFindRootBehavior(t *testing.T) {
    cases := []struct { guess, epsilon float64 }{
        {2.0, 1e-9},
        {3.0, 10.0},
        {1.0, 10.0},
        {2.5, 0.1},
    }
    for _, tc := range cases {
        want := verifierReference(tc.guess, tc.epsilon)
        got := FindRoot(tc.guess, tc.epsilon)
        if math.IsNaN(got) || math.IsInf(got, 0) {
            t.Fatalf("FindRoot(%g, %g) returned %v", tc.guess, tc.epsilon, got)
        }
        if math.Abs(got-want) > 1e-12 {
            t.Fatalf("FindRoot(%g, %g) = %.17g; want %.17g", tc.guess, tc.epsilon, got, want)
        }
    }
}
'''
    with open(verifier_test, "w") as f:
        f.write(test_source)
    try:
        result = subprocess.run(
            ["go", "test", "-count=1", "./..."],
            cwd=REPO_DIR,
            capture_output=True,
            text=True,
            timeout=120,
        )
    finally:
        try:
            os.remove(verifier_test)
        except FileNotFoundError:
            pass

    assert result.returncode == 0, f"Behavioral Go tests failed in {REPO_DIR}. Output:\n{result.stdout}\n{result.stderr}"


def test_go_tests_pass():
    assert os.path.isdir(REPO_DIR), f"Repository directory {REPO_DIR} is missing."

    result = subprocess.run(
        ["go", "test", "-count=1"],
        cwd=REPO_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )

    assert result.returncode == 0, f"'go test' failed in {REPO_DIR}. Output:\n{result.stdout}\n{result.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
