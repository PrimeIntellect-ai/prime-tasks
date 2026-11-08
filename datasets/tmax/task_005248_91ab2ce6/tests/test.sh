#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/evaluator.py"


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."


def test_evaluator_valid():
    cmd = ["python3", SCRIPT_PATH, "/home/user/expr_valid", "A"]
    result = subprocess.run(cmd, capture_output=True, text=True)

    assert result.returncode == 0, f"Expected exit code 0, got {result.returncode}. Stderr: {result.stderr}"
    assert result.stdout.strip() == "Result: 33", f"Expected 'Result: 33', got '{result.stdout.strip()}'"


def test_evaluator_invalid_ownership():
    cmd = ["python3", SCRIPT_PATH, "/home/user/expr_invalid", "X"]
    result = subprocess.run(cmd, capture_output=True, text=True)

    assert result.returncode == 1, f"Expected exit code 1, got {result.returncode}. Stderr: {result.stderr}"
    assert result.stdout.strip() == "OwnershipError: V", f"Expected 'OwnershipError: V', got '{result.stdout.strip()}'"


def test_evaluator_cycle():
    cmd = ["python3", SCRIPT_PATH, "/home/user/expr_cycle", "P"]
    result = subprocess.run(cmd, capture_output=True, text=True)

    assert result.returncode == 2, f"Expected exit code 2, got {result.returncode}. Stderr: {result.stderr}"
    assert result.stdout.strip() == "CircularDependency", f"Expected 'CircularDependency', got '{result.stdout.strip()}'"


def random_var(prefix):
    suffix = ''.join(secrets.choice(string.ascii_uppercase) for _ in range(12))
    return prefix + suffix


def run_generated(files, target):
    with tempfile.TemporaryDirectory(prefix="evaluator case ") as directory:
        for variable, expression in files.items():
            with open(os.path.join(directory, variable + ".expr"), "w", encoding="utf-8") as handle:
                handle.write(f"{variable} = {expression}\n")
        # Non-expression files must not affect directory evaluation.
        with open(os.path.join(directory, "ignored.txt"), "w", encoding="utf-8") as handle:
            handle.write("not an expression")
        return subprocess.run(
            ["python3", SCRIPT_PATH, directory, target],
            capture_output=True,
            text=True,
            timeout=10,
        )


def test_generated_arithmetic_and_dependencies():
    # Fresh names and values prevent dispatching on the three public examples.
    for _ in range(5):
        base = random_var("B")
        offset = random_var("O")
        left = random_var("L")
        right = random_var("R")
        target = random_var("T")

        a = secrets.randbelow(80) + 30
        b = secrets.randbelow(20) + 1
        c = secrets.randbelow(a - 1) + 1
        d = secrets.randbelow(8) + 2
        k = secrets.randbelow(7) + 2
        m = secrets.randbelow(6) + 2
        q = secrets.randbelow(20)

        files = {
            target: f"{left} + ({right} * {m}) - {q}",
            right: f"({base} - {c}) / {d}",
            offset: str(b),
            left: f"({base} * {k}) + {offset}",
            base: str(a),
        }
        expected = (a * k + b) + ((a - c) // d) * m - q
        result = run_generated(files, target)
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == f"Result: {expected}"


def test_generated_deep_resolution():
    variables = [random_var("D") for _ in range(7)]
    value = secrets.randbelow(10) + 2
    files = {variables[0]: str(value)}
    expected = value
    for index in range(1, len(variables)):
        multiplier = secrets.randbelow(4) + 2
        decrement = secrets.randbelow(5)
        files[variables[index]] = f"({variables[index - 1]} * {multiplier}) - {decrement}"
        expected = expected * multiplier - decrement

    result = run_generated(files, variables[-1])
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == f"Result: {expected}"


def test_generated_ownership_violation():
    shared = random_var("S")
    branches = [random_var("N") for _ in range(3)]
    target = random_var("T")
    value = secrets.randbelow(30) + 1
    files = {
        shared: str(value),
        branches[0]: f"{shared} * 2",
        branches[1]: f"{shared} + 7",
        branches[2]: f"{shared} - 3",
        target: f"{branches[0]} + {branches[1]} + {branches[2]}",
    }
    result = run_generated(files, target)
    assert result.returncode == 1, result.stderr
    assert result.stdout.strip() == f"OwnershipError: {shared}"


def test_generated_cycle():
    cycle = [random_var("C") for _ in range(4)]
    files = {
        cycle[0]: f"{cycle[1]} + 1",
        cycle[1]: f"{cycle[2]} * 2",
        cycle[2]: f"{cycle[3]} - 4",
        cycle[3]: f"{cycle[0]} + 9",
    }
    result = run_generated(files, cycle[0])
    assert result.returncode == 2, result.stderr
    assert result.stdout.strip() == "CircularDependency"


def test_only_reachable_variables_are_evaluated():
    live = random_var("L")
    target = random_var("T")
    dead_shared = random_var("S")
    dead = [random_var("U") for _ in range(4)]
    cyc_a = random_var("C")
    cyc_b = random_var("C")
    value = secrets.randbelow(40) + 1
    files = {
        live: str(value),
        target: f"{live} + {live}",
        dead_shared: "5",
        dead[0]: f"{dead_shared} + 1",
        dead[1]: f"{dead_shared} + 2",
        dead[2]: f"{dead_shared} + 3",
        dead[3]: f"{dead[0]} + {dead[1]} + {dead[2]}",
        cyc_a: f"{cyc_b} + 1",
        cyc_b: f"{cyc_a} + 1",
    }
    result = run_generated(files, target)
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == f"Result: {value * 2}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
