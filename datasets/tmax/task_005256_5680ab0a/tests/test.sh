#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
import tempfile

import pytest

REPO = "/home/user/legacy_tool"
PROCESS = os.path.join(REPO, "process")


@pytest.fixture(scope="session", autouse=True)
def build_fresh_process():
    # Require build.sh itself to produce a fresh executable.
    if os.path.lexists(PROCESS):
        os.remove(PROCESS)

    result = subprocess.run(
        ["bash", "build.sh"],
        cwd=REPO,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"build.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(PROCESS), "build.sh did not produce ./process."
    assert os.access(PROCESS, os.X_OK), "The produced ./process is not executable."
    with open(PROCESS, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The produced ./process is not an ELF executable."


def test_output_file_exists_and_content():
    output_path = "/home/user/output.txt"
    assert os.path.isfile(output_path), f"{output_path} does not exist."

    with open(output_path, "r") as f:
        content = f.read().strip()

    expected_content = "Processed: 1024.000000"
    assert content == expected_content, f"Output file content is incorrect. Expected '{expected_content}', got '{content}'."


def test_build_sh_includes_math_library():
    build_sh_path = "/home/user/legacy_tool/build.sh"
    assert os.path.isfile(build_sh_path), f"{build_sh_path} does not exist."

    with open(build_sh_path, "r") as f:
        content = f.read()

    assert "-lm" in content, "build.sh does not include the '-lm' flag to correctly link the math library."


def test_run_sh_safely_quotes_argument():
    run_sh_path = "/home/user/legacy_tool/run.sh"
    assert os.path.isfile(run_sh_path), f"{run_sh_path} does not exist."

    with open(run_sh_path, "r") as f:
        content = f.read()

    # Check if the script uses "$1", "$@", "${1}", or "${@}" to safely handle spaces
    pattern = r'"\$1"|"\$@"|"\$\{1\}"|"\$\{@\}"'
    assert re.search(pattern, content), "run.sh does not safely quote the filename argument (e.g., \"$1\")."


def test_recovered_test_file():
    test_case_path = "/home/user/legacy_tool/test case.txt"
    assert os.path.isfile(test_case_path), f"The lost test asset '{test_case_path}' was not recovered."

    with open(test_case_path, "r") as f:
        content = f.read().strip()

    assert content == "1048576", f"The recovered test file '{test_case_path}' does not contain the correct original data."


def test_process_and_wrapper_execute_on_generated_inputs():
    # Exercise both the freshly built C executable and the wrapper using filenames
    # containing spaces and values selected only at verification time.
    for _ in range(2):
        value = secrets.randbelow(8_000_000) + 1
        expected = f"Processed: {math.sqrt(value):.6f}"

        fd, input_path = tempfile.mkstemp(
            prefix="generated input ", suffix=" with spaces.txt", dir=REPO
        )
        try:
            with os.fdopen(fd, "w") as f:
                f.write(f"{value}\n")

            direct = subprocess.run(
                [PROCESS, input_path],
                cwd=REPO,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert direct.returncode == 0, f"./process failed: {direct.stderr}"
            assert direct.stdout.strip() == expected, (
                f"./process returned {direct.stdout.strip()!r}; expected {expected!r}."
            )

            wrapped = subprocess.run(
                ["bash", "run.sh", input_path],
                cwd=REPO,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert wrapped.returncode == 0, f"run.sh failed: {wrapped.stderr}"
            assert wrapped.stdout.strip() == expected, (
                f"run.sh returned {wrapped.stdout.strip()!r}; expected {expected!r}."
            )
        finally:
            if os.path.exists(input_path):
                os.remove(input_path)


def test_saved_output_matches_actual_recovered_file_run():
    recovered = os.path.join(REPO, "test case.txt")
    result = subprocess.run(
        ["bash", "run.sh", recovered],
        cwd=REPO,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"run.sh failed on the recovered file: {result.stderr}"
    with open("/home/user/output.txt", "r") as f:
        saved_output = f.read().strip()
    assert result.stdout.strip() == saved_output, (
        "output.txt does not match the output produced by run.sh on the recovered file."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
