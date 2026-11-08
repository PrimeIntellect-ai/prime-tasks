#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import uuid
from pathlib import Path

import pytest

PROJECT_DIR = Path("/home/user/vm_project")
EXECUTABLE = PROJECT_DIR / "simple_vm"
REPORT_JSON = PROJECT_DIR / "report.json"
TEST_RUNNER = PROJECT_DIR / "test_runner.py"
TESTS_DIR = PROJECT_DIR / "tests"

EXPECTED_MAKEFILE = """CC = gcc
CFLAGS = -Wall -Wextra -Werror

all: simple_vm

simple_vm: src/main.c src/vm.c
\t$(CC) $(CFLAGS) -o simple_vm src/main.c src/vm.c

clean:
\trm -f simple_vm
"""


def run_vm(program):
    name = f"verifier_{uuid.uuid4().hex}.asm"
    path = Path("/tmp") / name
    path.write_text(program)
    try:
        return subprocess.run(
            [str(EXECUTABLE), str(path)],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=5,
        )
    finally:
        path.unlink(missing_ok=True)


def assert_vm(program, output, code):
    result = run_vm(program)
    assert result.returncode == code, (
        f"Program {program!r} returned {result.returncode}, expected {code}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout == output, f"Expected stdout {output!r}, got {result.stdout!r}"


def test_executable_compiles_and_exists():
    """Run the required build and verify that it produces a native executable."""
    assert (PROJECT_DIR / "Makefile").read_text() == EXPECTED_MAKEFILE, "The Makefile was modified."

    clean = subprocess.run(
        ["make", "clean"], cwd=PROJECT_DIR, capture_output=True, text=True, timeout=20
    )
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}\n{clean.stderr}"

    build = subprocess.run(
        ["make"], cwd=PROJECT_DIR, capture_output=True, text=True, timeout=20
    )
    assert build.returncode == 0, f"make failed:\n{build.stdout}\n{build.stderr}"
    assert EXECUTABLE.is_file(), f"Executable {EXECUTABLE} is missing. Did the code compile successfully?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    assert EXECUTABLE.read_bytes()[:4] == b"\x7fELF", "simple_vm is not the compiled native executable."


def test_vm_behavior_normal():
    """Test that the VM correctly executes the original normal program."""
    test_file = TESTS_DIR / "test_normal.asm"
    result = subprocess.run([str(EXECUTABLE), str(test_file)], capture_output=True, text=True)
    assert result.returncode == 0, f"Expected exit code 0 for normal program, got {result.returncode}"
    assert result.stdout.strip() == "15", f"Expected output '15', got '{result.stdout.strip()}'"


def test_vm_behavior_overflow():
    """Test that the VM correctly handles the original overflow program."""
    test_file = TESTS_DIR / "test_overflow.asm"
    result = subprocess.run([str(EXECUTABLE), str(test_file)], capture_output=True, text=True)
    assert result.returncode == 1, f"Expected exit code 1 for stack overflow, got {result.returncode}"
    assert result.stdout.strip() == "Error: Stack Overflow", f"Expected 'Error: Stack Overflow', got '{result.stdout.strip()}'"


def test_vm_behavior_underflow():
    """Test that the VM correctly handles the original underflow program."""
    test_file = TESTS_DIR / "test_underflow.asm"
    result = subprocess.run([str(EXECUTABLE), str(test_file)], capture_output=True, text=True)
    assert result.returncode == 1, f"Expected exit code 1 for stack underflow, got {result.returncode}"
    assert result.stdout.strip() == "Error: Stack Underflow", f"Expected 'Error: Stack Underflow', got '{result.stdout.strip()}'"


def test_vm_dynamic_programs_and_all_underflows():
    """Exercise unpredictable programs and every specified stack boundary."""
    rng = random.SystemRandom()
    values = [rng.randint(-100000, 100000) for _ in range(6)]
    program = "".join(f"PUSH {v}\n" for v in values[:3])
    program += "ADD\nPRINT\nPRINT\n"
    assert_vm(program, f"{values[1] + values[2]}\n{values[0]}\n", 0)

    assert_vm("PRINT\n", "Error: Stack Underflow\n", 1)
    assert_vm("POP\n", "Error: Stack Underflow\n", 1)
    assert_vm("ADD\n", "Error: Stack Underflow\n", 1)
    assert_vm(f"PUSH {values[3]}\nADD\n", "Error: Stack Underflow\n", 1)
    assert_vm(f"PUSH {values[4]}\nPOP\n", "", 0)
    assert_vm(f"PUSH {values[5]}\nPOP\nPRINT\n", "Error: Stack Underflow\n", 1)

    overflow_values = [rng.randint(-100000, 100000) for _ in range(11)]
    overflow = "".join(f"PUSH {v}\n" for v in overflow_values) + "PRINT\n"
    assert_vm(overflow, "Error: Stack Overflow\n", 1)


def test_test_runner_exists():
    """Check that the Python test runner script exists."""
    assert TEST_RUNNER.is_file(), f"Test runner script {TEST_RUNNER} is missing."


def test_runner_discovers_executes_and_reports_dynamic_tests():
    """Run the orchestrator and prove it invokes simple_vm for every discovered asm file."""
    token = uuid.uuid4().hex
    good_name = f"dynamic_good_{token}.asm"
    under_name = f"dynamic_underflow_{token}.asm"
    fail_name = f"dynamic_expected_fail_{token}.asm"
    rng = random.SystemRandom()
    a, b = rng.randint(-50000, 50000), rng.randint(-50000, 50000)

    fixtures = {
        good_name: (f"PUSH {a}\nPUSH {b}\nADD\nPRINT\n", f"{a + b}\n"),
        under_name: ("PRINT\n", "Error: Stack Underflow\n"),
        fail_name: (f"PUSH {a}\nPRINT\n", f"{a + 1}\n"),
    }
    created = []
    real_executable = PROJECT_DIR / f".verifier-real-{token}"
    log_path = Path("/tmp") / f"vm-invocations-{token}.log"

    try:
        for name, (asm, expected) in fixtures.items():
            asm_path = TESTS_DIR / name
            expected_path = asm_path.with_suffix(".expected")
            asm_path.write_text(asm)
            expected_path.write_text(expected)
            created.extend([asm_path, expected_path])

        all_asm_names = {p.name for p in TESTS_DIR.glob("*.asm")}
        REPORT_JSON.unlink(missing_ok=True)

        os.replace(EXECUTABLE, real_executable)
        wrapper = (
            "#!/bin/sh\n"
            f"printf '%s\\n' \"$1\" >> '{log_path}'\n"
            f"exec '{real_executable}' \"$@\"\n"
        )
        EXECUTABLE.write_text(wrapper)
        EXECUTABLE.chmod(0o755)

        result = subprocess.run(
            ["python3", str(TEST_RUNNER)],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"test_runner.py failed with {result.returncode}:\n"
            f"stdout={result.stdout}\nstderr={result.stderr}"
        )
        assert REPORT_JSON.is_file(), "test_runner.py did not generate report.json"
        with REPORT_JSON.open() as f:
            report = json.load(f)

        assert set(report) == all_asm_names, "report.json does not contain exactly all discovered .asm files"
        assert report[good_name] == "pass"
        assert report[under_name] == "pass"
        assert report[fail_name] == "fail"
        assert report["test_normal.asm"] == "pass"
        assert report["test_overflow.asm"] == "pass"
        assert report["test_underflow.asm"] == "pass"

        invocations = log_path.read_text().splitlines() if log_path.exists() else []
        for name in all_asm_names:
            assert f"tests/{name}" in invocations, f"test_runner.py did not invoke ./simple_vm tests/{name}"
    finally:
        for path in created:
            path.unlink(missing_ok=True)
        log_path.unlink(missing_ok=True)
        if real_executable.exists():
            EXECUTABLE.unlink(missing_ok=True)
            os.replace(real_executable, EXECUTABLE)


def test_report_json_exists_and_correct():
    """Retain the original checks for the required fixture results."""
    assert REPORT_JSON.is_file(), f"Report file {REPORT_JSON} is missing."

    try:
        with REPORT_JSON.open() as f:
            report = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{REPORT_JSON} does not contain valid JSON.")

    expected_results = {
        "test_normal.asm": "pass",
        "test_overflow.asm": "pass",
        "test_underflow.asm": "pass",
    }
    for test_file, expected_status in expected_results.items():
        assert test_file in report, f"Test file {test_file} is missing from {REPORT_JSON}"
        assert report[test_file] == expected_status, (
            f"Expected {test_file} to be '{expected_status}', got '{report[test_file]}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
