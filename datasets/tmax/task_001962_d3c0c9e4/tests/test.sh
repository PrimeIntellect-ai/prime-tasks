#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import shutil
import subprocess

import pytest

REPO = "/home/user/math_build"
BUILD_SCRIPT = os.path.join(REPO, "build.sh")
SOURCE = os.path.join(REPO, "matrix_magic.c")
EXECUTABLE = os.path.join(REPO, "matrix_magic")


def get_expected_result(key="1a2b3c"):
    seed = int(key, 16)
    result = math.sqrt(seed) * 3.14159
    return f"{result:.2f}"


def remove_artifact(path):
    if not os.path.lexists(path):
        return
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        os.unlink(path)


def run_build():
    env = os.environ.copy()
    env["MATH_API_KEY"] = "1a2b3c"
    env["LC_ALL"] = "C"
    return subprocess.run(
        [BUILD_SCRIPT],
        cwd=REPO,
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )


def assert_elf_executable():
    assert os.path.isfile(EXECUTABLE), f"The build did not produce {EXECUTABLE}."
    assert not os.path.islink(EXECUTABLE), f"The produced executable {EXECUTABLE} must not be a symlink."
    assert os.access(EXECUTABLE, os.X_OK), f"The file {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The produced file {EXECUTABLE} is not a compiled ELF executable."


def test_build_script_fixes_and_builds_source():
    assert os.path.isfile(BUILD_SCRIPT), f"Build script {BUILD_SCRIPT} is missing."
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."

    with open(BUILD_SCRIPT, "r") as f:
        content = f.read()

    # Preserve the original checks.
    assert "-I./deps/v2" not in content, "The build script still includes the deprecated v2 headers (-I./deps/v2)."
    assert "-lm" in content.split(), "The build script does not link the math library (-lm)."

    # Replace the source briefly with an unpredictable probe. This verifies that
    # build.sh actually compiles matrix_magic.c rather than creating a canned file.
    with open(SOURCE, "rb") as f:
        original_source = f.read()
    original_mode = os.stat(SOURCE).st_mode
    token = "BUILD_PROBE_" + secrets.token_hex(16)
    probe = f'''#include <stdio.h>\n#include <math.h>\n#include "constants.h"\nint main(void) {{\n    volatile double x = 81.0;\n    volatile double y = sqrt(x) * PI_VALUE;\n    printf("{token}\\n");\n    return y < 0.0;\n}}\n'''

    try:
        with open(SOURCE, "w") as f:
            f.write(probe)
        remove_artifact(EXECUTABLE)
        built = run_build()
        assert built.returncode == 0, (
            f"Executing build.sh failed with return code {built.returncode}. "
            f"stdout: {built.stdout!r}; stderr: {built.stderr!r}"
        )
        assert_elf_executable()
        probe_run = subprocess.run(
            [EXECUTABLE], capture_output=True, text=True, timeout=10,
            env={**os.environ, "LC_ALL": "C"}
        )
        assert probe_run.returncode == 0, f"The probe executable failed: {probe_run.stderr}"
        assert probe_run.stdout.strip() == token, (
            "build.sh did not compile the current matrix_magic.c source into matrix_magic."
        )
    finally:
        with open(SOURCE, "wb") as f:
            f.write(original_source)
        os.chmod(SOURCE, original_mode)

    # Perform a clean build of the restored project source for the remaining tests.
    remove_artifact(EXECUTABLE)
    built = run_build()
    assert built.returncode == 0, (
        f"Executing build.sh on matrix_magic.c failed with return code {built.returncode}. "
        f"stdout: {built.stdout!r}; stderr: {built.stderr!r}"
    )
    assert_elf_executable()


def test_result_file_exists_and_correct():
    result_file = "/home/user/result.txt"
    assert os.path.isfile(result_file), f"The result file {result_file} does not exist."

    with open(result_file, "r") as f:
        content = f.read().strip()

    expected = get_expected_result()
    assert content == expected, f"Expected the result file to contain '{expected}', but found '{content}'."


def run_program(key):
    env = os.environ.copy()
    env["MATH_API_KEY"] = key
    env["LC_ALL"] = "C"
    return subprocess.run(
        [EXECUTABLE],
        env=env,
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_executable_exists_and_runnable():
    assert os.path.isfile(EXECUTABLE), f"The compiled executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"The file {EXECUTABLE} is not executable."

    result = run_program("1a2b3c")
    assert result.returncode == 0, (
        f"Running {EXECUTABLE} failed with return code {result.returncode} and stderr: {result.stderr}"
    )
    output = result.stdout.strip()
    expected = get_expected_result()
    assert output == expected, f"Running {EXECUTABLE} with correct MATH_API_KEY produced '{output}', expected '{expected}'."


def test_executable_handles_unpredictable_keys():
    # Runtime-generated keys prevent a fixed-output executable from passing.
    for _ in range(8):
        key = format(secrets.randbelow(0x7ffffffe) + 1, "x")
        result = run_program(key)
        assert result.returncode == 0, (
            f"matrix_magic failed for generated key {key!r}: {result.stderr}"
        )
        expected = get_expected_result(key)
        assert result.stdout.strip() == expected, (
            f"For generated key {key!r}, expected {expected!r} but got {result.stdout.strip()!r}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
