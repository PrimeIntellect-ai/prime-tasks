#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest


def test_gen_repro_exists_and_works():
    c_file = "/home/user/gen_repro.c"
    assert os.path.exists(c_file), f"Missing C program: {c_file}"

    # Compile the C program
    executable = "/home/user/gen_repro"
    compile_proc = subprocess.run(["gcc", c_file, "-o", executable], capture_output=True)
    assert compile_proc.returncode == 0, f"Failed to compile {c_file}:\n{compile_proc.stderr.decode()}"

    # Run the compiled program to generate the payload
    run_proc = subprocess.run([executable], capture_output=True)
    assert run_proc.returncode == 0, f"Running {executable} failed:\n{run_proc.stderr.decode()}"

    payload_path = "/home/user/minimized_crash.log"
    assert os.path.exists(payload_path), f"Failed: {payload_path} does not exist after running gen_repro"

    size = os.path.getsize(payload_path)

    # Run the vulnerable binary with the generated payload
    proc = subprocess.run(["/app/log_ingest", payload_path], capture_output=True)

    # Check for segfault (return code -11 in Python's subprocess, or 139 in shell)
    assert proc.returncode in (-11, 139), f"Failed: Payload did not cause a segmentation fault. Return code: {proc.returncode}"

    # Metric verification
    assert size <= 15, f"Metric failed: Payload size is {size} bytes, expected <= 15 bytes"

    # Ten bytes after the required four-byte UTC+ marker are the minimum
    # needed to corrupt enough of the saved pointer to trigger SIGSEGV.
    expected_minimum = 14
    assert size == expected_minimum, (
        f"Minimality failed: Payload size is {size} bytes, expected the absolute minimum "
        f"of {expected_minimum} bytes"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
