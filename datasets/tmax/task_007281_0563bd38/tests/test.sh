#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import re
import pytest

CRASH_ORIGINAL_PATH = "/home/user/crash_original.txt"
MRE_CPP_PATH = "/home/user/mre.cpp"
LOG_PROCESSOR_PATH = "/home/user/log_processor"
MRE_BIN_PATH = "/tmp/mre_bin"
MRE_OUTPUT_PATH = "/tmp/mre_output.txt"

def test_crash_original_content():
    assert os.path.exists(CRASH_ORIGINAL_PATH), f"File {CRASH_ORIGINAL_PATH} does not exist."
    with open(CRASH_ORIGINAL_PATH, "r") as f:
        content = f.read().strip()
    expected_line = "[DEBUG] Background job failed, retrying with code:2674"
    assert content == expected_line, f"Content of {CRASH_ORIGINAL_PATH} is incorrect. Expected: '{expected_line}', Got: '{content}'"

def test_mre_compiles_and_runs():
    assert os.path.exists(MRE_CPP_PATH), f"File {MRE_CPP_PATH} does not exist."

    # Compile mre.cpp
    compile_result = subprocess.run(
        ["g++", MRE_CPP_PATH, "-o", MRE_BIN_PATH],
        capture_output=True,
        text=True
    )
    assert compile_result.returncode == 0, f"Failed to compile {MRE_CPP_PATH}:\n{compile_result.stderr}"

    # Run mre_bin
    run_result = subprocess.run(
        [MRE_BIN_PATH],
        capture_output=True,
        text=True
    )
    assert run_result.returncode == 0, f"{MRE_BIN_PATH} did not exit cleanly."

    output = run_result.stdout.strip()
    assert output, "Output of mre_bin is empty."

    # Write output to a file for the next test
    with open(MRE_OUTPUT_PATH, "w") as f:
        f.write(output + "\n")

    # Check output format and constraints
    match = re.search(r"code:(\d+)", output)
    assert match is not None, "The output of mre_bin does not contain 'code:<number>'."

    code_val = int(match.group(1))
    assert code_val % 1337 == 0, f"The code value {code_val} is not a multiple of 1337."
    assert code_val != 2674, "The code value must NOT be 2674 (the original crashing value)."

def test_mre_triggers_crash():
    assert os.path.exists(MRE_OUTPUT_PATH), f"{MRE_OUTPUT_PATH} not found. Previous test may have failed."
    assert os.path.exists(LOG_PROCESSOR_PATH), f"{LOG_PROCESSOR_PATH} not found."

    # Run log_processor against the MRE output
    process = subprocess.run(
        [LOG_PROCESSOR_PATH, MRE_OUTPUT_PATH],
        capture_output=True
    )

    # Check for SIGFPE (usually return code 136 or -8 in Python's subprocess depending on shell vs direct execution)
    # subprocess.run returns negative returncode for signals on POSIX: -8 for SIGFPE
    assert process.returncode in (-8, 136), f"Expected log_processor to crash with SIGFPE, but got return code {process.returncode}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
