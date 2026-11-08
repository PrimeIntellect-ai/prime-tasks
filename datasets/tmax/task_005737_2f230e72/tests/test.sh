#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import tempfile

import pytest

RELEASE = "/home/user/release"


def run(cmd, **kwargs):
    return subprocess.run(cmd, timeout=30, text=True, capture_output=True, **kwargs)


def make_hidden_input(path):
    rng = random.SystemRandom()
    first = rng.randint(16, 5000)
    decoy = rng.randint(16, 5000)
    values = [rng.randint(-100, 100) for _ in range(12)]
    padding = " " * rng.randint(5000, 9000)
    with open(path, "w") as f:
        # A fixed-size fgets loop incorrectly processes the decoy as another value.
        f.write(f"{first}{padding}{decoy}\n")
        for value in values:
            f.write(f"{value}\n")
    expected = (first if first > 15 else 0) + sum(v for v in values if v > 15)
    return f"Sum: {expected}\n"


def assert_elf(path):
    assert os.path.isfile(path), f"{path} does not exist."
    assert os.access(path, os.X_OK), f"{path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def test_patch_applied():
    """Keep the original checks that the patch was applied to main.c."""
    main_c_path = os.path.join(RELEASE, "main.c")
    assert os.path.isfile(main_c_path), f"{main_c_path} does not exist."
    with open(main_c_path) as f:
        content = f.read()
    assert "getline" in content, "The patch does not appear to be applied (missing 'getline')."
    assert "char* line = NULL;" in content, "The patch does not appear to be applied (missing 'char* line = NULL;')."


def test_memory_leak_fixed_in_code():
    """Keep the original source assertion; Valgrind below verifies its behavior."""
    main_c_path = os.path.join(RELEASE, "main.c")
    assert os.path.isfile(main_c_path), f"{main_c_path} does not exist."
    with open(main_c_path) as f:
        content = f.read()
    assert "free(line);" in content, "The memory leak fix 'free(line);' was not found in main.c."


def test_compilation_successful():
    executable_path = os.path.join(RELEASE, "data_processor")
    assert os.path.isfile(executable_path), f"Compiled executable {executable_path} does not exist."
    assert os.access(executable_path, os.X_OK), f"{executable_path} is not executable."


def test_processed_output():
    output_path = os.path.join(RELEASE, "processed_output.txt")
    assert os.path.isfile(output_path), f"{output_path} does not exist."
    with open(output_path) as f:
        content = f.read().strip()
    assert "Sum: 66" in content, f"Expected 'Sum: 66' in {output_path}, but got: {content}"
    assert content == "Sum: 66", f"Unexpected processed output: {content!r}"


def test_valgrind_report():
    report_path = os.path.join(RELEASE, "valgrind_report.txt")
    assert os.path.isfile(report_path), f"{report_path} does not exist."
    with open(report_path) as f:
        content = f.read()

    success_indicators = ["All heap blocks were freed", "0 bytes in 0 blocks"]
    assert any(indicator in content for indicator in success_indicators), \
        "valgrind_report.txt does not indicate that all heap blocks were freed."
    assert "Memcheck, a memory error detector" in content, "The saved report is not a Valgrind Memcheck report."
    assert "HEAP SUMMARY:" in content, "The saved report lacks a Valgrind heap summary."
    assert "All heap blocks were freed -- no leaks are possible" in content, \
        "The saved report does not contain the required no-leaks result."
    assert re.search(r"ERROR SUMMARY: 0 errors", content), "The saved Valgrind report contains errors."


def test_clean_build_and_long_line_behavior():
    clean = run(["make", "clean"], cwd=RELEASE)
    assert clean.returncode == 0, clean.stdout + clean.stderr
    build = run(["make"], cwd=RELEASE)
    assert build.returncode == 0, build.stdout + build.stderr

    executable = os.path.join(RELEASE, "data_processor")
    assert_elf(executable)

    with tempfile.TemporaryDirectory() as td:
        hidden_data = os.path.join(td, "input.csv")
        expected = make_hidden_input(hidden_data)

        result = run([executable, hidden_data], cwd=RELEASE)
        assert result.returncode == 0, result.stderr
        assert result.stdout == expected, f"Incorrect output for an arbitrarily long line: {result.stdout!r}"

        # Compile the submitted C and C++ sources directly as well, so a forged
        # executable or Makefile cannot substitute for a functional source patch.
        main_o = os.path.join(td, "main.o")
        filter_o = os.path.join(td, "filter.o")
        direct_exe = os.path.join(td, "data_processor")
        commands = [
            ["gcc", "-g", "-c", os.path.join(RELEASE, "main.c"), "-o", main_o],
            ["g++", "-g", "-c", os.path.join(RELEASE, "filter.cpp"), "-o", filter_o],
            ["gcc", "-o", direct_exe, main_o, filter_o, "-lstdc++"],
        ]
        for command in commands:
            compiled = run(command)
            assert compiled.returncode == 0, compiled.stdout + compiled.stderr
        direct_result = run([direct_exe, hidden_data])
        assert direct_result.returncode == 0, direct_result.stderr
        assert direct_result.stdout == expected, "Directly compiled submitted sources produced incorrect output."


def test_fresh_valgrind_execution():
    build = run(["make"], cwd=RELEASE)
    assert build.returncode == 0, build.stdout + build.stderr
    executable = os.path.join(RELEASE, "data_processor")
    assert_elf(executable)

    with tempfile.TemporaryDirectory() as td:
        hidden_data = os.path.join(td, "valgrind_input.csv")
        expected = make_hidden_input(hidden_data)
        checked = run([
            "valgrind", "--leak-check=full", "--show-leak-kinds=all",
            "--errors-for-leak-kinds=all", "--error-exitcode=97",
            "./data_processor", hidden_data,
        ], cwd=RELEASE)

    assert checked.returncode == 0, checked.stderr
    assert checked.stdout == expected, "Program output under Valgrind was incorrect."
    assert "All heap blocks were freed -- no leaks are possible" in checked.stderr, \
        "A fresh Valgrind run found allocated heap blocks."
    assert re.search(r"ERROR SUMMARY: 0 errors", checked.stderr), \
        "A fresh Valgrind run reported memory errors."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
