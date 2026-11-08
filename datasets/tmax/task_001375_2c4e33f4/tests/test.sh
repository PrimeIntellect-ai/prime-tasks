#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess

C_PATH = "/home/user/find_steady_state.c"
SOLVER_PATH = "/home/user/solver"
CSV_PATH = "/home/user/steady_state.csv"
VALIDATE_PATH = "/home/user/validate.sh"


def run_program(path):
    result = subprocess.run([path], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"{path} exited with status {result.returncode}: {result.stderr}"
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert len(lines) == 1, f"{path} must print exactly one non-empty output line, got {result.stdout!r}"
    fields = lines[0].split(',')
    assert len(fields) == 2, f"Solver output must be '<x>,<y>', got {lines[0]!r}"
    try:
        values = tuple(float(field) for field in fields)
    except ValueError as exc:
        raise AssertionError(f"Solver output must contain two numbers, got {lines[0]!r}") from exc
    assert all(math.isfinite(value) for value in values), "Solver output contains NaN or infinity."
    return values


def test_solver_executable_exists_and_runs_built_source():
    assert os.path.isfile(SOLVER_PATH), f"Executable {SOLVER_PATH} does not exist."
    assert os.access(SOLVER_PATH, os.X_OK), f"Executable {SOLVER_PATH} is not executable."
    with open(SOLVER_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "solver must be a compiled executable, not a wrapper script."

    subprocess.run(
        ["gcc", C_PATH, "-o", "/tmp/verifier_solver", "-lm"],
        check=True, capture_output=True, text=True, timeout=20
    )
    submitted_values = run_program(SOLVER_PATH)
    source_values = run_program("/tmp/verifier_solver")

    for submitted, rebuilt in zip(submitted_values, source_values):
        assert abs(submitted - rebuilt) <= 1e-7, (
            f"solver output {submitted_values} does not match the submitted C source output {source_values}."
        )

    x, y = submitted_values
    assert abs(1.0 - x - 2.0*x*y) < 1e-5, "Solver output does not satisfy the first rate equation."
    assert abs(2.0*x - 2.0*y) < 1e-5, "Solver output does not satisfy the second rate equation."
    # With the prescribed initial state and regularized iteration, convergence is to the negative root.
    assert abs(x + 1.0) < 1e-5 and abs(y + 1.0) < 1e-5, (
        f"Unexpected root {submitted_values} for the prescribed initial state."
    )


def test_c_code_regularization():
    assert os.path.isfile(C_PATH), f"C source file {C_PATH} is missing."
    with open(C_PATH, 'r') as f:
        content = f.read()

    # Ignore comments so the two commented suggestions in the original file cannot satisfy this check.
    active = re.sub(r'/\*.*?\*/', '', content, flags=re.S)
    active = re.sub(r'//[^\n]*', '', active)

    # The supplied equations, Jacobian, and initial state must remain unchanged.
    required = [
        r'\*f1\s*=\s*1\.0\s*-\s*x\s*-\s*2\.0\s*\*\s*x\s*\*\s*y\s*;',
        r'\*f2\s*=\s*2\.0\s*\*\s*x\s*-\s*2\.0\s*\*\s*y\s*;',
        r'J\s*\[\s*0\s*\]\s*\[\s*0\s*\]\s*=\s*-1\.0\s*-\s*2\.0\s*\*\s*y\s*;',
        r'J\s*\[\s*0\s*\]\s*\[\s*1\s*\]\s*=\s*-2\.0\s*\*\s*x\s*;',
        r'J\s*\[\s*1\s*\]\s*\[\s*0\s*\]\s*=\s*2\.0\s*;',
        r'J\s*\[\s*1\s*\]\s*\[\s*1\s*\]\s*=\s*-2\.0\s*;',
        r'double\s+x\s*=\s*0\.0\s*;',
        r'double\s+y\s*=\s*-0\.5\s*;',
    ]
    for pattern in required:
        assert re.search(pattern, active), "The supplied equations, Jacobian, or initial guesses were changed."

    section_match = re.search(
        r'compute_jacobian\s*\(\s*x\s*,\s*y\s*,\s*J\s*\)\s*;(.*?)det\s*=',
        active, flags=re.S
    )
    assert section_match, "Could not locate regularization before the determinant calculation."
    section = section_match.group(1)
    number = r'1(?:\.0*)?[eE]-0*6'
    operand = rf'({number}|[A-Za-z_]\w*)'
    add0 = re.search(rf'J\s*\[\s*0\s*\]\s*\[\s*0\s*\]\s*\+=\s*{operand}\s*;', section)
    add1 = re.search(rf'J\s*\[\s*1\s*\]\s*\[\s*1\s*\]\s*\+=\s*{operand}\s*;', section)
    assert add0 and add1, "Both Jacobian diagonal entries must be actively regularized before det is calculated."

    for addition in (add0, add1):
        value = addition.group(1)
        if not re.fullmatch(number, value):
            assignment = rf'(?:double\s+)?{re.escape(value)}\s*=\s*{number}\s*;'
            assert re.search(assignment, active[:section_match.end()]), (
                f"Regularization variable {value!r} is not assigned 1e-6 before use."
            )


def test_csv_format_and_values_come_from_solver():
    assert os.path.isfile(CSV_PATH), f"CSV file {CSV_PATH} does not exist."
    with open(CSV_PATH, newline='') as f:
        rows = list(csv.reader(f))

    assert len(rows) == 2, "CSV file must contain exactly a header row and one data row."
    assert rows[0] == ['x', 'y'], "CSV header must be exactly 'x,y'."
    assert len(rows[1]) == 2, "CSV data row must contain exactly two fields."
    try:
        csv_values = tuple(float(value) for value in rows[1])
    except ValueError as exc:
        raise AssertionError("CSV data row must contain numeric values.") from exc
    assert all(math.isfinite(value) for value in csv_values), "CSV contains NaN or infinity."

    solver_values = run_program(SOLVER_PATH)
    for csv_value, solver_value in zip(csv_values, solver_values):
        assert abs(csv_value - solver_value) <= 1e-7, (
            f"CSV values {csv_values} do not match solver output {solver_values}."
        )


def run_validator(expected):
    result = subprocess.run([VALIDATE_PATH], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"validate.sh exited with status {result.returncode}: {result.stderr}"
    assert result.stdout.strip() == expected, (
        f"Expected validate.sh to output {expected!r}, got {result.stdout.strip()!r}."
    )


def test_validate_script_implements_strict_sum_check():
    assert os.path.isfile(VALIDATE_PATH), f"Script {VALIDATE_PATH} does not exist."
    assert os.access(VALIDATE_PATH, os.X_OK), f"Script {VALIDATE_PATH} is not executable."

    with open(CSV_PATH, 'rb') as f:
        original = f.read()
    cases = [
        ("x,y\n0.5,0.5\n", "VALID"),
        ("x,y\n0.4,0.5\n", "INVALID"),  # exactly 0.9 is excluded
        ("x,y\n0.6,0.5\n", "INVALID"),  # exactly 1.1 is excluded
        ("x,y\n-1.0,-1.0\n", "INVALID"),
    ]
    try:
        for data, expected in cases:
            with open(CSV_PATH, 'w') as f:
                f.write(data)
            run_validator(expected)
    finally:
        with open(CSV_PATH, 'wb') as f:
            f.write(original)

    with open(CSV_PATH, newline='') as f:
        rows = list(csv.reader(f))
    total = float(rows[1][0]) + float(rows[1][1])
    run_validator("VALID" if 0.9 < total < 1.1 else "INVALID")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
