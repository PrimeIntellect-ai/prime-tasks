#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess

C_FILE = "/home/user/solve_markov.c"
OUTPUT_FILE = "/home/user/stationary_dist.txt"
BINARY = "/tmp/solve_markov_verifier"

def test_c_program_exists():
    assert os.path.exists(C_FILE), f"C program file not found at {C_FILE}"
    assert os.path.isfile(C_FILE), f"{C_FILE} is not a file"

def test_c_program_compiles_and_executes():
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", C_FILE, "-lm", "-o", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "C program failed to compile:\n" +
        compile_result.stderr.decode("utf-8", errors="replace")
    )
    assert os.path.isfile(BINARY), "Compilation did not produce an executable"

    # Remove any precomputed answer so the checked output must come from this run.
    if os.path.lexists(OUTPUT_FILE):
        os.unlink(OUTPUT_FILE)

    run_result = subprocess.run(
        [BINARY],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert run_result.returncode == 0, (
        "Compiled C program failed during execution:\n" +
        run_result.stderr.decode("utf-8", errors="replace")
    )

    # Support programs that write the requested file directly and programs whose
    # standard output is intended to be redirected to that file.
    if not os.path.exists(OUTPUT_FILE) and run_result.stdout:
        with open(OUTPUT_FILE, "wb") as f:
            f.write(run_result.stdout)

def test_stationary_dist_output():
    output_path = OUTPUT_FILE
    assert os.path.exists(output_path), f"Output file not found at {output_path}"
    assert os.path.isfile(output_path), f"{output_path} is not a file"

    with open(output_path, "r") as f:
        content = f.read()

    # Remove standard newline at the end if present
    if content.endswith('\n'):
        content = content[:-1]

    expected = "0.2222,0.3111,0.2444,0.2222"
    assert content == expected, f"Expected output '{expected}', but got '{content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
