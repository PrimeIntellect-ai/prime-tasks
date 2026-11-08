#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import pytest

REPO = "/home/user/data_processor"
FIXED_SRC = "/home/user/fixed_processor.cpp"


def run_checked(cmd):
    return subprocess.run(
        cmd,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_bad_commit_hash():
    student_file = "/home/user/bad_commit.txt"
    assert os.path.isfile(student_file), f"Deliverable {student_file} does not exist."

    with open(student_file, "r") as f:
        student_hash = f.read().strip()

    expected_hash = run_checked(
        ["git", "-C", REPO, "rev-parse", "HEAD~114"]
    ).stdout.strip()

    assert re.fullmatch(r"[0-9a-f]{40}", student_hash), \
        "bad_commit.txt must contain one full lowercase SHA-1 hash."
    assert student_hash == expected_hash, \
        f"Incorrect bad commit hash. Expected {expected_hash}, got {student_hash}."


def compile_source(source, executable):
    compile_cmd = ["g++", "-O3", "-pthread", source, "-o", executable]
    try:
        run_checked(compile_cmd)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Compilation failed for {source}:\n{e.stderr}")
    assert os.path.isfile(executable), "Executable was not created after compilation."


def run_and_expect(executable, expected, runs):
    for i in range(runs):
        try:
            result = run_checked([executable])
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Execution {i + 1} failed:\n{e.stderr}")
        output = result.stdout.strip()
        assert output == str(expected), \
            f"Run {i + 1} failed: Expected output '{expected}', got '{output}'."


def code_without_comments_or_literals(source):
    token = re.compile(
        r'//.*?$|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'',
        re.MULTILINE | re.DOTALL,
    )
    return token.sub(lambda m: " " * len(m.group(0)), source)


def test_fixed_processor_compiles_and_runs():
    assert os.path.isfile(FIXED_SRC), f"Deliverable {FIXED_SRC} does not exist."

    with open(FIXED_SRC, "r") as f:
        source = f.read()

    code = code_without_comments_or_literals(source)
    assert re.search(r"\bstd\s*::\s*thread\b", code), \
        "The repaired program must retain its multithreaded workload."
    assert re.search(r"\bworker\s*\(", code), \
        "The repaired program must retain the worker routine."
    assert (
        re.search(r"\bemplace_back\s*\(\s*worker\b", code)
        or re.search(r"\bthread\s*\(\s*worker\b", code)
    ), "The program must continue launching threads that execute worker."
    assert re.search(r"(?<![0-9])10(?![0-9])", code), \
        "The intended ten-thread workload was not retained."
    assert re.search(r"(?<![0-9])1000000(?![0-9])", code), \
        "The intended per-thread iteration count was not retained."

    executable = "/tmp/proc_test"
    compile_source(FIXED_SRC, executable)

    # Preserve the original behavioral assertion.
    run_and_expect(executable, 10000000, 5)


def test_output_is_produced_by_the_workload_not_hard_coded():
    with open(FIXED_SRC, "r") as f:
        original = f.read()

    # Recompile the same implementation with verifier-selected workload sizes.
    # Correct code derives its result from the worker ranges; a constant printer
    # continues to print 10000000 and fails these checks.
    cases = [(7, 123457), (13, 54321)]
    for index, (threads, iterations) in enumerate(cases):
        varied, thread_replacements = re.subn(
            r"(?<![0-9])10(?![0-9])", str(threads), original
        )
        varied, iteration_replacements = re.subn(
            r"(?<![0-9])1000000(?![0-9])", str(iterations), varied
        )
        assert thread_replacements > 0 and iteration_replacements > 0

        varied_src = f"/tmp/varied_processor_{index}.cpp"
        varied_exe = f"/tmp/varied_processor_{index}"
        with open(varied_src, "w") as f:
            f.write(varied)

        compile_source(varied_src, varied_exe)
        run_and_expect(varied_exe, threads * iterations, 3)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
