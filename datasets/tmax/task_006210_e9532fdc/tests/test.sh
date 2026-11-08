#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

HOME = Path("/home/user")
RUNNER = HOME / "run_interpreter.sh"
TEST_RUNNER = HOME / "test.sh"
TESTS = HOME / "tests"
ACTUAL = HOME / "actual_output.txt"


def run_script(path, *args):
    return subprocess.run([str(path), *map(str, args)], cwd=str(HOME), capture_output=True, text=True)


def simulate(lines):
    stack = []
    output = []
    for line in lines:
        parts = line.split()
        op = parts[0]
        if op == "PUSH":
            stack.append(int(parts[1]))
        elif op == "ADD":
            if len(stack) < 2:
                output.append("ERROR")
                break
            top = stack.pop()
            second = stack.pop()
            stack.append(second + top)
        elif op == "SUB":
            if len(stack) < 2:
                output.append("ERROR")
                break
            top = stack.pop()
            second = stack.pop()
            stack.append(second - top)
        elif op == "PRINT":
            if not stack:
                output.append("ERROR")
                break
            output.append(str(stack.pop()))
    return output


def numeric_sort(lines):
    if not lines:
        return []
    result = subprocess.run(
        ["sort", "-n"], input="\n".join(lines) + "\n",
        capture_output=True, text=True, check=True,
        env={**os.environ, "LC_ALL": "C"},
    )
    return result.stdout.rstrip("\n").splitlines()


def test_scripts_exist_and_executable():
    scripts = [
        "/home/user/build.sh",
        "/home/user/run_interpreter.sh",
        "/home/user/test.sh"
    ]
    for script in scripts:
        assert os.path.isfile(script), f"Script {script} does not exist."
        assert os.access(script, os.X_OK), f"Script {script} is not executable."


def test_build_script_succeeds():
    build_script = "/home/user/build.sh"
    result = subprocess.run([build_script], cwd="/home/user", capture_output=True, text=True)
    assert result.returncode == 0, f"build.sh failed with exit code {result.returncode}. Stderr: {result.stderr}"


def test_test_script_produces_correct_output():
    result = run_script(TEST_RUNNER)
    assert result.returncode == 0, f"test.sh failed with exit code {result.returncode}. Stderr: {result.stderr}"
    assert ACTUAL.is_file(), f"Output file {ACTUAL} was not created."
    actual_content = ACTUAL.read_text().strip().splitlines()
    expected_content = ["-10", "ERROR", "30", "140"]
    assert actual_content == expected_content, f"Content of {ACTUAL} does not match expected. Got: {actual_content}, Expected: {expected_content}"


def test_run_interpreter_semantics_on_new_programs():
    rng = random.Random(913847)
    programs = [
        ["PUSH 19", "PUSH -8", "ADD", "PRINT"],
        ["PUSH 19", "PUSH -8", "SUB", "PRINT"],
        ["PUSH -12", "PRINT", "PUSH 7", "PUSH 3", "SUB", "PRINT"],
        ["ADD", "PUSH 999", "PRINT"],
        ["SUB", "PUSH 999", "PRINT"],
        ["PRINT", "PUSH 999", "PRINT"],
    ]
    for _ in range(8):
        lines = []
        depth = 0
        for _ in range(rng.randint(8, 18)):
            choices = ["PUSH"]
            if depth >= 2:
                choices += ["ADD", "SUB"]
            if depth >= 1:
                choices += ["PRINT"]
            op = rng.choice(choices)
            if op == "PUSH":
                lines.append(f"PUSH {rng.randint(-500, 500)}")
                depth += 1
            elif op in ("ADD", "SUB"):
                lines.append(op)
                depth -= 1
            else:
                lines.append("PRINT")
                depth -= 1
        while depth:
            lines.append("PRINT")
            depth -= 1
        programs.append(lines)

    with tempfile.TemporaryDirectory() as td:
        for index, lines in enumerate(programs):
            program = Path(td) / f"unseen_{index}.sm"
            program.write_text("\n".join(lines) + "\n")
            result = run_script(RUNNER, program)
            assert result.stdout.splitlines() == simulate(lines), (
                f"Incorrect output for {lines}: stdout={result.stdout!r}, stderr={result.stderr!r}"
            )

    assert run_script(RUNNER).returncode != 0, "run_interpreter.sh must reject zero arguments"
    assert run_script(RUNNER, "/tmp/a", "/tmp/b").returncode != 0, "run_interpreter.sh must reject more than one argument"


def test_test_script_discovers_invokes_and_sorts_new_fixtures():
    token = uuid.uuid4().hex
    backup_tests = HOME / f".tests_backup_{token}"
    saved_runner = HOME / f".run_interpreter_saved_{token}"
    call_log = Path(f"/tmp/sml_calls_{token}")

    TESTS.rename(backup_tests)
    TESTS.mkdir()
    RUNNER.rename(saved_runner)

    wrapper = f'''#!/usr/bin/env python3
import sys
log = {str(call_log)!r}
if len(sys.argv) != 2:
    sys.exit(2)
with open(log, "a") as f:
    f.write(sys.argv[1] + "\\n")
stack = []
for raw in open(sys.argv[1]):
    p = raw.split()
    if not p:
        continue
    if p[0] == "PUSH":
        stack.append(int(p[1]))
    elif p[0] in ("ADD", "SUB"):
        if len(stack) < 2:
            print("ERROR")
            break
        b = stack.pop(); a = stack.pop()
        stack.append(a + b if p[0] == "ADD" else a - b)
    elif p[0] == "PRINT":
        if not stack:
            print("ERROR")
            break
        print(stack.pop())
'''
    RUNNER.write_text(wrapper)
    RUNNER.chmod(0o755)

    fixture_programs = {
        f"alpha_{token}.sm": ["PUSH 43", "PUSH 17", "SUB", "PRINT"],
        f"beta_{token}.sm": ["PUSH -13", "PRINT", "PUSH 6", "PRINT"],
        f"gamma_{token}.sm": ["PUSH 4", "ADD", "PUSH 999", "PRINT"],
        f"delta_{token}.sm": ["PUSH 8", "PUSH 5", "ADD", "PUSH 2", "SUB", "PRINT"],
    }

    try:
        expected_lines = []
        expected_paths = []
        for name, lines in fixture_programs.items():
            path = TESTS / name
            path.write_text("\n".join(lines) + "\n")
            expected_paths.append(str(path))
            expected_lines.extend(simulate(lines))
        (TESTS / f"ignored_{token}.txt").write_text("PRINT\n")

        if ACTUAL.exists():
            ACTUAL.unlink()
        result = run_script(TEST_RUNNER)
        assert result.returncode == 0, f"test.sh failed on new fixtures: {result.stderr}"
        assert ACTUAL.is_file(), "test.sh did not create actual_output.txt"
        assert ACTUAL.read_text().strip().splitlines() == numeric_sort(expected_lines), (
            "test.sh did not collect and numerically sort outputs from the current .sm files"
        )
        calls = call_log.read_text().splitlines() if call_log.exists() else []
        assert sorted(map(os.path.realpath, calls)) == sorted(map(os.path.realpath, expected_paths)), (
            "test.sh must invoke run_interpreter.sh exactly once for every .sm file"
        )
    finally:
        if RUNNER.exists():
            RUNNER.unlink()
        saved_runner.rename(RUNNER)
        shutil.rmtree(TESTS, ignore_errors=True)
        backup_tests.rename(TESTS)
        if call_log.exists():
            call_log.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
