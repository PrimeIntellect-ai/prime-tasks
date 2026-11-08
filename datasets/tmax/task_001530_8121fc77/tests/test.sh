#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

PROJECT_DIR = "/home/user/math_project"
CRASH_LINE_TXT = os.path.join(PROJECT_DIR, "crash_line.txt")
FINAL_RESULT_TXT = os.path.join(PROJECT_DIR, "final_result.txt")
MAKEFILE = os.path.join(PROJECT_DIR, "Makefile")
CALC_C = os.path.join(PROJECT_DIR, "calc.c")
CALC_EXE = os.path.join(PROJECT_DIR, "calc")
DATA_TXT = os.path.join(PROJECT_DIR, "data.txt")


def test_crash_line_saved():
    assert os.path.isfile(CRASH_LINE_TXT), f"{CRASH_LINE_TXT} is missing."
    with open(CRASH_LINE_TXT, "r") as f:
        content = f.read().strip()
    assert "425 DIV 50 0" in content, f"crash_line.txt does not contain the correct crash line. Found: {content}"
    assert content == "425 DIV 50 0", f"crash_line.txt must contain the exact single crashing line. Found: {content}"


def test_final_result_saved():
    assert os.path.isfile(FINAL_RESULT_TXT), f"{FINAL_RESULT_TXT} is missing."
    with open(FINAL_RESULT_TXT, "r") as f:
        content = f.read().strip()
    assert "Total: 12693" in content, f"final_result.txt does not contain the correct total. Found: {content}"
    assert content == "Total: 12693", f"final_result.txt must contain only the saved program output. Found: {content}"


def test_make_succeeds():
    assert os.path.isfile(MAKEFILE), f"{MAKEFILE} is missing."
    assert os.path.isfile(CALC_C), f"{CALC_C} is missing."
    if os.path.isfile(CALC_EXE):
        os.remove(CALC_EXE)

    result = subprocess.run(["make"], cwd=PROJECT_DIR, capture_output=True, text=True)
    assert result.returncode == 0, f"make failed with error:\n{result.stderr}"
    assert os.path.isfile(CALC_EXE), f"make succeeded but {CALC_EXE} was not created."
    assert os.access(CALC_EXE, os.X_OK), f"{CALC_EXE} is not executable."
    with open(CALC_EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{CALC_EXE} is not a compiled executable."


def test_executable_runs_without_crash():
    assert os.path.isfile(CALC_EXE), f"{CALC_EXE} is missing, cannot test execution."
    result = subprocess.run(["./calc", "data.txt"], cwd=PROJECT_DIR, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Program crashed or returned non-zero exit code: {result.returncode}\nStderr: {result.stderr}"
    assert "Total: 12693" in result.stdout, f"Program output did not contain 'Total: 12693'. Found: {result.stdout}"


def c_div(a, b):
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q


def expected_value(rows):
    total = 0
    for _, op, a, b in rows:
        if op == "ADD":
            total += a + b
        elif op == "SUB":
            total += a - b
        elif op == "MUL":
            total += a * b
        elif op == "DIV" and b != 0:
            total += c_div(a, b)
    return total


def run_and_check(executable, input_path, expected):
    result = subprocess.run([executable, str(input_path)], cwd=PROJECT_DIR, capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Program failed on generated input with code {result.returncode}: {result.stderr}"
    match = re.fullmatch(r"Total: (-?\d+)\s*", result.stdout)
    assert match, f"Program output has the wrong format: {result.stdout!r}"
    assert int(match.group(1)) == expected, f"Expected Total: {expected}, found: {result.stdout.strip()}"


def test_calc_processes_generated_inputs_and_skips_division_by_zero(tmp_path):
    # Independently compile the submitted calc.c so behavior cannot be supplied by
    # a fabricated Makefile artifact unrelated to the requested source file.
    source_exe = tmp_path / "calc_from_source"
    build = subprocess.run(
        ["gcc", "-pthread", "-o", str(source_exe), CALC_C],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, f"calc.c does not compile with pthread support:\n{build.stderr}"

    rng = secrets.SystemRandom()
    cases = []
    # An isolated invalid operation proves that division by zero contributes zero.
    cases.append([(900001, "DIV", rng.randint(-100, 100), 0)])

    for case_num in range(6):
        rows = []
        count = rng.randint(35, 120)
        for i in range(count):
            op = rng.choice(["ADD", "SUB", "MUL", "DIV"])
            a = rng.randint(-100, 100)
            b = rng.randint(-10, 10)
            if op != "DIV" and b == 0:
                b = rng.choice([-7, -3, 2, 9])
            rows.append((rng.randint(10000, 999999), op, a, b))
        # Every case contains invalid divisions among otherwise valid work.
        rows.insert(rng.randrange(len(rows) + 1), (800000 + case_num, "DIV", rng.randint(-100, 100), 0))
        cases.append(rows)

    for case_num, rows in enumerate(cases):
        input_path = tmp_path / f"generated_{secrets.token_hex(8)}_{case_num}.txt"
        input_path.write_text("".join(f"{ident} {op} {a} {b}\n" for ident, op, a, b in rows))
        expected = expected_value(rows)
        run_and_check(CALC_EXE, input_path, expected)
        run_and_check(str(source_exe), input_path, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
